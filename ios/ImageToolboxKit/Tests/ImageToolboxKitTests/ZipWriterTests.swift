import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Zip archive writing")
struct ZipWriterTests {

  @Test("entries written by ZipWriter read back with their names and bytes")
  func roundTrip() throws {
    let text = Data(String(repeating: "image toolbox preset ", count: 80).utf8)
    var generator = SeededGenerator(seed: 3)
    let noise = Data((0..<300).map { _ in UInt8.random(in: 0...255, using: &generator) })
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "presets/curve.itcurve", data: text),
      ZipWriter.Entry(name: "noise.bin", data: noise),
      ZipWriter.Entry(name: "empty.txt", data: Data()),
    ])

    let entries = try ZipReader.entries(in: archive) { _ in true }
    #expect(entries.map(\.name) == ["presets/curve.itcurve", "noise.bin", "empty.txt"])
    #expect(entries[0].data == text)
    #expect(entries[1].data == noise)
    #expect(entries[2].data.isEmpty)
  }

  @Test("compressible data is deflated and makes the archive smaller")
  func deflateIsUsed() throws {
    let text = Data(String(repeating: "abcabcabc", count: 500).utf8)
    let archive = try ZipWriter.archive([ZipWriter.Entry(name: "a.txt", data: text)])
    #expect(archive.count < text.count / 4)
    let entry = try #require(try ZipReader.entries(in: archive) { _ in true }.first)
    #expect(entry.data == text)
  }

  @Test("an archive written here is accepted by the system unzip tool")
  func systemUnzipAccepts() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "hello.txt", data: Data("hello from ZipWriter\n".utf8))
    ])
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ZipWriterTests-\(UUID().uuidString).zip")
    try archive.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-tq", url.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }
}
