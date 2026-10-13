import Compression
import Foundation

/// Reads entries of a zip archive from memory. Entries stored without compression, deflated with
/// the Compression framework, or compressed with bzip2 (12), LZMA (14), zstd (93) or xz (95) are
/// read, from classic and Zip64 archives, with or without a password: WinZip AES (AE-1 and AE-2,
/// 128, 192 and 256 bit) and the traditional PKWARE encryption are decrypted. Split archives and
/// strong (PKWARE certificate) encryption are not.
public enum ZipReader {

  public struct Entry: Equatable, Sendable {
    public let name: String
    public let data: Data

    /// The name after the Android app's path rules (`ZipEntryPath`), or nil when it is not safe to
    /// use as a file name, for example because it leaves the target folder with "..".
    public var safeName: String? { ZipEntryPath.safeName(name) }
  }

  /// An entry as the central directory lists it. Nothing is read or decrypted for this.
  public struct Info: Equatable, Sendable {
    public let name: String
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let isDirectory: Bool
    public let isEncrypted: Bool
  }

  public enum Failure: Error, Equatable {
    /// The data has no end-of-central-directory record, or a record points outside the data.
    case malformed
    /// An entry uses a compression method or feature this reader does not support.
    case unsupported
    /// The archive or an entry is larger than the limits the caller set.
    case tooLarge
  }

  /// Why an encrypted entry could not be read. These are separate from `Failure`, so a caller can
  /// ask for a password and try again.
  public enum PasswordFailure: Error, Equatable {
    /// The entry is encrypted and no password was given.
    case passwordRequired
    /// The password does not match the one the entry was encrypted with.
    case wrongPassword
    /// The decrypted data failed its integrity check. The archive was changed or damaged, or, once
    /// in a long while, the password is wrong although it passed the quick check.
    case authenticationFailed
  }

  /// Whether the entries of an archive are encrypted, and whether this reader can decrypt them.
  public enum EncryptionStatus: Equatable, Sendable {
    case none
    case passwordRequired
    /// Some entry uses an encryption this reader does not know.
    case unsupported
  }

  private static let endOfCentralDirectory: UInt32 = 0x0605_4B50
  private static let centralDirectoryHeader: UInt32 = 0x0201_4B50
  private static let localFileHeader: UInt32 = 0x0403_4B50
  private static let storedMethod: UInt16 = 0
  private static let deflateMethod: UInt16 = 8
  private static let bzip2Method: UInt16 = 12
  private static let lzmaMethod: UInt16 = 14
  private static let zstdMethod: UInt16 = 93
  private static let xzMethod: UInt16 = 95
  /// General purpose flag bit 0: the entry is encrypted.
  private static let encryptedFlag: UInt16 = 0x0001
  /// Bit 3: the sizes and the CRC-32 follow the data. The central directory still holds them.
  private static let dataDescriptorFlag: UInt16 = 0x0008
  /// Bit 6: strong encryption. Bit 13: the local header values are masked.
  private static let strongEncryptionFlags: UInt16 = 0x0040 | 0x2000
  /// Deflate cannot expand data by more than this factor, which bounds the memory a header that
  /// lies about the size can make the reader allocate.
  private static let maximumDeflateRatio: UInt64 = 1032
  /// An entry is held in memory, so one of 2 GiB or more is refused whatever the limits say.
  private static let maximumInMemoryEntrySize = UInt64(Int32.max)

  // MARK: - Reading

  /// The entries whose names `include` accepts, in central-directory order. Directories are
  /// skipped.
  /// - Parameters:
  ///   - password: used for encrypted entries. Without one an encrypted entry throws
  ///     `PasswordFailure.passwordRequired`.
  ///   - maximumEntries: the most entries the archive may list. More than that is an error.
  ///   - maximumEntrySize: the largest uncompressed size of an entry that is read.
  public static func entries(
    in data: Data,
    password: String? = nil,
    maximumEntries: Int = 128,
    maximumEntrySize: Int = 2 * 1024 * 1024,
    include: (String) -> Bool
  ) throws -> [Entry] {
    let limits = ZipLimits(
      maximumEntries: maximumEntries,
      maximumEntrySize: UInt64(max(0, maximumEntrySize)),
      maximumTotalSize: .max)
    return try entries(in: data, password: password, limits: limits, include: include)
  }

