import Foundation

/// Reads a bitstream backwards, as the zstd entropy coders write it: the last byte holds a
/// marker bit above the data, and reading starts below that marker and moves toward byte zero.
struct ZstdBackwardReader {
  private let bytes: UnsafeBufferPointer<UInt8>
  /// The number of data bits not read yet. It goes negative when the stream is over-read.
  private(set) var remaining: Int

  /// - Throws: `malformed` when the last byte is zero, so there is no marker.
  init(bytes: UnsafeBufferPointer<UInt8>) throws {
    guard let last = bytes.last, last != 0 else { throw ArchiveCodecError.malformed }
    self.bytes = bytes
    remaining = (bytes.count - 1) * 8 + (7 - last.leadingZeroBitCount)
  }

  /// Whether more bits were consumed than the stream holds.
  var overflowed: Bool { remaining < 0 }

  @inline(__always)
  private func bits(at bitIndex: Int, count: Int) -> UInt64 {
    let byteIndex = bitIndex >> 3
    var word: UInt64 = 0
    var shift: UInt64 = 0
    var index = byteIndex
    while shift < 64 && index < bytes.count {
      word |= UInt64(bytes[index]) << shift
      shift += 8
      index += 1
    }
    return (word >> UInt64(bitIndex & 7)) & ((1 << UInt64(count)) - 1)
  }

  /// The next `count` bits (at most 56) without consuming them. Bits before the start of the
  /// stream read as zero.
  @inline(__always)
  func peek(_ count: Int) -> Int {
    guard count > 0 else { return 0 }
    let start = remaining - count
    let low = max(start, 0)
    let available = remaining - low
    guard available > 0 else { return 0 }
    return Int(bits(at: low, count: available)) << (low - start)
  }

  @inline(__always)
  mutating func consume(_ count: Int) { remaining -= count }

  @inline(__always)
  mutating func read(_ count: Int) -> Int {
    let value = peek(count)
    remaining -= count
    return value
  }
}

/// A forward little-endian bit reader, for the header of an FSE table.
struct ZstdForwardReader {
  private let bytes: UnsafeBufferPointer<UInt8>
  private(set) var bitPosition = 0

  init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

  /// The number of bytes touched so far.
  var consumedBytes: Int { (bitPosition + 7) / 8 }

  mutating func peek(_ count: Int) -> Int {
    var word: UInt64 = 0
    var index = bitPosition >> 3
    var shift: UInt64 = 0
    while shift < 64 && index < bytes.count {
      word |= UInt64(bytes[index]) << shift
      shift += 8
      index += 1
    }
    return Int((word >> UInt64(bitPosition & 7)) & ((1 << UInt64(count)) - 1))
  }

  mutating func skip(_ count: Int) { bitPosition += count }

  /// Whether the reader is past the end of its bytes.
  var overran: Bool { bitPosition > bytes.count * 8 }
}

/// A finite state entropy decoding table.
struct ZstdFSETable {
  var accuracyLog: Int
  var symbols: [UInt8]
  var bitCounts: [UInt8]
  var baselines: [UInt16]

  /// A table with one state that always yields `symbol` and reads no bits.
  static func repeating(_ symbol: UInt8) -> ZstdFSETable {
    ZstdFSETable(accuracyLog: 0, symbols: [symbol], bitCounts: [0], baselines: [0])
  }

  /// Builds the decoding table from normalized counts. A count of -1 stands for a probability
  /// of less than one, and takes one state from the end of the table.
  init(counts: [Int], accuracyLog: Int) throws {
    let size = 1 << accuracyLog
    var symbols = [UInt8](repeating: 0, count: size)
    var next = [Int](repeating: 0, count: counts.count)
    var highThreshold = size - 1
    for (symbol, count) in counts.enumerated() {
      if count == -1 {
        symbols[highThreshold] = UInt8(symbol)
        highThreshold -= 1
        next[symbol] = 1
      } else {
        next[symbol] = count
      }
    }
    let step = (size >> 1) + (size >> 3) + 3
    let mask = size - 1
    var position = 0
    for (symbol, count) in counts.enumerated() where count > 0 {
      for _ in 0..<count {
        symbols[position] = UInt8(symbol)
        repeat { position = (position + step) & mask } while position > highThreshold
      }
    }
    guard position == 0 else { throw ArchiveCodecError.malformed }

    var bitCounts = [UInt8](repeating: 0, count: size)
    var baselines = [UInt16](repeating: 0, count: size)
    for state in 0..<size {
      let symbol = Int(symbols[state])
      let nextState = next[symbol]
      next[symbol] += 1
      let bits = accuracyLog - (Int.bitWidth - 1 - nextState.leadingZeroBitCount)
      bitCounts[state] = UInt8(bits)
      baselines[state] = UInt16(truncatingIfNeeded: (nextState << bits) - size)
    }
    self.accuracyLog = accuracyLog
    self.symbols = symbols
    self.bitCounts = bitCounts
    self.baselines = baselines
  }

