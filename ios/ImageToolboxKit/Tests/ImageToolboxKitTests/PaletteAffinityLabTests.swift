import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Affinity, CLF and KOffice palette formats")
struct PaletteAffinityLabTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  private static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  @Test("Affinity starts with the byte order mark and the NClP and VlaP sections")
  func affinityHeader() {
    let data = [UInt8](AFPaletteCoder.encode(Self.sample))
    #expect(Array(data.prefix(8)) == [0x00, 0xFF, 0x4B, 0x41, 11, 0, 0, 0])
    #expect(Array(data[8..<12]) == [0x50, 0x6C, 0x43, 0x4E])
    let vlap = [UInt8](Array("PalV".utf8))
    #expect(data.firstRange(of: vlap) != nil)
  }

  @Test("Affinity round trip keeps names and colours")
  func affinityRoundTrip() throws {
    #expect(try AFPaletteCoder.decode(AFPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Affinity rejects a colour type that the coder does not know")
  func affinityUnknownType() {
    let data = AFPaletteCoder.encode([PaletteColour(red: 1, green: 2, blue: 3)])
    var bytes = [UInt8](data)
    if let index = bytes.firstRange(of: Array("ABGR".utf8))?.lowerBound {
      bytes.replaceSubrange(index..<index + 4, with: Array("ZZZZ".utf8))
    }
    #expect(throws: PaletteFormatError.unknownColourModel("ZZZZ")) {
      try AFPaletteCoder.decode(Data(bytes))
    }
  }

  @Test("CLF writes name, L, a and b separated by tabs")
  func clfLayout() {
    let text = Self.text(
      CLFPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)]))
    let fields = text.split(separator: "\t")
    #expect(fields.count == 4)
    #expect(fields[0] == "Red")
    #expect(abs((Double(fields[1]) ?? 0) - 53.24) < 0.1)
  }

  @Test("CLF round trip keeps names and colours to within one step")
  func clfRoundTrip() throws {
    let colours = try CLFPaletteCoder.decode(CLFPaletteCoder.encode(Self.sample))
    #expect(colours.map(\.name) == Self.sample.map(\.name))
    for (decoded, original) in zip(colours, Self.sample) {
      #expect(abs(Int(decoded.red) - Int(original.red)) <= 1)
      #expect(abs(Int(decoded.green) - Int(original.green)) <= 1)
      #expect(abs(Int(decoded.blue) - Int(original.blue)) <= 1)
    }
  }

  @Test("CLF accepts decimal commas and skips lines that are not colours")
  func clfDecimalCommas() throws {
    let data = Data("Grey\t50,0\t0,0\t0,0\nnot a colour\n".utf8)
    let colours = try CLFPaletteCoder.decode(data)
    #expect(colours.count == 1)
    #expect(abs(Int(colours[0].red) - Int(colours[0].green)) <= 1)
    #expect(abs(Int(colours[0].green) - Int(colours[0].blue)) <= 1)
    #expect(abs(Int(colours[0].red) - 119) <= 1)
  }

  @Test("KOffice writes the header and tab-separated channels with names")
  func kofficeLayout() {
    let data = KOfficePaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    #expect(Self.text(data) == "KDE RGB Palette\n255\t0\t0\tRed\n1\t2\t3\n")
  }

  @Test("KOffice round trip keeps names and colours, and reads space-separated lines")
  func koffice() throws {
    #expect(try KOfficePaletteCoder.decode(KOfficePaletteCoder.encode(Self.sample)) == Self.sample)
    let spaced = Data("KDE RGB Palette\n  12 34 56 Spaced Name\n".utf8)
    #expect(
      try KOfficePaletteCoder.decode(spaced) == [
        PaletteColour(name: "Spaced Name", red: 12, green: 34, blue: 56)
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try KOfficePaletteCoder.decode(Data("Not a palette\n1 2 3\n".utf8))
    }
  }
}
