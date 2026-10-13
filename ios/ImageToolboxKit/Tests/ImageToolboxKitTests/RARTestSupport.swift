import Foundation

@testable import ImageToolboxKit

/// Builds RAR archives from the byte layouts of RAR 4 and RAR 5, so that the reader is tested on
/// bytes no RAR tool wrote. Each archive holds one file, stored without compression.
///
/// RAR 4 layout: a marker block, an archive header, a file header with the file data after it, and
/// an end-of-archive block. The header CRC is the low 16 bits of CRC32 over the block after it.
/// The file CRC is CRC32 of the file data.
///
/// RAR 5 layout: a signature, a main header, a file header with the file data after it, and an
/// end header. The header CRC is CRC32 over the header size and the header. The file CRC is CRC32
/// of the file data.
enum RARArchiveBuilder {

  /// The file time of the RAR 4 file header, 2024-01-01 00:00:00 in DOS form: the date is the high
  /// word and the time the low word.
  private static let dosTime: UInt32 = 0x5821_0000

  // MARK: - RAR 4

  /// A RAR 4 archive with one file, stored with method 0x30.
  static func rar4(name: String, data: Data) -> Data {
    let marker: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    // The archive header has two reserved fields, HighPosAV (2 bytes) and PosAV (4 bytes).
    let mainHeader = rar4Block(type: 0x73, flags: 0x0000, body: [UInt8](repeating: 0, count: 6))
    let nameBytes = Array(name.utf8)
    var fileBody: [UInt8] = []
    fileBody += littleEndian32(UInt32(data.count))  // PACK_SIZE
    fileBody += littleEndian32(UInt32(data.count))  // UNP_SIZE
    fileBody.append(2)  // HOST_OS: Win32
    fileBody += littleEndian32(CRC32.checksum(data))  // FILE_CRC
    fileBody += littleEndian32(dosTime)  // FTIME
    fileBody.append(29)  // UNP_VER: RAR 2.9
    fileBody.append(0x30)  // METHOD: store
    fileBody += littleEndian16(UInt16(nameBytes.count))  // NAME_SIZE
    fileBody += littleEndian32(0x20)  // ATTR: archive
    fileBody += nameBytes
    let fileHeader = rar4Block(type: 0x74, flags: 0x8000, body: fileBody)
    let endBlock = rar4Block(type: 0x7B, flags: 0x4000, body: [])
    var archive = marker
    archive += mainHeader
    archive += fileHeader
    archive += [UInt8](data)
    archive += endBlock
    return Data(archive)
  }

  /// A RAR 4 block: HEAD_CRC, HEAD_TYPE, HEAD_FLAGS, HEAD_SIZE, then the body. HEAD_SIZE counts
  /// the whole block, the CRC field included.
  private static func rar4Block(type: UInt8, flags: UInt16, body: [UInt8]) -> [UInt8] {
    var rest: [UInt8] = [type]
    rest += littleEndian16(flags)
    rest += littleEndian16(UInt16(7 + body.count))
    rest += body
    let crc = UInt16(truncatingIfNeeded: CRC32.checksum(Data(rest)))
    return littleEndian16(crc) + rest
  }

  // MARK: - RAR 5

  /// A RAR 5 archive with one file, stored with method 0 in its compression information.
  static func rar5(name: String, data: Data) -> Data {
    let signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    // The main header holds the archive flags, which are zero here.
    let mainHeader = rar5Block(type: 1, flags: 0, fields: vint(0))
    let nameBytes = Array(name.utf8)
    var fields: [UInt8] = []
    fields += vint(0x0004)  // file flags: CRC32 present
    fields += vint(UInt64(data.count))  // unpacked size
    fields += vint(0o100644)  // attributes: a regular file, mode rw-r--r--
    fields += littleEndian32(CRC32.checksum(data))  // CRC32 of the file data
    fields += vint(0)  // compression information: version 0, method 0 (store)
    fields += vint(1)  // host OS: Unix
    fields += vint(UInt64(nameBytes.count))  // name length
    fields += nameBytes
    let fileHeader = rar5Block(type: 2, flags: 0x0002, dataSize: data.count, fields: fields)
    let endHeader = rar5Block(type: 5, flags: 0x0004, fields: vint(0))
    var archive = signature
    archive += mainHeader
    archive += fileHeader
    archive += [UInt8](data)
    archive += endHeader
    return Data(archive)
  }

  /// A RAR 5 block: the header CRC32, the header size, then the header. The header holds the
  /// type, the flags, the data size when the data area flag is set, and the fields of the type.
  /// The CRC32 covers the header size and the header, not the data area.
  private static func rar5Block(
    type: UInt64, flags: UInt64, dataSize: Int? = nil, fields: [UInt8]
  ) -> [UInt8] {
    var header = vint(type) + vint(flags)
    if let dataSize { header += vint(UInt64(dataSize)) }
    header += fields
    let sized = vint(UInt64(header.count)) + header
    return littleEndian32(CRC32.checksum(Data(sized))) + sized
  }

  // MARK: - Encodings

  /// A variable-length integer: seven bits per byte, least significant group first, with the
  /// high bit set on every byte but the last.
  private static func vint(_ value: UInt64) -> [UInt8] {
    var rest = value
    var bytes: [UInt8] = []
    repeat {
      let group = UInt8(rest & 0x7F)
      rest >>= 7
      bytes.append(rest == 0 ? group : group | 0x80)
    } while rest != 0
    return bytes
  }

  private static func littleEndian16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
  }

  private static func littleEndian32(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
  }
}
