import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Binary palette formats: Adobe Color Book, ColorPaletteCodable and RIFF")
struct PaletteBinaryFormatsTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  private func be16(_ value: Int) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
  }

  private func le16(_ value: Int) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
  }

  private func be32(_ value: Int) -> [UInt8] {
    [
      UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  private func le32(_ value: Int) -> [UInt8] {
    Array(be32(value).reversed())
  }

  private func utf16BE(_ text: String) -> [UInt8] {
    text.utf16.flatMap { be16(Int($0)) }
  }

  /// A 32-bit big-endian count of UTF-16 units, then the units, as the Adobe Pascal strings.
  private func adobeString(_ text: String) -> [UInt8] {
    be32(text.utf16.count) + utf16BE(text)
  }

  @Test("ACB encodes the header, the title and a named colour in the Adobe layout")
  func acbLayout() {
    let data = ACBPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
    var expected = Array("8BCB".utf8) + be16(1) + be16(0)
    expected += adobeString("Palette")
    expected += be32(0) + be32(0) + be32(0)  // Prefix, suffix and description.
    expected += be16(1) + be16(0) + be16(0) + be16(0)  // Count, page size, selector, RGB.
    expected += adobeString("Red") + Array("FF0000".utf8) + [255, 0, 0]
    #expect([UInt8](data) == expected)
  }

  @Test("ACB round trip keeps names and RGB values")
  func acbRoundTrip() throws {
    #expect(try ACBPaletteCoder.decode(ACBPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("ACB reads CMYK colours with inverted inks and skips colours with no name or code")
  func acbCMYK() throws {
    var data = Array("8BCB".utf8) + be16(1) + be16(0)
    data += be32(0) + be32(0) + be32(0) + be32(0)
    data += be16(2) + be16(0) + be16(0) + be16(2)  // Two colours, CMYK.
    data += adobeString("") + Array("CYAN00".utf8) + [0, 255, 255, 255]
    data += adobeString("") + Array("      ".utf8) + [0, 0, 0, 0]  // Blank name and code.
    let colours = try ACBPaletteCoder.decode(Data(data))
    #expect(colours == [PaletteColour(red: 0, green: 255, blue: 255)])
  }

  @Test("ACB rejects a file without the 8BCB header and an unknown colour space")
  func acbRejectsBadInput() {
    #expect(throws: PaletteFormatError.invalidHeader) {
      try ACBPaletteCoder.decode(Data("8BCX".utf8) + Data(count: 40))
    }
    var data = Array("8BCB".utf8) + be16(1) + be16(0)
    data += be32(0) + be32(0) + be32(0) + be32(0)
    data += be16(0) + be16(0) + be16(0) + be16(5)
    #expect(throws: PaletteFormatError.unknownColourSpace(5)) {
      try ACBPaletteCoder.decode(Data(data))
    }
  }

  @Test("ColorPaletteCodable starts with the byte order mark and version, little-endian")
  func dcpHeader() {
    let data = [UInt8](DCPPaletteCoder.encode(Self.sample))
    #expect(Array(data.prefix(4)) == [0x9C, 0x7D, 0x01, 0x00])
    // The palette name is empty and the single global group is written next.
    #expect(Array(data[4..<6]) == [0, 0])
    #expect(Array(data[6..<8]) == [1, 0])  // One group.
    #expect(data[8] == 0xEA)
  }

  @Test("ColorPaletteCodable round trip keeps names and float colours")
  func dcpRoundTrip() throws {
    #expect(try DCPPaletteCoder.decode(DCPPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("ColorPaletteCodable rejects a wrong byte order mark")
  func dcpRejectsBadMark() {
    #expect(throws: PaletteFormatError.invalidHeader) {
      try DCPPaletteCoder.decode(Data([0x00, 0x00, 0x01, 0x00]))
    }
  }

  @Test("RIFF writes the file size after the RIFF header, little-endian")
  func riffSize() {
    let data = [UInt8](RIFFPaletteCoder.encode(Self.sample))
    #expect(Array(data[4..<8]) == le32(data.count - 8))
    #expect(Array(data[0..<4]) == Array("RIFF".utf8))
    #expect(Array(data[8..<12]) == Array("PAL ".utf8))
  }

  @Test("RIFF entries are red, green, blue and an unused byte, after the version and count")
  func riffEntries() {
    let data = [UInt8](RIFFPaletteCoder.encode([PaletteColour(red: 1, green: 2, blue: 3)]))
    #expect(Array(data[12..<16]) == Array("data".utf8))
    #expect(Array(data[24..<28]) == [1, 2, 3, 0])
  }

  @Test("RIFF round trip keeps names, and a palette without names has no name chunk")
  func riffRoundTrip() throws {
    #expect(try RIFFPaletteCoder.decode(RIFFPaletteCoder.encode(Self.sample)) == Self.sample)

    let unnamed = [PaletteColour(red: 9, green: 8, blue: 7)]
    let data = [UInt8](RIFFPaletteCoder.encode(unnamed))
    #expect(data.count == 28)
    #expect(try RIFFPaletteCoder.decode(Data(data)) == unnamed)
  }
}