  private init(accuracyLog: Int, symbols: [UInt8], bitCounts: [UInt8], baselines: [UInt16]) {
    self.accuracyLog = accuracyLog
    self.symbols = symbols
    self.bitCounts = bitCounts
    self.baselines = baselines
  }

  /// Reads a table description from the start of `bytes`.
  /// - Returns: the table and the number of bytes the description took.
  static func read(
    _ bytes: UnsafeBufferPointer<UInt8>, maximumSymbol: Int, maximumAccuracyLog: Int
  ) throws -> (table: ZstdFSETable, consumed: Int) {
    var reader = ZstdForwardReader(bytes: bytes)
    let accuracyLog = reader.peek(4) + 5
    reader.skip(4)
    guard accuracyLog <= maximumAccuracyLog else { throw ArchiveCodecError.malformed }

    var counts: [Int] = []
    var remaining = (1 << accuracyLog) + 1
    var threshold = 1 << accuracyLog
    var bitCount = accuracyLog + 1
    var previousWasZero = false
    while remaining > 1 && counts.count <= maximumSymbol {
      if previousWasZero {
        var zeros = 0
        while true {
          let repeatFlag = reader.peek(2)
          reader.skip(2)
          zeros += repeatFlag
          if repeatFlag != 3 { break }
          guard zeros <= maximumSymbol + 1 else { throw ArchiveCodecError.malformed }
        }
        guard counts.count + zeros <= maximumSymbol + 1 else { throw ArchiveCodecError.malformed }
        counts += [Int](repeating: 0, count: zeros)
        previousWasZero = false
        continue
      }
      let maximum = (2 * threshold - 1) - remaining
      var count: Int
      let low = reader.peek(bitCount - 1)
      if low < maximum {
        count = low
        reader.skip(bitCount - 1)
      } else {
        count = reader.peek(bitCount)
        if count >= threshold { count -= maximum }
        reader.skip(bitCount)
      }
      count -= 1
      remaining -= abs(count)
      counts.append(count)
      previousWasZero = count == 0
      while remaining < threshold {
        bitCount -= 1
        threshold >>= 1
      }
      guard !reader.overran else { throw ArchiveCodecError.malformed }
    }
    guard remaining == 1, !reader.overran else { throw ArchiveCodecError.malformed }
    return (try ZstdFSETable(counts: counts, accuracyLog: accuracyLog), reader.consumedBytes)
  }
}

/// A Huffman decoding table for literals: every index of `maximumBits` bits maps to a symbol
/// and the number of bits it really used.
struct ZstdHuffmanTable {
  let maximumBits: Int
  private(set) var symbols: [UInt8]
  private(set) var bitCounts: [UInt8]

  /// Builds the table from the weights of the first symbols. The weight of the last symbol is
  /// implied: it completes the code to a power of two.
  init(weights: [UInt8]) throws {
    guard weights.count <= 255 else { throw ArchiveCodecError.malformed }
    var total = 0
    for weight in weights where weight > 0 {
      guard weight <= 11 else { throw ArchiveCodecError.malformed }
      total += 1 << (Int(weight) - 1)
    }
    guard total > 0 else { throw ArchiveCodecError.malformed }
    let bits = Int.bitWidth - 1 - total.leadingZeroBitCount + 1
    guard bits <= 11 else { throw ArchiveCodecError.malformed }
    let rest = (1 << bits) - total
    guard rest > 0, rest & (rest - 1) == 0 else { throw ArchiveCodecError.malformed }
    var allWeights = weights
    allWeights.append(UInt8(Int.bitWidth - 1 - rest.leadingZeroBitCount + 1))

    maximumBits = bits
    var symbols = [UInt8](repeating: 0, count: 1 << bits)
    var bitCounts = [UInt8](repeating: 0, count: 1 << bits)
    var position = 0
    for weight in 1...bits {
      for (symbol, symbolWeight) in allWeights.enumerated() where Int(symbolWeight) == weight {
        let span = 1 << (weight - 1)
        for index in position..<(position + span) {
          symbols[index] = UInt8(symbol)
          bitCounts[index] = UInt8(bits + 1 - weight)
        }
        position += span
      }
    }
    guard position == 1 << bits else { throw ArchiveCodecError.malformed }
    self.symbols = symbols
    self.bitCounts = bitCounts
  }

