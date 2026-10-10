import Foundation

/// The file headers of a RAR 4 or RAR 5 archive, read without decoding any data. libarchive does
/// not check the CRC32 of stored files, so `RARReader` compares the data with the CRC that these
/// headers keep. Only the block layout is read here: the header checksums are left to libarchive,
/// which has already accepted the archive when this runs.
enum RARHeaders {

  /// A file or a directory header, in archive order.
  struct FileHeader: Equatable {
    let isDirectory: Bool
    /// The CRC32 of the unpacked data, or nil when the header keeps none.
    let crc: UInt32?
  }

  /// The first six bytes of every RAR signature. The seventh tells RAR 4 (0x00) from RAR 5 (0x01).
  private static let marker: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]

  /// The file headers of the archive in `bytes`, directories included, in the order libarchive
  /// lists them. The packed data of each file is skipped.
  /// - Throws: `RARReader.Failure.malformed` for a block that does not fit in the bytes,
  ///   `.unsupported` for a file split over volumes, and `.encrypted` for encrypted headers.
  static func files(in bytes: [UInt8]) throws -> [FileHeader] {
    guard let start = bytes.firstRange(of: marker)?.upperBound, start < bytes.count else {
      throw RARReader.Failure.malformed
    }
    switch bytes[start] {
    case 0x00:
      return try rar4Files(bytes, from: start + 1)
    case 0x01:
      guard start + 1 < bytes.count, bytes[start + 1] == 0x00 else {
        throw RARReader.Failure.malformed
      }
      return try rar5Files(bytes, from: start + 2)
    default:
      throw RARReader.Failure.malformed
    }
  }

  // MARK: - RAR 4

  /// Blocks of a RAR 4 archive. Each block starts with HEAD_CRC (2 bytes), HEAD_TYPE (1), HEAD_FLAGS
  /// (2) and HEAD_SIZE (2), which counts the whole block. A file header is followed by its packed
  /// data, and a block with the long flag is followed by ADD_SIZE bytes.
  private static func rar4Files(_ bytes: [UInt8], from start: Int) throws -> [FileHeader] {
    var headers: [FileHeader] = []
    var position = start
    while position < bytes.count {
      guard position + 7 <= bytes.count else { throw RARReader.Failure.malformed }
      let type = bytes[position + 2]
      let flags = LittleEndian.uint16(bytes, position + 3)
      let size = LittleEndian.uint16(bytes, position + 5)
      guard size >= 7, size <= bytes.count - position else { throw RARReader.Failure.malformed }
      var next = position + size
      switch type {
      case 0x74:
        // The file header. PACK_SIZE is at offset 7, FILE_CRC at 16, and with the large flag the
        // high half of the packed size follows the attributes at offset 32.
        let large = flags & 0x0100 != 0
        guard size >= (large ? 40 : 32) else { throw RARReader.Failure.malformed }
        var packed = Int(LittleEndian.uint32(bytes, position + 7))
        if large { packed += Int(LittleEndian.uint32(bytes, position + 32)) << 32 }
        // Split files continue in another volume, so no CRC of the file is in this archive.
        guard flags & 0x0003 == 0 else { throw RARReader.Failure.unsupported }
        headers.append(
          FileHeader(
            isDirectory: flags & 0x00E0 == 0x00E0,
            crc: LittleEndian.uint32(bytes, position + 16)))
        next += packed
      case 0x7B:
        return headers
      default:
        if flags & 0x8000 != 0 {
          guard size >= 11 else { throw RARReader.Failure.malformed }
          next += Int(LittleEndian.uint32(bytes, position + 7))
        }
      }
      guard next <= bytes.count else { throw RARReader.Failure.malformed }
      position = next
    }
    return headers
  }

  // MARK: - RAR 5

  /// Blocks of a RAR 5 archive: CRC32 (4 bytes), HeaderSize (a variable-length number), then the
  /// header itself, and after it the data area of DataSize bytes when the flag says so.
  private static func rar5Files(_ bytes: [UInt8], from start: Int) throws -> [FileHeader] {
    var headers: [FileHeader] = []
    var position = start
    while position < bytes.count {
      guard position + 4 < bytes.count else { throw RARReader.Failure.malformed }
      var sizeCursor = Cursor(bytes: bytes, position: position + 4, limit: bytes.count)
      let headerSize = try sizeCursor.number()
      let headerStart = sizeCursor.position
      guard headerSize <= UInt64(bytes.count - headerStart) else {
        throw RARReader.Failure.malformed
      }
      let headerEnd = headerStart + Int(headerSize)
      var cursor = Cursor(bytes: bytes, position: headerStart, limit: headerEnd)
      let type = try cursor.number()
      let flags = try cursor.number()
      if flags & 0x0001 != 0 { _ = try cursor.number() }  // the extra area, after the fields
      var dataSize: UInt64 = 0
      if flags & 0x0002 != 0 { dataSize = try cursor.number() }
      switch type {
      case 2:
        // Split files continue in another volume, so no CRC of the file is in this archive.
        guard flags & 0x0018 == 0 else { throw RARReader.Failure.unsupported }
        headers.append(try fileHeader(&cursor))
      case 4:
        // The headers are encrypted, so the blocks behind this one cannot be read.
        throw RARReader.Failure.encrypted
      case 5:
        return headers
      default:
        break  // the main header and the service headers hold no file
      }
      guard dataSize <= UInt64(bytes.count - headerEnd) else { throw RARReader.Failure.malformed }
      position = headerEnd + Int(dataSize)
    }
    return headers
  }

  /// A RAR 5 file header: the file flags, the unpacked size, the attributes, then the modification
  /// time and the CRC32 when the flags say they are present.
  private static func fileHeader(_ cursor: inout Cursor) throws -> FileHeader {
    let fileFlags = try cursor.number()
    _ = try cursor.number()  // the unpacked size
    _ = try cursor.number()  // the attributes
    if fileFlags & 0x0002 != 0 { _ = try cursor.uint32() }  // the modification time
    var crc: UInt32?
    if fileFlags & 0x0004 != 0 { crc = try cursor.uint32() }
    return FileHeader(isDirectory: fileFlags & 0x0001 != 0, crc: crc)
  }

  /// A reader over the bytes of one RAR 5 header. Reading past `limit` is a malformed header.
  private struct Cursor {
    let bytes: [UInt8]
    var position: Int
    let limit: Int

    mutating func byte() throws -> UInt8 {
      guard position < limit else { throw RARReader.Failure.malformed }
      position += 1
      return bytes[position - 1]
    }

    /// A variable-length number: seven bits per byte, least significant group first, with the high
    /// bit set on every byte but the last.
    mutating func number() throws -> UInt64 {
      var value: UInt64 = 0
      var shift: UInt64 = 0
      while true {
        guard shift < 64 else { throw RARReader.Failure.malformed }
        let next = try byte()
        value |= UInt64(next & 0x7F) << shift
        if next & 0x80 == 0 { return value }
        shift += 7
      }
    }

    mutating func uint32() throws -> UInt32 {
      guard limit - position >= 4 else { throw RARReader.Failure.malformed }
      position += 4
      return LittleEndian.uint32(bytes, position - 4)
    }
  }
}
