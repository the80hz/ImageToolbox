import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("bzip2")
struct BZip2CodecTests {

  /// `bzip2 -9` of the lines sample.
  private static let vector = archiveVector(
    """
    QlpoOTFBWSZTWVuPudsAAM1fgAAQQAB/4AAgBAA6551AMADtoGBoP/VUAAACFTH/qqmEwjCaMjCaqpPU/1U9T1
    PUaADBLJpJIT0U1K7KSUBQJgJwgCAbZttttpppp70O1DrQ7qHHfffffvzMzO+RQKYmBSURMBU7RMATMAAzMzMz
    hwzMzjQ1of1DWh/UOlDnQ7UOVDjQ/aHKhrQ50OtDyocqHWhpQ6UOtDah7UO1Dxoa0NaH+LuSKcKEgtx9ztg=
    """)

  @Test("a stream made by bzip2 is read")
  func vectorIsRead() throws {
    #expect(try BZip2Codec.decompress(Self.vector) == ArchiveTestData.lines(60))
  }

  @Test("a damaged stream is refused")
  func damaged() throws {
    var flipped = [UInt8](Self.vector)
    flipped[60] ^= 0x04
    #expect(throws: ArchiveCodecError.self) { try BZip2Codec.decompress(Data(flipped)) }
    #expect(throws: ArchiveCodecError.self) { try BZip2Codec.decompress(Self.vector.prefix(80)) }
    #expect(throws: ArchiveCodecError.self) { try BZip2Codec.decompress(Data()) }
    #expect(throws: ArchiveCodecError.self) {
      try BZip2Codec.decompress(Data("not a bzip2 file".utf8))
    }
    #expect(throws: ArchiveCodecError.tooLarge) {
      try BZip2Codec.decompress(Self.vector, maximumOutputSize: 100)
    }
  }

  @Test(
    "files made by the system bzip2 are read", .enabled(if: SystemTool.isAvailable("bzip2")),
    arguments: ["-1", "-5", "-9"])
  func systemBZip2(level: String) throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try SystemTool.run("bzip2", ["-c", level], input: sample.data)
      #expect(compressed.status == 0)
      let decoded = try BZip2Codec.decompress(compressed.output)
      #expect(decoded == sample.data, "\(sample.name) at \(level)")
    }
  }

  @Test("concatenated streams are read", .enabled(if: SystemTool.isAvailable("bzip2")))
  func concatenated() throws {
    let first = ArchiveTestData.text(30_000)
    let second = ArchiveTestData.runs(12_000)
    let one = try SystemTool.run("bzip2", ["-c"], input: first).output
    let two = try SystemTool.run("bzip2", ["-c"], input: second).output
    #expect(try BZip2Codec.decompress(one + two) == first + second)
    #expect(try BZip2Codec.decompress(one + Data([0, 0, 0])) == first)
  }

  @Test(
    "output passes bzip2 -t and bzip2 -d", .enabled(if: SystemTool.isAvailable("bzip2")),
    arguments: [1, 9])
  func writtenBZip2(level: Int) throws {
    for sample in ArchiveTestData.samples() {
      let compressed = try BZip2Codec.compress(sample.data, level: level)
      let test = try SystemTool.run("bzip2", ["-t"], input: compressed)
      #expect(test.status == 0, "\(sample.name): \(test.errors)")
      let decoded = try SystemTool.run("bzip2", ["-dc"], input: compressed)
      #expect(decoded.status == 0)
      #expect(decoded.output == sample.data, "\(sample.name)")
      #expect(try BZip2Codec.decompress(compressed) == sample.data, "\(sample.name)")
    }
  }

  @Test("a large input spans several blocks", .enabled(if: SystemTool.isAvailable("bzip2")))
  func severalBlocks() throws {
    let data = ArchiveTestData.mixed(260_000, seed: 21)
    let compressed = try BZip2Codec.compress(data, level: 1)
    let test = try SystemTool.run("bzip2", ["-dc"], input: compressed)
    #expect(test.status == 0)
    #expect(test.output == data)
    #expect(try BZip2Codec.decompress(compressed) == data)
  }

  @Test(
    "long runs and periodic data survive the transform",
    .enabled(if: SystemTool.isAvailable("bzip2")))
  func degenerateInput() throws {
    var inputs: [Data] = [
      Data(repeating: 0x61, count: 1_000_000),
      Data((0..<50_000).map { UInt8($0 % 3) }),
      Data((0..<40_000).map { UInt8($0 % 256) }),
      Data(repeating: 0, count: 255),
      Data(repeating: 7, count: 4),
      Data(repeating: 7, count: 5),
      Data(repeating: 7, count: 259),
    ]
    inputs.append(Data("ab".utf8) + Data(repeating: 0x61, count: 300) + Data("b".utf8))
    for input in inputs {
      let compressed = try BZip2Codec.compress(input)
      let test = try SystemTool.run("bzip2", ["-dc"], input: compressed)
      #expect(test.status == 0, "\(input.count) bytes: \(test.errors)")
      #expect(test.output == input)
      #expect(try BZip2Codec.decompress(compressed) == input)
    }
  }

  @Test("compressible text shrinks by more than half")
  func compresses() throws {
    let data = ArchiveTestData.text(100_000)
    #expect(try BZip2Codec.compress(data).count < data.count / 2)
  }

  @Test("an empty input gives the 14-byte stream of the reference")
  func emptyInput() throws {
    let compressed = try BZip2Codec.compress(Data())
    #expect(compressed == archiveVector("QlpoORdyRThQkAAAAAA="))
    #expect(try BZip2Codec.decompress(compressed).isEmpty)
  }
}
