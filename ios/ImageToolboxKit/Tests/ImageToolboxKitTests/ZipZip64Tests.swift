import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Zip64 reading and writing")
struct ZipZip64Tests {

  /// `zip -X -fz` (Info-ZIP 3.0) of `hello.txt` (19 bytes, stored) and `lines.txt` (5,000 bytes,
  /// deflated). Zip64 is forced: the local headers hold both sizes in an extra field, the central
  /// records replace only the uncompressed size, and the end record marks the directory offset.
  static let infoZipForced = ZipTools.data(
    base64: """
      UEsDBC0AAAAAAGBySV2Ancfv//////////8JABQAaGVsbG8udHh0AQAQABMAAAAAAAAAEwAAAAAAAAB6aXA2NCBmb3Jj
      ZWQgaGVsbG8KUEsDBC0AAAAIAGBySV0YPJeS//////////8JABQAbGluZXMudHh0AQAQAIgTAAAAAAAAOwAAAAAAAADt
      ybEJgDAQAMA+U/wQwX0UgjxE38JCnN4lLO/ay2PdR9xVc6sn3ryWHjPP0VIIIYQQQgghhBBCCPFXfFBLAQIeAy0AAAAA
      AGBySV2AncfvEwAAAP////8JAAwAAAAAAAEAAACkgQAAAABoZWxsby50eHQBAAgAEwAAAAAAAABQSwECHgMtAAAACABg
      ckldGDyXkjsAAAD/////CQAMAAAAAAABAAAApIFOAAAAbGluZXMudHh0AQAIAIgTAAAAAAAAUEsGBiwAAAAAAAAAHgMt
      AAAAAAAAAAAAAgAAAAAAAAACAAAAAAAAAIYAAAAAAAAAxAAAAAAAAABQSwYHAAAAAEoBAAAAAAAAAQAAAFBLBQYAAAAA
      AgACAIYAAAD/////AAA=
      """)

  /// What the writer produced before Zip64 existed, from a Python copy of that code: `hello.txt`
  /// ("hello zip"), the directory `dir/` and the empty `empty.txt`.
  static let classicGolden = ZipTools.data(
    base64: """
      UEsDBBQAAAgAAAAAIQCLc5WsCQAAAAkAAAAJAAAAaGVsbG8udHh0aGVsbG8gemlwUEsDBBQAAAgAAAAAIQAAAAAAAAAA
      AAAAAAAEAAAAZGlyL1BLAwQUAAAIAAAAACEAAAAAAAAAAAAAAAAACQAAAGVtcHR5LnR4dFBLAQIUABQAAAgAAAAAIQCL
      c5WsCQAAAAkAAAAJAAAAAAAAAAAAAAAAAAAAAABoZWxsby50eHRQSwECFAAUAAAIAAAAACEAAAAAAAAAAAAAAAAABAAA
      AAAAAAAAAAAAAAAwAAAAZGlyL1BLAQIUABQAAAgAAAAAIQAAAAAAAAAAAAAAAAAJAAAAAAAAAAAAAAAAAFIAAABlbXB0
      eS50eHRQSwUGAAAAAAMAAwCgAAAAeQAAAAAA
      """)

  static let helloText = Data("zip64 forced hello\n".utf8)
  static let linesText = Data(String(repeating: "image toolbox zip64 line\n", count: 200).utf8)

  static func noise(_ count: Int, seed: UInt64) -> Data {
    var generator = SeededGenerator(seed: seed)
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
  }

  /// Empty files with distinct names, which is the cheapest way to make a large directory.
  static func manyEntries(_ count: Int) -> [ZipWriter.Entry] {
    (0..<count).map { ZipWriter.Entry(name: "f\($0)", data: Data()) }
  }

  // MARK: - Reading

