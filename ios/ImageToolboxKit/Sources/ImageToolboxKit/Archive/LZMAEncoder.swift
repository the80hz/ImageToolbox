import Foundation

/// The range encoder of LZMA: the mirror of `LZMARangeDecoder`.
struct LZMARangeEncoder {
  private var low: UInt64 = 0
  private var range: UInt32 = 0xFFFF_FFFF
  private var cache: UInt8 = 0
  private var cacheSize = 1
  private(set) var output: [UInt8] = []

  mutating func reset() {
    low = 0
    range = 0xFFFF_FFFF
    cache = 0
    cacheSize = 1
    output.removeAll(keepingCapacity: true)
  }

  private mutating func shiftLow() {
    if UInt32(truncatingIfNeeded: low) < 0xFF00_0000 || low >> 32 != 0 {
      var pending = cache
      let carry = UInt8(truncatingIfNeeded: low >> 32)
      repeat {
        output.append(pending &+ carry)
        pending = 0xFF
        cacheSize -= 1
      } while cacheSize != 0
      cache = UInt8(truncatingIfNeeded: low >> 24)
    }
    cacheSize += 1
    low = (low & 0x00FF_FFFF) << 8
  }

  @inline(__always)
  mutating func encode(_ probability: UnsafeMutablePointer<UInt16>, bit: Int) {
    let value = UInt32(probability.pointee)
    let bound = (range >> 11) &* value
    if bit == 0 {
      range = bound
      probability.pointee = UInt16(truncatingIfNeeded: value + ((2048 - value) >> 5))
    } else {
      low &+= UInt64(bound)
      range &-= bound
      probability.pointee = UInt16(truncatingIfNeeded: value - (value >> 5))
    }
    while range < 1 << 24 {
      range <<= 8
      shiftLow()
    }
  }

  mutating func encodeBitTree(
    _ probabilities: UnsafeMutablePointer<UInt16>, bits: Int, symbol: Int
  ) {
    var node = 1
    for index in stride(from: bits - 1, through: 0, by: -1) {
      let bit = (symbol >> index) & 1
      encode(probabilities + node, bit: bit)
      node = node << 1 | bit
    }
  }

  mutating func encodeReverseBitTree(
    _ probabilities: UnsafeMutablePointer<UInt16>, bits: Int, symbol: Int
  ) {
    var node = 1
    var rest = symbol
    for _ in 0..<bits {
      let bit = rest & 1
      rest >>= 1
      encode(probabilities + node, bit: bit)
      node = node << 1 | bit
    }
  }

  mutating func encodeDirect(_ value: Int, bits: Int) {
    for index in stride(from: bits - 1, through: 0, by: -1) {
      range >>= 1
      if (value >> index) & 1 == 1 { low &+= UInt64(range) }
      while range < 1 << 24 {
        range <<= 8
        shiftLow()
      }
    }
  }

  /// Writes out the pending bytes. The encoder must be reset before it is used again.
  mutating func finish() {
    for _ in 0..<5 { shiftLow() }
  }
}

/// A hash chain over three-byte prefixes. Positions are inserted in order; `find` looks for the
/// longest earlier match.
private struct LZMAMatchFinder {
  private static let hashBits = 17

  private let window: Int
  private var head: [Int32]
  private var previous: [Int32]
  private let depth: Int
  private let niceLength: Int

  init(window: Int, depth: Int, niceLength: Int) {
    self.window = window
    self.depth = depth
    self.niceLength = niceLength
    head = [Int32](repeating: -1, count: 1 << Self.hashBits)
    previous = [Int32](repeating: -1, count: window)
  }

  @inline(__always)
  private func hash(_ input: UnsafePointer<UInt8>, _ position: Int) -> Int {
    let value =
      UInt32(input[position]) | UInt32(input[position + 1]) << 8 | UInt32(input[position + 2]) << 16
    return Int((value &* 0x9E37_79B1) >> UInt32(32 - Self.hashBits))
  }

