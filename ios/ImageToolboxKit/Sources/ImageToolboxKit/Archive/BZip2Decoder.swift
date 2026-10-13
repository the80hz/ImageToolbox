import Foundation

/// A most-significant-bit-first reader over a byte buffer, as bzip2 packs its bits.
struct BZip2BitReader {
  private let bytes: UnsafeBufferPointer<UInt8>
  private(set) var position: Int
  private var buffer: UInt64 = 0
  private var bitCount = 0

  init(bytes: UnsafeBufferPointer<UInt8>, position: Int) {
    self.bytes = bytes
    self.position = position
  }

  /// The index of the first byte that has not been touched by a read.
  var bytePosition: Int { position - bitCount / 8 }

  @inline(__always)
  private mutating func fill() {
    while bitCount <= 56 && position < bytes.count {
      buffer |= UInt64(bytes[position]) << UInt64(56 - bitCount)
      bitCount += 8
      position += 1
    }
  }

  /// The next `count` bits, at most 32, without consuming them. Missing bits read as zero.
  @inline(__always)
  mutating func peek(_ count: Int) -> Int {
    if bitCount < count { fill() }
    return Int(buffer >> UInt64(64 - count))
  }

  /// Consumes `count` bits that `peek` showed. Returns false when fewer were left.
  @inline(__always)
  mutating func skip(_ count: Int) -> Bool {
    guard bitCount >= count else { return false }
    buffer <<= UInt64(count)
    bitCount -= count
    return true
  }

  @inline(__always)
  mutating func read(_ count: Int) throws -> Int {
    let value = peek(count)
    guard skip(count) else { throw ArchiveCodecError.malformed }
    return value
  }

  /// Drops the bits up to the next byte boundary.
  mutating func alignToByte() {
    _ = skip(bitCount % 8)
  }
}

/// A canonical Huffman code of bzip2: shorter codes first, equal lengths in symbol order.
struct BZip2HuffmanTable {
  private static let maximumLength = 20

  private var limit = [Int](repeating: 0, count: maximumLength + 2)
  private var firstCode = [Int](repeating: 0, count: maximumLength + 2)
  private var offset = [Int](repeating: 0, count: maximumLength + 2)
  private var permutation: [UInt16] = []
  private var minimumLength = maximumLength
  private var maximumUsedLength = 1

  init(lengths: [UInt8]) {
    var counts = [Int](repeating: 0, count: Self.maximumLength + 2)
    for length in lengths { counts[Int(length)] += 1 }
    minimumLength = lengths.min().map(Int.init) ?? 1
    maximumUsedLength = lengths.max().map(Int.init) ?? 1
    var code = 0
    var index = 0
    for length in 1...Self.maximumLength {
      firstCode[length] = code
      offset[length] = index
      code += counts[length]
      index += counts[length]
      limit[length] = code << (Self.maximumLength - length)
      code <<= 1
    }
    for length in 1...Self.maximumLength {
      for (symbol, symbolLength) in lengths.enumerated() where Int(symbolLength) == length {
        permutation.append(UInt16(symbol))
      }
    }
  }

  @inline(__always)
  func decode(_ reader: inout BZip2BitReader) throws -> Int {
    let value = reader.peek(Self.maximumLength)
    var length = minimumLength
    while length <= maximumUsedLength {
      if value < limit[length] {
        let code = value >> (Self.maximumLength - length)
        let index = offset[length] + code - firstCode[length]
        guard index >= 0, index < permutation.count, reader.skip(length) else {
          throw ArchiveCodecError.malformed
        }
        return Int(permutation[index])
      }
      length += 1
    }
    throw ArchiveCodecError.malformed
  }
}

/// The bzip2 format: Huffman coded move-to-front symbols of a Burrows-Wheeler transformed block.
public enum BZip2Codec {

  static let blockMagic: UInt64 = 0x3141_5926_5359
  static let endMagic: UInt64 = 0x1772_4538_5090

