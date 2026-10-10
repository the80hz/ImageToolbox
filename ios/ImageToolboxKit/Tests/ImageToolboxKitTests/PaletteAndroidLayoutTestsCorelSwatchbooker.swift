import Foundation
import Testing

@testable import ImageToolboxKit

// Layouts of the CorelDraw XML and Swatchbooker palettes, checked against the Android coders. The
// Swatchbooker XML is read back from its zip entry, and the CorelDraw GUID is replaced before the
// text is compared, since the Android coder makes a new one each time.

@Suite("Android layout: CorelDraw XML and Swatchbooker palettes")
struct PaletteAndroidLayoutTestsCorelSwatchbooker {

  @Test("CorelDraw XML writer writes one page of RGB tints with six decimals")
  func corelXMLWriterLayout() throws {
    let data = CorelXMLPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255),
    ])
    let text = String(decoding: data, as: UTF8.self).replacingOccurrences(
      of: #"guid="[^"]*""#, with: "guid=\"ID\"", options: .regularExpression)
    let expected =
      "<?xml version=\"1.0\"?>\n<palette guid=\"ID\">\n<colors>\n"
      + "<page><color name=\"Red\" cs=\"RGB\" tints=\"1.000000,0.000000,0.000000\"/>\n"
      + "<color cs=\"RGB\" tints=\"0.000000,0.501961,1.000000\"/>\n"
      + "</page>\n</colors>\n</palette>\n"
    #expect(text == expected)
  }

  @Test("CorelDraw XML reader reads the global page, then named pages after it")
  func corelXMLReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\"?><palette guid=\"x\"><colors>"
      + "<page><color name=\"Red\" cs=\"RGB\" tints=\"1,0,0\"/>"
      + "<color name=\"Cyan\" cs=\"CMYK\" tints=\"1,0,0,0\"/></page>"
      + "<page name=\"G\"><color cs=\"gray\" tints=\"0.5\"/></page>"
      + "</colors></palette>"
    let colours = try CorelXMLPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Cyan", red: 0, green: 255, blue: 255),
        PaletteColour(red: 128, green: 128, blue: 128),
      ])
  }

  @Test("Swatchbooker writer writes the Android swatchbook.xml inside the zip entry")
  func swatchbookerWriterLayout() throws {
    let data = SwatchbookerPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
    ])
    let entries = try ZipReader.entries(in: data) { $0 == "swatchbook.xml" }
    let xml = String(decoding: try #require(entries.first).data, as: UTF8.self)
    let expected =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<SwatchBook xmlns=\"http://www.selapa.net/swatchbook/1.0/\" "
      + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
      + "  <metadata>\n    <dc:title></dc:title>\n  </metadata>\n"
      + "  <materials>\n"
      + "    <color usage=\"standard\">\n"
      + "      <metadata>\n"
      + "        <dc:title>Red</dc:title>\n"
      + "        <dc:identifier>color_0</dc:identifier>\n"
      + "      </metadata>\n"
      + "      <values model=\"RGB\">\n"
      + "        1.0 0.0 0.0 1.0\n"
      + "      </values>\n"
      + "    </color>\n"
      + "  </materials>\n"
      + "  <book>\n"
      + "    <swatch material=\"color_0\"/>\n"
      + "  </book>\n"
      + "</SwatchBook>\n"
    #expect(xml == expected)
  }

  @Test("Swatchbooker reader reads the Android RGB values with their alpha")
  func swatchbookerReaderOnAndroidBytes() throws {
    let xml =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<SwatchBook xmlns=\"http://www.selapa.net/swatchbook/1.0/\" "
      + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
      + "  <materials>\n"
      + "    <color usage=\"standard\">\n"
      + "      <metadata>\n"
      + "        <dc:title>Red</dc:title>\n"
      + "        <dc:identifier>color_0</dc:identifier>\n"
      + "      </metadata>\n"
      + "      <values model=\"RGB\">\n"
      + "        1.0 0.0 0.0 1.0\n"
      + "      </values>\n"
      + "    </color>\n"
      + "  </materials>\n"
      + "  <book>\n"
      + "    <swatch material=\"color_0\"/>\n"
      + "  </book>\n"
      + "</SwatchBook>\n"
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "swatchbook.xml", data: Data(xml.utf8))
    ])
    let colours = try SwatchbookerPaletteCoder.decode(archive)
    #expect(colours == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }
}
