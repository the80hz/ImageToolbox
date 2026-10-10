import Foundation

/// The adaptive binary range decoder of LZMA. Reading past the end of the input feeds zeros and
/// sets `overrun`, so the hot loop needs no error handling; callers check the flag.
struct LZMARangeDecoder {
  var range: UInt32 = 0xFFFF_FFFF
  var code: UInt32 = 0
  let input: UnsafePointer<UInt8>
  var position: Int
  let end: Int
  var overrun = false

  init(input: UnsafePointer<UInt8>, start: Int, end: Int) {
    self.input = input
    position = start
    self.end = end
  }

  /// Reads the five initial bytes. The first must be zero.
  mutating func start() -> Bool {
    guard end - position >= 5, input[position] == 0 else { return false }
    code =
      UInt32(input[position + 1]) << 24 | UInt32(input[position + 2]) << 16
      | UInt32(input[position + 3]) << 8 | UInt32(input[position + 4])
    position += 5
    return true
  }

  @inline(__always)
  mutating func normalize() {
    if range < 1 << 24 {
      range <<= 8
      if position < end {
        code = code << 8 | UInt32(input[position])
        position += 1
      } else {
        code <<= 8
        overrun = true
      }
    }
  }

  @inline(__always)
  mutating func bit(_ probability: UnsafeMutablePointer<UInt16>) -> Int {
    normalize()
    let value = UInt32(probability.pointee)
    let bound = (range >> 11) &* value
    if code < bound {
      range = bound
      probability.pointee = UInt16(truncatingIfNeeded: value + ((2048 - value) >> 5))
      return 0
    }
    range &-= bound
    code &-= bound
    probability.pointee = UInt16(truncatingIfNeeded: value - (value >> 5))
    return 1
  }

  @inline(__always)
  mutating func bitTree(_ probabilities: UnsafeMutablePointer<UInt16>, bits: Int) -> Int {
    var node = 1
    for _ in 0..<bits { node = node << 1 | bit(probabilities + node) }
    return node - (1 << bits)
  }

  @inline(__always)
  mutating func reverseBitTree(_ probabilities: UnsafeMutablePointer<UInt16>, bits: Int) -> Int {
    var node = 1
    var symbol = 0
    for index in 0..<bits {
      let value = bit(probabilities + node)
      node = node << 1 | value
      symbol |= value << index
    }
    return symbol
  }

  @inline(__always)
  mutating func direct(bits: Int) -> Int {
    var result = 0
    for _ in 0..<bits {
      normalize()
      range >>= 1
      if code >= range {
        code &-= range
        result = result << 1 | 1
      } else {
        result <<= 1
      }
    }
    return result
  }
}

/// Where each group of probabilities lives inside the one array the LZMA coders share.
enum LZMAModel {
  static let isMatch = 0
  static let isRep = isMatch + 12 * 16
  static let isRepG0 = isRep + 12
  static let isRepG1 = isRepG0 + 12
  static let isRepG2 = isRepG1 + 12
  static let isRepLong = isRepG2 + 12
  static let posSlot = isRepLong + 12 * 16
  static let posSpecial = posSlot + 4 * 64
  static let align = posSpecial + 115
  static let lengthCoder = align + 16
  static let lengthCoderSize = 2 + 16 * 8 * 2 + 256
  static let repLengthCoder = lengthCoder + lengthCoderSize
  static let literal = repLengthCoder + lengthCoderSize

  /// The longest match, in bytes.
  static let maximumMatch = 273

  /// The number of probabilities for the given literal context and position bits.
  static func size(literalContextBits: Int, literalPositionBits: Int) -> Int {
    literal + (0x300 << (literalContextBits + literalPositionBits))
  }
}

/// The LZMA probability model and the decoder state that survives between LZMA2 chunks.
final class LZMADecoder {

  /// The longest match, in bytes.
  private static let maximumMatch = 273

  private var probabilities: UnsafeMutablePointer<UInt16>
  private var probabilityCount: Int
  private var literalContextBits = 0
  private var literalPositionBits = 0
  private var positionBits = 0
  private var state = 0
  private var rep0 = 0
  private var rep1 = 0
  private var rep2 = 0
  private var rep3 = 0