  /// The content of all bzip2 streams in `data`, one after the other. Bytes after the last
  /// stream that do not start another stream are ignored, as `bzip2` does.
  public static func decompress(
    _ data: Data, maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> Data {
    let bytes = [UInt8](data)
    let sink = ByteSink(limit: maximumOutputSize)
    try bytes.withUnsafeBufferPointer { buffer in
      var position = 0
      var streams = 0
      while position + 4 <= buffer.count, buffer[position] == 0x42, buffer[position + 1] == 0x5A,
        buffer[position + 2] == 0x68
      {
        position = try decodeStream(buffer, from: position, into: sink)
        streams += 1
      }
      guard streams > 0 else { throw ArchiveCodecError.malformed }
    }
    return sink.data()
  }

  private static func decodeStream(
    _ buffer: UnsafeBufferPointer<UInt8>, from start: Int, into sink: ByteSink
  ) throws -> Int {
    let level = Int(buffer[start + 3]) - 0x30
    guard (1...9).contains(level) else { throw ArchiveCodecError.malformed }
    let maximumBlock = level * 100_000
    var reader = BZip2BitReader(bytes: buffer, position: start + 4)
    var combinedCRC: UInt32 = 0
    var work = [UInt32](repeating: 0, count: maximumBlock)

    while true {
      let magic = UInt64(try reader.read(24)) << 24 | UInt64(try reader.read(24))
      if magic == endMagic {
        let stored = UInt32(try reader.read(32))
        guard stored == combinedCRC else { throw ArchiveCodecError.checksumMismatch }
        reader.alignToByte()
        return reader.bytePosition
      }
      guard magic == blockMagic else { throw ArchiveCodecError.malformed }
      let storedCRC = UInt32(try reader.read(32))
      let blockStart = sink.count
      try decodeBlock(&reader, work: &work, maximumBlock: maximumBlock, into: sink)
      let actual = ArchiveChecksum.bzip2CRC(sink.buffer(from: blockStart, to: sink.count))
      guard actual == storedCRC else { throw ArchiveCodecError.checksumMismatch }
      combinedCRC = (combinedCRC << 1 | combinedCRC >> 31) ^ actual
    }
  }

  private static func decodeBlock(
    _ reader: inout BZip2BitReader, work: inout [UInt32], maximumBlock: Int, into sink: ByteSink
  ) throws {
    guard try reader.read(1) == 0 else { throw ArchiveCodecError.unsupported }
    let originalPointer = try reader.read(24)

    // The bytes that occur in the block.
    let usedGroups = try reader.read(16)
    var usedBytes: [UInt8] = []
    for group in 0..<16 where usedGroups & (0x8000 >> group) != 0 {
      let mask = try reader.read(16)
      for bit in 0..<16 where mask & (0x8000 >> bit) != 0 {
        usedBytes.append(UInt8(group * 16 + bit))
      }
    }
    guard !usedBytes.isEmpty else { throw ArchiveCodecError.malformed }
    let alphabetSize = usedBytes.count + 2

    // The table to use for each group of fifty symbols.
    let tableCount = try reader.read(3)
    guard (2...6).contains(tableCount) else { throw ArchiveCodecError.malformed }
    let selectorCount = try reader.read(15)
    guard selectorCount >= 1 else { throw ArchiveCodecError.malformed }
    var order = Array(0..<UInt8(tableCount))
    var selectors: [UInt8] = []
    selectors.reserveCapacity(selectorCount)
    for _ in 0..<selectorCount {
      var index = 0
      while try reader.read(1) == 1 {
        index += 1
        guard index < tableCount else { throw ArchiveCodecError.malformed }
      }
      let table = order.remove(at: index)
      order.insert(table, at: 0)
      selectors.append(table)
    }

    // The code lengths of each table, delta coded.
    var tables: [BZip2HuffmanTable] = []
    for _ in 0..<tableCount {
      var length = try reader.read(5)
      var lengths = [UInt8](repeating: 0, count: alphabetSize)
      for symbol in 0..<alphabetSize {
        while true {
          guard (1...20).contains(length) else { throw ArchiveCodecError.malformed }
          if try reader.read(1) == 0 { break }
          length += try reader.read(1) == 0 ? 1 : -1
        }
        lengths[symbol] = UInt8(length)
      }
      tables.append(BZip2HuffmanTable(lengths: lengths))
    }

    // The symbols: run-length coded zeros (RUNA, RUNB) and move-to-front positions.
    let endOfBlock = alphabetSize - 1
    var front = [UInt8](repeating: 0, count: 256)
    for index in 0..<usedBytes.count { front[index] = UInt8(index) }
    var counts = [Int](repeating: 0, count: 256)
    var length = 0
    var selectorIndex = 0
    var remainingInGroup = 0
    var table = tables[0]
    var run = 0
    var runWeight = 1

    try work.withUnsafeMutableBufferPointer { block in
      while true {
        if remainingInGroup == 0 {
          guard selectorIndex < selectors.count else { throw ArchiveCodecError.malformed }
          table = tables[Int(selectors[selectorIndex])]
          selectorIndex += 1
          remainingInGroup = 50
        }
        remainingInGroup -= 1
        let symbol = try table.decode(&reader)

        if symbol <= 1 {
          run += runWeight << symbol
          runWeight <<= 1
          guard run <= maximumBlock else { throw ArchiveCodecError.malformed }
          continue
        }
        if run > 0 {
          let byte = usedBytes[Int(front[0])]
          guard length + run <= maximumBlock else { throw ArchiveCodecError.malformed }
          counts[Int(byte)] += run
          for _ in 0..<run {
            block[length] = UInt32(byte)
            length += 1
          }
          run = 0
          runWeight = 1
        }
        if symbol == endOfBlock { break }

        let position = symbol - 1
        guard position < usedBytes.count, length < maximumBlock else {
          throw ArchiveCodecError.malformed
        }
        let index = front[position]
        var move = position
        while move > 0 {
          front[move] = front[move - 1]
          move -= 1
        }
        front[0] = index
        let byte = usedBytes[Int(index)]
        block[length] = UInt32(byte)
        counts[Int(byte)] += 1
        length += 1
      }

      guard originalPointer < length else { throw ArchiveCodecError.malformed }

      // Inverse Burrows-Wheeler transform: link every byte to its successor.
      var starts = [Int](repeating: 0, count: 256)
      var total = 0
      for index in 0..<256 {
        starts[index] = total
        total += counts[index]
      }
      for index in 0..<length {
        let byte = Int(block[index] & 0xFF)
        block[starts[byte]] |= UInt32(index) << 8
        starts[byte] += 1
      }

      // Walk the links and undo the initial run-length coding: four equal bytes are followed by
      // the number of further repeats.
      try sink.reserve(length)
      var cursor = Int(block[originalPointer] >> 8)
      var previous = -1
      var equal = 0
      for _ in 0..<length {
        let entry = block[cursor]
        cursor = Int(entry >> 8)
        let byte = Int(entry & 0xFF)
        if equal == 4 {
          try sink.append(repeating: UInt8(previous), count: byte)
          equal = 0
          previous = -1
        } else {
          if byte == previous {
            equal += 1
          } else {
            equal = 1
            previous = byte
          }
          try sink.append(UInt8(byte))
        }
      }
      try sink.checkLimit()
    }
  }
}
