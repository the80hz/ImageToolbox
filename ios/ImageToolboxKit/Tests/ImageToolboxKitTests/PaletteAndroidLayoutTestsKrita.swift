import Foundation
import Testing

@testable import ImageToolboxKit

// Layout of the Krita palette archive written by the Android coder: a "mimetype" entry first, then
// the colorset XML and the profiles XML.

@Suite("Android layout: Krita palettes (KPL)")
struct PaletteAndroidLayoutTestsKrita {

  @Test("Krita writer writes mimetype first and the colorset XML of the Android coder")
  func kritaWriterLayout() throws {
    let data = KRITAPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255),
    ])
    let entries = try ZipReader.entries(in: data) { _ in true }
    #expect(entries.map(\.name) == ["mimetype", "colorset.xml", "profiles.xml"])
    #expect(
      String(decoding: try #require(entries.first).data, as: UTF8.self)
        == "application/x-krita-palette")

    let colorset = String(decoding: try #require(entries.dropFirst().first).data, as: UTF8.self)
    let expected =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<Colorset name=\"\" comment=\"\" columns=\"2\" rows=\"1\" readonly=\"false\" "
      + "version=\"1.0\">\n"
      + "  <ColorSetEntry name=\"Red\" id=\"global_1\" bitdepth=\"F32\" spot=\"false\">\n"
      + "    <sRGB r=\"1\" g=\"0\" b=\"0\"/>\n"
      + "    <Position row=\"0\" column=\"0\"/>\n"
      + "  </ColorSetEntry>\n"
      + "  <ColorSetEntry name=\"\" id=\"global_2\" bitdepth=\"F32\" spot=\"false\">\n"
      + "    <sRGB r=\"0\" g=\"0.501961\" b=\"1\"/>\n"
      + "    <Position row=\"0\" column=\"1\"/>\n"
      + "  </ColorSetEntry>\n"
      + "</Colorset>\n"
    #expect(colorset == expected)
  }
}