  /// The result of one call to `decode`.
  struct Outcome {
    /// The input position after the last byte read.
    let position: Int
    /// Whether the stream ended with the end marker before the requested size was reached.
    let sawEndMarker: Bool
    /// Whether the range coder ended in its expected final state (code value zero).
    let cleanEnd: Bool
  }

  init() {
    probabilityCount = LZMAModel.size(literalContextBits: 0, literalPositionBits: 0)
    probabilities = .allocate(capacity: probabilityCount)
  }

  deinit { probabilities.deallocate() }

  /// Sets lc, lp and pb from the packed properties byte and resets the whole model.
  func setProperties(_ byte: UInt8) throws {
    guard byte < 9 * 5 * 5 else { throw ArchiveCodecError.malformed }
    let value = Int(byte)
    literalContextBits = value % 9
    literalPositionBits = value / 9 % 5
    positionBits = value / 45
    let needed = LZMAModel.size(
      literalContextBits: literalContextBits, literalPositionBits: literalPositionBits)
    if needed != probabilityCount {
      probabilities.deallocate()
      probabilityCount = needed
      probabilities = .allocate(capacity: needed)
    }
    resetState()
  }

  var literalPlusContextBits: Int { literalContextBits + literalPositionBits }

  /// Puts every probability back to one half and clears the state and the repeat distances.
  func resetState() {
    probabilities.initialize(repeating: 1024, count: probabilityCount)
    state = 0
    rep0 = 0
    rep1 = 0
    rep2 = 0
    rep3 = 0
  }

  /// Decodes from `input[start..<end]` into `sink`.
  /// - Parameters:
  ///   - dictionaryStart: the sink position of the last dictionary reset. Matches cannot reach
  ///     before it, and the literal context is zero there.
  ///   - produce: the number of bytes to decode, or nil to decode until the end marker.
  func decode(
    input: UnsafePointer<UInt8>, start: Int, end: Int, sink: ByteSink, dictionaryStart: Int,
    produce: Int?
  ) throws -> Outcome {
    var rc = LZMARangeDecoder(input: input, start: start, end: end)
    guard rc.start() else { throw ArchiveCodecError.malformed }

    let probs = probabilities
    var state = self.state
    var rep0 = self.rep0
    var rep1 = self.rep1
    var rep2 = self.rep2
    var rep3 = self.rep3
    let literalBits = literalContextBits
    let literalMask = (1 << literalPositionBits) - 1
    let positionMask = (1 << positionBits) - 1

    var count = sink.count
    try sink.reserveForDecoding()
    var out = sink.base
    var softLimit = sink.capacity - LZMAModel.maximumMatch - 8
    let target = produce.map { count + $0 } ?? Int.max
    var sawEndMarker = false

    while count < target {
      if count >= softLimit {
        if rc.overrun { throw ArchiveCodecError.malformed }
        sink.count = count
        try sink.checkLimit()
        try sink.reserveForDecoding()
        out = sink.base
        softLimit = sink.capacity - LZMAModel.maximumMatch - 8
      }
      let dictionaryPosition = count - dictionaryStart
      let posState = dictionaryPosition & positionMask
      let stateIndex = state << 4 + posState

      if rc.bit(probs + LZMAModel.isMatch + stateIndex) == 0 {
        let previous = dictionaryPosition > 0 ? Int(out[count - 1]) : 0
        let context =
          ((dictionaryPosition & literalMask) << literalBits) + (previous >> (8 - literalBits))
        let table = probs + LZMAModel.literal + 0x300 * context
        var symbol = 1
        if state >= 7 {
          guard rep0 < dictionaryPosition else { throw ArchiveCodecError.malformed }
          var matchByte = Int(out[count - rep0 - 1])
          var offset = 0x100
          repeat {
            matchByte <<= 1
            let matchBit = matchByte & offset
            let value = rc.bit(table + offset + matchBit + symbol)
            symbol = symbol << 1 | value
            offset &= value == 0 ? ~matchBit : matchBit
          } while symbol < 0x100
        } else {
          repeat { symbol = symbol << 1 | rc.bit(table + symbol) } while symbol < 0x100
        }
        out[count] = UInt8(truncatingIfNeeded: symbol)
        count += 1
        state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6)
        continue
      }

      var length: Int
      if rc.bit(probs + LZMAModel.isRep + state) == 0 {
        rep3 = rep2
        rep2 = rep1
        rep1 = rep0
        length = Self.decodeLength(&rc, probs + LZMAModel.lengthCoder, posState: posState)
        state = state < 7 ? 7 : 10
        let slotTable = probs + LZMAModel.posSlot + min(length, 3) * 64
        let slot = rc.bitTree(slotTable, bits: 6)
        if slot < 4 {
          rep0 = slot
        } else {
          let directBits = (slot >> 1) - 1
          var distance = (2 | (slot & 1)) << directBits
          if slot < 14 {
            distance += rc.reverseBitTree(
              probs + LZMAModel.posSpecial + distance - slot - 1, bits: directBits)
          } else {
            distance += rc.direct(bits: directBits - 4) << 4
            distance += rc.reverseBitTree(probs + LZMAModel.align, bits: 4)
          }
          rep0 = distance
          if distance == 0xFFFF_FFFF {
            sawEndMarker = true
            break
          }
        }
      } else {
        guard dictionaryPosition > 0 else { throw ArchiveCodecError.malformed }
        if rc.bit(probs + LZMAModel.isRepG0 + state) == 0 {
          if rc.bit(probs + LZMAModel.isRepLong + stateIndex) == 0 {
            guard rep0 < dictionaryPosition else { throw ArchiveCodecError.malformed }
            state = state < 7 ? 9 : 11
            out[count] = out[count - rep0 - 1]
            count += 1
            continue
          }
        } else {
          let distance: Int
          if rc.bit(probs + LZMAModel.isRepG1 + state) == 0 {
            distance = rep1
          } else {
            if rc.bit(probs + LZMAModel.isRepG2 + state) == 0 {
              distance = rep2
            } else {
              distance = rep3
              rep3 = rep2
            }
            rep2 = rep1
          }
          rep1 = rep0
          rep0 = distance
        }
        length = Self.decodeLength(&rc, probs + LZMAModel.repLengthCoder, posState: posState)
        state = state < 7 ? 8 : 11
      }

      length += 2
      guard rep0 < dictionaryPosition, length <= target - count else {
        throw ArchiveCodecError.malformed
      }
      var source = count - rep0 - 1
      for _ in 0..<length {
        out[count] = out[source]
        count += 1
        source += 1
      }
    }

