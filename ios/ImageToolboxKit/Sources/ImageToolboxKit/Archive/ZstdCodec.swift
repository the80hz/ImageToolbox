import Foundation

/// Zstandard (RFC 8878) frames. Reading handles raw, run-length and compressed blocks, Huffman
/// and FSE tables, repeat offsets, skippable frames and the content checksum; frames that need a
/// dictionary are refused. Writing produces valid frames of raw and run-length blocks.
public enum ZstdCodec {

  private static let frameMagic: UInt32 = 0xFD2F_B528
  private static let skippableMask: UInt32 = 0xFFFF_FFF0
  private static let skippableMagic: UInt32 = 0x184D_2A50
  private static let maximumBlockSize = 1 << 17

  // MARK: - Reading

  /// The content of all frames in `data`, one after the other.
  public static func decompress(
    _ data: Data, maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> Data {
    let bytes = [UInt8](data)
    let sink = ByteSink(limit: maximumOutputSize)
    try bytes.withUnsafeBufferPointer { buffer in
      var position = 0
      var frames = 0
      while position < buffer.count {
        guard position + 4 <= buffer.count else { throw ArchiveCodecError.malformed }
        let magic = readUInt32(buffer, position)
        if magic & skippableMask == skippableMagic {
          guard position + 8 <= buffer.count else { throw ArchiveCodecError.malformed }
          let size = Int(readUInt32(buffer, position + 4))
          guard size <= buffer.count - position - 8 else { throw ArchiveCodecError.malformed }
          position += 8 + size
        } else if magic == frameMagic {
          var decoder = ZstdFrameDecoder(input: buffer, sink: sink)
          position = try decoder.decodeFrame(at: position)
        } else {
          throw ArchiveCodecError.malformed
        }
        frames += 1
      }
      guard frames > 0 else { throw ArchiveCodecError.malformed }
    }
    return sink.data()
  }

  fileprivate static func readUInt32(_ buffer: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt32
  {
    UInt32(buffer[offset]) | UInt32(buffer[offset + 1]) << 8 | UInt32(buffer[offset + 2]) << 16
      | UInt32(buffer[offset + 3]) << 24
  }

  // MARK: - Writing

  /// A zstd frame holding `data`, with a content checksum. Blocks of one repeated byte are
  /// written as run-length blocks and the others are stored.
  public static func compress(_ data: Data) throws -> Data {
    let content = [UInt8](data)
    var output = LittleEndian.bytes(frameMagic)
    // Descriptor: 4-byte content size (flag 2), checksum on, no dictionary, with a window byte.
    let sizeFlag: UInt8 = content.count < 1 << 32 ? 2 : 3
    output.append(sizeFlag << 6 | 0x04)
    output.append(0x38)  // a window of 128 KiB, the largest block
    if sizeFlag == 2 {
      output += LittleEndian.bytes(UInt32(content.count))
    } else {
      output += LittleEndian.bytes(UInt64(content.count))
    }

    var offset = 0
    repeat {
      let size = min(maximumBlockSize, content.count - offset)
      let last: UInt32 = offset + size >= content.count ? 1 : 0
      let first = size > 0 ? content[offset] : 0
      let isRun = size > 1 && content[offset..<(offset + size)].allSatisfy { $0 == first }
      let kind: UInt32 = isRun ? 1 : 0
      let header = last | kind << 1 | UInt32(size) << 3
      output += [UInt8(header & 0xFF), UInt8((header >> 8) & 0xFF), UInt8(header >> 16)]
      if isRun {
        output.append(first)
      } else {
        output += content[offset..<(offset + size)]
      }
      offset += size
    } while offset < content.count

    let checksum = content.withUnsafeBufferPointer { ArchiveChecksum.xxh64($0) }
    output += LittleEndian.bytes(UInt32(truncatingIfNeeded: checksum))
    return Data(output)
  }
}

/// Decodes one frame into a sink, keeping the tables that later blocks may repeat.
private struct ZstdFrameDecoder {
  private let input: UnsafeBufferPointer<UInt8>
  private let sink: ByteSink

  private var frameStart = 0
  private var repeatOffsets = [1, 4, 8]
  private var huffman: ZstdHuffmanTable?
  private var literalLengthTable: ZstdFSETable?
  private var offsetTable: ZstdFSETable?
  private var matchLengthTable: ZstdFSETable?

  init(input: UnsafeBufferPointer<UInt8>, sink: ByteSink) {
    self.input = input
    self.sink = sink
  }

  /// Decodes the frame that starts at `start` and returns the position after it.
  mutating func decodeFrame(at start: Int) throws -> Int {
    var position = start + 4
    guard position < input.count else { throw ArchiveCodecError.malformed }
    let descriptor = input[position]
    position += 1
    let sizeFlag = Int(descriptor >> 6)
    let singleSegment = descriptor & 0x20 != 0
    let hasChecksum = descriptor & 0x04 != 0
    guard descriptor & 0x08 == 0 else { throw ArchiveCodecError.malformed }
    if !singleSegment { position += 1 }
    let dictionaryBytes = [0, 1, 2, 4][Int(descriptor & 3)]
    guard position + dictionaryBytes <= input.count else { throw ArchiveCodecError.malformed }
    for index in 0..<dictionaryBytes where input[position + index] != 0 {
      throw ArchiveCodecError.unsupported
    }
    position += dictionaryBytes
    let contentSizeBytes = [singleSegment ? 1 : 0, 2, 4, 8][sizeFlag]
    guard position + contentSizeBytes <= input.count else { throw ArchiveCodecError.malformed }
    var declaredSize: UInt64?
    if contentSizeBytes > 0 {
      var value: UInt64 = 0
      for index in 0..<contentSizeBytes {
        value |= UInt64(input[position + index]) << UInt64(8 * index)
      }
      if contentSizeBytes == 2 { value += 256 }
      declaredSize = value
      position += contentSizeBytes
    }
    if let declaredSize, declaredSize > UInt64(sink.limit) { throw ArchiveCodecError.tooLarge }

    frameStart = sink.count
    var last = false
    while !last {
      guard position + 3 <= input.count else { throw ArchiveCodecError.malformed }
      let header =
        Int(input[position]) | Int(input[position + 1]) << 8
        | Int(input[position + 2]) << 16
      position += 3
      last = header & 1 == 1
      let size = header >> 3
      switch (header >> 1) & 3 {
      case 0:
        guard size <= 1 << 17, position + size <= input.count else {
          throw ArchiveCodecError.malformed
        }
        try sink.append(
          contentsOf: UnsafeBufferPointer(rebasing: input[position..<(position + size)]))
        position += size
      case 1:
        guard size <= 1 << 17, position < input.count else { throw ArchiveCodecError.malformed }
        try sink.append(repeating: input[position], count: size)
        position += 1
      case 2:
        guard size <= 1 << 17, position + size <= input.count else {
          throw ArchiveCodecError.malformed
        }
        try decodeCompressedBlock(
          UnsafeBufferPointer(rebasing: input[position..<(position + size)]))
        position += size
      default:
        throw ArchiveCodecError.malformed
      }
      try sink.checkLimit()
    }

    let produced = sink.count - frameStart
    if let declaredSize, declaredSize != UInt64(produced) { throw ArchiveCodecError.malformed }
    if hasChecksum {
      guard position + 4 <= input.count else { throw ArchiveCodecError.malformed }
      let stored = ZstdCodec.readUInt32(input, position)
      let actual = ArchiveChecksum.xxh64(sink.buffer(from: frameStart, to: sink.count))
      guard stored == UInt32(truncatingIfNeeded: actual) else {
        throw ArchiveCodecError.checksumMismatch
      }
      position += 4
    }
    return position
  }

  // MARK: - Compressed blocks

  private mutating func decodeCompressedBlock(_ block: UnsafeBufferPointer<UInt8>) throws {
    var position = 0
    let literals = try decodeLiterals(block, position: &position)

    // Number of sequences.
    guard position < block.count else { throw ArchiveCodecError.malformed }
    var sequenceCount = Int(block[position])
    position += 1
    if sequenceCount == 0 {
      try sink.append(contentsOf: literals)
      return
    }
    if sequenceCount >= 128 {
      if sequenceCount < 255 {
        guard position < block.count else { throw ArchiveCodecError.malformed }
        sequenceCount = ((sequenceCount - 128) << 8) + Int(block[position])
        position += 1
      } else {
        guard position + 2 <= block.count else { throw ArchiveCodecError.malformed }
        sequenceCount = Int(block[position]) + Int(block[position + 1]) << 8 + 0x7F00
        position += 2
      }
    }

    guard position < block.count else { throw ArchiveCodecError.malformed }
    let modes = block[position]
    position += 1
    guard modes & 3 == 0 else { throw ArchiveCodecError.malformed }
    let literalLengths = try readTable(
      mode: Int(modes >> 6), previous: literalLengthTable,
      predefined: ZstdDefaults.literalLengthTable,
      maximumSymbol: 35, maximumAccuracyLog: 9, block: block, position: &position)
    let offsets = try readTable(
      mode: Int((modes >> 4) & 3), previous: offsetTable, predefined: ZstdDefaults.offsetTable,
      maximumSymbol: 31, maximumAccuracyLog: 8, block: block, position: &position)
    let matchLengths = try readTable(
      mode: Int((modes >> 2) & 3), previous: matchLengthTable,
      predefined: ZstdDefaults.matchLengthTable,
      maximumSymbol: 52, maximumAccuracyLog: 9, block: block, position: &position)
    literalLengthTable = literalLengths
    offsetTable = offsets
    matchLengthTable = matchLengths

    var reader = try ZstdBackwardReader(
      bytes: UnsafeBufferPointer(rebasing: block[position...]))
    var literalState = reader.read(literalLengths.accuracyLog)
    var offsetState = reader.read(offsets.accuracyLog)
    var matchState = reader.read(matchLengths.accuracyLog)

    var literalPosition = 0
    for index in 0..<sequenceCount {
      let literalCode = Int(literalLengths.symbols[literalState])
      let offsetCode = Int(offsets.symbols[offsetState])
      let matchCode = Int(matchLengths.symbols[matchState])
      guard literalCode < ZstdDefaults.literalLengthBase.count,
        matchCode < ZstdDefaults.matchLengthBase.count
      else { throw ArchiveCodecError.malformed }

      let offsetValue = (1 << offsetCode) + reader.read(offsetCode)
      let matchLength =
        ZstdDefaults.matchLengthBase[matchCode]
        + reader.read(ZstdDefaults.matchLengthBits[matchCode])
      let literalLength =
        ZstdDefaults.literalLengthBase[literalCode]
        + reader.read(ZstdDefaults.literalLengthBits[literalCode])
      if index + 1 < sequenceCount {
        literalState =
          Int(literalLengths.baselines[literalState])
          + reader.read(Int(literalLengths.bitCounts[literalState]))
        matchState =
          Int(matchLengths.baselines[matchState])
          + reader.read(Int(matchLengths.bitCounts[matchState]))
        offsetState =
          Int(offsets.baselines[offsetState]) + reader.read(Int(offsets.bitCounts[offsetState]))
      }
      guard !reader.overflowed else { throw ArchiveCodecError.malformed }

      // Literals first, then the match.
      guard literalLength <= literals.count - literalPosition else {
        throw ArchiveCodecError.malformed
      }
      try appendLiterals(literals, from: literalPosition, count: literalLength)
      literalPosition += literalLength

      let offset = resolveOffset(offsetValue, literalLength: literalLength)
      guard offset > 0, offset <= sink.count - frameStart else { throw ArchiveCodecError.malformed }
      try sink.appendCopy(distance: offset, length: matchLength)
      try sink.checkLimit()
    }
    guard reader.remaining == 0 else { throw ArchiveCodecError.malformed }
    try appendLiterals(literals, from: literalPosition, count: literals.count - literalPosition)
  }

  private func appendLiterals(_ literals: [UInt8], from start: Int, count: Int) throws {
    try literals.withUnsafeBufferPointer {
      try sink.append(contentsOf: UnsafeBufferPointer(rebasing: $0[start..<(start + count)]))
    }
  }

  /// Turns an offset value into a distance and updates the three most recent offsets.
  private mutating func resolveOffset(_ value: Int, literalLength: Int) -> Int {
    if value > 3 {
      let offset = value - 3
      repeatOffsets = [offset, repeatOffsets[0], repeatOffsets[1]]
      return offset
    }
    let index = value - 1 + (literalLength == 0 ? 1 : 0)
    switch index {
    case 0:
      return repeatOffsets[0]
    case 1:
      let offset = repeatOffsets[1]
      repeatOffsets = [offset, repeatOffsets[0], repeatOffsets[2]]
      return offset
    case 2:
      let offset = repeatOffsets[2]
      repeatOffsets = [offset, repeatOffsets[0], repeatOffsets[1]]
      return offset
    default:
      let offset = repeatOffsets[0] - 1
      repeatOffsets = [offset, repeatOffsets[0], repeatOffsets[1]]
      return offset
    }
  }

  private func readTable(
    mode: Int, previous: ZstdFSETable?, predefined: ZstdFSETable, maximumSymbol: Int,
    maximumAccuracyLog: Int, block: UnsafeBufferPointer<UInt8>, position: inout Int
  ) throws -> ZstdFSETable {
    switch mode {
    case 0:
      return predefined
    case 1:
      guard position < block.count else { throw ArchiveCodecError.malformed }
      let symbol = block[position]
      position += 1
      guard Int(symbol) <= maximumSymbol else { throw ArchiveCodecError.malformed }
      return .repeating(symbol)
    case 2:
      let (table, consumed) = try ZstdFSETable.read(
        UnsafeBufferPointer(rebasing: block[position...]), maximumSymbol: maximumSymbol,
        maximumAccuracyLog: maximumAccuracyLog)
      position += consumed
      return table
    default:
      guard let previous else { throw ArchiveCodecError.malformed }
      return previous
    }
  }

  // MARK: - Literals

  private mutating func decodeLiterals(
    _ block: UnsafeBufferPointer<UInt8>, position: inout Int
  ) throws -> [UInt8] {
    guard position < block.count else { throw ArchiveCodecError.malformed }
    let first = Int(block[position])
    let type = first & 3
    let format = (first >> 2) & 3

    if type < 2 {
      var headerSize = 1
      var regenerated = first >> 3
      if format == 1 {
        headerSize = 2
      } else if format == 3 {
        headerSize = 3
      }
      guard position + headerSize <= block.count else { throw ArchiveCodecError.malformed }
      if headerSize == 2 {
        regenerated = (first | Int(block[position + 1]) << 8) >> 4
      } else if headerSize == 3 {
        regenerated =
          (first | Int(block[position + 1]) << 8 | Int(block[position + 2]) << 16) >> 4
      }
      guard regenerated <= 1 << 17 else { throw ArchiveCodecError.malformed }
      position += headerSize
      if type == 0 {
        guard position + regenerated <= block.count else { throw ArchiveCodecError.malformed }
        let result = Array(block[position..<(position + regenerated)])
        position += regenerated
        return result
      }
      guard position < block.count else { throw ArchiveCodecError.malformed }
      position += 1
      return [UInt8](repeating: block[position - 1], count: regenerated)
    }

    // Huffman coded literals.
    let streams = format == 0 ? 1 : 4
    let headerSize = format <= 1 ? 3 : (format == 2 ? 4 : 5)
    guard position + headerSize <= block.count else { throw ArchiveCodecError.malformed }
    var header: UInt64 = 0
    for index in 0..<headerSize { header |= UInt64(block[position + index]) << UInt64(8 * index) }
    let fieldBits = format == 3 ? 18 : (format == 2 ? 14 : 10)
    let regenerated = Int((header >> 4) & ((1 << UInt64(fieldBits)) - 1))
    let compressed = Int((header >> UInt64(4 + fieldBits)) & ((1 << UInt64(fieldBits)) - 1))
    guard regenerated <= 1 << 17, position + headerSize + compressed <= block.count else {
      throw ArchiveCodecError.malformed
    }
    position += headerSize
    var section = UnsafeBufferPointer(rebasing: block[position..<(position + compressed)])
    position += compressed

    if type == 2 {
      let (table, consumed) = try ZstdHuffmanTable.read(section)
      huffman = table
      section = UnsafeBufferPointer(rebasing: section[consumed...])
    }
    guard let table = huffman else { throw ArchiveCodecError.malformed }

    var output = [UInt8](repeating: 0, count: regenerated)
    guard regenerated > 0 else { throw ArchiveCodecError.malformed }
    try output.withUnsafeMutableBufferPointer { destination in
      let storage = destination.baseAddress!
      if streams == 1 {
        try table.decode(stream: section, count: regenerated, into: storage)
      } else {
        guard section.count >= 6 else { throw ArchiveCodecError.malformed }
        let size1 = Int(section[0]) | Int(section[1]) << 8
        let size2 = Int(section[2]) | Int(section[3]) << 8
        let size3 = Int(section[4]) | Int(section[5]) << 8
        let size4 = section.count - 6 - size1 - size2 - size3
        guard size4 > 0 else { throw ArchiveCodecError.malformed }
        let part = (regenerated + 3) / 4
        guard regenerated >= part * 3 else { throw ArchiveCodecError.malformed }
        var streamStart = 6
        var outputStart = 0
        for (size, count) in [
          (size1, part), (size2, part), (size3, part), (size4, regenerated - 3 * part),
        ] {
          try table.decode(
            stream: UnsafeBufferPointer(rebasing: section[streamStart..<(streamStart + size)]),
            count: count, into: storage + outputStart)
          streamStart += size
          outputStart += count
        }
      }
    }
    return output
  }
}
