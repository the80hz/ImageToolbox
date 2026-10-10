import Foundation
import Testing

@testable import ImageToolboxKit

/// Zip entries compressed with bzip2 (12), LZMA (14), zstd (93) and xz (95). The payloads come
/// from the system tools, and the zip structure around them is written here, because the zip
/// writer of libarchive on this Mac cannot store these methods.
private let zipMethodToolsAvailable =
  SystemTool.isAvailable("xz") && SystemTool.isAvailable("bzip2") && SystemTool.isAvailable("zstd")

@Suite("zip entries compressed with bzip2, LZMA, zstd and xz")
struct ZipCompressionMethodTests {

  enum Method: CaseIterable, CustomStringConvertible {
    case bzip2
    case lzma
    case zstd
    case xz

    var zipMethod: UInt16 {
      switch self {
      case .bzip2: 12
      case .lzma: 14
      case .zstd: 93
      case .xz: 95
      }
    }

    var description: String { "method \(zipMethod)" }
  }

  /// The output of a system tool, which must succeed.
  private static func tool(_ name: String, _ arguments: [String], _ input: Data) throws -> [UInt8] {
    let result = try SystemTool.run(name, arguments, input: input)
    #expect(result.status == 0, "\(name) \(arguments): \(result.errors)")
    return [UInt8](result.output)
  }

  /// The payload of a zip entry holding `content`, as the system tool writes it for the method.
  private static func payload(_ method: Method, of content: Data) throws -> [UInt8] {
    switch method {
    case .bzip2:
      return try tool("bzip2", ["-c", "-9"], content)
    case .xz:
      return try tool("xz", ["-c", "-6"], content)
    case .zstd:
      return try tool("zstd", ["-c", "-q", "-3"], content)
    case .lzma:
      // `xz --format=lzma` writes a 13-byte header (properties, dictionary size, size) and then
      // the stream, which ends with an end marker. A zip entry holds the coder's own version and
      // five-byte properties, then the stream, and it records the size in its headers instead.
      let alone = try tool("xz", ["-c", "--format=lzma", "-6"], content)
      return [9, 20, 5, 0] + Array(alone[0..<5]) + Array(alone[13...])
    }
  }

  /// A zip archive with one entry. `claimedSize` is the uncompressed size the headers state; it
  /// defaults to the size of `content`.
  private static func zipArchive(
    name: String, method: UInt16, payload: [UInt8], content: [UInt8], claimedSize: Int? = nil
  ) -> Data {
    let nameBytes = Array(name.utf8)
    let size = UInt32(claimedSize ?? content.count)
    let crc = ArchiveChecksum.crc32(content)
    let compressed = UInt32(payload.count)
    func short(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
    func long(_ value: UInt32) -> [UInt8] { LittleEndian.bytes(value) }

    var local = long(0x0403_4B50)
    local += short(20) + short(0) + short(Int(method)) + short(0) + short(0x21)
    local += long(crc) + long(compressed) + long(size)
    local += short(nameBytes.count) + short(0)
    local += nameBytes + payload

    var directory = long(0x0201_4B50)
    directory += short(20) + short(20) + short(0) + short(Int(method)) + short(0) + short(0x21)
    directory += long(crc) + long(compressed) + long(size)
    directory += short(nameBytes.count) + short(0) + short(0) + short(0) + short(0)
    directory += long(0) + long(0)
    directory += nameBytes

    var end = long(0x0605_4B50)
    end += short(0) + short(0) + short(1) + short(1)
    end += long(UInt32(directory.count)) + long(UInt32(local.count)) + short(0)

    return Data(local + directory + end)
  }

  private static func read(_ archive: Data) throws -> [ZipReader.Entry] {
    try ZipReader.entries(in: archive, limits: .android) { _ in true }
  }

  @Test(
    "entries written by the system tools are read back at every size",
    .enabled(if: zipMethodToolsAvailable))
  func systemToolEntries() throws {
    for sample in ArchiveTestData.samples() {
      let content = [UInt8](sample.data)
      for method in Method.allCases {
        let packed = try Self.payload(method, of: sample.data)
        let archive = Self.zipArchive(
          name: "picture.bin", method: method.zipMethod, payload: packed, content: content)
        let entries = try Self.read(archive)
        #expect(entries.map(\.name) == ["picture.bin"], "\(sample.name) with \(method)")
        #expect(entries.first?.data == sample.data, "\(sample.name) with \(method)")
      }
    }
  }

  @Test(
    "a damaged payload is refused whatever the method", .enabled(if: zipMethodToolsAvailable))
  func damagedPayloads() throws {
    let content = ArchiveTestData.text(20_000, seed: 31)
    for method in Method.allCases {
      var packed = try Self.payload(method, of: content)
      packed[packed.count / 2] ^= 0x10
      let archive = Self.zipArchive(
        name: "text.txt", method: method.zipMethod, payload: packed,
        content: [UInt8](content))
      #expect(throws: ZipReader.Failure.self, "\(method)") {
        try Self.read(archive)
      }
    }
  }

  @Test(
    "an entry whose size disagrees with its data is refused", .enabled(if: zipMethodToolsAvailable))
  func sizeMismatch() throws {
    let content = ArchiveTestData.text(5_000, seed: 32)
    let packed = try Self.payload(.bzip2, of: content)
    let larger = Self.zipArchive(
      name: "a.txt", method: Method.bzip2.zipMethod, payload: packed,
      content: [UInt8](content), claimedSize: content.count + 1)
    let smaller = Self.zipArchive(
      name: "a.txt", method: Method.bzip2.zipMethod, payload: packed,
      content: [UInt8](content), claimedSize: content.count - 1)
    #expect(throws: ZipReader.Failure.malformed) { try Self.read(larger) }
    #expect(throws: ZipReader.Failure.tooLarge) { try Self.read(smaller) }
  }

  @Test(
    "an LZMA entry with other than five property bytes is refused",
    .enabled(if: zipMethodToolsAvailable))
  func lzmaProperties() throws {
    let content = ArchiveTestData.text(3_000, seed: 33)
    var packed = try Self.payload(.lzma, of: content)
    packed[2] = 4
    let archive = Self.zipArchive(
      name: "a.txt", method: Method.lzma.zipMethod, payload: packed, content: [UInt8](content))
    #expect(throws: ZipReader.Failure.malformed) { try Self.read(archive) }
  }

  @Test(
    "zip files built around the system tool output are listed by libarchive",
    .enabled(if: SystemTool.isAvailable("bsdtar") && zipMethodToolsAvailable))
  func libarchiveReadsTheFixtures() throws {
    let content = ArchiveTestData.text(40_000, seed: 34)
    for method in [Method.bzip2, .lzma, .xz] {
      let packed = try Self.payload(method, of: content)
      let archive = Self.zipArchive(
        name: "text.txt", method: method.zipMethod, payload: packed, content: [UInt8](content))
      try SystemTool.inDirectory(files: ["fixture.zip": archive]) { directory in
        let extracted = try SystemTool.run(
          "bsdtar", ["-xOf", "fixture.zip"], in: directory)
        #expect(extracted.status == 0, "\(method): \(extracted.errors)")
        #expect(extracted.output == content, "\(method)")
      }
    }
  }
}