  /// Adds `position` to the chains. The three bytes must exist.
  mutating func insert(_ input: UnsafePointer<UInt8>, count: Int, position: Int) {
    guard position + 3 <= count else { return }
    let slot = hash(input, position)
    previous[position & (window - 1)] = head[slot]
    head[slot] = Int32(truncatingIfNeeded: position)
  }

  /// The longest match for `position`, as a length and a distance. The length is zero when
  /// there is none of at least three bytes.
  func find(
    _ input: UnsafePointer<UInt8>, count: Int, position: Int, maximum: Int
  ) -> (length: Int, distance: Int) {
    guard maximum >= 3, position + 3 <= count else { return (0, 0) }
    var best = (length: 0, distance: 0)
    var candidate = Int(head[hash(input, position)])
    var steps = depth
    while candidate >= 0, steps > 0 {
      let distance = position - candidate
      if distance >= window || distance <= 0 { break }
      if input[candidate + best.length] == input[position + best.length]
        || best.length == 0
      {
        var length = 0
        while length < maximum, input[candidate + length] == input[position + length] {
          length += 1
        }
        if length > best.length {
          best = (length, distance)
          if length >= niceLength || length == maximum { break }
        }
      }
      candidate = Int(previous[candidate & (window - 1)])
      steps -= 1
    }
    return best.length >= 3 ? best : (0, 0)
  }
}

/// A greedy LZMA encoder with one step of lazy matching, writing the same models the decoder reads.
final class LZMAEncoder {

  /// lc, lp and pb of the standard `0x5D` properties byte.
  static let literalContextBits = 3
  static let literalPositionBits = 0
  static let positionBits = 2
  static var propertiesByte: UInt8 {
    UInt8((positionBits * 5 + literalPositionBits) * 9 + literalContextBits)
  }

  /// The dictionary size an encoder uses for `count` bytes of input: a power of two between
  /// 4 KiB and 4 MiB.
  static func dictionarySize(for count: Int) -> Int {
    var size = 1 << 12
    while size < count && size < 1 << 22 { size <<= 1 }
    return size
  }

  private let input: UnsafePointer<UInt8>
  private let count: Int
  private var finder: LZMAMatchFinder
  private let probabilities: UnsafeMutablePointer<UInt16>
  private let probabilityCount: Int
  private var state = 0
  private var reps = [0, 0, 0, 0]
  private(set) var encoder = LZMARangeEncoder()

  /// The next position the match finder has not been told about.
  private var inserted = 0

  /// Creates an encoder over `input`, which must stay valid as long as the encoder is used.
  init(input: UnsafeBufferPointer<UInt8>, window: Int) {
    self.input = input.baseAddress ?? UnsafePointer(bitPattern: 1)!
    count = input.count
    finder = LZMAMatchFinder(window: window, depth: 40, niceLength: 128)
    probabilityCount = LZMAModel.size(
      literalContextBits: Self.literalContextBits, literalPositionBits: Self.literalPositionBits)
    probabilities = .allocate(capacity: probabilityCount)
    resetModel()
  }

  deinit { probabilities.deallocate() }

  /// Forgets what the model learned: probabilities, state and repeat distances.
  func resetModel() {
    probabilities.initialize(repeating: 1024, count: probabilityCount)
    state = 0
    reps = [0, 0, 0, 0]
  }

  /// Starts a new range coder output.
  func resetRangeCoder() { encoder.reset() }

  /// Flushes the range coder and returns what it wrote.
  func finishRangeCoder() -> [UInt8] {
    encoder.finish()
    return encoder.output
  }