  /// The same, with the limits as one value, for example `ZipLimits.android`. The entry count
  /// covers every record, as in the Android app. The per-entry and total size limits cover the
  /// entries that are read: a skipped entry is never decompressed, so its size costs nothing here.
  public static func entries(
    in data: Data,
    password: String? = nil,
    limits: ZipLimits,
    include: (String) -> Bool
  ) throws -> [Entry] {
    let passwordBytes = passwordBytes(password)
    return try data.withUnsafeBytes { buffer in
      let reader = ZipByteReader(bytes: buffer)
      var entries: [Entry] = []
      var total: UInt64 = 0
      for record in try records(in: reader, maximumEntries: limits.maximumEntries) {
        if record.isDirectory || !include(record.name) { continue }
        guard record.uncompressedSize <= limits.maximumEntrySize else { throw Failure.tooLarge }
        let (sum, overflow) = total.addingReportingOverflow(record.uncompressedSize)
        guard !overflow, sum <= limits.maximumTotalSize else { throw Failure.tooLarge }
        total = sum
        let bytes = try decodedContent(of: record, in: reader, password: passwordBytes)
        entries.append(Entry(name: record.name, data: bytes))
      }
      return entries
    }
  }

  /// Every entry of the central directory, directories included, without reading any data. Like
  /// the Android app's listing, only the entry count is limited.
  public static func list(in data: Data, limits: ZipLimits = .android) throws -> [Info] {
    try data.withUnsafeBytes { buffer in
      try records(in: ZipByteReader(bytes: buffer), maximumEntries: limits.maximumEntries).map {
        Info(
          name: $0.name, compressedSize: $0.compressedSize,
          uncompressedSize: $0.uncompressedSize, isDirectory: $0.isDirectory,
          isEncrypted: $0.protection != .none)
      }
    }
  }

  /// Whether any entry is encrypted. Directories do not count.
  public static func encryptionStatus(of data: Data) throws -> EncryptionStatus {
    try data.withUnsafeBytes { buffer in
      let files = try records(in: ZipByteReader(bytes: buffer), maximumEntries: .max)
        .filter { !$0.isDirectory }
      if files.contains(where: { $0.protection == .unsupported }) { return .unsupported }
      return files.contains(where: { $0.protection != .none }) ? .passwordRequired : .none
    }
  }

  /// Whether the password opens the archive, judged on the first encrypted file only, as the
  /// Android app does. WinZip AES is checked with its password verifier and the authentication
  /// code of that entry. The traditional encryption has a one-byte check, so a wrong password
  /// passes it once in 256 times. An archive without encrypted files accepts any password, and an
  /// empty password never matches.
  public static func isPasswordCorrect(_ password: String, in data: Data) throws -> Bool {
    guard let passwordBytes = passwordBytes(password) else { return false }
    return try data.withUnsafeBytes { buffer in
      let reader = ZipByteReader(bytes: buffer)
      let all = try records(in: reader, maximumEntries: .max)
      guard let record = all.first(where: { !$0.isDirectory && $0.protection != .none }) else {
        return true
      }
      let payload = try payloadSlice(of: record, in: reader)
      switch record.protection {
      case .none:
        return true
      case .unsupported:
        throw Failure.unsupported
      case .traditional:
        let check = ZipCrypto.checkByte(
          crc: record.crc, modifiedTime: record.modifiedTime,
          hasDataDescriptor: record.flags & dataDescriptorFlag != 0)
        return ZipCrypto.passwordMatches(header: payload, password: passwordBytes, checkByte: check)
      case .aes(let header):
        do {
          _ = try ZipAES.open(payload, password: passwordBytes, strength: header.strength)
          return true
        } catch ZipReader.PasswordFailure.wrongPassword {
          return false
        } catch ZipReader.PasswordFailure.authenticationFailed {
          return false
        } catch is ZipAES.KeyFailure {
          throw Failure.unsupported
        }
      }
    }
  }

