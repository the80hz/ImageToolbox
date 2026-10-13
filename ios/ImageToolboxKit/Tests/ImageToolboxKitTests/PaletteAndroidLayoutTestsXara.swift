import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layout of the Xara palette (JCW), checked against the Android coder.

@Suite("Android layout: Xara palettes (JCW)")
struct PaletteAndroidLayoutTestsXara {

  /// Two RGB colours as the Android coder writes them: "Red" with full red, and a colour whose
  /// channels are truncated to 5019, 39 and 78 out of 10000.
  private static let androidBytes: [UInt8] = [
    0x4A, 0x43, 0x57,  // "JCW"
    0x01,  // version
    0x02, 0x00,  // two colours, little-endian
    0x0A,  // colour space code 10, RGB
    0x0E,  // name length 14
    // "Red": 10000, 0, 0 and a zero fourth value, then the name padded with zeros.
    0x10, 0x27, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x52, 0x65, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    // Unnamed: 5019, 39, 78 and a zero fourth value, then an empty name.
    0x9B, 0x13, 0x27, 0x00, 0x4E, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]

  @Test("Xara writer writes the header, truncated 16-bit channels and 14-byte names")
  func xaraWriterLayout() {
    let data = JCWPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 128, green: 1, blue: 2),
    ])
    #expect(Array(data) == Self.androidBytes)
  }

  @Test("Xara reader reads the Android colours and names an unnamed colour by its index")
  func xaraReaderOnAndroidBytes() throws {
    let colours = try JCWPaletteCoder.decode(Data(Self.androidBytes))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "c1", red: 128, green: 1, blue: 2),
      ])
  }
}