  /// Encodes `input[start..<end]` into the range coder. Matches never reach past `end`.
  func encode(from start: Int, to end: Int) {
    let probs = probabilities
    var position = start
    var lookahead: (position: Int, length: Int, distance: Int)?

    while position < end {
      let remaining = end - position
      let maximum = min(LZMAModel.maximumMatch, remaining)

      var main: (length: Int, distance: Int)
      if let cached = lookahead, cached.position == position {
        main = (cached.length, cached.distance)
      } else {
        main = finder.find(input, count: count, position: position, maximum: maximum)
      }
      lookahead = nil
      insertPositions(upTo: position + 1)

      // The best repeat match among the four distances.
      var repLength = 0
      var repIndex = 0
      if position > 0 {
        for index in 0..<4 where reps[index] < position {
          let length = commonLength(position, position - reps[index] - 1, maximum: maximum)
          if length > repLength {
            repLength = length
            repIndex = index
          }
        }
      }
      if main.length == 3 && main.distance > 1 << 13 { main = (0, 0) }

      let nice = 128
      var useRep = false
      var useMain = false
      if repLength >= nice {
        useRep = true
      } else if main.length >= nice {
        useMain = true
      } else if repLength >= 2 && repLength + 1 >= main.length {
        useRep = true
      } else if main.length >= 3 {
        useMain = true
        if remaining > main.length {
          let next = finder.find(
            input, count: count, position: position + 1,
            maximum: min(LZMAModel.maximumMatch, remaining - 1))
          if next.length > main.length {
            useMain = false
            lookahead = (position + 1, next.length, next.distance)
          }
        }
      }

      if useRep {
        encodeRepeat(index: repIndex, length: repLength, position: position, probs: probs)
        insertPositions(upTo: position + repLength)
        position += repLength
      } else if useMain {
        encodeMatch(
          distance: main.distance, length: main.length, position: position, probs: probs)
        insertPositions(upTo: position + main.length)
        position += main.length
      } else if position > reps[0], input[position] == input[position - reps[0] - 1] {
        encodeShortRepeat(position: position, probs: probs)
        position += 1
      } else {
        encodeLiteral(position: position, probs: probs)
        position += 1
      }
    }
  }

  private func insertPositions(upTo limit: Int) {
    while inserted < limit {
      finder.insert(input, count: count, position: inserted)
      inserted += 1
    }
  }

  @inline(__always)
  private func commonLength(_ first: Int, _ second: Int, maximum: Int) -> Int {
    var length = 0
    while length < maximum, input[first + length] == input[second + length] { length += 1 }
    return length
  }

  // MARK: - Symbols

