import CArchive
import Foundation

/// Reads RAR archives, versions 4 and 5, from memory. The work is done by the system libarchive,
/// which the SDKs link. RAR is read only: the format's encoder belongs to its vendor, so nothing
/// here writes RAR. Encrypted archives are refused, since no password is taken.
public enum RARReader {

  /// A file of an archive. Directories are not listed.
  public struct Entry: Equatable, Sendable {
    public let name: String
    public let data: Data
  }

  /// An entry as its header describes it. Its data is not read.
  public struct Info: Equatable, Sendable {
    public let name: String
    public let uncompressedSize: UInt64
    public let isDirectory: Bool
  }

  public enum Failure: Error, Equatable, Sendable {
    /// The data is not a RAR archive that the system library recognizes.
    case notRAR
    /// The archive is damaged or truncated, or the data of a file does not match the CRC32 that
    /// its header keeps.
    case malformed
    /// The archive or a file in it is encrypted, and this reader takes no password.
    case encrypted
    /// The archive uses a feature the system library does not read, such as several volumes.
    case unsupported
    /// The archive has more entries, or its files add up to more bytes, than the limits allow.
    case tooLarge
  }

  /// The return codes of libarchive, as its archive.h gives them.
  private enum Status {
    static let ok: Int32 = 0
    static let eof: Int32 = 1
    static let warn: Int32 = -20
  }

  /// The file type bits of a mode, and the type of a directory.
  private static let fileTypeMask: mode_t = 0o170000
  private static let directoryType: mode_t = 0o040000
  private static let readChunkSize = 1 << 16
  /// The length of the longest RAR signature, the one of RAR 5.
  private static let signatureLength = 8

  /// The headers of the archive, directories included, without reading any data.
  /// - Parameter maximumEntries: the most headers the archive may have. More than that is an
  ///   error.
  public static func list(in data: Data, maximumEntries: Int = 100_000) throws -> [Info] {
    try withReader(data) { reader in
      var infos: [Info] = []
      while let entry = try nextEntry(reader) {
        guard infos.count < maximumEntries else { throw Failure.tooLarge }
        infos.append(
          Info(
            name: name(of: entry),
            uncompressedSize: UInt64(max(0, archive_entry_size(entry))),
            isDirectory: isDirectory(entry)))
      }
      try requireMainHeader(in: data, headers: infos.count)
      return infos
    }
  }

  /// The files of the archive, with their content, in archive order. Directories are skipped.
  /// Each file is checked against the CRC32 that its header keeps.
  /// - Parameters:
  ///   - maximumEntries: the most headers the archive may have, directories included.
  ///   - maximumOutputSize: the most bytes all the files may add up to.
  public static func entries(
    in data: Data, maximumEntries: Int = 100_000,
    maximumOutputSize: Int = ArchiveCodecLimits.defaultMaximumOutputSize
  ) throws -> [Entry] {
    try withReader(data) { reader in
      var entries: [Entry] = []
      // The CRC32 of each file's data, keyed by the index of its header.
      var checksums: [Int: UInt32] = [:]
      var headers = 0
      var total = 0
      while let entry = try nextEntry(reader) {
        headers += 1
        guard headers <= maximumEntries else { throw Failure.tooLarge }
        let entryName = name(of: entry)
        guard !isDirectory(entry) else { continue }
        let bytes = try content(of: entry, in: reader, budget: maximumOutputSize - total)
        total += bytes.count
        checksums[headers - 1] = ArchiveChecksum.crc32(bytes)
        entries.append(Entry(name: entryName, data: Data(bytes)))
      }
      try requireMainHeader(in: data, headers: headers)
      try requireChecksums(checksums, headers: headers, in: data)
      return entries
    }
  }

  // MARK: - Reading through libarchive

  /// libarchive lists an archive that ends right after its signature as empty. Such a file has
  /// no main header, so it is damaged, and it is refused here.
  private static func requireMainHeader(in data: Data, headers: Int) throws {
    guard headers > 0 || data.count > signatureLength else { throw Failure.malformed }
  }

  /// The data of each file must match the CRC32 that its header keeps. The headers are read again
  /// here, and their count must equal the number libarchive listed, or the files cannot be matched
  /// with their headers.
  private static func requireChecksums(
    _ checksums: [Int: UInt32], headers: Int, in data: Data
  ) throws {
    let stored = try RARHeaders.files(in: [UInt8](data))
    guard stored.count == headers else { throw Failure.malformed }
    for (index, actual) in checksums {
      if let expected = stored[index].crc, expected != actual { throw Failure.malformed }
    }
  }

  /// Runs `body` with a reader over `data`. The reader is closed and freed afterwards.
  private static func withReader<T>(_ data: Data, _ body: (OpaquePointer) throws -> T) throws -> T {
    guard !data.isEmpty else { throw Failure.notRAR }
    return try data.withUnsafeBytes { bytes in
      // A null reader means the library could not allocate one, so the archive cannot be read.
      guard let reader = archive_read_new() else { throw Failure.unsupported }
      defer {
        _ = archive_read_close(reader)
        _ = archive_read_free(reader)
      }
      // Only RAR formats are enabled. The filters include the pass-through that plain data needs.
      guard archive_read_support_format_rar(reader) == Status.ok,
        archive_read_support_format_rar5(reader) == Status.ok,
        archive_read_support_filter_all(reader) == Status.ok,
        archive_read_open_memory(reader, bytes.baseAddress, bytes.count) == Status.ok
      else { throw failure(for: reader) }
      return try body(reader)
    }
  }

  /// The header of the next entry, or nil at the end of the archive. The entry stays valid until
  /// the next call.
  private static func nextEntry(_ reader: OpaquePointer) throws -> OpaquePointer? {
    var entry: OpaquePointer?
    let status = archive_read_next_header(reader, &entry)
    if status == Status.eof { return nil }
    guard status == Status.ok || status == Status.warn, let entry else {
      throw failure(for: reader)
    }
    return entry
  }

  /// The bytes of the current entry. They must fit in `budget`. The CRC32 is checked afterwards by
  /// `requireChecksums`, because libarchive 3.7.4 reports no mismatch for stored files.
  private static func content(
    of entry: OpaquePointer, in reader: OpaquePointer, budget: Int
  ) throws -> [UInt8] {
    let declared = archive_entry_size(entry)
    guard declared >= 0 else { throw Failure.malformed }
    guard declared <= Int64(budget) else { throw Failure.tooLarge }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: readChunkSize)
    while true {
      let count = chunk.withUnsafeMutableBytes {
        archive_read_data(reader, $0.baseAddress, $0.count)
      }
      if count == 0 { return bytes }
      guard count > 0 else { throw failure(for: reader) }
      guard count <= budget - bytes.count else { throw Failure.tooLarge }
      bytes.append(contentsOf: chunk[0..<count])
    }
  }

  private static func isDirectory(_ entry: OpaquePointer) -> Bool {
    (archive_entry_filetype(entry) & fileTypeMask) == directoryType
  }

  private static func name(of entry: OpaquePointer) -> String {
    archive_entry_pathname(entry).map { String(cString: $0) } ?? ""
  }

  /// The failure that the library's last message describes. The messages are matched in English,
  /// which is the language libarchive writes them in.
  private static func failure(for reader: OpaquePointer) -> Failure {
    let message = archive_error_string(reader).map { String(cString: $0) }?.lowercased() ?? ""
    if message.contains("unrecognized") { return .notRAR }
    if message.contains("encrypt") { return .encrypted }
    if message.contains("unsupported") || message.contains("not supported") { return .unsupported }
    return .malformed
  }
}