    rc.normalize()
    guard !rc.overrun else { throw ArchiveCodecError.malformed }
    sink.count = count
    try sink.checkLimit()
    self.state = state
    self.rep0 = rep0
    self.rep1 = rep1
    self.rep2 = rep2
    self.rep3 = rep3
    return Outcome(position: rc.position, sawEndMarker: sawEndMarker, cleanEnd: rc.code == 0)
  }

  @inline(__always)
  private static func decodeLength(
    _ rc: inout LZMARangeDecoder, _ table: UnsafeMutablePointer<UInt16>, posState: Int
  ) -> Int {
    if rc.bit(table) == 0 { return rc.bitTree(table + 2 + posState * 8, bits: 3) }
    if rc.bit(table + 1) == 0 { return 8 + rc.bitTree(table + 130 + posState * 8, bits: 3) }
    return 16 + rc.bitTree(table + 258, bits: 8)
  }
}

/// The LZMA2 chunk framing around LZMA: chunks that reset state, properties or dictionary, and
/// chunks of stored bytes.
enum LZMA2Decoder {

  /// Decodes the chunks that start at `start` until the end byte, and returns the position
  /// after it.
  static func decode(
    input: UnsafeBufferPointer<UInt8>, start: Int, end: Int, into sink: ByteSink
  ) throws -> Int {
    guard let base = input.baseAddress else { throw ArchiveCodecError.malformed }
    let decoder = LZMADecoder()
    var position = start
    var needDictionaryReset = true
    var needProperties = true
    var dictionaryStart = sink.count

    while true {
      guard position < end else { throw ArchiveCodecError.malformed }
      let control = base[position]
      position += 1
      if control == 0 { return position }

      if control >= 0xE0 || control == 1 {
        needProperties = true
        needDictionaryReset = false
        dictionaryStart = sink.count
      } else if needDictionaryReset {
        throw ArchiveCodecError.malformed
      }

      if control >= 0x80 {
        guard position + 4 <= end else { throw ArchiveCodecError.malformed }
        let uncompressed =
          (Int(control & 0x1F) << 16 | Int(base[position]) << 8 | Int(base[position + 1])) + 1
        let compressed = (Int(base[position + 2]) << 8 | Int(base[position + 3])) + 1
        position += 4
        if control >= 0xC0 {
          guard position < end else { throw ArchiveCodecError.malformed }
          try decoder.setProperties(base[position])
          guard decoder.literalPlusContextBits <= 4 else { throw ArchiveCodecError.malformed }
          position += 1
          needProperties = false
        } else if needProperties {
          throw ArchiveCodecError.malformed
        } else if control >= 0xA0 {
          decoder.resetState()
        }
        guard position + compressed <= end else { throw ArchiveCodecError.malformed }
        let outcome = try decoder.decode(
          input: base, start: position, end: position + compressed, sink: sink,
          dictionaryStart: dictionaryStart, produce: uncompressed)
        guard !outcome.sawEndMarker, outcome.position == position + compressed else {
          throw ArchiveCodecError.malformed
        }
        guard outcome.cleanEnd else { throw ArchiveCodecError.malformed }
        position += compressed
      } else {
        guard control <= 2, position + 2 <= end else { throw ArchiveCodecError.malformed }
        let size = (Int(base[position]) << 8 | Int(base[position + 1])) + 1
        position += 2
        guard position + size <= end else { throw ArchiveCodecError.malformed }
        try sink.append(contentsOf: UnsafeBufferPointer(start: base + position, count: size))
        position += size
      }
    }
  }
}

