import Foundation
import Testing

@testable import ImageToolboxKit

// Layouts of the XML palette formats (Android colors.xml, Scribus and OpenOffice), checked against
// the Android coders.

@Suite("Android layout: colors.xml, Scribus and OpenOffice palettes")
struct PaletteAndroidLayoutTestsXML {

  @Test("colors.xml writer writes uppercase #AARRGGBB and underscores in names")
  func colorsXMLWriterLayout() {
    let data = AndroidColorsXMLPaletteCoder.encode([
      PaletteColour(name: "Hot Pink", red: 255, green: 0, blue: 128),
      PaletteColour(red: 0, green: 0, blue: 0),
    ])
    let expected =
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
      + "   <color name=\"Hot_Pink\">#FFFF0080</color>\n"
      + "   <color name=\"color_1\">#FF000000</color>\n"
      + "</resources>\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("colors.xml reader reads ARGB, names unnamed colours by position and skips bad values")
  func colorsXMLReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\" encoding=\"utf-8\"?><resources>"
      + "<color name=\"accent\">#80FF0000</color><color>#FF00FF00</color>"
      + "<color name=\"bad\">#12</color></resources>"
    let colours = try AndroidColorsXMLPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "accent", red: 255, green: 0, blue: 0, alpha: 128),
        PaletteColour(name: "color_1", red: 0, green: 255, blue: 0),
      ])
  }

  @Test("Scribus writer writes RGB colours with names and the space before the closing bracket")
  func scribusWriterLayout() {
    let data = ScribusXMLPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 255),
    ])
    let expected =
      "<?xml version=\"1.0\"?>\n<SCRIBUSCOLORS >\n"
      + "<COLOR RGB=\"#ff0000\" NAME=\"Red\" />\n"
      + "<COLOR RGB=\"#0000ff\" />\n"
      + "</SCRIBUSCOLORS>\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Scribus reader reads RGB and CMYK hex colours, and skips a colour with neither")
  func scribusReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\"?><SCRIBUSCOLORS Name=\"Demo\">"
      + "<COLOR RGB=\"#ff0000\" NAME=\"Red\" />"
      + "<COLOR CMYK=\"#ffffffff\" NAME=\"Black\" />"
      + "<COLOR CMYK=\"ffffffff\"/><COLOR NAME=\"Nothing\"/></SCRIBUSCOLORS>"
    let colours = try ScribusXMLPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Black", red: 0, green: 0, blue: 0),
        PaletteColour(red: 0, green: 0, blue: 0),
      ])
  }

  @Test("OpenOffice writer writes the Android namespace header and uppercase draw:color values")
  func openOfficeWriterLayout() {
    let data = OpenOfficePaletteCoder.encode([
      PaletteColour(name: "Red & Blue", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    let text = String(decoding: data, as: UTF8.self)
    let header =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<office:color-table xmlns:office=\"http://openoffice.org/2000/office\" "
      + "xmlns:style=\"http://openoffice.org/2000/style\" "
      + "xmlns:text=\"http://openoffice.org/2000/text\" "
      + "xmlns:table=\"http://openoffice.org/2000/table\" "
      + "xmlns:draw=\"http://openoffice.org/2000/drawing\" "
      + "xmlns:fo=\"http://www.w3.org/1999/XSL/Format\" "
      + "xmlns:xlink=\"http://www.w3.org/1999/xlink\" "
      + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
      + "xmlns:meta=\"http://openoffice.org/2000/meta\" "
      + "xmlns:number=\"http://openoffice.org/2000/datastyle\" "
      + "xmlns:svg=\"http://www.w3.org/2000/svg\" "
      + "xmlns:chart=\"http://openoffice.org/2000/chart\" "
      + "xmlns:dr3d=\"http://openoffice.org/2000/dr3d\" "
      + "xmlns:math=\"http://www.w3.org/1998/Math/MathML\" "
      + "xmlns:form=\"http://openoffice.org/2000/form\" "
      + "xmlns:script=\"http://openoffice.org/2000/script\">\n"
    #expect(text.hasPrefix(header))
    #expect(
      text.hasSuffix(
        "<draw:color draw:name=\"Red &amp; Blue\" draw:color=\"#FF0000\"/>\n"
          + "<draw:color draw:name=\"\" draw:color=\"#010203\"/>\n"
          + "</office:color-table>\n"))
  }

  @Test("OpenOffice reader reads draw:color values, with an unnamed colour when no name is set")
  func openOfficeReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      + "<office:color-table xmlns:office=\"http://openoffice.org/2000/office\" "
      + "xmlns:draw=\"http://openoffice.org/2000/drawing\">"
      + "<draw:color draw:name=\"Red\" draw:color=\"#FF0000\"/>"
      + "<draw:color draw:color=\"#00ff00\"/></office:color-table>"
    let colours = try OpenOfficePaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
  }
}
