import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the Corel Palette (CPL) versions that the Android reader accepts and the Android
// writer never writes, so they are built from the Android reader code. Versions 0xCCBC and 0xCCDC
// have no palette name. Versions 0xCDBC, 0xCDDC and 0xCDDD start with a header table of three
// entries, the name, the palette type and the colour count, each at the offset its entry gives.
// Colour names are Latin 1 for 0xCCDC and 0xCDDC, and UTF-16 for the other versions. Versions
// 0xCDBC and 0xCDDD give two colours per record unless the palette type is 5 or 16 or at least 38.
// Version 0xCDDD adds 12 bytes of row and column data after each record.

@Suite("Android layout: Corel Palette (CPL) versions the writer does not produce")
struct PaletteAndroidLayoutTestsCorelPaletteVersions {

  @Test("CPL version 0xCCBC reads UTF-16 colour names with no palette name")
  func cplVersionCCBC() throws {
    let bytes: [UInt8] = [
      0xCC, 0xBC,  // version, big-endian
      0x01, 0x00,  // one colour, little-endian
      0x05, 0x00,  // model 5, BGR fractions
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x00, 0x00, 0xFF, 0x00,  // blue, green, red, one unused byte
      0x03,  // name length, in UTF-16 units
      0x52, 0x00, 0x65, 0x00, 0x64, 0x00,  // "Red"
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }

  @Test("CPL version 0xCCBC with no colours is rejected")
  func cplVersionCCBCEmpty() {
    let bytes: [UInt8] = [0xCC, 0xBC, 0x00, 0x00]
    #expect(throws: PaletteFormatError.invalidFormat) {
      try CPLPaletteCoder.decode(Data(bytes))
    }
  }

  @Test("CPL version 0xCCDC reads Latin 1 names, and an unnamed colour gets none")
  func cplVersionCCDC() throws {
    let bytes: [UInt8] = [
      0xCC, 0xDC,  // version, big-endian
      0x02, 0x00,  // two colours, little-endian
      // Red, named "Caf" plus an e acute, which is the byte 0xE9 in Latin 1.
      0x05, 0x00,  // model 5, BGR fractions
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x00, 0x00, 0xFF, 0x00,  // blue, green, red, one unused byte
      0x04, 0x43, 0x61, 0x66, 0xE9,  // name length 4, "Caf" and 0xE9, which is e acute
      // Unnamed, with blue 3, green 2 and red 1.
      0x05, 0x00,  // model 5, BGR fractions
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x03, 0x02, 0x01, 0x00,  // blue, green, red, one unused byte
      0x00,  // name length 0
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [
          PaletteColour(name: "Caf\u{E9}", red: 255, green: 0, blue: 0),
          PaletteColour(red: 1, green: 2, blue: 3),
        ])
  }

  @Test("CPL version 0xCCDC reads a model 4 record with its fourth byte, and skips unknown models")
  func cplVersionCCDCModels() throws {
    let bytes: [UInt8] = [
      0xCC, 0xDC,  // version, big-endian
      0x03, 0x00,  // three colours, little-endian
      // Model 7 is unknown. Its eight bytes after the model and two unused bytes are skipped,
      // and it gives no colour. The name is "X".
      0x07, 0x00,  // model 7
      0x00, 0x00,  // two unused bytes
      0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,  // eight bytes that are skipped
      0x01, 0x58,  // name length 1, "X"
      // Model 4 is CMY. The Android reader takes four bytes after the four unused ones, and
      // ignores the last. The colour is cyan, named "C".
      0x04, 0x00,  // model 4
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0xFF, 0x00, 0x00, 0x7F,  // cyan, magenta, yellow, then the ignored byte
      0x01, 0x43,  // name length 1, "C"
      // Red, named "Red".
      0x05, 0x00,  // model 5
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x00, 0x00, 0xFF, 0x00,  // blue, green, red, one unused byte
      0x03, 0x52, 0x65, 0x64,  // name length 3, "Red"
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [
          PaletteColour(name: "C", red: 0, green: 255, blue: 255),
          PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        ])
  }

