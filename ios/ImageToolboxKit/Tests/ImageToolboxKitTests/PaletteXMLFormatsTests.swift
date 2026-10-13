import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("XML palette formats: Basic XML, Autodesk Color Book and SVG")
struct PaletteXMLFormatsTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green & Co", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255, alpha: 128),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  private static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  @Test("Basic XML round trip keeps names, hex values and alpha")
  func basicXMLRoundTrip() throws {
    #expect(
      try BasicXMLPaletteCoder.decode(BasicXMLPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Basic XML reads RGBA hex values and channel attributes")
  func basicXMLDecode() throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <palette name="Basic">
        <color name="Red" r="255" g="0" b="0" a="255" />
        <color hex="00FF00" />
        <color name="Bad" hex="zz" />
      </palette>
      """
    #expect(
      try BasicXMLPaletteCoder.decode(Data(xml.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
  }

  @Test("Autodesk Color Book reads entries inside pages and ignores the book name")
  func autodeskDecode() throws {
    let xml = """
      <colorBook>
        <bookName>Book</bookName>
        <colorPage>
          <colorEntry>
            <colorName>Red</colorName>
            <RGB8><red>255</red><green>0</green><blue>0</blue></RGB8>
          </colorEntry>
        </colorPage>
        <colorEntry>
          <colorName>Outside</colorName>
          <RGB8><red>1</red><green>1</green><blue>1</blue></RGB8>
        </colorEntry>
      </colorBook>
      """
    #expect(
      try AutodeskColorBookPaletteCoder.decode(Data(xml.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
      ])
  }

  @Test("Autodesk Color Book round trip keeps names and RGB values")
  func autodeskRoundTrip() throws {
    let encoded = AutodeskColorBookPaletteCoder.encode(Self.sample)
    #expect(Self.text(encoded).contains("<colorName>Green &amp; Co</colorName>"))
    #expect(
      try AutodeskColorBookPaletteCoder.decode(encoded)
        == Self.sample.map {
          PaletteColour(name: $0.name, red: $0.red, green: $0.green, blue: $0.blue)
        })
  }

  @Test("SVG writes the first swatch at the edge inset with its hex fill")
  func svgLayout() {
    let text = Self.text(
      SVGPaletteCoder.encode([
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
      ]))
    #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\t<svg "))
    #expect(
      text.contains(
        "      <rect x=\"4\" y=\"4\" width=\"40\" height=\"40\" id=\"Red\" fill=\"#FF0000\" "
          + "fill-opacity=\"1\" />\n"))
    #expect(text.hasSuffix("</svg>\n"))
  }

  @Test("SVG round trip keeps names, hex fills and opacity")
  func svgRoundTrip() throws {
    let colours = try SVGPaletteCoder.decode(SVGPaletteCoder.encode(Self.sample))
    #expect(colours.map(\.name) == Self.sample.map(\.name))
    #expect(colours.map(\.red) == Self.sample.map(\.red))
    #expect(colours.map(\.alpha) == Self.sample.map(\.alpha))
  }

  @Test("SVG reads rgb() and rgba() fills and skips rectangles without a colour")
  func svgDecode() throws {
    let svg = """
      <svg>
        <rect fill="rgb(10, 20, 30)" id="Plain" />
        <rect fill="rgba(255, 0, 0, 0.5)" fill-opacity="1" />
        <rect fill="none" />
        <rect fill="#0F0" fill-opacity="0.25" id="Short" />
      </svg>
      """
    #expect(
      try SVGPaletteCoder.decode(Data(svg.utf8)) == [
        PaletteColour(name: "Plain", red: 10, green: 20, blue: 30),
        PaletteColour(red: 255, green: 0, blue: 0, alpha: 128),
        PaletteColour(name: "Short", red: 0, green: 255, blue: 0, alpha: 64),
      ])
  }
}
