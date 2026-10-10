import CryptoKit
import Foundation

/// The xz container (`.xz`) with LZMA2 as the only filter. Reading accepts several blocks, several
/// concatenated streams and the integrity checks none, CRC32, CRC64 and SHA-256. Writing produces
/// one stream with one block and a CRC64 check.
public enum XZCodec {

  private static let headerMagic: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]
  private static let footerMagic: [UInt8] = [0x59, 0x5A]
  private static let lzma2FilterID: UInt64 = 0x21

  private enum Check: Int {
    case none = 0
    case crc32 = 1
    case crc64 = 4
    case sha256 = 10

    var size: Int {
      switch self {
      case .none: 0
      case .crc32: 4
      case .crc64: 8
      case .sha256: 32
      }
    }
  }

  // MARK: - Reading

  /// The content of all streams of an xz file, one after the other.
  public static func decompress(
    _ data: Data, maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> Data {
    let bytes = [UInt8](data)
    let sink = ByteSink(limit: maximumOutputSize)
    var position = 0
    var streams = 0
    while position < bytes.count {
      if streams > 0 {
        // Stream padding: zero bytes, in a multiple of four, between streams.
        var padding = 0
        while position + padding < bytes.count, bytes[position + padding] == 0 { padding += 1 }
        guard padding % 4 == 0 else { throw ArchiveCodecError.malformed }
        position += padding
        if position == bytes.count { break }
      }
      position = try readStream(bytes, from: position, into: sink)
      streams += 1
    }
    guard streams > 0 else { throw ArchiveCodecError.malformed }
    return sink.data()
  }

  private struct BlockRecord {
    let unpaddedSize: UInt64
    let uncompressedSize: UInt64
  }

  private static func readStream(_ bytes: [UInt8], from start: Int, into sink: ByteSink) throws
    -> Int
  {
    guard bytes.count - start >= 12, Array(bytes[start..<(start + 6)]) == headerMagic else {
      throw ArchiveCodecError.malformed
    }
    let flags = Array(bytes[(start + 6)..<(start + 8)])
    guard LittleEndian.uint32(bytes, start + 8) == ArchiveChecksum.crc32(flags) else {
      throw ArchiveCodecError.malformed
    }
    guard flags[0] == 0, flags[1] & 0xF0 == 0 else { throw ArchiveCodecError.malformed }
    guard let check = Check(rawValue: Int(flags[1])) else { throw ArchiveCodecError.unsupported }

    var position = start + 12
    var records: [BlockRecord] = []
    while true {
      guard position < bytes.count else { throw ArchiveCodecError.malformed }
      if bytes[position] == 0 { break }
      let (record, next) = try readBlock(bytes, from: position, check: check, into: sink)
      records.append(record)
      position = next
    }

    // Index.
    let indexStart = position
    position += 1
    let count = try readVarint(bytes, &position)
    guard count == UInt64(records.count) else { throw ArchiveCodecError.malformed }
    for record in records {
      let unpadded = try readVarint(bytes, &position)
      let uncompressed = try readVarint(bytes, &position)
      guard unpadded == record.unpaddedSize, uncompressed == record.uncompressedSize else {
        throw ArchiveCodecError.malformed
      }
    }
    while (position - indexStart) % 4 != 0 {
      guard position < bytes.count, bytes[position] == 0 else { throw ArchiveCodecError.malformed }
      position += 1
    }
    guard position + 4 <= bytes.count,
      LittleEndian.uint32(bytes, position)
        == ArchiveChecksum.crc32(Array(bytes[indexStart..<position]))
    else { throw ArchiveCodecError.malformed }
    let indexSize = position + 4 - indexStart
    position += 4

    // Footer.
    guard position + 12 <= bytes.count else { throw ArchiveCodecError.malformed }
    let footerCRC = LittleEndian.uint32(bytes, position)
    guard footerCRC == ArchiveChecksum.crc32(Array(bytes[(position + 4)..<(position + 10)])),
      Int(LittleEndian.uint32(bytes, position + 4)) + 1 == indexSize / 4,
      Array(bytes[(position + 8)..<(position + 10)]) == flags,
      Array(bytes[(position + 10)..<(position + 12)]) == footerMagic
    else { throw ArchiveCodecError.malformed }
    return position + 12
  }

  private static func readBlock(
    _ bytes: [UInt8], from start: Int, check: Check, into sink: ByteSink
  ) throws -> (BlockRecord, Int) {
    let headerSize = (Int(bytes[start]) + 1) * 4
    guard start + headerSize <= bytes.count, headerSize >= 8 else {
      throw ArchiveCodecError.malformed
    }
    let header = Array(bytes[start..<(start + headerSize)])
    guard
      LittleEndian.uint32(header, headerSize - 4)
        == ArchiveChecksum.crc32(Array(header[0..<(headerSize - 4)]))
    else { throw ArchiveCodecError.malformed }

    let flags = header[1]
    guard flags & 0x3C == 0 else { throw ArchiveCodecError.unsupported }
    var cursor = 2
    var declaredCompressed: UInt64?
    var declaredUncompressed: UInt64?
    if flags & 0x40 != 0 {
      declaredCompressed = try readVarint(header, &cursor, limit: headerSize - 4)
    }
    if flags & 0x80 != 0 {
      declaredUncompressed = try readVarint(header, &cursor, limit: headerSize - 4)
    }
    let filterCount = Int(flags & 3) + 1
    guard filterCount == 1 else { throw ArchiveCodecError.unsupported }
    let filterID = try readVarint(header, &cursor, limit: headerSize - 4)
    let propertySize = try readVarint(header, &cursor, limit: headerSize - 4)
    guard filterID == lzma2FilterID else { throw ArchiveCodecError.unsupported }
    guard propertySize == 1, cursor < headerSize - 4, header[cursor] <= 40 else {
      throw ArchiveCodecError.malformed
    }
    cursor += 1
    guard header[cursor..<(headerSize - 4)].allSatisfy({ $0 == 0 }) else {
      throw ArchiveCodecError.malformed
    }

    let dataStart = start + headerSize
    let blockOutputStart = sink.count
    let dataEnd = try bytes.withUnsafeBufferPointer { buffer in
      try LZMA2Decoder.decode(input: buffer, start: dataStart, end: buffer.count, into: sink)
    }
    let compressedSize = dataEnd - dataStart
    let uncompressedSize = sink.count - blockOutputStart
    if let declaredCompressed, declaredCompressed != UInt64(compressedSize) {
      throw ArchiveCodecError.malformed
    }
    if let declaredUncompressed, declaredUncompressed != UInt64(uncompressedSize) {
      throw ArchiveCodecError.malformed
    }

    var position = dataEnd
    while (position - dataStart) % 4 != 0 {
      guard position < bytes.count, bytes[position] == 0 else { throw ArchiveCodecError.malformed }
      position += 1
    }
    guard position + check.size <= bytes.count else { throw ArchiveCodecError.malformed }
    let content = sink.buffer(from: blockOutputStart, to: sink.count)
    switch check {
    case .none:
      break
    case .crc32:
      guard LittleEndian.uint32(bytes, position) == ArchiveChecksum.crc32(content) else {
        throw ArchiveCodecError.checksumMismatch
      }
    case .crc64:
      guard LittleEndian.uint64(bytes, position) == ArchiveChecksum.crc64(content) else {
        throw ArchiveCodecError.checksumMismatch
      }
    case .sha256:
      let digest = Array(SHA256.hash(data: content))
      guard digest == Array(bytes[position..<(position + 32)]) else {
        throw ArchiveCodecError.checksumMismatch
      }
    }
    position += check.size
    let record = BlockRecord(
      unpaddedSize: UInt64(headerSize + compressedSize + check.size),
      uncompressedSize: UInt64(uncompressedSize))
    return (record, position)
  }

  /// A multibyte integer: seven bits per byte, least significant group first.
  private static func readVarint(_ bytes: [UInt8], _ position: inout Int, limit: Int? = nil) throws
    -> UInt64
  {
    let end = limit ?? bytes.count
    var value: UInt64 = 0
    for index in 0..<9 {
      guard position < end else { throw ArchiveCodecError.malformed }
      let byte = bytes[position]
      position += 1
      value |= UInt64(byte & 0x7F) << UInt64(7 * index)
      if byte & 0x80 == 0 {
        // The last byte of a longer number may not be zero (no padding in the encoding).
        if byte == 0 && index > 0 { throw ArchiveCodecError.malformed }
        return value
      }
    }
    throw ArchiveCodecError.malformed
  }

  // MARK: - Writing

  /// An xz file holding `data`: LZMA2 in one block, checked with CRC64.
  public static func compress(_ data: Data) throws -> Data {
    let content = [UInt8](data)
    var output = headerMagic
    let streamFlags: [UInt8] = [0x00, UInt8(Check.crc64.rawValue)]
    output += streamFlags
    output += LittleEndian.bytes(ArchiveChecksum.crc32(streamFlags))

    var records: [(unpadded: UInt64, uncompressed: UInt64)] = []
    if !content.isEmpty {
      let encoded = LZMA2Encoder.encode(content)
      var header: [UInt8] = [0x02, 0x00, 0x21, 0x01, encoded.dictionaryProperty, 0, 0, 0]
      header += LittleEndian.bytes(ArchiveChecksum.crc32(header))
      output += header
      output += encoded.stream
      let padding = (4 - encoded.stream.count % 4) % 4
      output += [UInt8](repeating: 0, count: padding)
      let check = content.withUnsafeBufferPointer { ArchiveChecksum.crc64($0) }
      output += LittleEndian.bytes(check)
      records.append(
        (UInt64(header.count + encoded.stream.count + 8), UInt64(content.count)))
    }

    var index: [UInt8] = [0x00]
    index += varint(UInt64(records.count))
    for record in records {
      index += varint(record.unpadded)
      index += varint(record.uncompressed)
    }
    while index.count % 4 != 0 { index.append(0) }
    index += LittleEndian.bytes(ArchiveChecksum.crc32(index))
    output += index

    var footer = LittleEndian.bytes(UInt32(index.count / 4 - 1))
    footer += streamFlags
    output += LittleEndian.bytes(ArchiveChecksum.crc32(footer))
    output += footer
    output += footerMagic
    return Data(output)
  }

  private static func varint(_ value: UInt64) -> [UInt8] {
    var result: [UInt8] = []
    var rest = value
    while rest >= 0x80 {
      result.append(UInt8(rest & 0x7F) | 0x80)
      rest >>= 7
    }
    result.append(UInt8(rest))
    return result
  }
}