  @Test("CPL version 0xCDDC reads the header table and Latin 1 names, with one colour per record")
  func cplVersionCDDC() throws {
    let bytes: [UInt8] = [
      0xCD, 0xDC,  // version, big-endian
      0x03, 0x00, 0x00, 0x00,  // three header entries, little-endian
      0x01, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00,  // entry 1: the name at offset 30
      0x02, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00,  // entry 2: the palette type at 34
      0x03, 0x00, 0x00, 0x00, 0x24, 0x00, 0x00, 0x00,  // entry 3: the colour count at 36
      0x03, 0x50, 0x61, 0x6C,  // at 30: name length 3, "Pal"
      0x05, 0x00,  // at 34: palette type 5, which gives one colour per record
      0x01, 0x00,  // at 36: one colour, so the records start at 38
      0x05, 0x00,  // model 5
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x00, 0x00, 0xFF, 0x00,  // blue, green, red, one unused byte
      0x03, 0x52, 0x65, 0x64,  // name length 3, "Red"
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }

  @Test("CPL version 0xCDBC reads two colours per record, each with a UTF-16 name")
  func cplVersionCDBC() throws {
    let bytes: [UInt8] = [
      0xCD, 0xBC,  // version, big-endian
      0x03, 0x00, 0x00, 0x00,  // three header entries, little-endian
      0x01, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00,  // entry 1: the name at offset 30
      0x02, 0x00, 0x00, 0x00, 0x25, 0x00, 0x00, 0x00,  // entry 2: the palette type at 37
      0x03, 0x00, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00,  // entry 3: the colour count at 39
      0x03, 0x50, 0x00, 0x61, 0x00, 0x6C, 0x00,  // at 30: "Pal" in UTF-16, 3 units
      0x01, 0x00,  // at 37: palette type 1, which gives two colours per record
      0x01, 0x00,  // at 39: one record, so the records start at 41
      0x00, 0x00, 0x00, 0x00,  // a 4-byte prefix that is not used
      0x05, 0x00,  // first colour: model 5
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x00, 0x00, 0xFF, 0x00,  // blue, green, red, one unused byte
      0x02, 0x00,  // second colour: model 2, CMYK percentages
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x64, 0x00, 0x00, 0x00,  // cyan 100, magenta 0, yellow 0, black 0
      0x03,  // name length, in UTF-16 units, shared by both colours
      0x44, 0x00, 0x75, 0x00, 0x6F, 0x00,  // "Duo"
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [
          PaletteColour(name: "Duo", red: 255, green: 0, blue: 0),
          PaletteColour(name: "Duo", red: 0, green: 255, blue: 255),
        ])
  }

  @Test("CPL version 0xCDDD reads two colours per record and skips 12 bytes of row and column")
  func cplVersionCDDD() throws {
    let bytes: [UInt8] = [
      0xCD, 0xDD,  // version, big-endian
      0x03, 0x00, 0x00, 0x00,  // three header entries, little-endian
      0x01, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00,  // entry 1: the name at offset 30
      0x02, 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00,  // entry 2: the palette type at 31
      0x03, 0x00, 0x00, 0x00, 0x21, 0x00, 0x00, 0x00,  // entry 3: the colour count at 33
      0x00,  // at 30: name length 0
      0x01, 0x00,  // at 31: palette type 1, which gives two colours per record
      0x01, 0x00,  // at 33: one record, so the records start at 35
      0x00, 0x00, 0x00, 0x00,  // a 4-byte prefix that is not used
      0x03, 0x00,  // first colour: model 3, CMYK fractions
      0x00, 0x00,  // two unused bytes
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0xFF, 0x00, 0x00, 0x00,  // cyan 255, magenta, yellow and black 0
      0x09, 0x00,  // second colour: model 9, grey
      0x00, 0x00, 0x00, 0x00,  // four unused bytes
      0x80,  // black ink 128, which gives grey 127
      0x00, 0x00, 0x00,  // three unused bytes
      0x00,  // name length 0
      0x01, 0x00, 0x00, 0x00,  // row, as a 32-bit value
      0x02, 0x00, 0x00, 0x00,  // column, as a 32-bit value
      0x03, 0x00, 0x00, 0x00,  // a third 32-bit value
    ]
    #expect(
      try CPLPaletteCoder.decode(Data(bytes))
        == [
          PaletteColour(red: 0, green: 255, blue: 255),
          PaletteColour(red: 127, green: 127, blue: 127),
        ])
  }
}
