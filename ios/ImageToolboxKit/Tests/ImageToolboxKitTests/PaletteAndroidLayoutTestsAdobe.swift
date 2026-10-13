import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the Adobe Photoshop swatch (ACO) and Adobe Colour Table (ACT) formats, checked
// against the Android coders.

@Suite("Android layout: Adobe swatches (ACO) and colour tables (ACT)")
struct PaletteAndroidLayoutTestsAdobe {

  @Test("ACO writer writes a version 1 and a version 2 section with 16-bit channel values")
  func acoWriterLayout() {
    let data = ACOPaletteCoder.encode([
      PaletteColour(name: "A", red: 255, green: 0, blue: 128)
    ])
    let expected: [UInt8] = [
      // Version 1: version, count, then the colour space and four 16-bit values.
      0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x80, 0x80, 0x00, 0x00,
      // Version 2: the same colour and a name, which is a 32-bit count of units and the units.
      0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x80, 0x80, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x41,
    ]
    #expect(Array(data) == expected)
  }

  @Test("ACO reader accepts a version 2 name whose count includes the zero unit")
  func acoReaderOnAdobeNames() throws {
    let file: [UInt8] = [
      0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      // Name count 2 includes the zero unit, as the Adobe format writes it.
      0x00, 0x00, 0x00, 0x02, 0x00, 0x41, 0x00, 0x00,
    ]
    let colours = try ACOPaletteCoder.decode(Data(file))
    #expect(colours == [PaletteColour(name: "A", red: 255, green: 0, blue: 0)])
  }

  @Test("ACO reader gives an unknown colour space the Android fallback colour")
  func acoUnknownColourSpace() throws {
    let file: [UInt8] = [
      0x00, 0x01, 0x00, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
    let colours = try ACOPaletteCoder.decode(Data(file))
    #expect(
      colours == [
        PaletteColour(name: "Unsupported Colorspace", red: 255, green: 0, blue: 0, alpha: 128)
      ])
  }

  @Test("ACT writer pads to 256 entries and writes the count and 0xFFFF without transparency")
  func actWriterLayout() {
    let data = Array(
      ACTPaletteCoder.encode([PaletteColour(red: 1, green: 2, blue: 3, alpha: 0)]))
    #expect(data.count == 772)
    #expect(Array(data.prefix(3)) == [1, 2, 3])
    #expect(data[3..<768].allSatisfy { $0 == 0 })
    // The alpha channel is not written, so the index is always 0xFFFF.
    #expect(Array(data.suffix(4)) == [0x00, 0x01, 0xFF, 0xFF])
  }

  @Test("ACT reader applies the colour count, a missing transparency index and the names")
  func actReaderOnAndroidBytes() throws {
    var file: [UInt8] = [1, 2, 3, 4, 5, 6]
    file += [UInt8](repeating: 0, count: 768 - file.count)
    file += [0x00, 0x02, 0xFF, 0xFF]  // Two colours, no transparency.
    file += Array("; ACT_NAMES: A|".utf8)
    let colours = try ACTPaletteCoder.decode(Data(file))
    #expect(
      colours == [
        PaletteColour(name: "A", red: 1, green: 2, blue: 3),
        PaletteColour(red: 4, green: 5, blue: 6),
      ])
  }
}
