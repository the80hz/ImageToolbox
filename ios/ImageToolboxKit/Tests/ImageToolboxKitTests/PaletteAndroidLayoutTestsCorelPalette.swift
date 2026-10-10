import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layout of the Corel Palette (CPL) format written by the Android coder: version 0xDCDC, the
// palette name, then one record per colour with the BGR model 5.

@Suite("Android layout: Corel Palette (CPL)")
struct PaletteAndroidLayoutTestsCorelPalette {

  /// Two colours as the Android coder writes them: "Red", and an unnamed colour.
  private static let androidBytes: [UInt8] = [
    0xDC, 0xDC,  // version, big-endian
    0x07, 0x50, 0x61, 0x6C, 0x65, 0x74, 0x74, 0x65,  // "Palette" with its length
    0x02, 0x00,  // two colours, little-endian
    // "Red": model 5, six unused bytes, then B, G, R and one unused byte, then the name.
    0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x03,
    0x52, 0x65, 0x64,
    // Unnamed: blue 3, green 2, red 1 and an empty name.
    0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x02, 0x01, 0x00, 0x00,
  ]

  @Test("CPL writer writes version 0xDCDC, the palette name and BGR records")
  func cplWriterLayout() {
    let data = CPLPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    #expect(Array(data) == Self.androidBytes)
  }

  @Test("CPL reader reads the Android records and their names")
  func cplReaderOnAndroidBytes() throws {
    let colours = try CPLPaletteCoder.decode(Data(Self.androidBytes))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 1, green: 2, blue: 3),
      ])
  }
}
