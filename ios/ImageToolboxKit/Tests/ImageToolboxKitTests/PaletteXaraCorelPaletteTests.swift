import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Xara and Corel Palette binary formats")
struct PaletteXaraCorelPaletteTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  private func le16(_ value: Int) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
  }

  /// The parts laid end to end, so that long byte sequences stay readable.
  private func bytes(_ parts: [UInt8]...) -> Data {
    Data(parts.flatMap { $0 })
  }

  @Test("Xara records hold four 16-bit values and a 14-byte name")
  func jcwLayout() {
    let encoded = JCWPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
    let data = [UInt8](encoded)
    var expected: [UInt8] = Array("JCW".utf8) + [1] + le16(1) + [10, 14]
    expected += le16(10000) + le16(0) + le16(0) + le16(0)
    expected += Array("Red".utf8)
    expected += [UInt8](repeating: 0, count: 11)
    #expect(data == expected)
  }

  @Test("Xara round trip keeps names and the RGB values to the nearest 8-bit step")
  func jcwRoundTrip() throws {
    #expect(try JCWPaletteCoder.decode(JCWPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Xara names a colour without a name by its index, and reads HSB colours")
  func jcwDefaultNameAndHSB() throws {
    let rgb = bytes(
      Array("JCW".utf8), [1], le16(1), [2, 0], le16(10000), le16(0), le16(0), le16(0))
    #expect(
      try JCWPaletteCoder.decode(rgb) == [PaletteColour(name: "c0", red: 255, green: 0, blue: 0)])

    // Hue 0, saturation 1 and brightness 1 give red. Each colour holds its four values, then the
    // name, as the Android coder reads them.
    let hsb = bytes(
      Array("JCW".utf8), [1], le16(1), [3, 3], le16(0), le16(10000), le16(10000), le16(0),
      Array("Hue".utf8))
    #expect(
      try JCWPaletteCoder.decode(hsb) == [PaletteColour(name: "Hue", red: 255, green: 0, blue: 0)])
  }

  @Test("Corel Palette encodes the version 0xDCDC layout with BGR colours")
  func cplLayout() {
    let encoded = CPLPaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
    let data = [UInt8](encoded)
    var expected: [UInt8] = [0xDC, 0xDC, 7]
    expected += Array("Palette".utf8)
    expected += le16(1) + le16(5) + [0, 0] + [0, 0, 0, 0]
    expected += [0, 0, 255, 0]
    expected += [3]
    expected += Array("Red".utf8)
    #expect(data == expected)
  }

  @Test("Corel Palette round trip keeps names and colours")
  func cplRoundTrip() throws {
    #expect(try CPLPaletteCoder.decode(CPLPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Corel Palette reads the version 0xCCBC layout, which has no name")
  func cplWithoutName() throws {
    // One BGR record with no name: blue 0, green 0, red 255.
    let data = bytes(
      [0xCC, 0xBC], le16(1), le16(5), [0, 0], [0, 0, 0, 0], [0, 0, 255, 0], [0])
    #expect(try CPLPaletteCoder.decode(data) == [PaletteColour(red: 255, green: 0, blue: 0)])
  }

  @Test("Corel Palette reads grey records as the inverse of the black ink")
  func cplGrey() throws {
    // Model 9: four bytes, then the black ink (0 is white), then three bytes.
    let data = bytes(
      [0xDC, 0xDC, 0], le16(1), le16(9), [0, 0], [0, 0, 0, 0], [0], [0, 0, 0], [0])
    #expect(try CPLPaletteCoder.decode(data) == [PaletteColour(red: 255, green: 255, blue: 255)])
  }
}
