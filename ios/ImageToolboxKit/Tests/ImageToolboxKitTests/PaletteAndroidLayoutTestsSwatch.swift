import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the swatch text formats (Paint Shop Pro, Homesite, Skencil and Corel Painter),
// checked against the Android coders.

@Suite("Android layout: Paint Shop Pro, Homesite, Skencil and Corel Painter")
struct PaletteAndroidLayoutTestsSwatch {

  @Test("Paint Shop Pro writer writes the JASC header, the count and optional name lines")
  func paintShopProWriterLayout() {
    let data = PaintShopProPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    #expect(Array(data) == Array("JASC-PAL\n0100\n2\n; Red\n255 0 0\n1 2 3\n".utf8))
  }

  @Test("Paint Shop Pro reader clamps large channels and skips lines with extra fields")
  func paintShopProReaderOnAndroidBytes() throws {
    let file = "JASC-PAL\n0100\n3\n; Red\n300 0 0\n1 2 3 extra\n 4 5 6 \n"
    let colours = try PaintShopProPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 4, green: 5, blue: 6),
      ])
  }

  @Test("Paint Shop Pro reader compares the version line exactly, as the Android coder does")
  func paintShopProVersionIsExact() {
    #expect(throws: PaletteFormatError.invalidFormat) {
      try PaintShopProPaletteCoder.decode(Data("JASC-PAL\n0100 \n3\n1 2 3\n".utf8))
    }
  }

  @Test("Homesite writer writes the three header lines, then names and channels")
  func homesiteWriterLayout() {
    let data = HPLPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    let expected = "Palette\nVersion 4.0\n-----------\n; Red\n255 0 0\n1 2 3\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Homesite reader ignores text after the third number of a colour line")
  func homesiteReaderOnAndroidBytes() throws {
    let file = "Palette\nVersion 4.0\n-----------\n; Red\n255 0 0 trailing\n1 2 3abc\n"
    let colours = try HPLPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 1, green: 2, blue: 3),
      ])
  }

  @Test("Skencil writer writes six decimals per channel, then the name")
  func skencilWriterLayout() {
    let data = SkencilPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255),
    ])
    let expected =
      "##Sketch RGBPalette 0\n1.000000 0.000000 0.000000 Red\n"
      + "0.000000 0.501961 1.000000\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Skencil reader accepts numbers such as .5 and rounds them to 8 bits")
  func skencilReaderOnAndroidBytes() throws {
    let file = "##Sketch RGBPalette 0\n1 0 0 Red\n0.5 .5 0.25 Half\n 1 1 1 \n"
    let colours = try SkencilPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Half", red: 128, green: 128, blue: 64),
        PaletteColour(red: 255, green: 255, blue: 255),
      ])
  }

  @Test("Corel Painter writer writes the fixed header and the R, G, B and fixed HSV fields")
  func corelPainterWriterLayout() {
    let data = CorelPainterPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    let expected =
      "ROWS 12\nCOLS 22\nWIDTH 16\nHEIGHT 16\nTEXTHEIGHT 0\nSPACING 1\n"
      + "R: 255, G:0, B:0  HV:0.00, SV:0.00, VV:0.00  Red\n"
      + "R: 1, G:2, B:3  HV:0.00, SV:0.00, VV:0.00\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Corel Painter reader skips decimal channels and needs the ROWS header at the start")
  func corelPainterReaderOnAndroidBytes() throws {
    let header = "ROWS 12\nCOLS 22\nWIDTH 16\nHEIGHT 16\nTEXTHEIGHT 0\nSPACING 1\n"
    let file =
      header + "R: 255, G:0, B:0  HV:0.00, SV:0.00, VV:0.00  Red\n"
      + "R: 1.5, G:2, B:3\nR: 7, G: 8, B: 9\n"
    let colours = try CorelPainterPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 7, green: 8, blue: 9),
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try CorelPainterPaletteCoder.decode(Data(("\u{FEFF}" + header + "R: 1, G:2, B:3\n").utf8))
    }
  }
}