  private func encodeLiteral(position: Int, probs: UnsafeMutablePointer<UInt16>) {
    let posState = position & ((1 << Self.positionBits) - 1)
    encoder.encode(probs + LZMAModel.isMatch + (state << 4) + posState, bit: 0)
    let previous = position > 0 ? Int(input[position - 1]) : 0
    let context =
      ((position & ((1 << Self.literalPositionBits) - 1)) << Self.literalContextBits)
      + (previous >> (8 - Self.literalContextBits))
    let table = probs + LZMAModel.literal + 0x300 * context
    let symbol = Int(input[position])
    var node = 1
    if state >= 7 {
      var matchByte = Int(input[position - reps[0] - 1])
      var offset = 0x100
      for index in stride(from: 7, through: 0, by: -1) {
        matchByte <<= 1
        let matchBit = matchByte & offset
        let bit = (symbol >> index) & 1
        encoder.encode(table + offset + matchBit + node, bit: bit)
        node = node << 1 | bit
        offset &= bit == 0 ? ~matchBit : matchBit
      }
    } else {
      encoder.encodeBitTree(table, bits: 8, symbol: symbol)
    }
    state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6)
  }

  private func encodeMatch(
    distance: Int, length: Int, position: Int, probs: UnsafeMutablePointer<UInt16>
  ) {
    let posState = position & ((1 << Self.positionBits) - 1)
    encoder.encode(probs + LZMAModel.isMatch + (state << 4) + posState, bit: 1)
    encoder.encode(probs + LZMAModel.isRep + state, bit: 0)
    encodeLength(length - 2, table: probs + LZMAModel.lengthCoder, posState: posState)
    encodeDistance(distance - 1, length: length - 2, probs: probs)
    reps = [distance - 1, reps[0], reps[1], reps[2]]
    state = state < 7 ? 7 : 10
  }

  private func encodeRepeat(
    index: Int, length: Int, position: Int, probs: UnsafeMutablePointer<UInt16>
  ) {
    let posState = position & ((1 << Self.positionBits) - 1)
    encoder.encode(probs + LZMAModel.isMatch + (state << 4) + posState, bit: 1)
    encoder.encode(probs + LZMAModel.isRep + state, bit: 1)
    if index == 0 {
      encoder.encode(probs + LZMAModel.isRepG0 + state, bit: 0)
      encoder.encode(probs + LZMAModel.isRepLong + (state << 4) + posState, bit: 1)
    } else {
      encoder.encode(probs + LZMAModel.isRepG0 + state, bit: 1)
      if index == 1 {
        encoder.encode(probs + LZMAModel.isRepG1 + state, bit: 0)
      } else {
        encoder.encode(probs + LZMAModel.isRepG1 + state, bit: 1)
        encoder.encode(probs + LZMAModel.isRepG2 + state, bit: index - 2)
      }
      let distance = reps[index]
      reps.remove(at: index)
      reps.insert(distance, at: 0)
    }
    encodeLength(length - 2, table: probs + LZMAModel.repLengthCoder, posState: posState)
    state = state < 7 ? 8 : 11
  }

  private func encodeShortRepeat(position: Int, probs: UnsafeMutablePointer<UInt16>) {
    let posState = position & ((1 << Self.positionBits) - 1)
    encoder.encode(probs + LZMAModel.isMatch + (state << 4) + posState, bit: 1)
    encoder.encode(probs + LZMAModel.isRep + state, bit: 1)
    encoder.encode(probs + LZMAModel.isRepG0 + state, bit: 0)
    encoder.encode(probs + LZMAModel.isRepLong + (state << 4) + posState, bit: 0)
    state = state < 7 ? 9 : 11
  }

  private func encodeLength(_ length: Int, table: UnsafeMutablePointer<UInt16>, posState: Int) {
    if length < 8 {
      encoder.encode(table, bit: 0)
      encoder.encodeBitTree(table + 2 + posState * 8, bits: 3, symbol: length)
    } else if length < 16 {
      encoder.encode(table, bit: 1)
      encoder.encode(table + 1, bit: 0)
      encoder.encodeBitTree(table + 130 + posState * 8, bits: 3, symbol: length - 8)
    } else {
      encoder.encode(table, bit: 1)
      encoder.encode(table + 1, bit: 1)
      encoder.encodeBitTree(table + 258, bits: 8, symbol: length - 16)
    }
  }

  /// Writes a distance as stored by LZMA: the distance minus one.
  private func encodeDistance(_ distance: Int, length: Int, probs: UnsafeMutablePointer<UInt16>) {
    let slot: Int
    if distance < 4 {
      slot = distance
    } else {
      let top = Int.bitWidth - 1 - distance.leadingZeroBitCount
      slot = top * 2 + ((distance >> (top - 1)) & 1)
    }
    encoder.encodeBitTree(
      probs + LZMAModel.posSlot + min(length, 3) * 64, bits: 6, symbol: slot)
    guard slot >= 4 else { return }
    let footerBits = (slot >> 1) - 1
    let base = (2 | (slot & 1)) << footerBits
    let reduced = distance - base
    if slot < 14 {
      encoder.encodeReverseBitTree(
        probs + LZMAModel.posSpecial + base - slot - 1, bits: footerBits, symbol: reduced)
    } else {
      encoder.encodeDirect(reduced >> 4, bits: footerBits - 4)
      encoder.encodeReverseBitTree(probs + LZMAModel.align, bits: 4, symbol: reduced & 15)
    }
  }
}

