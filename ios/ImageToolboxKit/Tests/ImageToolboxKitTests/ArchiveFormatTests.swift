import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Gzip and tar archives")
struct ArchiveFormatTests {

  /// Runs a system tool on a temporary file and returns its exit status and output.
  private static func runSystemTool(_ path: String, _ arguments: [String], file: Data) throws -> (
    Int32, String
  ) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArchiveFormatTests-\(UUID().uuidString)")
    try file.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments + [url.path]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (process.terminationStatus, text)
  }

  @Test("gzip output is accepted by the system gzip tool")
  func gzipAcceptedBySystem() throws {
    let text = Data(String(repeating: "gzip round trip ", count: 200).utf8)
    let compressed = try GzipCodec.compress(text)
    let (status, _) = try Self.runSystemTool("/usr/bin/gzip", ["-t"], file: compressed)
    #expect(status == 0)
    #expect(try GzipCodec.decompress(compressed) == text)
  }

  @Test("a gzip file made by the system gzip tool is read")
  func gzipFromSystem() throws {
    // `printf 'hello gzip archive\n' | gzip -c`, base64 encoded.
    let fixture = Data(base64Encoded: "H4sIAAn2x2oAA8tIzcnJV0ivyixQSCxKzsgsS+UCAAqYHVQTAAAA")!
    #expect(try GzipCodec.decompress(fixture) == Data("hello gzip archive\n".utf8))
  }

  @Test("an empty gzip round-trips")
  func gzipEmpty() throws {
    let compressed = try GzipCodec.compress(Data())
    #expect(try GzipCodec.decompress(compressed).isEmpty)
  }

  @Test("a corrupted gzip checksum is refused")
  func gzipChecksum() throws {
    var compressed = [UInt8](try GzipCodec.compress(Data("abc".utf8)))
    compressed[compressed.count - 8] ^= 0xFF
    #expect(throws: GzipCodec.Failure.checksumMismatch) {
      try GzipCodec.decompress(Data(compressed))
    }
  }

  @Test("tar entries round-trip, including a name split into prefix and base")
  func tarRoundTrip() throws {
    let longName = String(repeating: "folder/", count: 20) + "preset.itcurve"
    let archive = try TarArchive.archive([
      TarArchive.Entry(name: "readme.txt", data: Data("hello tar\n".utf8)),
      TarArchive.Entry(name: longName, data: Data(repeating: 7, count: 1000)),
    ])
    let entries = try TarArchive.entries(in: archive)
    #expect(entries.map(\.name) == ["readme.txt", longName])
    #expect(entries[0].data == Data("hello tar\n".utf8))
    #expect(entries[1].data.count == 1000)
  }

  @Test("a tar archive written here is listed by the system tar tool")
  func tarAcceptedBySystem() throws {
    let archive = try TarArchive.archive([
      TarArchive.Entry(name: "hello.txt", data: Data("hello from TarArchive\n".utf8))
    ])
    let (status, listing) = try Self.runSystemTool("/usr/bin/tar", ["-tf"], file: archive)
    #expect(status == 0)
    #expect(listing.contains("hello.txt"))
  }

  @Test("a name that cannot be split into the tar fields is refused")
  func tarNameTooLong() {
    let name = String(repeating: "x", count: 300)
    #expect(throws: TarArchive.Failure.nameTooLong) {
      try TarArchive.archive([TarArchive.Entry(name: name, data: Data())])
    }
  }
}
