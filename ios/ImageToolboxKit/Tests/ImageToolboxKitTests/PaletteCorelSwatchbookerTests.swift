import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("CorelDraw XML and Swatchbooker palette formats")
struct PaletteCorelSwatchbookerTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  @Test("CorelDraw XML reads pages, colour spaces and the colour space templates")
  func corelXMLDecode() throws {
    let xml = """
      <?xml version="1.0"?>
      <palette name="Demo">
        <colorspaces>
          <cs name="Spot">
            <color name="Ignored" cs="rgb" tints="0,0,0"/>
          </cs>
        </colorspaces>
        <colors>
          <page name="">
            <color name="Red" cs="RGB" tints="1,0,0"/>
            <color name="Green" cs="cmyk" tints="1,0,1,0"/>
            <color name="Templated" cs="spot"/>
          </page>
          <page name="Named">
            <color name="Blue" cs="rgb" tints="0,0,1"/>
          </page>
        </colors>
      </palette>
      """
    #expect(
      try CorelXMLPaletteCoder.decode(Data(xml.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
        // The template is the first colour of the "Spot" colour space, which is black.
        PaletteColour(name: "Templated", red: 0, green: 0, blue: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
  }

  @Test("CorelDraw XML round trip keeps names and colours")
  func corelXMLRoundTrip() throws {
    #expect(
      try CorelXMLPaletteCoder.decode(CorelXMLPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Swatchbooker writes swatchbook.xml in a zip archive")
  func swatchbookerLayout() throws {
    let archive = SwatchbookerPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
    ])
    let entries = try ZipReader.entries(in: archive) { _ in true }
    #expect(entries.map(\.name) == ["swatchbook.xml"])
    let xml = String(decoding: entries[0].data, as: UTF8.self)
    #expect(xml.contains("<values model=\"RGB\">\n        1.0 0.0 0.0 1.0\n"))
    #expect(xml.contains("<swatch material=\"color_0\"/>"))
  }

  @Test("Swatchbooker round trip keeps names and colours")
  func swatchbookerRoundTrip() throws {
    #expect(
      try SwatchbookerPaletteCoder.decode(SwatchbookerPaletteCoder.encode(Self.sample))
        == Self.sample)
  }

  @Test("Swatchbooker lists colours in the order of the book, then the rest")
  func swatchbookerBookOrder() throws {
    let xml = """
      <SwatchBook xmlns:dc="http://purl.org/dc/elements/1.1/">
        <materials>
          <color><metadata><dc:title>First</dc:title><dc:identifier>a</dc:identifier></metadata>
            <values model="HSV">0 1 1</values></color>
          <color><metadata><dc:title>Second</dc:title><dc:identifier>b</dc:identifier></metadata>
            <values model="GRAY">0.5</values></color>
          <color><metadata><dc:title>Third</dc:title><dc:identifier>c</dc:identifier></metadata>
            <values model="CMYK">0 0 0 1</values></color>
        </materials>
        <book><swatch material="c"/><swatch material="a"/></book>
      </SwatchBook>
      """
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "swatchbook.xml", data: Data(xml.utf8))
    ])
    let colours = try SwatchbookerPaletteCoder.decode(archive)
    #expect(colours.map(\.name) == ["Third", "First", "Second"])
    #expect(colours[1] == PaletteColour(name: "First", red: 255, green: 0, blue: 0))
    #expect(colours[2] == PaletteColour(name: "Second", red: 128, green: 128, blue: 128))
  }
}
