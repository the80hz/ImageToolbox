import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("LZMA and xz")
struct LZMAXZCodecTests {

  // MARK: - Vectors made by xz 5.x and the lines sample

  private static let lines = ArchiveTestData.lines(60)

  /// `xz -c -6e`, CRC64 check.
  private static let xzCRC64 = archiveVector(
    """
    /Td6WFoAAATm1rRGBMCaAe4PIQEWAAAAAAAAALU8+mngB+0Akl0AJJtIJpV8o9KeavVQosn70k1vR511/Prh2W
    vm0icZHi0r+ecZ9M6w8ohyu7QUQoYUUP686l7XdhOz/VKax6rQp1ofMOMVsYw9Q3wTlZp5sOoGdWyrFc2fLJOG
    vV8beki6cuvFiVkEaKB+RHy9WuY7YbNQCY1Z8y3GPiONMPRWIhPhxBN1KI5cmjPfqU9DooyKIAAAAAD2DxvFxW
    LDfwABtgHuDwAAM3xaD7HEZ/sCAAAAAARZWg==
    """)

  private static let xzCRC32 = archiveVector(
    """
    /Td6WFoAAAFpIt42BMCaAe4PIQEWAAAAAAAAALU8+mngB+0Akl0AJJtIJpV8o9KeavVQosn70k1vR511/Prh2W
    vm0icZHi0r+ecZ9M6w8ohyu7QUQoYUUP686l7XdhOz/VKax6rQp1ofMOMVsYw9Q3wTlZp5sOoGdWyrFc2fLJOG
    vV8beki6cuvFiVkEaKB+RHy9WuY7YbNQCY1Z8y3GPiONMPRWIhPhxBN1KI5cmjPfqU9DooyKIAAAAACOkeFkAA
    GyAe4PAAAlPsuUPjANiwIAAAAAAVla
    """)

  private static let xzNone = archiveVector(
    """
    /Td6WFoAAAD/EtlBBMCaAe4PIQEWAAAAAAAAALU8+mngB+0Akl0AJJtIJpV8o9KeavVQosn70k1vR511/Prh2W
    vm0icZHi0r+ecZ9M6w8ohyu7QUQoYUUP686l7XdhOz/VKax6rQp1ofMOMVsYw9Q3wTlZp5sOoGdWyrFc2fLJOG
    vV8beki6cuvFiVkEaKB+RHy9WuY7YbNQCY1Z8y3GPiONMPRWIhPhxBN1KI5cmjPfqU9DooyKIAAAAAAAAa4B7g
    8AAMX83+CoAAr8AgAAAAAAWVo=
    """)

  private static let xzSHA256 = archiveVector(
    """
    /Td6WFoAAArh+wyhBMCaAe4PIQEWAAAAAAAAALU8+mngB+0Akl0AJJtIJpV8o9KeavVQosn70k1vR511/Prh2W
    vm0icZHi0r+ecZ9M6w8ohyu7QUQoYUUP686l7XdhOz/VKax6rQp1ofMOMVsYw9Q3wTlZp5sOoGdWyrFc2fLJOG
    vV8beki6cuvFiVkEaKB+RHy9WuY7YbNQCY1Z8y3GPiONMPRWIhPhxBN1KI5cmjPfqU9DooyKIAAAAABbfILkO/
    9Nt9RDaKjkKX/hLK1UGRMsOItOZFARVMdN+QABzgHuDwAAn/Mr6Lbp3xwCAAAAAApZWg==
    """)

  /// `xz -c --format=lzma -6e`: the size is unknown, so the stream ends with an end marker.
  private static let lzmaAlone = archiveVector(
    """
    XQAAgAD//////////wAkm0gmlXyj0p5q9VCiyfvSTW9HnXX8+uHZa+bSJxkeLSv55xn0zrDyiHK7tBRChhRQ/r
    zqXtd2E7P9UprHqtCnWh8w4xWxjD1DfBOVmnmw6gZ1bKsVzZ8sk4a9Xxt6SLpy68WJWQRooH5EfL1a5jths1AJ
    jVnzLcY+I40w9FYiE+HEE3UojlyaM9+pT0OimhiO3//9fbLA
    """)

  @Test("xz files made with each integrity check are read")
  func xzVectors() throws {
    for (name, vector) in [
      ("crc64", Self.xzCRC64), ("crc32", Self.xzCRC32), ("none", Self.xzNone),
      ("sha256", Self.xzSHA256),
    ] {
      let decoded = try XZCodec.decompress(vector)
      #expect(decoded == Self.lines, "check \(name)")
    }
  }