/// The LZMA "alone" file format (`.lzma`) and the raw LZMA streams used inside other containers.
public enum LZMACodec {

  /// Decodes a `.lzma` file: a 13-byte header (properties, dictionary size, size) and one LZMA
  /// stream. The size may be unknown, in which case the stream ends with an end marker.
  public static func decompress(
    _ data: Data, maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> Data {
    let bytes = [UInt8](data)
    guard bytes.count >= 13 else { throw ArchiveCodecError.malformed }
    let size = LittleEndian.uint64(bytes, 5)
    let known = size != UInt64.max
    if known && size > UInt64(maximumOutputSize) { throw ArchiveCodecError.tooLarge }
    let sink = ByteSink(limit: maximumOutputSize)
    let decoder = LZMADecoder()
    try decoder.setProperties(bytes[0])
    try bytes.withUnsafeBufferPointer { buffer in
      let outcome = try decoder.decode(
        input: buffer.baseAddress!, start: 13, end: buffer.count, sink: sink,
        dictionaryStart: 0, produce: known ? Int(size) : nil)
      if !known && !outcome.sawEndMarker { throw ArchiveCodecError.malformed }
    }
    return sink.data()
  }

  /// Decodes a raw LZMA stream whose size is known, as stored by the 7z coder `030101`.
  /// - Parameter properties: the five bytes of the coder: the packed lc/lp/pb byte and the
  ///   dictionary size.
  static func decodeRaw(
    _ input: [UInt8], properties: [UInt8], size: Int, maximumOutputSize: Int
  ) throws -> [UInt8] {
    guard properties.count >= 5 else { throw ArchiveCodecError.malformed }
    guard size <= maximumOutputSize else { throw ArchiveCodecError.tooLarge }
    let sink = ByteSink(limit: maximumOutputSize)
    let decoder = LZMADecoder()
    try decoder.setProperties(properties[0])
    try input.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else { throw ArchiveCodecError.malformed }
      _ = try decoder.decode(
        input: base, start: 0, end: buffer.count, sink: sink, dictionaryStart: 0, produce: size)
    }
    return sink.array()
  }

  /// Decodes a raw LZMA2 stream, as stored by the 7z coder `21`.
  static func decodeLZMA2(_ input: [UInt8], maximumOutputSize: Int) throws -> [UInt8] {
    let sink = ByteSink(limit: maximumOutputSize)
    try input.withUnsafeBufferPointer { buffer in
      _ = try LZMA2Decoder.decode(input: buffer, start: 0, end: buffer.count, into: sink)
    }
    return sink.array()
  }
}
