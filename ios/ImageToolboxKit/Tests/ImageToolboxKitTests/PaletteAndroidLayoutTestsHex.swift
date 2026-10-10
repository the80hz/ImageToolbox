import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the hex text formats (HEX, RGB and RGBA), checked against the Android coders.

@Suite("Android layout: HEX, RGB and RGBA text palettes")
struct PaletteAndroidLayoutTestsHex {

  @Test("HEX writer writes a name line and #rrggbb, or #rrggbbaa for a colour with alpha")
  func hexWriterLayout() {
    let data = HEXPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3, alpha: 128),
    ])
    #expect(Array(data) == Array("; Red\n#ff0000\n#01020380\n".utf8))
  }

  @Test("HEX reader takes every hex run of a line, so a word of hex letters is a colour")
  func hexReaderRuns() throws {
    // "Red1" reads as the run "ed1", a three digit colour. "#12" has two digits and is skipped.
    let file = "; Red\n#ff0000 #00ff00\nDead Beef\nRed1\n#12\n"
    let colours = try HEXPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
        PaletteColour(red: 221, green: 238, blue: 170, alpha: 221),
        PaletteColour(red: 187, green: 238, blue: 238),
        PaletteColour(red: 238, green: 221, blue: 17),
      ])
  }

  @Test("RGB reader takes the leading digits of each line and ignores lines without them")
  func rgbReaderOnAndroidBytes() throws {
    let file = "#ff0000 Red\n00ff00\nzz\n0000ff Blue\n"
    let colours = try RGBPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
  }

  @Test("RGB writer joins colours with CRLF and writes no line break after the last one")
  func rgbWriterLayout() {
    let data = RGBPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 255, blue: 0),
    ])
    #expect(Array(data) == Array("#ff0000 Red\r\n#00ff00".utf8))
  }

  @Test("RGBA writer writes #rrggbbaa lines with CRLF between them")
  func rgbaWriterLayout() {
    let data = RGBAPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0, alpha: 128),
      PaletteColour(red: 0, green: 255, blue: 0),
    ])
    #expect(Array(data) == Array("#ff000080 Red\r\n#00ff00ff".utf8))
  }

  @Test("RGBA reader reads alpha and names and rejects a line that is not a colour")
  func rgbaReaderOnAndroidBytes() throws {
    let file = "#ff000080 Red\r\n00ff00ff\n"
    let colours = try RGBAPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0, alpha: 128),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try RGBAPaletteCoder.decode(Data("#ff0000\nzz\n".utf8))
    }
  }
}
