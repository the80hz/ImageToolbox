import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the text palette formats, checked against the Android coders. The expected bytes
// are the ones the Android writers produce for the same colours, worked out from their code.

@Suite("Android layout: GIMP, Paint.NET and CSV text palettes")
struct PaletteAndroidLayoutTestsText {

  @Test("GIMP writer matches the Android header, tab separated channels and optional names")
  func gimpWriterLayout() {
    let data = GIMPPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    let expected =
      "GIMP Palette\nName: \nColumns: 0\n#Colors: 2\n255\t0\t0\tRed\n1\t2\t3\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("GIMP reader accepts an Android file with a BOM, metadata and out of range lines")
  func gimpReaderOnAndroidBytes() throws {
    let file =
      "\u{FEFF}GIMP Palette\nName: Demo\nColumns: 0\n# comment\n256 0 0 Skipped\n"
      + "255 0 0 Red Dark\n1\t2\t3\n"
    let colours = try GIMPPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red Dark", red: 255, green: 0, blue: 0),
        PaletteColour(red: 1, green: 2, blue: 3),
      ])
  }

  @Test("Paint.NET writer keeps LF header lines and CRLF colour lines as the Android coder does")
  func paintNETWriterLayout() {
    let data = PaintNETPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 128, green: 1, blue: 2, alpha: 128),
    ])
    let expected =
      "; paint.net Palette File\n"
      + "; Lines that start with a semicolon are comments\n"
      + "; Colors are written as 8-digit hexadecimal numbers: aarrggbb\n"
      + "; Red\r\nFFFF0000\r\n80800102\r\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Paint.NET reader skips the BOM and reads the name comment and the alpha byte")
  func paintNETReaderOnAndroidBytes() throws {
    let file =
      "\u{FEFF}; paint.net Palette File\n"
      + "; Lines that start with a semicolon are comments\n"
      + "; Colors are written as 8-digit hexadecimal numbers: aarrggbb\n"
      + "; Red\r\nFFFF0000\r\n80800102\r\n"
    let colours = try PaintNETPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 128, green: 1, blue: 2, alpha: 128),
      ])
  }

  @Test("CSV writer writes lower case #rrggbb lines and names after a comma")
  func csvWriterLayout() {
    let data = CSVPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 18, green: 171, blue: 15),
    ])
    #expect(Array(data) == Array("#ff0000, Red\n#12ab0f\n".utf8))
  }

  @Test("CSV reader on Android lines reads a name, a 4 digit RGBA colour and skips 0x colours")
  func csvReaderOnAndroidBytes() throws {
    // "0xf00" keeps its zero, so the four digits form RGBA with alpha 0. "0x00ff00" has seven
    // digits once the "x" is dropped, so it is skipped. Both follow the Android coder.
    let file = "#ff0000, Red\n#12ab0f\n0xf00\n0x00ff00\n"
    let colours = try CSVPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 18, green: 171, blue: 15),
        PaletteColour(red: 0, green: 255, blue: 0, alpha: 0),
      ])
  }
}
