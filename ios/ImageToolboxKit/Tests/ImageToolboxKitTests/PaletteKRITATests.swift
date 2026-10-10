import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Krita palette format")
struct PaletteKRITATests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  /// The colour set from the Android test: a global sRGB colour, then a group with a CMYK colour.
  private static let colorset = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Colorset name="Demo Palette" comment="" columns="2" rows="1" readonly="false" version="1.0">
      <ColorSetEntry name="Red" id="red_1" bitdepth="F32" spot="false">
        <Position row="0" column="0"/>
        <sRGB r="1.0" g="0.0" b="0.0"/>
      </ColorSetEntry>
      <Group name="Group One" rows="1">
        <ColorSetEntry name="Green Spot" id="green_1" bitdepth="F32" spot="true">
          <Position row="0" column="0"/>
          <CMYK c="1.0" m="0.0" y="1.0" k="0.0"/>
        </ColorSetEntry>
      </Group>
    </Colorset>
    """

  @Test("Krita reads the colour set in a zip archive, global colours first")
  func decodesColorset() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "mimetype", data: Data("application/x-krita-palette".utf8)),
      ZipWriter.Entry(name: "colorset.xml", data: Data(Self.colorset.utf8)),
    ])
    #expect(
      try KRITAPaletteCoder.decode(archive) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Green Spot", red: 0, green: 255, blue: 0),
      ])
  }

  @Test("Krita sorts colours by their row and column")
  func sortsByPosition() throws {
    let xml = """
      <Colorset>
        <ColorSetEntry name="Second"><Position row="0" column="1"/><sRGB r="0" g="0" b="1"/></ColorSetEntry>
        <ColorSetEntry name="First"><Position row="0" column="0"/><sRGB r="1" g="0" b="0"/></ColorSetEntry>
      </Colorset>
      """
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "colorset.xml", data: Data(xml.utf8))
    ])
    #expect(try KRITAPaletteCoder.decode(archive).map(\.name) == ["First", "Second"])
  }

  @Test("Krita writes the mimetype first, stored without compression")
  func mimetypeIsStored() throws {
    let data = [UInt8](KRITAPaletteCoder.encode(Self.sample))
    // The local file header of the first entry: the method is at offset 8, and 0 is stored.
    #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
    #expect(Array(data[8..<10]) == [0, 0])
    #expect(Array(data[30..<38]) == Array("mimetype".utf8))
  }

  @Test("Krita writes the colour set with a grid of positions and six-decimal channels")
  func writesColorset() throws {
    let entries = try ZipReader.entries(in: KRITAPaletteCoder.encode(Self.sample)) { _ in true }
    #expect(entries.map(\.name) == ["mimetype", "colorset.xml", "profiles.xml"])
    let xml = String(decoding: entries[1].data, as: UTF8.self)
    #expect(xml.contains("columns=\"2\" rows=\"2\""))
    #expect(xml.contains("<sRGB r=\"1\" g=\"0\" b=\"0\"/>\n    <Position row=\"0\" column=\"0\"/>"))
    #expect(xml.contains("<Position row=\"1\" column=\"0\"/>"))
  }

  @Test("Krita round trip keeps names and colours")
  func roundTrip() throws {
    #expect(try KRITAPaletteCoder.decode(KRITAPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Krita rejects an archive without a colour set")
  func rejectsMissingColorset() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "other.xml", data: Data("<x/>".utf8))
    ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try KRITAPaletteCoder.decode(archive)
    }
  }
}
