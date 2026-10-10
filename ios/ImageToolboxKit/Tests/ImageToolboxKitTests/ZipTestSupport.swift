import Foundation

/// Runs the system archive tools and reads the raw records of an archive, for the zip tests.
enum ZipTools {

  static func data(base64 text: String) -> Data {
    Data(base64Encoded: text.filter { !$0.isWhitespace })!
  }

  /// Runs a tool and returns its exit status and standard output.
  static func run(_ executable: String, _ arguments: [String]) throws -> (
    status: Int32, output: Data
  ) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, data)
  }

  static func withFile<T>(_ data: Data, _ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ZipTests-\(UUID().uuidString).zip")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
  }

  /// Whether `unzip -tq` finds no error in the archive.
  static func unzipAccepts(_ archive: Data) throws -> Bool {
    try withFile(archive) { url in
      try run("/usr/bin/unzip", ["-tq", url.path]).status == 0
    }
  }

  /// The entry names `bsdtar -tf` (libarchive) lists.
  static func bsdtarList(_ archive: Data) throws -> [String] {
    try withFile(archive) { url in
      let result = try run("/usr/bin/bsdtar", ["-tf", url.path])
      guard result.status == 0 else { return ["bsdtar failed with \(result.status)"] }
      return String(decoding: result.output, as: UTF8.self).split(separator: "\n").map(String.init)
    }
  }

  /// The bytes `bsdtar` (libarchive) extracts for one entry, decrypted with the password.
  static func bsdtarExtract(_ archive: Data, entry: String, password: String) throws -> (
    status: Int32, data: Data
  ) {
    try withFile(archive) { url in
      let result = try run(
        "/usr/bin/bsdtar", ["-xOf", url.path, "--passphrase", password, entry])
      return (result.status, result.output)
    }
  }
}

/// A raw view of a central directory record, with the fields as written.
struct ZipRecord {
  var name: String
  var versionNeeded: UInt16
  var flags: UInt16
  var method: UInt16
  var crc: UInt32
  var compressedSize32: UInt32
  var uncompressedSize32: UInt32
  var localOffset32: UInt32
  var extra: [UInt8]

  /// The data of each extra field by id.
  var extraFields: [UInt16: [UInt8]] {
    var fields: [UInt16: [UInt8]] = [:]
    var offset = 0
    while offset + 4 <= extra.count {
      let id = UInt16(extra[offset]) | UInt16(extra[offset + 1]) << 8
      let size = Int(extra[offset + 2]) | Int(extra[offset + 3]) << 8
      fields[id] = Array(extra[(offset + 4)..<(offset + 4 + size)])
      offset += 4 + size
    }
    return fields
  }
}

/// The end records of an archive that has no comment, and its central directory records.
struct ZipLayout {
  var records: [ZipRecord]
  var entryCount16: UInt16
  var directorySize32: UInt32
  var directoryOffset32: UInt32
  /// The entry count of the Zip64 end record, when the archive has a locator.
  var zip64EntryCount: UInt64?

  init(_ archive: Data) {
    let bytes = [UInt8](archive)
    func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    func u64(_ offset: Int) -> UInt64 { UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32 }

    let end = bytes.count - 22
    entryCount16 = u16(end + 10)
    directorySize32 = u32(end + 12)
    directoryOffset32 = u32(end + 16)
    var count = Int(entryCount16)
    var offset = Int(directoryOffset32)
    let locator = end - 20
    if locator >= 0, u32(locator) == 0x0706_4B50 {
      let record = Int(u64(locator + 8))
      zip64EntryCount = u64(record + 32)
      if entryCount16 == 0xFFFF { count = Int(u64(record + 32)) }
      if directoryOffset32 == 0xFFFF_FFFF { offset = Int(u64(record + 48)) }
    }

    var records: [ZipRecord] = []
    for _ in 0..<count {
      let nameLength = Int(u16(offset + 28))
      let extraLength = Int(u16(offset + 30))
      let commentLength = Int(u16(offset + 32))
      records.append(
        ZipRecord(
          name: String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self),
          versionNeeded: u16(offset + 6), flags: u16(offset + 8), method: u16(offset + 10),
          crc: u32(offset + 16), compressedSize32: u32(offset + 20),
          uncompressedSize32: u32(offset + 24), localOffset32: u32(offset + 42),
          extra: Array(
            bytes[(offset + 46 + nameLength)..<(offset + 46 + nameLength + extraLength)])))
      offset += 46 + nameLength + extraLength + commentLength
    }
    self.records = records
  }
}
