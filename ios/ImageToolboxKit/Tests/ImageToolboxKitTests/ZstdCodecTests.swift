import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Zstandard")
struct ZstdCodecTests {

  private static let lines = ArchiveTestData.lines(60)

  /// `zstd -1` of the lines sample, with the content checksum.
  private static let level1 = archiveVector(
    """
    KLUv/QRIjQUA0oUSF4BrOkgO2F8zEi24AAJOI5tSykrbVK5YSPL////btm3bbdu2LUmSJLlt27ZkIAjc5RAA1W
    JhqGlUQ+VYEgeGQo9jYM4pFEJREAI7ILAzSgejjDcyo4w3sqOMNzKjjDeyUYw3slGON7JRjDeyUcYzslHGO7JR
    xjOyUcYbmVHGG9lRxtPIrhjFauNVdWRUjDK18aQ6sihGgdp4Tx3DyTmcxQU/nOESP5zhkvEb0tgn8Xw0lA==
    """)

  /// `zstd -3`.
  private static let level3 = archiveVector(
    """
    KLUv/QRYjQUA0oUSF4BrOkgO2F8zEi24AAJOI5tSykrbVK5YSPL////btm3bbdu2LUmSJLlt27ZkIAjc5RAA1W
    JhqGlUQ+VYEgeGQo9jYM4pFEJREAI7ILAzSgejjDcyo4w3sqOMNzKjjDeyUYw3slGON7JRjDeyUcYzslHGO7JR
    xjOyUcYbmVHGG9lRxtPIrhjFauNVdWRUjDK18aQ6sihGgdp4Tx3DyTmcxQU/nOESP5zhkvEb0tgn8Xw0lA==
    """)

  /// `zstd -19`, which uses the largest tables.
  private static let level19 = archiveVector(
    """
    KLUv/QRonQMAEkYTEZB9HA0UniSzPpHukySqx0EJIKFjChnvoiR0TCHjXZCEjilkvIuR0DGFjHfxCR1TyHj3hI
    4pZLwDEV6VM2T8cnhaRndZ2LZNa9eDjKo7qBHAu/9n8DXWEfz/j/D4A9CVt3mbtyFFlk5VtVo0NwSQVfF8NJQ=
    """)

  /// `zstd -19 --no-check`.
  private static let noChecksum = archiveVector(
    """
    KLUv/QBonQMAEkYTEZB9HA0UniSzPpHukySqx0EJIKFjChnvoiR0TCHjXZCEjilkvIuR0DGFjHfxCR1TyHj3hI
    4pZLwDEV6VM2T8cnhaRndZ2LZNa9eDjKo7qBHAu/9n8DXWEfz/j/D4A9CVt3mbtyFFlk5VtVo0NwSQVQ==
    """)

  @Test("frames made by zstd at levels 1, 3 and 19 are read")
  func vectors() throws {
    for (name, vector) in [
      ("level 1", Self.level1), ("level 3", Self.level3), ("level 19", Self.level19),
      ("no checksum", Self.noChecksum),
    ] {
      #expect(try ZstdCodec.decompress(vector) == Self.lines, "\(name)")
    }
  }

  @Test("xxh64 matches the published vectors")
  func xxh64Vectors() {
    func hash(_ text: String) -> UInt64 {
      Array(text.utf8).withUnsafeBufferPointer { ArchiveChecksum.xxh64($0) }
    }
    #expect(hash("") == 0xEF46_DB37_51D8_E999)
    #expect(hash("a") == 0xD24E_C4F1_A98C_6E5B)
    #expect(hash("abc") == 0x44BC_2CF5_AD77_0999)
  }

  @Test("predefined distributions add up to their table size")
  func predefinedTables() {
    func total(_ counts: [Int]) -> Int { counts.reduce(0) { $0 + max($1, 1) } }
    #expect(total(ZstdDefaults.literalLengthCounts) == 64)
    #expect(total(ZstdDefaults.matchLengthCounts) == 64)
    #expect(total(ZstdDefaults.offsetCounts) == 32)
    #expect(ZstdDefaults.literalLengthCounts.count == 36)
    #expect(ZstdDefaults.matchLengthCounts.count == 53)
    #expect(ZstdDefaults.offsetCounts.count == 29)
  }