  private static func passwordBytes(_ password: String?) -> [UInt8]? {
    guard let password, !password.isEmpty else { return nil }
    return Array(password.utf8)
  }

  // MARK: - Central directory

  /// How the data of an entry is protected.
  private enum Protection: Equatable {
    case none
    case traditional
    case aes(ZipAES.Header)
    case unsupported
  }

  private struct Record {
    let name: String
    let flags: UInt16
    /// The method field of the entry. It is 99 for WinZip AES.
    let method: UInt16
    let modifiedTime: UInt16
    let crc: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localOffset: UInt64
    let protection: Protection

    var isDirectory: Bool { name.hasSuffix("/") }
  }

  /// All records of the central directory, in order. More than `maximumEntries` is an error.
  private static func records(in reader: ZipByteReader, maximumEntries: Int) throws -> [Record] {
    let directory = try locateDirectory(in: reader)
    guard directory.count <= UInt64(max(0, maximumEntries)) else { throw Failure.tooLarge }
    // A record takes at least 46 bytes, so a larger count cannot be true.
    guard directory.count <= UInt64(reader.count / 46) else { throw Failure.malformed }

    var records: [Record] = []
    records.reserveCapacity(Int(directory.count))
    var offset = directory.offset
    for _ in 0..<directory.count {
      let (record, next) = try readRecord(at: offset, in: reader)
      records.append(record)
      offset = next
    }
    return records
  }

  /// The number of entries and the offset of the central directory. The end record is searched in
  /// the last 64 KiB, where the archive comment can push it. Its fields hold the markers 0xFFFF or
  /// 0xFFFFFFFF when the Zip64 end record has the real values.
  private static func locateDirectory(
    in reader: ZipByteReader
  ) throws -> (count: UInt64, offset: Int) {
    let lowest = max(0, reader.count - 22 - 65535)
    var end = reader.count - 22
    while end >= lowest {
      if try reader.uint32(end) == endOfCentralDirectory {
        let commentLength = Int(try reader.uint16(end + 20))
        if end + 22 + commentLength <= reader.count { break }
      }
      end -= 1
    }
    guard end >= lowest else { throw Failure.malformed }

    let disk = try reader.uint16(end + 4)
    let directoryDisk = try reader.uint16(end + 6)
    var count = UInt64(try reader.uint16(end + 10))
    var offset = UInt64(try reader.uint32(end + 16))
    let directorySize = UInt64(try reader.uint32(end + 12))
    let hasMarker =
      count == UInt64(Zip64.marker16) || directorySize == UInt64(Zip64.marker32)
      || offset == UInt64(Zip64.marker32)
    if hasMarker, let zip64 = try Zip64.endRecord(in: reader, classicEnd: end) {
      if count == UInt64(Zip64.marker16) { count = zip64.entryCount }
      if offset == UInt64(Zip64.marker32) { offset = zip64.directoryOffset }
    } else if directorySize == UInt64(Zip64.marker32) || offset == UInt64(Zip64.marker32) {
      throw Failure.malformed
    } else if disk != 0 || directoryDisk != 0 {
      throw Failure.unsupported
    }
    return (count, try ZipByteReader.int(offset))
  }