  @Test("an Info-ZIP archive with forced Zip64 is read, with the markers in the directory")
  func readsInfoZip() throws {
    let layout = ZipLayout(Self.infoZipForced)
    #expect(layout.directoryOffset32 == 0xFFFF_FFFF)
    #expect(layout.zip64EntryCount == 2)
    #expect(layout.records.map(\.uncompressedSize32) == [0xFFFF_FFFF, 0xFFFF_FFFF])
    #expect(layout.records.map(\.compressedSize32) == [0x13, 0x3B])

    let entries = try ZipReader.entries(in: Self.infoZipForced) { _ in true }
    #expect(
      entries == [
        ZipReader.Entry(name: "hello.txt", data: Self.helloText),
        ZipReader.Entry(name: "lines.txt", data: Self.linesText),
      ])
    #expect(try ZipTools.unzipAccepts(Self.infoZipForced))
    let list = try ZipReader.list(in: Self.infoZipForced)
    #expect(list.map(\.uncompressedSize) == [19, 5000])
    #expect(list.map(\.compressedSize) == [19, 59])
  }

  @Test("the extra field of an entry replaces exactly the fields that hold the marker")
  func resolvesEachMarker() throws {
    let marker = UInt32.max
    func field(_ values: [UInt64], extraBytes: [UInt8] = []) -> [UInt8] {
      Zip64.extraField(values) + extraBytes
    }
    func resolve(
      _ uncompressed: UInt32, _ compressed: UInt32, _ offset: UInt32, disk: UInt16 = 0,
      extra: [UInt8]
    ) throws -> Zip64.EntryFields {
      try extra.withUnsafeBytes {
        try Zip64.resolve(
          uncompressedSize: uncompressed, compressedSize: compressed, localOffset: offset,
          disk: disk, extra: $0)
      }
    }

    let fields = try resolve(marker, marker, marker, extra: field([1 << 33, 1 << 34, 1 << 35]))
    #expect(
      fields
        == Zip64.EntryFields(
          uncompressedSize: 1 << 33, compressedSize: 1 << 34, localOffset: 1 << 35))
    let uncompressedOnly = try resolve(marker, 7, 9, extra: field([1 << 33]))
    #expect(
      uncompressedOnly
        == Zip64.EntryFields(
          uncompressedSize: 1 << 33, compressedSize: 7, localOffset: 9))
    let compressedOnly = try resolve(5, marker, 9, extra: field([1 << 34]))
    #expect(
      compressedOnly
        == Zip64.EntryFields(
          uncompressedSize: 5, compressedSize: 1 << 34, localOffset: 9))
    let offsetOnly = try resolve(5, 7, marker, extra: field([1 << 35]))
    #expect(
      offsetOnly
        == Zip64.EntryFields(
          uncompressedSize: 5, compressedSize: 7, localOffset: 1 << 35))
    let compressedAndOffset = try resolve(5, marker, marker, extra: field([1 << 34, 1 << 35]))
    #expect(
      compressedAndOffset
        == Zip64.EntryFields(
          uncompressedSize: 5, compressedSize: 1 << 34, localOffset: 1 << 35))

    // Some writers list both sizes when one of them is replaced.
    let bothListed = try resolve(5, marker, 9, extra: field([5, 1 << 34]))
    #expect(
      bothListed
        == Zip64.EntryFields(
          uncompressedSize: 5, compressedSize: 1 << 34, localOffset: 9))

    // Other extra fields around it, and an unreplaced entry that has none.
    let other: [UInt8] = [0x55, 0x54, 0x01, 0x00, 0x03]
    let surrounded = try resolve(marker, 7, 9, extra: other + field([1 << 33]) + other)
    #expect(surrounded.uncompressedSize == 1 << 33)
    let plain = try resolve(5, 7, 9, extra: [])
    #expect(plain == Zip64.EntryFields(uncompressedSize: 5, compressedSize: 7, localOffset: 9))

    // A marker with no field, a short field and a disk other than the first are refused.
    #expect(throws: ZipReader.Failure.malformed) { try resolve(marker, 7, 9, extra: []) }
    #expect(throws: ZipReader.Failure.malformed) {
      try resolve(marker, marker, 9, extra: field([1 << 33]))
    }
    #expect(throws: ZipReader.Failure.malformed) {
      try resolve(marker, 7, 9, extra: Array(field([1 << 33]).dropLast()))
    }
    let diskField: [UInt8] = [0x01, 0x00, 0x04, 0x00, 2, 0, 0, 0]
    #expect(throws: ZipReader.Failure.unsupported) {
      try resolve(5, 7, 9, disk: 0xFFFF, extra: diskField)
    }
  }

  @Test("a damaged Zip64 end record or locator is malformed")
  func damagedEndRecords() {
    let size = Self.infoZipForced.count
    func patched(_ position: Int, _ bytes: [UInt8]) -> Data {
      var copy = Self.infoZipForced
      copy.replaceSubrange(position..<(position + bytes.count), with: bytes)
      return copy
    }
    let locator = size - 22 - 20

    // The record offset in the locator points past the end of the data.
    let beyond = patched(locator + 8, [0xFF, 0xFF, 0xFF, 0x7F, 0, 0, 0, 0])
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: beyond) { _ in true }
    }
    // The Zip64 record signature is wrong.
    let record = locator - 56
    let signature = patched(record, [0x50, 0x4B, 0x06, 0x05])
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: signature) { _ in true }
    }
    // The locator announces a second disk.
    let disks = patched(locator + 16, [2, 0, 0, 0])
    #expect(throws: ZipReader.Failure.unsupported) {
      try ZipReader.entries(in: disks) { _ in true }
    }
    // The central directory starts in the middle of nothing.
    let directory = patched(record + 48, [0xF0, 0xFF, 0, 0, 0, 0, 0, 0])
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: directory) { _ in true }
    }
  }

  @Test("markers in the end record without a Zip64 locator are malformed")
  func markersWithoutLocator() {
    // The directory offset field of a plain archive set to 0xFFFFFFFF.
    var plain = ZipReaderTests.storedArchive
    plain.replaceSubrange((plain.count - 6)..<(plain.count - 2), with: [0xFF, 0xFF, 0xFF, 0xFF])
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: plain) { _ in true }
    }
    // The size field of a central record set to 0xFFFFFFFF, with no extra field to replace it.
    var sizes = ZipReaderTests.storedArchive
    let centralOffset = Int(ZipLayout(sizes).directoryOffset32)
    sizes.replaceSubrange(
      (centralOffset + 24)..<(centralOffset + 28), with: [0xFF, 0xFF, 0xFF, 0xFF])
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: sizes) { _ in true }
    }
  }

  @Test("a header that claims more data than the compressed bytes can hold is refused")
  func inflatedSizeClaims() {
    var archive = ZipReaderTests.deflatedArchive
    let centralOffset = Int(ZipLayout(archive).directoryOffset32)
    // 256 MiB from 134 compressed bytes: deflate cannot expand data that much.
    archive.replaceSubrange((centralOffset + 24)..<(centralOffset + 28), with: [0, 0, 0, 0x10])
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive) { _ in true }
    }
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: archive, limits: .android) { _ in true }
    }
    // An absurd size in a Zip64 field is refused before anything is allocated.
    let forced = try! ZipWriter.archive(
      [ZipWriter.Entry(name: "lines.txt", data: Self.linesText)],
      options: ZipWriter.Options(zip64: .always))
    var absurd = forced
    let record = Int(ZipLayout(forced).directoryOffset32)
    let uncompressedSize = record + 46 + "lines.txt".utf8.count + 4
    absurd.replaceSubrange(
      uncompressedSize..<(uncompressedSize + 8), with: [0, 0, 0, 0, 0, 1, 0, 0])
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: absurd, limits: .android) { _ in true }
    }
    let limits = ZipLimits(maximumEntries: 10, maximumEntrySize: 1 << 40, maximumTotalSize: .max)
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: absurd, limits: limits) { _ in true }
    }
  }

  // MARK: - Writing

  @Test("a small archive is still written in the classic format, byte for byte")
  func classicOutputIsUnchanged() throws {
    let entries = [
      ZipWriter.Entry(name: "hello.txt", data: Data("hello zip".utf8)),
      ZipWriter.Entry(name: "dir/", data: Data()),
      ZipWriter.Entry(name: "empty.txt", data: Data()),
    ]
    #expect(try ZipWriter.archive(entries) == Self.classicGolden)
    #expect(
      try ZipWriter.archive(entries, options: ZipWriter.Options(zip64: .never))
        == Self.classicGolden)
    let read = try ZipReader.entries(in: Self.classicGolden) { _ in true }
    #expect(read.map(\.name) == ["hello.txt", "empty.txt"])
  }

  @Test("Zip64 forced writes the extra fields, the end record and the locator")
  func forcedZip64() throws {
    let entries = [
      ZipWriter.Entry(name: "hello.txt", data: Self.helloText),
      ZipWriter.Entry(name: "lines.txt", data: Self.linesText),
      ZipWriter.Entry(name: "noise.bin", data: Self.noise(300, seed: 1)),
    ]
    let archive = try ZipWriter.archive(entries, options: ZipWriter.Options(zip64: .always))
    #expect(try ZipTools.unzipAccepts(archive))
    #expect(try ZipTools.bsdtarList(archive) == entries.map(\.name))

    let layout = ZipLayout(archive)
    #expect(layout.zip64EntryCount == 3)
    #expect(layout.entryCount16 == 3)  // the real count fits, so it stays in the classic field
    for record in layout.records {
      #expect(record.versionNeeded == 45)
      #expect(record.compressedSize32 == 0xFFFF_FFFF)
      #expect(record.uncompressedSize32 == 0xFFFF_FFFF)
      #expect(record.localOffset32 == 0xFFFF_FFFF)
      #expect(record.extraFields[0x0001]?.count == 24)
    }
    // The extra field holds the real values: the uncompressed size, the compressed size, the offset.
    func value(_ field: [UInt8], _ index: Int) -> UInt64 {
      (0..<8).reduce(0) { $0 | UInt64(field[index * 8 + $1]) << UInt64($1 * 8) }
    }
    let lines = try #require(layout.records[1].extraFields[0x0001])
    #expect(value(lines, 0) == 5000)
    #expect(value(lines, 1) < 100)
    #expect(value(lines, 2) > 0)

    let read = try ZipReader.entries(in: archive) { _ in true }
    #expect(read.map(\.data) == entries.map(\.data))
    #expect(read.map(\.name) == entries.map(\.name))
  }

  @Test("with small thresholds each entry gets Zip64 fields only for what overflows")
  func partialZip64() throws {
    var options = ZipWriter.Options()
    options.sizeThreshold = 100
    let entries = [
      ZipWriter.Entry(name: "s", data: Self.noise(10, seed: 2)),  // fits everywhere
      ZipWriter.Entry(name: "a", data: Self.noise(300, seed: 3)),  // large, offset still small
      ZipWriter.Entry(name: "b", data: Self.noise(10, seed: 4)),  // small, offset large
      ZipWriter.Entry(name: "c", data: Self.noise(300, seed: 5)),  // large, offset large
    ]
    let archive = try ZipWriter.archive(entries, options: options)
    #expect(try ZipTools.unzipAccepts(archive))

    let layout = ZipLayout(archive)
    let sizes = layout.records.map { $0.extraFields[0x0001]?.count }
    #expect(sizes == [nil, 16, 8, 24])
    #expect(layout.records.map(\.versionNeeded) == [20, 45, 45, 45])
    #expect(layout.records.map { $0.localOffset32 == 0xFFFF_FFFF } == [false, false, true, true])
    #expect(
      layout.records.map { $0.compressedSize32 == 0xFFFF_FFFF } == [false, true, false, true])
    // The directory is larger than the threshold, and so is its offset.
    #expect(layout.directoryOffset32 == 0xFFFF_FFFF)
    #expect(layout.directorySize32 == 0xFFFF_FFFF)
    #expect(layout.zip64EntryCount == 4)
    #expect(layout.entryCount16 == 4)

    let read = try ZipReader.entries(in: archive) { _ in true }
    #expect(read.map(\.data) == entries.map(\.data))
  }

  @Test("an entry count at the threshold marks the end record")
  func entryCountThreshold() throws {
    var options = ZipWriter.Options()
    options.entryThreshold = 3
    let entries = Self.manyEntries(5)
    let archive = try ZipWriter.archive(entries, options: options)
    let layout = ZipLayout(archive)
    #expect(layout.entryCount16 == 0xFFFF)
    #expect(layout.zip64EntryCount == 5)
    #expect(layout.records.count == 5)
    #expect(try ZipTools.unzipAccepts(archive))
    #expect(try ZipReader.entries(in: archive) { _ in true }.count == 5)

    options.entryThreshold = 6
    let classic = try ZipWriter.archive(entries, options: options)
    #expect(ZipLayout(classic).zip64EntryCount == nil)
  }

  @Test("Zip64 together with AES encryption round-trips and libarchive reads it")
  func zip64WithEncryption() throws {
    var options = ZipWriter.Options(password: "pw 64", strength: .aes128)
    options.sizeThreshold = 100
    let entries = [
      ZipWriter.Entry(name: "a.txt", data: Self.helloText),
      ZipWriter.Entry(name: "b.bin", data: Self.noise(400, seed: 6)),
      ZipWriter.Entry(name: "c.txt", data: Self.linesText),
    ]
    let archive = try ZipWriter.archive(entries, options: options)
    let layout = ZipLayout(archive)
    #expect(layout.records.allSatisfy { $0.extraFields[0x9901] != nil })
    #expect(layout.records.last?.extraFields[0x0001] != nil)

    let read = try ZipReader.entries(in: archive, password: "pw 64") { _ in true }
    #expect(read.map(\.data) == entries.map(\.data))
    for entry in entries {
      let result = try ZipTools.bsdtarExtract(archive, entry: entry.name, password: "pw 64")
      #expect(result.status == 0)
      #expect(result.data == entry.data)
    }
  }

  @Test("the classic-only mode refuses what needs Zip64")
  func neverMode() throws {
    #expect(throws: ZipWriter.Failure.tooManyEntries) {
      try ZipWriter.archive(Self.manyEntries(65_536), options: ZipWriter.Options(zip64: .never))
    }
    // 65,535 is the Zip64 marker, so the classic count stops one entry earlier.
    #expect(throws: ZipWriter.Failure.tooManyEntries) {
      try ZipWriter.archive(Self.manyEntries(65_535), options: ZipWriter.Options(zip64: .never))
    }
    var options = ZipWriter.Options(zip64: .never)
    options.sizeThreshold = 100
    #expect(throws: ZipWriter.Failure.tooLarge) {
      try ZipWriter.archive(
        [ZipWriter.Entry(name: "big", data: Self.noise(300, seed: 7))], options: options)
    }
    // The directory outgrows the threshold although every entry fits.
    #expect(throws: ZipWriter.Failure.tooLarge) {
      try ZipWriter.archive(
        Self.manyEntries(3), options: options)
    }
  }

  // MARK: - Many entries

  @Test("65,534 entries still fit the classic format")
  func classicEntryCountBoundary() throws {
    let classic = try ZipWriter.archive(Self.manyEntries(65_534))
    #expect(ZipLayout(classic).zip64EntryCount == nil)
    #expect(ZipLayout(classic).entryCount16 == 65_534)
    #expect(try ZipReader.list(in: classic).count == 65_534)
  }

  @Test("an archive with 65,535 entries needs Zip64, is read back and accepted by unzip")
  func manyEntriesArchive() throws {
    let entries = (0..<65_535).map {
      ZipWriter.Entry(name: "dir\($0 % 7)/file\($0).txt", data: Data("n\($0)".utf8))
    }
    let archive = try ZipWriter.archive(entries)
    let layout = ZipLayout(archive)
    #expect(layout.entryCount16 == 0xFFFF)  // the marker: the real count is in the Zip64 record
    #expect(layout.zip64EntryCount == 65_535)
    #expect(layout.records.count == 65_535)

    let read = try ZipReader.entries(in: archive, limits: .android) { _ in true }
    #expect(read.count == 65_535)
    #expect(read[0].name == "dir0/file0.txt" && read[0].data == Data("n0".utf8))
    #expect(read[65_534].data == Data("n65534".utf8))

    // The default limits of the reader are those of a preset file, 128 entries.
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive) { _ in true }
    }
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(
        in: archive,
        limits: ZipLimits(maximumEntries: 65_534, maximumEntrySize: 1 << 20, maximumTotalSize: .max)
      ) { _ in true }
    }
    #expect(try ZipTools.unzipAccepts(archive))
  }
}
