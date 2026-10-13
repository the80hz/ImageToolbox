import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("7z archives")
struct SevenZipArchiveTests {

  /// `bsdtar --format 7zip` with the Copy method: `a.txt` ("hello 7z") and an empty `empty.txt`.
  private static let copyVector = archiveVector(
    """
    N3q8ryccAAM/hVGXCQAAAAAAAACQAAAAAAAAAJMCxEloZWxsbyA3egoBBAYAAQkJAAcLAQABAQAMCQAICgGotO
    gFAAAFAg4BQA8BgBEhAGEALgB0AHgAdAAAAGUAbQBwAHQAeQAuAHQAeAB0AAAAFBIBAP2IdbfaV90BnIt1t9pX
    3QESEgEA/Yh1t9pX3QHhjHW32lfdARMSAQAqy4a32lfdAZyLdbfaV90BFQoBACCApIEggKSBAAA=
    """)

  /// The same tool with LZMA2: `a.txt`, `empty.txt`, a directory entry and `dir/b.txt`, which holds
  /// the 60 lines sample. The header is stored compressed.
  private static let lzma2Vector = archiveVector(
    """
    N3q8ryccAAPLCiCFPwEAAAAAAAAdAAAAAAAAAILnRobgB/YAml0ANBlJ7o3pBhLse+78hupG/Flp6G1QEeKpiR
    zAK13hIsXI8kQNYpsIpSdfcT7eI5yJ+7ZiYJuv6uSumDkfFEPcGaf+UJ8Fjd/+pIqUYIUO6og6hyEHUTnqzuZv
    IEjvHtRE7T1XkTq8EDr3cI7w5ROleGUxH4qWCfQZLv7TCtVkqpxOoJ7oY5PNdGQJfAdEXZ0oniWZgLTedLCwAA
    DgAO8AlV0AAIEzB64P1TBoUZck0/6zcBaxfdi8deXWIpvbPfT9sMGxBc3De5G2xYPVtuyYQtCINujOPJrz79oJ
    Js+yQOOFNyCD0otPZeF7DMYBzgoQN41Aa4QaNt/4tna5roShcEmCJ8W93qbqx64GkNkeKrUj3QGJPPBI3HrfSH
    7T+U5UznPVr40ouiLYdViIj8bEa3DIYUwAAAAAFwaAogEJgJ0ABwsBAAEhIQEWDIDwCgEKiJd5AAA=
    """)

  private typealias Entry = SevenZipArchive.Entry