  /// The record at `offset` and the offset of the next one.
  private static func readRecord(
    at offset: Int, in reader: ZipByteReader
  ) throws -> (record: Record, next: Int) {
    guard try reader.uint32(offset) == centralDirectoryHeader else { throw Failure.malformed }
    let flags = try reader.uint16(offset + 8)
    let method = try reader.uint16(offset + 10)
    let nameLength = Int(try reader.uint16(offset + 28))
    let extraLength = Int(try reader.uint16(offset + 30))
    let commentLength = Int(try reader.uint16(offset + 32))
    let nameBytes = try reader.slice(offset + 46, nameLength)
    let extra = try reader.slice(offset + 46 + nameLength, extraLength)

    let fields = try Zip64.resolve(
      uncompressedSize: try reader.uint32(offset + 24),
      compressedSize: try reader.uint32(offset + 20),
      localOffset: try reader.uint32(offset + 42),
      disk: try reader.uint16(offset + 34),
      extra: extra)
    let record = Record(
      name: String(decoding: nameBytes, as: UTF8.self),
      flags: flags,
      method: method,
      modifiedTime: try reader.uint16(offset + 12),
      crc: try reader.uint32(offset + 16),
      compressedSize: fields.compressedSize,
      uncompressedSize: fields.uncompressedSize,
      localOffset: fields.localOffset,
      protection: protection(flags: flags, method: method, extra: extra))
    return (record, offset + 46 + nameLength + extraLength + commentLength)
  }

  private static func protection(
    flags: UInt16, method: UInt16, extra: UnsafeRawBufferPointer
  ) -> Protection {
    if method == ZipAES.methodMarker {
      let field = ZipExtra.fields(in: extra).first { $0.id == ZipAES.extraFieldID }
      guard let field, let header = ZipAES.Header(fieldData: field.data) else {
        return .unsupported
      }
      return .aes(header)
    }
    guard flags & encryptedFlag != 0 else { return .none }
    return flags & strongEncryptionFlags == 0 ? .traditional : .unsupported
  }

  // MARK: - Entry data

  /// The stored bytes of an entry, found through its local header.
  private static func payloadSlice(
    of record: Record, in reader: ZipByteReader
  ) throws -> UnsafeRawBufferPointer {
    let offset = try ZipByteReader.int(record.localOffset)
    guard try reader.uint32(offset) == localFileHeader else { throw Failure.malformed }
    let nameLength = Int(try reader.uint16(offset + 26))
    let extraLength = Int(try reader.uint16(offset + 28))
    let start = offset + 30 + nameLength + extraLength
    return try reader.slice(start, try ZipByteReader.int(record.compressedSize))
  }

  /// The decrypted and decompressed content of an entry, checked against its CRC-32.
  private static func decodedContent(
    of record: Record, in reader: ZipByteReader, password: [UInt8]?
  ) throws -> Data {
    guard record.uncompressedSize <= maximumInMemoryEntrySize else { throw Failure.tooLarge }
    let size = try ZipByteReader.int(record.uncompressedSize)
    let payload = try payloadSlice(of: record, in: reader)

    switch record.protection {
    case .unsupported:
      throw Failure.unsupported
    case .none:
      guard isSupported(method: record.method) else { throw Failure.unsupported }
      let data = try decode(method: record.method, payload, size: size)
      guard CRC32.checksum(data) == record.crc else { throw Failure.malformed }
      return data
    case .traditional:
      guard isSupported(method: record.method) else { throw Failure.unsupported }
      guard let password else { throw PasswordFailure.passwordRequired }
      let check = ZipCrypto.checkByte(
        crc: record.crc, modifiedTime: record.modifiedTime,
        hasDataDescriptor: record.flags & dataDescriptorFlag != 0)
      let plain = try ZipCrypto.decrypt(payload, password: password, checkByte: check)
      // The check byte is weak, so a wrong password can still get here. The CRC-32 settles it.
      do {
        let data = try plain.withUnsafeBytes {
          try decode(method: record.method, $0, size: size)
        }
        guard CRC32.checksum(data) == record.crc else { throw Failure.malformed }
        return data
      } catch Failure.malformed {
        throw PasswordFailure.authenticationFailed
      }
    case .aes(let header):
      guard isSupported(method: header.method) else { throw Failure.unsupported }
      guard let password else { throw PasswordFailure.passwordRequired }
      let plain: [UInt8]
      do {
        plain = try ZipAES.open(payload, password: password, strength: header.strength)
      } catch is ZipAES.KeyFailure {
        throw Failure.unsupported
      }
      let data = try plain.withUnsafeBytes { try decode(method: header.method, $0, size: size) }
      // AE-2 stores no CRC-32. The authentication code has already vouched for the data.
      if header.version == .ae1, CRC32.checksum(data) != record.crc { throw Failure.malformed }
      return data
    }
  }

