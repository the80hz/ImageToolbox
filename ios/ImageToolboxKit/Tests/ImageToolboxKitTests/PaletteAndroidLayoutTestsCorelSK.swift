import Foundation
import Testing

@testable import ImageToolboxKit

// Layouts of the CorelDraw version 3, SK1 and image palettes, checked against the Android coders.

@Suite("Android layout: CorelDraw 3, SK1 and image palettes")
struct PaletteAndroidLayoutTestsCorelSK {

  @Test("CorelDraw 3 writer writes CMYK percentages with four spaces and CRLF line ends")
  func corelDraw3WriterLayout() {
    let data = CorelDraw3PaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 128, green: 128, blue: 128),
    ])
    let expected = "\"Red\"    0    100    100    0\r\n\"\"    0    0    0    50\r\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("CorelDraw 3 reader reads the quoted name and four percentages")
  func corelDraw3ReaderOnAndroidBytes() throws {
    let file = "\"Cyan\"    100    0    0    0\r\n\"Grey\" 0 0 0 50\n"
    let colours = try CorelDraw3PaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Cyan", red: 0, green: 255, blue: 255),
        PaletteColour(name: "Grey", red: 128, green: 128, blue: 128),
      ])
  }

  @Test("SK1 writer writes the set-up lines, colours with Kotlin doubles and palette_end")
  func sk1WriterLayout() {
    let data = SKPPaletteCoder.encode([
      PaletteColour(name: "A'b", red: 255, green: 0, blue: 128, alpha: 128)
    ])
    let expected =
      "##sK1 palette\n"
      + "Palette.Builder()\n"
      + "set_name('')\n"
      + "set_source('ColorPaletteCodable')\n"
      + "set_columns(4)\n"
      + "color(['RGB', [1.0, 0.0, 0.5019607843137255], 0.5019607843137255, 'A_b'])\n"
      + "palette_end()\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("SK1 reader reads Android colour lines with their alpha and names")
  func sk1ReaderOnAndroidBytes() throws {
    let file =
      "##sK1 palette\n"
      + "set_name('Demo')\n"
      + "color(['RGB', [1.0, 0.0, 0.0], 1.0, 'Red'])\n"
      + "color(['RGB', [0.5, 0.5, 0.5], 0.5, 'Grey'])\n"
      + "palette_end()\n"
    let colours = try SKPPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Grey", red: 128, green: 128, blue: 128, alpha: 128),
      ])
  }

  @Test("Image palette ends with the names line after the PNG, with empty names kept")
  func imageNamesLayout() throws {
    let data = ImagePaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 255),
    ])
    let suffix = Array("\n; IMAGE_NAMES: Red|\n".utf8)
    #expect(Array(data.suffix(suffix.count)) == suffix)
    // The PNG part starts with its signature. Its bytes come from a different encoder than the
    // Android Bitmap encoder, so only the signature and the names are compared.
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
  }

  @Test("Image palette reads its own names and the swatch colours back")
  func imageRoundTrip() throws {
    let colours = [
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    ]
    let decoded = try ImagePaletteCoder.decode(ImagePaletteCoder.encode(colours))
    #expect(decoded == colours)
  }
}
