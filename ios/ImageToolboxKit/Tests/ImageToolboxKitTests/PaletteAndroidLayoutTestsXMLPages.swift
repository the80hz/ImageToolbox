import Foundation
import Testing

@testable import ImageToolboxKit

// Layouts of the basic XML, Autodesk Color Book and SVG palettes, checked against the Android
// coders. The SVG expectations use the DecimalFormat "#.###" output the Android coder writes.

@Suite("Android layout: basic XML, Autodesk Color Book and SVG palettes")
struct PaletteAndroidLayoutTestsXMLPages {

  @Test("Basic XML writer writes RGBA hex and the decimal channels of each colour")
  func basicXMLWriterLayout() {
    let data = BasicXMLPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3, alpha: 128),
    ])
    let expected =
      "<?xml version=\"1.0\"?>\n<palette>\n"
      + "<color name=\"Red\" hex=\"ff0000ff\" r=\"255\" g=\"0\" b=\"0\" a=\"255\" />\n"
      + "<color hex=\"01020380\" r=\"1\" g=\"2\" b=\"3\" a=\"128\" />\n"
      + "</palette>\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Basic XML reader skips a colour whose hex is invalid and uses r, g, b otherwise")
  func basicXMLReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\"?><palette name=\"Demo\">"
      + "<color name=\"Red\" hex=\"ff0000\"/>"
      + "<color name=\"Blue\" r=\"0\" g=\"0\" b=\"255\" a=\"128\"/>"
      + "<color hex=\"zz\"/><color r=\"1\" g=\"2\"/></palette>"
    let colours = try BasicXMLPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255, alpha: 128),
      ])
  }

  @Test("Autodesk writer writes the book header, one page and the RGB8 block of each colour")
  func autodeskWriterLayout() {
    let data = AutodeskColorBookPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3),
    ])
    let expected =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<colorBook>\n"
      + "   <bookName>Untitled</bookName>\n"
      + "   <majorVersion>1</majorVersion>\n"
      + "   <minorVersion>0</minorVersion>\n"
      + "   <colorPage>\n"
      + "      <colorEntry>\n"
      + "         <colorName>Red</colorName>\n"
      + "         <RGB8>\n"
      + "            <red>255</red>\n"
      + "            <green>0</green>\n"
      + "            <blue>0</blue>\n"
      + "         </RGB8>\n"
      + "      </colorEntry>\n"
      + "      <colorEntry>\n"
      + "         <colorName>Color</colorName>\n"
      + "         <RGB8>\n"
      + "            <red>1</red>\n"
      + "            <green>2</green>\n"
      + "            <blue>3</blue>\n"
      + "         </RGB8>\n"
      + "      </colorEntry>\n"
      + "   </colorPage>\n"
      + "</colorBook>\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Autodesk reader reads the colour entries of a page and ignores the RGB8 wrapper")
  func autodeskReaderOnAndroidBytes() throws {
    let file =
      "<?xml version=\"1.0\"?><colorBook><bookName>Demo</bookName>"
      + "<colorPage name=\"P\"><colorEntry><colorName>Red</colorName>"
      + "<RGB8><red>255</red><green>0</green><blue>0</blue></RGB8></colorEntry>"
      + "</colorPage></colorBook>"
    let colours = try AutodeskColorBookPaletteCoder.decode(Data(file.utf8))
    #expect(colours == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }

  @Test("SVG writer writes the Android header, one rect per colour and the #.### numbers")
  func svgWriterLayout() {
    let data = SVGPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255, alpha: 128),
    ])
    let expected =
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
      + "\t<svg xmlns=\"http://www.w3.org/2000/svg\" "
      + "xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" "
      + "viewBox=\"0 0 600 48\" xml:space=\"preserve\">\n"
      + "      <rect x=\"4\" y=\"4\" width=\"40\" height=\"40\" id=\"Red\" "
      + "fill=\"#FF0000\" fill-opacity=\"1\" />\n"
      + "      <rect x=\"45\" y=\"4\" width=\"40\" height=\"40\" "
      + "fill=\"#0080FF\" fill-opacity=\".502\" />\n"
      + "</svg>\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("SVG reader reads hex, rgb and rgba fills with their opacity and skips other rects")
  func svgReaderOnAndroidBytes() throws {
    let file =
      "<svg><rect fill=\"#ff0000\" id=\"Red\"/>"
      + "<rect fill=\"rgb(0, 128, 255)\" fill-opacity=\"0.5\"/>"
      + "<rect fill=\"rgba(1, 2, 3, 0.25)\"/><rect fill=\"none\"/></svg>"
    let colours = try SVGPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 128, blue: 255, alpha: 128),
        PaletteColour(red: 1, green: 2, blue: 3, alpha: 64),
      ])
  }
}