  @Test("a damaged or cut frame is refused")
  func damaged() throws {
    var flipped = [UInt8](Self.level19)
    flipped[40] ^= 0x20
    #expect(throws: ArchiveCodecError.self) { try ZstdCodec.decompress(Data(flipped)) }
    var badChecksum = [UInt8](Self.level3)
    badChecksum[badChecksum.count - 1] ^= 0x01
    #expect(throws: ArchiveCodecError.checksumMismatch) {
      try ZstdCodec.decompress(Data(badChecksum))
    }
    #expect(throws: ArchiveCodecError.self) { try ZstdCodec.decompress(Self.level3.prefix(60)) }
    #expect(throws: ArchiveCodecError.self) { try ZstdCodec.decompress(Data()) }
    #expect(throws: ArchiveCodecError.self) { try ZstdCodec.decompress(Data(count: 12)) }
    #expect(throws: ArchiveCodecError.tooLarge) {
      try ZstdCodec.decompress(Self.level3, maximumOutputSize: 100)
    }
  }

  @Test("a frame that names a dictionary is refused as unsupported")
  func dictionaryFrame() {
    // Magic, descriptor with a one-byte dictionary id (1), window byte, id, one empty last block.
    let frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x01, 0x58, 0x01, 0x01, 0x00, 0x00])
    #expect(throws: ArchiveCodecError.unsupported) { try ZstdCodec.decompress(frame) }
  }

  @Test("skippable frames and concatenated frames are read")
  func skippableAndConcatenated() throws {
    let skippable = Data([0x5A, 0x2A, 0x4D, 0x18, 0x03, 0x00, 0x00, 0x00, 1, 2, 3])
    let joined = skippable + Self.level1 + skippable + Self.level19
    #expect(try ZstdCodec.decompress(joined) == Self.lines + Self.lines)
    #expect(try ZstdCodec.decompress(skippable + skippable).isEmpty)
  }

  // MARK: - Against the system zstd

  private static func zstd(_ arguments: [String], _ input: Data) throws -> Data {
    let result = try SystemTool.run("zstd", ["-c", "-q"] + arguments, input: input)
    #expect(result.status == 0, "zstd \(arguments): \(result.errors)")
    return result.output
  }

  @Test(
    "frames made by zstd at many levels are read", .enabled(if: SystemTool.isAvailable("zstd")),
    arguments: [["-1"], ["-3"], ["-9"], ["-19"], ["--ultra", "-22"], ["--fast=7"]])
  func systemLevels(options: [String]) throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try Self.zstd(options, sample.data)
      let decoded = try ZstdCodec.decompress(compressed)
      #expect(decoded == sample.data, "\(sample.name) with \(options)")
    }
  }

  @Test(
    "frames with other window and strategy settings are read",
    .enabled(if: SystemTool.isAvailable("zstd")),
    arguments: [
      ["--zstd=strategy=1,wlog=10"], ["--zstd=strategy=3,hlog=12,clog=12"],
      ["--zstd=strategy=5,wlog=17,mml=3"], ["--zstd=strategy=9,tlen=999"],
      ["--long=27", "-5"], ["-3", "--no-check"], ["-3", "--no-content-size"],
      ["-7", "--rsyncable"],
    ])
  func systemSettings(options: [String]) throws {
    let data = ArchiveTestData.mixed(150_000, seed: 8)
    let compressed = try Self.zstd(options, data)
    #expect(try ZstdCodec.decompress(compressed) == data, "\(options)")
  }

  @Test(
    "a frame of several blocks with repeated tables is read",
    .enabled(if: SystemTool.isAvailable("zstd")))
  func systemManyBlocks() throws {
    let data = ArchiveTestData.text(700_000, seed: 12)
    for level in ["-1", "-5", "-15"] {
      let compressed = try Self.zstd([level], data)
      #expect(try ZstdCodec.decompress(compressed) == data, "\(level)")
    }
    let parallel = try Self.zstd(["-3", "-T2", "--block-size=32768"], data)
    #expect(try ZstdCodec.decompress(parallel) == data)
  }

  @Test("concatenated system frames are read", .enabled(if: SystemTool.isAvailable("zstd")))
  func systemConcatenated() throws {
    let first = ArchiveTestData.text(40_000)
    let second = ArchiveTestData.runs(9_000)
    let joined = try Self.zstd(["-3"], first) + Self.zstd(["-19"], second)
    #expect(try ZstdCodec.decompress(joined) == first + second)
  }

  // MARK: - Writing

  @Test("output passes zstd -t and zstd -d", .enabled(if: SystemTool.isAvailable("zstd")))
  func writtenZstd() throws {
    var inputs = ArchiveTestData.samples()
    inputs.append(("one run", Data(repeating: 0x55, count: 300_000)))
    inputs.append(("two blocks", ArchiveTestData.random(131_073)))
    for sample in inputs {
      let compressed = try ZstdCodec.compress(sample.data)
      let test = try SystemTool.run("zstd", ["-t", "-q"], input: compressed)
      #expect(test.status == 0, "\(sample.name): \(test.errors)")
      let decoded = try SystemTool.run("zstd", ["-dc", "-q"], input: compressed)
      #expect(decoded.status == 0)
      #expect(decoded.output == sample.data, "\(sample.name)")
      #expect(try ZstdCodec.decompress(compressed) == sample.data, "\(sample.name)")
    }
  }

  @Test("a run of one byte is written as a run-length block")
  func runLengthBlock() throws {
    let compressed = try ZstdCodec.compress(Data(repeating: 0, count: 100_000))
    #expect(compressed.count < 40)
  }
}