  @Test("a damaged xz file is refused")
  func xzDamaged() throws {
    // A flipped bit in the stored check, in the compressed data, and in the footer.
    for (offset, expected) in [(190, ArchiveCodecError.checksumMismatch), (60, nil), (215, nil)] {
      var damaged = [UInt8](Self.xzCRC64)
      damaged[offset] ^= 0x10
      do {
        _ = try XZCodec.decompress(Data(damaged))
        Issue.record("offset \(offset) was accepted")
      } catch let error as ArchiveCodecError {
        if let expected { #expect(error == expected) }
      }
    }
    #expect(throws: ArchiveCodecError.self) {
      try XZCodec.decompress(Self.xzCRC64.prefix(100))
    }
    #expect(throws: ArchiveCodecError.self) { try XZCodec.decompress(Data()) }
    #expect(throws: ArchiveCodecError.tooLarge) {
      try XZCodec.decompress(Self.xzCRC64, maximumOutputSize: 500)
    }
  }

  @Test("an lzma file with an end marker is read")
  func lzmaVector() throws {
    #expect(try LZMACodec.decompress(Self.lzmaAlone) == Self.lines)
    #expect(throws: ArchiveCodecError.self) {
      try LZMACodec.decompress(Self.lzmaAlone.prefix(80))
    }
  }

  // MARK: - Against the system xz

  private static func xz(_ arguments: [String], _ input: Data) throws -> Data {
    let result = try SystemTool.run("xz", arguments, input: input)
    #expect(result.status == 0, "xz \(arguments): \(result.errors)")
    return result.output
  }

  @Test(
    "files made by xz at several presets and checks are read",
    .enabled(if: SystemTool.isAvailable("xz")),
    arguments: [
      ["-0"], ["-6"], ["-9e", "--check=sha256"], ["-3", "--check=crc32"], ["-1", "--check=none"],
    ])
  func systemXZ(options: [String]) throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try Self.xz(["-c"] + options, sample.data)
      let decoded = try XZCodec.decompress(compressed)
      #expect(decoded == sample.data, "\(sample.name) with \(options)")
    }
  }

  @Test(
    "xz files with other literal and position bits are read",
    .enabled(if: SystemTool.isAvailable("xz")),
    arguments: [
      "lc=0,lp=0,pb=0", "lc=4,lp=0,pb=4", "lc=0,lp=4,pb=0", "lc=1,lp=3,pb=2",
      "lc=3,lp=1,pb=1,dict=64KiB,nice=273,mf=bt4",
    ])
  func systemXZContexts(options: String) throws {
    let data = ArchiveTestData.mixed(120_000, seed: 5)
    let compressed = try Self.xz(["-c", "--lzma2=\(options)"], data)
    #expect(try XZCodec.decompress(compressed) == data)
  }

  @Test(
    "an xz file with several blocks and concatenated streams is read",
    .enabled(if: SystemTool.isAvailable("xz")))
  func systemXZBlocks() throws {
    let data = ArchiveTestData.mixed(300_000, seed: 9)
    let blocks = try Self.xz(["-c", "-T2", "--block-size=40000", "-3"], data)
    #expect(try XZCodec.decompress(blocks) == data)

    let other = ArchiveTestData.text(5000, seed: 4)
    let first = try Self.xz(["-c"], data)
    let second = try Self.xz(["-c", "--check=crc32"], other)
    let padding = Data(count: 8)
    #expect(try XZCodec.decompress(first + second) == data + other)
    #expect(try XZCodec.decompress(first + padding + second) == data + other)
    #expect(throws: ArchiveCodecError.self) {
      try XZCodec.decompress(first + Data(count: 3) + second)
    }
  }

  @Test("lzma files made by xz are read", .enabled(if: SystemTool.isAvailable("xz")))
  func systemLZMA() throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try Self.xz(["-c", "--format=lzma", "-5"], sample.data)
      #expect(try LZMACodec.decompress(compressed) == sample.data, "\(sample.name)")
    }
    let data = ArchiveTestData.text(30000)
    let tuned = try Self.xz(["-c", "--format=lzma", "--lzma1=lc=2,lp=1,pb=3,dict=32KiB"], data)
    #expect(try LZMACodec.decompress(tuned) == data)
  }

  // MARK: - Writing

  @Test("xz output passes xz -t and xz -d", .enabled(if: SystemTool.isAvailable("xz")))
  func writtenXZ() throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try XZCodec.compress(sample.data)
      let test = try SystemTool.run("xz", ["-t"], input: compressed)
      #expect(test.status == 0, "\(sample.name): \(test.errors)")
      let decoded = try SystemTool.run("xz", ["-dc"], input: compressed)
      #expect(decoded.status == 0)
      #expect(decoded.output == sample.data, "\(sample.name)")
      #expect(try XZCodec.decompress(compressed) == sample.data, "\(sample.name)")
    }
  }

  @Test("xz output of compressible data is smaller than the input")
  func writtenXZCompresses() throws {
    let data = ArchiveTestData.text(100_000)
    let compressed = try XZCodec.compress(data)
    #expect(compressed.count < data.count / 3)
  }

  @Test("an empty xz file has the size of the reference")
  func emptyXZ() throws {
    // `xz -c < /dev/null` is a 32-byte file: header, empty index, footer.
    #expect(try XZCodec.compress(Data()).count == 32)
    #expect(try XZCodec.decompress(XZCodec.compress(Data())).isEmpty)
  }

  @Test(
    "lzma alone output passes xz -t and is read back", .enabled(if: SystemTool.isAvailable("xz")))
  func writtenLZMA() throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try LZMACodec.compress(sample.data)
      let test = try SystemTool.run("xz", ["-t", "--format=lzma"], input: compressed)
      #expect(test.status == 0, "\(sample.name): \(test.errors)")
      let decoded = try SystemTool.run("xz", ["-dc", "--format=lzma"], input: compressed)
      #expect(decoded.output == sample.data, "\(sample.name)")
      #expect(try LZMACodec.decompress(compressed) == sample.data, "\(sample.name)")
    }
  }
}