  private static func isSupported(method: UInt16) -> Bool {
    switch method {
    case storedMethod, deflateMethod, bzip2Method, lzmaMethod, zstdMethod, xzMethod: true
    default: false
    }
  }

  private static func decode(
    method: UInt16, _ input: UnsafeRawBufferPointer, size: Int
  ) throws -> Data {
    switch method {
    case storedMethod:
      guard input.count == size else { throw Failure.malformed }
      return Data(input)
    case deflateMethod:
      return try inflate(input, uncompressedSize: size)
    case bzip2Method:
      return try sized(
        codecFailures { try BZip2Codec.decompress(Data(input), maximumOutputSize: size) }, size)
    case lzmaMethod:
      return try sized(lzmaContent(input, size: size), size)
    case zstdMethod:
      return try sized(
        codecFailures { try ZstdCodec.decompress(Data(input), maximumOutputSize: size) }, size)
    case xzMethod:
      return try sized(
        codecFailures { try XZCodec.decompress(Data(input), maximumOutputSize: size) }, size)
    default:
      throw Failure.unsupported
    }
  }

  /// The content of an LZMA entry (method 14): the version, the size of the properties (five),
  /// the five property bytes, then a raw LZMA stream without a header of its own.
  private static func lzmaContent(_ input: UnsafeRawBufferPointer, size: Int) throws -> Data {
    let bytes = Array(input)
    guard bytes.count > 9, Int(bytes[2]) | Int(bytes[3]) << 8 == 5 else {
      throw Failure.malformed
    }
    let properties = Array(bytes[4..<9])
    let stream = Array(bytes[9...])
    return Data(
      try codecFailures {
        try LZMACodec.decodeRaw(
          stream, properties: properties, size: size, maximumOutputSize: size)
      })
  }

  /// Runs a codec from the Archive folder and turns its errors into the reader's own, so a wrong
  /// password is still recognised when the decrypted bytes are not valid.
  private static func codecFailures<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let error as ArchiveCodecError {
      switch error {
      case .unsupported: throw Failure.unsupported
      case .tooLarge: throw Failure.tooLarge
      case .malformed, .checksumMismatch: throw Failure.malformed
      }
    }
  }

  /// The decoded data, which must have exactly the size the entry records.
  private static func sized(_ data: Data, _ size: Int) throws -> Data {
    guard data.count == size else { throw Failure.malformed }
    return data
  }

  /// Zip stores raw deflate data, which is what the Compression framework calls zlib.
  private static func inflate(_ input: UnsafeRawBufferPointer, uncompressedSize: Int) throws -> Data
  {
    guard uncompressedSize > 0 else { return Data() }
    guard let source = input.baseAddress, !input.isEmpty else { throw Failure.malformed }
    guard UInt64(uncompressedSize) <= UInt64(input.count) * maximumDeflateRatio + 1024 else {
      throw Failure.malformed
    }
    var output = Data(count: uncompressedSize)
    let written = output.withUnsafeMutableBytes { destination -> Int in
      guard let target = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
      return compression_decode_buffer(
        target, uncompressedSize, source.assumingMemoryBound(to: UInt8.self), input.count, nil,
        COMPRESSION_ZLIB)
    }
    guard written == uncompressedSize else { throw Failure.malformed }
    return output
  }
}