  /// Reads the tree description at the start of `bytes`.
  /// - Returns: the table and the number of bytes the description took.
  static func read(_ bytes: UnsafeBufferPointer<UInt8>) throws -> (
    table: ZstdHuffmanTable, consumed: Int
  ) {
    guard let header = bytes.first else { throw ArchiveCodecError.malformed }
    var weights: [UInt8] = []
    var consumed: Int
    if header >= 128 {
      let count = Int(header) - 127
      consumed = 1 + (count + 1) / 2
      guard consumed <= bytes.count else { throw ArchiveCodecError.malformed }
      for index in 0..<count {
        let byte = bytes[1 + index / 2]
        weights.append(index % 2 == 0 ? byte >> 4 : byte & 0x0F)
      }
    } else {
      let size = Int(header)
      consumed = 1 + size
      guard size > 0, consumed <= bytes.count else { throw ArchiveCodecError.malformed }
      let compressed = UnsafeBufferPointer(rebasing: bytes[1..<consumed])
      let (table, used) = try ZstdFSETable.read(
        compressed, maximumSymbol: 12, maximumAccuracyLog: 6)
      let stream = UnsafeBufferPointer(rebasing: compressed[used...])
      var reader = try ZstdBackwardReader(bytes: stream)
      var first = reader.read(table.accuracyLog)
      var second = reader.read(table.accuracyLog)
      // Two interleaved states. Updating a state may read past the start of the stream, which
      // means the other state still holds the final symbol.
      while true {
        weights.append(table.symbols[first])
        first = Int(table.baselines[first]) + reader.read(Int(table.bitCounts[first]))
        if reader.overflowed {
          weights.append(table.symbols[second])
          break
        }
        weights.append(table.symbols[second])
        second = Int(table.baselines[second]) + reader.read(Int(table.bitCounts[second]))
        if reader.overflowed {
          weights.append(table.symbols[first])
          break
        }
        guard weights.count <= 255 else { throw ArchiveCodecError.malformed }
      }
    }
    return (try ZstdHuffmanTable(weights: weights), consumed)
  }

  /// Decodes `count` symbols from one stream into `output`.
  func decode(
    stream: UnsafeBufferPointer<UInt8>, count: Int, into output: UnsafeMutablePointer<UInt8>
  ) throws {
    var reader = try ZstdBackwardReader(bytes: stream)
    for index in 0..<count {
      let slot = reader.peek(maximumBits)
      output[index] = symbols[slot]
      reader.consume(Int(bitCounts[slot]))
    }
    guard reader.remaining == 0 else { throw ArchiveCodecError.malformed }
  }
}

/// The predefined distributions and the base values of the sequence codes.
enum ZstdDefaults {

  static let literalLengthCounts = [
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
    -1, -1, -1, -1,
  ]

  static let matchLengthCounts =
    [1, 4, 3, 2, 2, 2, 2, 2, 2] + [Int](repeating: 1, count: 37) + [Int](repeating: -1, count: 7)

  static let offsetCounts = [
    1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
  ]

  static let literalLengthTable = try! ZstdFSETable(counts: literalLengthCounts, accuracyLog: 6)
  static let matchLengthTable = try! ZstdFSETable(counts: matchLengthCounts, accuracyLog: 6)
  static let offsetTable = try! ZstdFSETable(counts: offsetCounts, accuracyLog: 5)

  /// Literal length codes: the smallest length and the extra bits for each code.
  static let literalLengthBase: [Int] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 40, 48, 64,
    128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
  ]
  static let literalLengthBits: [Int] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11,
    12, 13, 14, 15, 16,
  ]

  /// Match length codes: the smallest length and the extra bits for each code.
  static let matchLengthBase: [Int] =
    Array(3...34) + [35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099]
    + [8195, 16387, 32771, 65539]
  static let matchLengthBits: [Int] =
    [Int](repeating: 0, count: 32) + [1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12]
    + [13, 14, 15, 16]
}
