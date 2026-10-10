import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Zip archive reading")
struct ZipReaderTests {

  /// `curve.itcurve`, deflated, from the `zip` command. The preset is a JSON file of 603 bytes.
  static let deflatedArchive = Data(
    base64Encoded: """
      UEsDBBQAAAAIAEm9SF3hpHa1hgAAAFsCAAANAAAAY3VydmUuaXRjdXJ2ZavmUlBQSssvyk0sUbJSUPLMTUxPDcnPz0nKr1BwLi0qSy1W0gEpKUstKs7MzwOqMQTzkyFyVgrRQJ4ClETQCgoGOggmlBWrg6lKzxRJnZ4FbpWGCHWGMFVcSGrJdQEdzAV6kj4u5oKqV0rOz8kvCs9ITc3BjCK4JQbYHEORLNSfYHdw1QIAUEsBAh4DFAAAAAgASb1IXeGkdrWGAAAAWwIAAA0AAAAAAAAAAQAAAKSBAAAAAGN1cnZlLml0Y3VydmVQSwUGAAAAAAEAAQA7AAAAsQAAAAAA
      """.filter { !$0.isWhitespace })!

  /// `readme.txt` with the text "not a preset", stored without compression.
  static let storedArchive = Data(
    base64Encoded: """
      UEsDBAoAAAAAAEm9SF3uYKhKDAAAAAwAAAAKAAAAcmVhZG1lLnR4dG5vdCBhIHByZXNldFBLAQIeAwoAAAAAAEm9SF3uYKhKDAAAAAwAAAAKAAAAAAAAAAAAAACkgQAAAAByZWFkbWUudHh0UEsFBgAAAAABAAEAOAAAADQAAAAAAA==
      """.filter { !$0.isWhitespace })!

  @Test("a deflated entry is inflated to its original bytes")
  func deflatedEntry() throws {
    let entries = try ZipReader.entries(in: Self.deflatedArchive) { _ in true }
    let entry = try #require(entries.first)
    #expect(entry.name == "curve.itcurve")
    #expect(entry.data.count == 603)
    let text = String(decoding: entry.data, as: UTF8.self)
    #expect(text.contains("\"format\": \"ImageToolbox Curves\""))
  }

  @Test("a stored entry is returned as it is")
  func storedEntry() throws {
    let entries = try ZipReader.entries(in: Self.storedArchive) { _ in true }
    #expect(entries == [ZipReader.Entry(name: "readme.txt", data: Data("not a preset".utf8))])
  }

  @Test("the include filter decides which entries are read")
  func includeFilter() throws {
    let skipped = try ZipReader.entries(in: Self.deflatedArchive) { $0.hasSuffix(".xmp") }
    #expect(skipped.isEmpty)
  }

  @Test("data without an end record is malformed")
  func notAZip() {
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: Data("plain text".utf8)) { _ in true }
    }
  }

  @Test("the entry size and entry count limits are enforced")
  func limits() {
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: Self.deflatedArchive, maximumEntrySize: 10) { _ in true }
    }
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: Self.deflatedArchive, maximumEntries: 0) { _ in true }
    }
  }
}