  @Test("an archive made by libarchive with the Copy method is read")
  func copyVector() throws {
    let entries = try SevenZipArchive.entries(in: Self.copyVector)
    #expect(
      entries == [
        Entry(name: "a.txt", data: Data("hello 7z\n".utf8)),
        Entry(name: "empty.txt", data: Data()),
      ])
  }

  @Test("an archive with LZMA2 and an encoded header is read")
  func lzma2Vector() throws {
    let entries = try SevenZipArchive.entries(in: Self.lzma2Vector)
    #expect(entries.map(\.name).sorted() == ["a.txt", "dir/b.txt", "empty.txt"])
    #expect(entries.first { $0.name == "dir/b.txt" }?.data == ArchiveTestData.lines(60))
    #expect(entries.first { $0.name == "a.txt" }?.data == Data("hello 7z\n".utf8))
    #expect(entries.first { $0.name == "empty.txt" }?.data == Data())
  }

  @Test("damaged archives are refused")
  func damaged() throws {
    let valid = [UInt8](Self.lzma2Vector)
    // The start header, the packed data and the encoded header each have a checksum.
    for offset in [14, 40, 100, valid.count - 5] {
      var copy = valid
      copy[offset] ^= 0x40
      #expect(throws: ArchiveCodecError.self, "byte \(offset)") {
        try SevenZipArchive.entries(in: Data(copy))
      }
    }
    #expect(throws: ArchiveCodecError.self) {
      try SevenZipArchive.entries(in: Data(valid.prefix(200)))
    }
    #expect(throws: ArchiveCodecError.self) { try SevenZipArchive.entries(in: Data()) }
    #expect(throws: ArchiveCodecError.self) {
      try SevenZipArchive.entries(in: Data("PK\u{3}\u{4} not a 7z file at all, no".utf8))
    }
    #expect(throws: ArchiveCodecError.tooLarge) {
      try SevenZipArchive.entries(in: Self.lzma2Vector, maximumOutputSize: 100)
    }
  }

  // MARK: - Against libarchive

  private static let sampleFiles: [String: Data] = [
    "a.txt": Data("hello 7z\n".utf8),
    "empty.txt": Data(),
    "dir/sub/text.txt": ArchiveTestData.text(60_000, seed: 3),
    "dir/random.bin": ArchiveTestData.random(9_000, seed: 5),
    "runs.bin": ArchiveTestData.runs(25_000),
  ]

  @Test(
    "archives made by libarchive with every method are read",
    .enabled(if: SystemTool.isAvailable("bsdtar")),
    arguments: ["copy", "deflate", "bzip2", "lzma1", "lzma2"])
  func libarchiveMethods(method: String) throws {
    try SystemTool.inDirectory(files: Self.sampleFiles) { directory in
      let names = Self.sampleFiles.keys.sorted()
      let made = try SystemTool.run(
        "bsdtar",
        ["--format", "7zip", "--options", "7zip:compression=\(method)", "-cf", "out.7z"]
          + names, in: directory)
      #expect(made.status == 0, "\(made.errors)")
      let data = try Data(contentsOf: directory.appendingPathComponent("out.7z"))
      let entries = try SevenZipArchive.entries(in: data)
      #expect(entries.map(\.name).sorted() == names)
      for entry in entries {
        #expect(entry.data == Self.sampleFiles[entry.name], "\(entry.name) with \(method)")
      }
    }
  }

  @Test(
    "a solid archive of many small files is read", .enabled(if: SystemTool.isAvailable("bsdtar")))
  func libarchiveManyFiles() throws {
    var files: [String: Data] = [:]
    for index in 0..<120 {
      files["f\(index % 7)/file-\(index).txt"] = ArchiveTestData.text(
        200 + index * 37, seed: UInt64(index + 1))
    }
    try SystemTool.inDirectory(files: files) { directory in
      let names = files.keys.sorted()
      let made = try SystemTool.run(
        "bsdtar", ["--format", "7zip", "-cf", "many.7z"] + names, in: directory)
      #expect(made.status == 0)
      let entries = try SevenZipArchive.entries(
        in: Data(contentsOf: directory.appendingPathComponent("many.7z")))
      #expect(entries.count == files.count)
      for entry in entries { #expect(entry.data == files[entry.name], "\(entry.name)") }
    }
  }

  // MARK: - Writing

  @Test(
    "an archive written here lists and extracts with libarchive",
    .enabled(if: SystemTool.isAvailable("bsdtar")))
  func writtenArchive() throws {
    let entries = Self.sampleFiles.keys.sorted().map {
      Entry(name: $0, data: Self.sampleFiles[$0]!)
    }
    let archive = try SevenZipArchive.archive(entries)
    try SystemTool.inDirectory(files: ["mine.7z": archive]) { directory in
      try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("out"), withIntermediateDirectories: true)
      let listing = try SystemTool.run("bsdtar", ["-tf", "mine.7z"], in: directory)
      #expect(listing.status == 0, "\(listing.errors)")
      let listed = String(decoding: listing.output, as: UTF8.self)
        .split(separator: "\n").map(String.init)
      #expect(listed.sorted() == entries.map(\.name).sorted())
      let extracted = try SystemTool.run("bsdtar", ["-xf", "mine.7z", "-C", "out"], in: directory)
      #expect(extracted.status == 0, "\(extracted.errors)")
      for entry in entries {
        let url = directory.appendingPathComponent("out/" + entry.name)
        #expect(try Data(contentsOf: url) == entry.data, "\(entry.name)")
      }
    }
  }

  @Test("written archives read back, compressed or copied")
  func writtenRoundTrip() throws {
    let text = Entry(name: "text.txt", data: ArchiveTestData.text(50_000))
    let noise = Entry(name: "noise.bin", data: ArchiveTestData.random(5_000))
    let empty = Entry(name: "folder/empty", data: Data())
    let compressed = try SevenZipArchive.archive([text, empty])
    #expect(compressed.count < 20_000)
    #expect(try SevenZipArchive.entries(in: compressed) == [text, empty])

    let copied = try SevenZipArchive.archive([noise])
    #expect(copied.count > 5_000)
    #expect(try SevenZipArchive.entries(in: copied) == [noise])

    #expect(try SevenZipArchive.entries(in: SevenZipArchive.archive([])).isEmpty)
    let onlyEmpty = [Entry(name: "a", data: Data()), Entry(name: "b/c", data: Data())]
    #expect(try SevenZipArchive.entries(in: SevenZipArchive.archive(onlyEmpty)) == onlyEmpty)
    let unicode = [
      Entry(
        name: "\u{43A}\u{430}\u{440}\u{442}\u{438}\u{43D}\u{43A}\u{430} \u{1F600}.png",
        data: Data([1, 2, 3]))
    ]
    #expect(try SevenZipArchive.entries(in: SevenZipArchive.archive(unicode)) == unicode)
  }

  @Test(
    "data that does not shrink is stored with the copy method and extracted by libarchive",
    .enabled(if: SystemTool.isAvailable("bsdtar")))
  func writtenCopiedArchive() throws {
    // Random bytes do not shrink under LZMA2, so the writer stores them verbatim.
    let noise = [
      Entry(name: "noise.bin", data: ArchiveTestData.random(20_000, seed: 13)),
      Entry(name: "more.bin", data: ArchiveTestData.random(3_000, seed: 14)),
    ]
    let archive = try SevenZipArchive.archive(noise)
    #expect(archive.range(of: noise[0].data + noise[1].data) != nil)
    try SystemTool.inDirectory(files: ["copied.7z": archive]) { directory in
      try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("out"), withIntermediateDirectories: true)
      let extracted = try SystemTool.run(
        "bsdtar", ["-xf", "copied.7z", "-C", "out"], in: directory)
      #expect(extracted.status == 0, "\(extracted.errors)")
      for entry in noise {
        let url = directory.appendingPathComponent("out/" + entry.name)
        #expect(try Data(contentsOf: url) == entry.data, "\(entry.name)")
      }
    }
  }

  @Test("a written archive with a flipped byte is refused")
  func writtenDamaged() throws {
    let archive = [UInt8](
      try SevenZipArchive.archive([Entry(name: "a.txt", data: ArchiveTestData.text(3_000))]))
    for offset in [20, 40, archive.count - 8] {
      var copy = archive
      copy[offset] ^= 0x01
      #expect(throws: ArchiveCodecError.self, "byte \(offset)") {
        try SevenZipArchive.entries(in: Data(copy))
      }
    }
  }

  @Test("names that cannot be stored are refused")
  func refusedNames() {
    #expect(throws: ArchiveCodecError.self) {
      try SevenZipArchive.archive([Entry(name: "", data: Data([1]))])
    }
  }
}
