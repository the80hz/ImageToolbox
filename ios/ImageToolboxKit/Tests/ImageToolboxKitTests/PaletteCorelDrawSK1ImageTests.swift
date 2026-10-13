import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("CorelDraw V3, SK1 and image palette formats")
struct PaletteCorelDrawSK1ImageTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  @Test("CorelDraw V3 writes CMYK percentages on CRLF lines")
  func corelDraw3Layout() {
    let text = String(
      decoding: CorelDraw3PaletteCoder.encode([
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
      ]),
      as: UTF8.self)
    #expect(text == "\"Red\"    0    100    100    0\r\n")
  }

  @Test("CorelDraw V3 reads CMYK percentages and keeps the quoted name")
  func corelDraw3Decode() throws {
    let colours = try CorelDraw3PaletteCoder.decode(Data("\"Cyan\" 100 0 0 0\n".utf8))
    #expect(colours == [PaletteColour(name: "Cyan", red: 0, green: 255, blue: 255)])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try CorelDraw3PaletteCoder.decode(Data("no colours here\n".utf8))
    }
  }

  @Test("SK1 writes the header lines and one colour call per colour")
  func sk1Layout() {
    let text = String(
      decoding: SKPPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)]),
      as: UTF8.self)
    #expect(text.hasPrefix("##sK1 palette\nPalette.Builder()\n"))
    #expect(text.contains("color(['RGB', [1.0, 0.0, 0.0], 1.0, 'Red'])\n"))
    #expect(text.hasSuffix("palette_end()\n"))
  }

  @Test("SK1 round trip keeps names and colours")
  func sk1RoundTrip() throws {
    #expect(try SKPPaletteCoder.decode(SKPPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("SK1 reads the alpha value and ignores the palette name line")
  func sk1Decode() throws {
    let text = """
      ##sK1 palette
      set_name('Demo')
      color(['RGB', [0.0, 1.0, 0.5], 0.5, 'Teal'])
      """
    let colours = try SKPPaletteCoder.decode(Data(text.utf8))
    #expect(colours == [PaletteColour(name: "Teal", red: 0, green: 255, blue: 128, alpha: 128)])
  }

  @Test("Image palette writes a PNG with one swatch per colour, then the names")
  func imageLayout() {
    let data = [UInt8](ImagePaletteCoder.encode(Self.sample))
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    let names = Array("; IMAGE_NAMES: Red|Green|Blue|Accent\n".utf8)
    #expect(data.firstRange(of: names) != nil)
  }

  @Test("Image palette round trip reads the centre of each swatch and the names")
  func imageRoundTrip() throws {
    #expect(try ImagePaletteCoder.decode(ImagePaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Image palette rejects data that is not an image")
  func imageRejectsText() {
    #expect(throws: PaletteFormatError.invalidFormat) {
      try ImagePaletteCoder.decode(Data("not an image".utf8))
    }
  }
}
