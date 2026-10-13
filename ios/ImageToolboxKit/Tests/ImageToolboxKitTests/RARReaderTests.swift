import Foundation
import Testing

@testable import ImageToolboxKit

// The archives are built byte by byte by RARArchiveBuilder, from the RAR 4 and RAR 5 layouts, and
// the system libarchive reads them back. No RAR archive is stored in the repository or downloaded.
@Suite("RAR reading")
struct RARReaderTests {

  private static let name = "readme.txt"
  private static let content = Data("RAR stored file, read back byte for byte.\n".utf8)

  /// The two layouts the reader takes, each holding `content` under `name`.
  enum Layout: CaseIterable, Sendable {
    case rar4
    case rar5

    var archive: Data {
      switch self {
      case .rar4: RARArchiveBuilder.rar4(name: RARReaderTests.name, data: RARReaderTests.content)
      case .rar5: RARArchiveBuilder.rar5(name: RARReaderTests.name, data: RARReaderTests.content)
      }
    }
  }

  private static let zipData = try! ZipWriter.archive([
    ZipWriter.Entry(name: "a.txt", data: Data("hello".utf8))
  ])

  @Test("data that is not a RAR archive is refused as not RAR")
  func notRAR() throws {
    let inputs: [Data] = [
      Data(),
      Self.zipData,
      try SevenZipArchive.archive([SevenZipArchive.Entry(name: "a.txt", data: Data([1, 2]))]),
      ArchiveTestData.random(4_000),
      Data("plain text, not an archive at all\n".utf8),
    ]
    for input in inputs {
      #expect(throws: RARReader.Failure.notRAR) { try RARReader.entries(in: input) }
      #expect(throws: RARReader.Failure.notRAR) { try RARReader.list(in: input) }
    }
  }

  @Test("a RAR signature without the rest of the archive is refused")
  func truncatedSignature() {
    let rar4 = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
    let rar5 = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
    for input in [rar4, rar5, rar5 + ArchiveTestData.random(64)] {
      #expect(throws: RARReader.Failure.self) { try RARReader.entries(in: input) }
      #expect(throws: RARReader.Failure.self) { try RARReader.list(in: input) }
    }
  }

  @Test("a stored file is listed with its name and size", arguments: Layout.allCases)
  func listsStoredFile(layout: Layout) throws {
    let infos = try RARReader.list(in: layout.archive)
    #expect(
      infos == [
        RARReader.Info(
          name: Self.name, uncompressedSize: UInt64(Self.content.count), isDirectory: false)
      ])
  }

  @Test("a stored file is extracted byte for byte", arguments: Layout.allCases)
  func extractsStoredFile(layout: Layout) throws {
    let entries = try RARReader.entries(in: layout.archive)
    #expect(entries == [RARReader.Entry(name: Self.name, data: Self.content)])
  }

  @Test("the builder writes the header bytes of RAR 4 and RAR 5 archives")
  func knownHeaderBytes() {
    // The RAR 4 archive header (CRC 0x90CF) and end block (CRC 0x3DC4), and the RAR 5 end header
    // (CRC 0x5156771D over the size 03 and the header 05 04 00).
    let rar4 = [UInt8](Layout.rar4.archive)
    #expect(Array(rar4[7..<20]) == [0xCF, 0x90, 0x73, 0x00, 0x00, 0x0D, 0, 0, 0, 0, 0, 0, 0])
    #expect(Array(rar4.suffix(7)) == [0xC4, 0x3D, 0x7B, 0x00, 0x40, 0x07, 0x00])
    let rar5 = [UInt8](Layout.rar5.archive)
    #expect(Array(rar5.suffix(8)) == [0x1D, 0x77, 0x56, 0x51, 0x03, 0x05, 0x04, 0x00])
  }

  @Test("a file whose data fails its CRC is refused as malformed", arguments: Layout.allCases)
  func corruptedDataIsRefused(layout: Layout) throws {
    var archive = [UInt8](layout.archive)
    let range = try #require(archive.firstRange(of: [UInt8](Self.content)))
    archive[range.lowerBound] ^= 0xFF
    // libarchive returns stored data without checking its CRC, so the reader compares it itself.
    #expect(throws: RARReader.Failure.malformed) {
      try RARReader.entries(in: Data(archive))
    }
  }

  @Test("the headers keep the CRC32 of each file and mark directories", arguments: Layout.allCases)
  func headersKeepChecksum(layout: Layout) throws {
    let headers = try RARHeaders.files(in: [UInt8](layout.archive))
    #expect(
      headers == [
        RARHeaders.FileHeader(isDirectory: false, crc: CRC32.checksum(Self.content))
      ])
  }

  @Test("a damaged header is refused as malformed", arguments: Layout.allCases)
  func damagedHeaderIsRefused(layout: Layout) throws {
    var archive = [UInt8](layout.archive)
    let range = try #require(archive.firstRange(of: [UInt8](Self.name.utf8)))
    archive[range.lowerBound] ^= 0x20
    #expect(throws: RARReader.Failure.malformed) { try RARReader.list(in: Data(archive)) }
  }

  @Test("a file cut short is refused as malformed", arguments: Layout.allCases)
  func truncatedFileIsRefused(layout: Layout) {
    let archive = layout.archive
    let cut = archive.prefix(archive.count - 20)
    #expect(throws: RARReader.Failure.malformed) { try RARReader.entries(in: Data(cut)) }
  }

  @Test("the entry and size limits refuse an archive that exceeds them", arguments: Layout.allCases)
  func limitsAreEnforced(layout: Layout) {
    #expect(throws: RARReader.Failure.tooLarge) {
      try RARReader.entries(in: layout.archive, maximumEntries: 0)
    }
    #expect(throws: RARReader.Failure.tooLarge) {
      try RARReader.entries(in: layout.archive, maximumOutputSize: Self.content.count - 1)
    }
  }
}
