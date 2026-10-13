import Foundation

/// Reads and writes 7z archives in memory.
///
/// Reading handles plain and encoded (compressed) headers, solid and non-solid folders, and the
/// coders Copy, LZMA, LZMA2, Deflate, BZip2 and 7zAES, and the filters BCJ (x86) and Delta, alone
/// or chained through bind pairs of one input and one output. An encrypted archive is read with
/// its password. Other filters such as ARM, PPMd and multi-volume archives are refused as
/// unsupported. Writing stores all files in one solid folder, compressed with LZMA2 or, when that
/// does not help, copied, behind a plain header.
public enum SevenZipArchive {

  /// A file of an archive. Directories are not listed.
  public struct Entry: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
      self.name = name
      self.data = data
    }
  }

  /// Why an encrypted archive cannot be read.
  public enum PasswordFailure: Error, Equatable, Sendable {
    /// The archive is encrypted and no password was given.
    case passwordRequired
    /// The decrypted data does not match its checksum. 7z stores no password check, so a wrong
    /// password shows only this way, and damaged data looks the same.
    case wrongPassword
  }

  static let signature: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]

  // Property ids of the header.
  enum Property {
    static let end = 0x00
    static let header = 0x01
    static let archiveProperties = 0x02
    static let additionalStreams = 0x03
    static let mainStreams = 0x04
    static let filesInfo = 0x05
    static let packInfo = 0x06
    static let unpackInfo = 0x07
    static let subStreamsInfo = 0x08
    static let size = 0x09
    static let crc = 0x0A
    static let folder = 0x0B
    static let codersUnpackSize = 0x0C
    static let numUnpackStream = 0x0D
    static let emptyStream = 0x0E
    static let emptyFile = 0x0F
    static let names = 0x11
    static let attributes = 0x15
    static let encodedHeader = 0x17
  }

  // MARK: - Reading

  /// The regular files of an archive, in archive order, with their content.
  /// - Parameters:
  ///   - password: the password of an encrypted archive. Without one, encrypted data is refused
  ///     with `PasswordFailure.passwordRequired`. An empty password counts as none.
  ///   - maximumEntries: the most files an archive may list.
  ///   - maximumOutputSize: the most bytes all decoded files may add up to.
  public static func entries(
    in data: Data, password: String? = nil, maximumEntries: Int = 100_000,
    maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> [Entry] {
    let password = password.flatMap { $0.isEmpty ? nil : $0 }
    let bytes = [UInt8](data)
    guard bytes.count >= 32, Array(bytes[0..<6]) == signature, bytes[6] == 0 else {
      throw ArchiveCodecError.malformed
    }
    guard LittleEndian.uint32(bytes, 8) == ArchiveChecksum.crc32(Array(bytes[12..<32])) else {
      throw ArchiveCodecError.malformed
    }
    let headerOffset = LittleEndian.uint64(bytes, 12)
    let headerSize = LittleEndian.uint64(bytes, 20)
    let headerCRC = LittleEndian.uint32(bytes, 28)
    if headerSize == 0 { return [] }
    guard headerOffset <= UInt64(bytes.count - 32),
      headerSize <= UInt64(bytes.count - 32) - headerOffset
    else { throw ArchiveCodecError.malformed }
    let start = 32 + Int(headerOffset)
    var header = Array(bytes[start..<(start + Int(headerSize))])
    guard ArchiveChecksum.crc32(header) == headerCRC else { throw ArchiveCodecError.malformed }

    var budget = maximumOutputSize
    // A header may itself be stored as a compressed stream, possibly more than once.
    for _ in 0..<4 {
      var cursor = HeaderCursor(bytes: header)
      let kind = try cursor.readNumber()
      if kind == UInt64(Property.header) {
        return try readHeader(
          &cursor, archive: bytes, password: password, budget: &budget,
          maximumEntries: maximumEntries)
      }
      guard kind == UInt64(Property.encodedHeader) else { throw ArchiveCodecError.malformed }
      let streams = try readStreamsInfo(&cursor)
      guard !streams.folders.isEmpty else { throw ArchiveCodecError.malformed }
      header = try unpack(
        folder: 0, of: streams, archive: bytes, password: password, budget: &budget)
    }
    throw ArchiveCodecError.malformed
  }

  private static func readHeader(
    _ cursor: inout HeaderCursor, archive: [UInt8], password: String?, budget: inout Int,
    maximumEntries: Int
  ) throws -> [Entry] {
    var streams = StreamsInfo()
    var files: [FileRecord] = []
    while true {
      let property = Int(try cursor.readNumber())
      switch property {
      case Property.end:
        return try assemble(
          files: files, streams: streams, archive: archive, password: password, budget: &budget)
      case Property.archiveProperties:
        while try cursor.readNumber() != 0 { try cursor.skip(try cursor.readNumber()) }
      case Property.additionalStreams:
        _ = try readStreamsInfo(&cursor)
      case Property.mainStreams:
        streams = try readStreamsInfo(&cursor)
      case Property.filesInfo:
        files = try readFiles(&cursor, maximumEntries: maximumEntries)
      default:
        throw ArchiveCodecError.malformed
      }
    }
  }

  private static func assemble(
    files: [FileRecord], streams: StreamsInfo, archive: [UInt8], password: String?,
    budget: inout Int
  ) throws -> [Entry] {
    var entries: [Entry] = []
    var folderIndex = 0
    var streamIndex = 0
    var folderData: [UInt8] = []
    var folderOffset = 0
    var folderLoaded = false

    for file in files {
      if !file.hasStream {
        // An entry without data is an empty file only when marked so; otherwise a directory.
        let isDirectory = (file.attributes ?? 0) & 0x10 != 0
        if file.isEmptyFile && !isDirectory {
          entries.append(Entry(name: file.name, data: Data()))
        }
        continue
      }
      while folderIndex < streams.subStreams.count
        && streamIndex >= streams.subStreams[folderIndex].count
      {
        folderIndex += 1
        streamIndex = 0
        folderLoaded = false
      }
      guard folderIndex < streams.subStreams.count else { throw ArchiveCodecError.malformed }
      if !folderLoaded {
        folderData = try unpack(
          folder: folderIndex, of: streams, archive: archive, password: password, budget: &budget)
        folderOffset = 0
        folderLoaded = true
      }
      let stream = streams.subStreams[folderIndex][streamIndex]
      guard stream.size <= UInt64(folderData.count - folderOffset) else {
        throw ArchiveCodecError.malformed
      }
      let content = Array(folderData[folderOffset..<(folderOffset + Int(stream.size))])
      if let crc = stream.crc, crc != ArchiveChecksum.crc32(content) {
        if streams.folders[folderIndex].isEncrypted { throw PasswordFailure.wrongPassword }
        throw ArchiveCodecError.checksumMismatch
      }
      folderOffset += content.count
      streamIndex += 1
      entries.append(Entry(name: file.name, data: Data(content)))
    }
    return entries
  }
}