/// Writes LZMA2 streams: chunks of LZMA, or of stored bytes where LZMA does not help.
enum LZMA2Encoder {

  /// The uncompressed size of one chunk. Small enough that the packed chunk stays within the
  /// 64 KiB the format allows even for incompressible input.
  private static let chunkSize = 1 << 15

  /// The LZMA2 stream for `content`, with the dictionary size byte of the xz filter properties.
  static func encode(_ content: [UInt8]) -> (stream: [UInt8], dictionaryProperty: UInt8) {
    let window = LZMAEncoder.dictionarySize(for: content.count)
    var stream: [UInt8] = []
    content.withUnsafeBufferPointer { buffer in
      let encoder = LZMAEncoder(input: buffer, window: window)
      var offset = 0
      var first = true
      var needProperties = true
      var needStateReset = false
      while offset < buffer.count {
        let end = min(buffer.count, offset + chunkSize)
        let size = end - offset
        encoder.resetRangeCoder()
        encoder.encode(from: offset, to: end)
        let packed = encoder.finishRangeCoder()
        if packed.count < size {
          var control: UInt8 = 0x80
          if first {
            control = 0xE0
          } else if needProperties {
            control = 0xC0
          } else if needStateReset {
            control = 0xA0
          }
          stream.append(control | UInt8((size - 1) >> 16))
          stream.append(UInt8(((size - 1) >> 8) & 0xFF))
          stream.append(UInt8((size - 1) & 0xFF))
          stream.append(UInt8((packed.count - 1) >> 8))
          stream.append(UInt8((packed.count - 1) & 0xFF))
          if control >= 0xC0 { stream.append(LZMAEncoder.propertiesByte) }
          stream += packed
          needProperties = false
          needStateReset = false
        } else {
          stream.append(first ? 0x01 : 0x02)
          stream.append(UInt8((size - 1) >> 8))
          stream.append(UInt8((size - 1) & 0xFF))
          stream += buffer[offset..<end]
          if first { needProperties = true }
          needStateReset = true
          encoder.resetModel()
        }
        first = false
        offset = end
      }
    }
    stream.append(0x00)
    return (stream, dictionaryProperty(for: window))
  }

  /// The smallest xz dictionary size byte that covers `size` bytes.
  static func dictionaryProperty(for size: Int) -> UInt8 {
    for property in 0...39 {
      let candidate = (2 | (property & 1)) << (property / 2 + 11)
      if candidate >= size { return UInt8(property) }
    }
    return 40
  }
}

extension LZMACodec {

  /// A `.lzma` file holding `data`: the 13-byte header with the exact size, then one LZMA stream
  /// without an end marker.
  public static func compress(_ data: Data) throws -> Data {
    let content = [UInt8](data)
    let window = LZMAEncoder.dictionarySize(for: content.count)
    var output: [UInt8] = [LZMAEncoder.propertiesByte]
    output += LittleEndian.bytes(UInt32(window))
    output += LittleEndian.bytes(UInt64(content.count))
    content.withUnsafeBufferPointer { buffer in
      let encoder = LZMAEncoder(input: buffer, window: window)
      encoder.resetRangeCoder()
      encoder.encode(from: 0, to: buffer.count)
      output += encoder.finishRangeCoder()
    }
    return Data(output)
  }

  /// A raw LZMA stream for the 7z coder `030101`, with its five property bytes.
  static func encodeRaw(_ content: [UInt8]) -> (stream: [UInt8], properties: [UInt8]) {
    let window = LZMAEncoder.dictionarySize(for: content.count)
    var stream: [UInt8] = []
    content.withUnsafeBufferPointer { buffer in
      let encoder = LZMAEncoder(input: buffer, window: window)
      encoder.resetRangeCoder()
      encoder.encode(from: 0, to: buffer.count)
      stream = encoder.finishRangeCoder()
    }
    return (stream, [LZMAEncoder.propertiesByte] + LittleEndian.bytes(UInt32(window)))
  }
}
