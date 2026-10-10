import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the Affinity Designer, CLF and KOffice palettes, checked against the Android
// coders. The Affinity bytes are the ones the Android writer produces for a single red colour.

@Suite("Android layout: Affinity, CLF and KOffice palettes")
struct PaletteAndroidLayoutTestsAffinity {

  /// One red colour named "Red", as the Android AF writer lays it out: the byte order mark, the
  /// file name "Palette", the "VlaP" count, the "rloC" record with its "ABGR" floats, then the
  /// "VNaP" section with the UTF-8 names.
  private static let androidRed: [UInt8] = [
    0x00, 0xFF, 0x4B, 0x41,  // byte order mark, little-endian 0x414BFF00
    0x0B, 0x00, 0x00, 0x00,  // 11
    0x50, 0x6C, 0x43, 0x4E,  // "NClP" written in reverse
    0x07, 0x00, 0x00, 0x00, 0x50, 0x61, 0x6C, 0x65, 0x74, 0x74, 0x65,  // "Palette"
    0x50, 0x61, 0x6C, 0x56,  // "VlaP" written in reverse
    0x01, 0x00, 0x00, 0x00,  // one colour
    0x72, 0x6C, 0x6F, 0x43,  // "rloC"
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // six bytes that are not used
    0x41, 0x42, 0x47, 0x52,  // "ABGR"
    0x44, 0x6C, 0x6F, 0x63, 0x5F,  // "Dloc_"
    0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 1.0, 0.0, 0.0
    0x50, 0x61, 0x4E, 0x56,  // "VNaP" written in reverse
    0x00, 0x00, 0x00, 0x00,  // not used
    0x01, 0x00, 0x00, 0x00,  // one name
    0x03, 0x00, 0x00, 0x00, 0x52, 0x65, 0x64,  // "Red"
  ]

  @Test("Affinity writer matches the Android layout for one named colour")
  func affinityWriterLayout() {
    let data = AFPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
    #expect(Array(data) == Self.androidRed)
  }

  @Test("Affinity reader accepts the Android bytes and reads the name section")
  func affinityReaderOnAndroidBytes() throws {
    let colours = try AFPaletteCoder.decode(Data(Self.androidRed))
    #expect(colours == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }

  @Test("CLF writer writes name, L, a and b on one tab separated line per colour")
  func clfWriterLayout() throws {
    let data = CLFPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 0),
    ])
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 2)
    #expect(lines[0].split(separator: "\t").count == 4)
    #expect(lines[0].hasPrefix("Red\t"))
    #expect(lines[1].hasPrefix("Color\t"))
    // No line break follows the last colour, as in the Android coder.
    #expect(!String(decoding: data, as: UTF8.self).hasSuffix("\n"))
    let back = try CLFPaletteCoder.decode(data)
    #expect(
      back == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Color", red: 0, green: 0, blue: 0),
      ])
  }

  @Test("CLF reader takes decimal commas and skips lines without four fields")
  func clfReaderOnAndroidBytes() throws {
    let file = "Mid\t50,0\t0,0\t0,0\nbad line\n"
    let colours = try CLFPaletteCoder.decode(Data(file.utf8))
    let expected = PaletteLab.toSRGB(l: 50, a: 0, b: 0)
    #expect(
      colours == [
        PaletteColour(name: "Mid", red: expected.red, green: expected.green, blue: expected.blue)
      ])
  }

  @Test("KOffice writer writes the header, tab separated channels and optional names")
  func koOfficeWriterLayout() {
    let data = KOfficePaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    #expect(Array(data) == Array("KDE RGB Palette\n255\t0\t0\tRed\n1\t2\t3\n".utf8))
  }

  @Test("KOffice reader clamps channels above 255 and reads the name after the channels")
  func koOfficeReaderOnAndroidBytes() throws {
    let file = "KDE RGB Palette\n255 0 0 Red\n 1 2 3\t Blue\n300 0 0\nxx\n"
    let colours = try KOfficePaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Blue", red: 1, green: 2, blue: 3),
        PaletteColour(red: 255, green: 0, blue: 0),
      ])
  }
}
