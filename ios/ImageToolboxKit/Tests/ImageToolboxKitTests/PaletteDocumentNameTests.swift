import Foundation
import Testing

@testable import ImageToolboxKit

// The palette name in the formats that store one. Each format is read and written as the Android
// coder does: a name that is empty or missing reads as no name, and a format that needs a name
// writes its default ("Palette" or "Untitled") when the palette has none.

@Suite("Palette documents: palette names")
struct PaletteDocumentNameTests {

  private static let red = PaletteColour(name: "Red", red: 255, green: 0, blue: 0)
  private static let blue = PaletteColour(name: "Blue", red: 0, green: 0, blue: 255)

  /// A document with the name and the two test colours, which every format can store.
  private static func document(named name: String?) -> PaletteDocument {
    PaletteDocument(name: name, colours: [red, blue])
  }

  @Test("GIMP reads the Name line and writes it, with an empty name when there is none")
  func gimpName() throws {
    let text = "GIMP Palette\nName: Warm set\nColumns: 0\n# note\n255 0 0 Red\n"
    let read = try GIMPPaletteCoder.decodeDocument(Data(text.utf8))
    #expect(read == PaletteDocument(name: "Warm set", colours: [Self.red]))

    let written = GIMPPaletteCoder.encodeDocument(Self.document(named: "Warm set"))
    #expect(
      String(decoding: written, as: UTF8.self)
        == "GIMP Palette\nName: Warm set\nColumns: 0\n#Colors: 2\n"
        + "255\t0\t0\tRed\n0\t0\t255\tBlue\n")
    let unnamed = GIMPPaletteCoder.encodeDocument(Self.document(named: nil))
    #expect(
      String(decoding: unnamed, as: UTF8.self).hasPrefix("GIMP Palette\nName: \nColumns: 0\n"))
  }

  @Test(
    "Paint.NET reads the Palette Name comment, the last one wins, and writes it after the header")
  func paintNETName() throws {
    let text =
      "; paint.net Palette File\n; Palette Name: First\n; Palette: Warm\nFFFF0000\n"
    let read = try PaintNETPaletteCoder.decodeDocument(Data(text.utf8))
    #expect(
      read == PaletteDocument(name: "Warm", colours: [PaletteColour(red: 255, green: 0, blue: 0)]))

    let written = String(
      decoding: PaintNETPaletteCoder.encodeDocument(Self.document(named: "Warm")), as: UTF8.self)
    #expect(written.contains("; Palette Name: Warm\r\n"))
    #expect(
      !String(
        decoding: PaintNETPaletteCoder.encodeDocument(Self.document(named: nil)), as: UTF8.self
      ).contains("Palette Name"))
  }

  @Test("Adobe Colour Book writes the title, or Palette when there is none, and keeps the title")
  func acbName() throws {
    let named = try ACBPaletteCoder.decodeDocument(
      ACBPaletteCoder.encodeDocument(Self.document(named: "Warm")))
    #expect(named.name == "Warm")

    let unnamed = try ACBPaletteCoder.decodeDocument(
      ACBPaletteCoder.encodeDocument(Self.document(named: nil)))
    #expect(unnamed.name == "Palette")
  }

  @Test("Adobe Colour Book keeps only the text after the last equals sign of a $$$ title")
  func acbDollarTitle() throws {
    let data = ACBPaletteCoder.encodeDocument(Self.document(named: "$$$/Book=Real"))
    #expect(try ACBPaletteCoder.decodeDocument(data).name == "Real")
  }

  @Test("Corel Palette stores the name in its header and writes Palette when there is none")
  func corelPaletteName() throws {
    let named = try CPLPaletteCoder.decodeDocument(
      CPLPaletteCoder.encodeDocument(Self.document(named: "Warm")))
    #expect(named.name == "Warm")
    #expect(named.colours == [Self.red, Self.blue])

    let unnamed = try CPLPaletteCoder.decodeDocument(
      CPLPaletteCoder.encodeDocument(Self.document(named: nil)))
    #expect(unnamed.name == "Palette")
  }

  @Test("Basic XML reads and writes the name attribute of the palette element")
  func basicXMLName() throws {
    let written = BasicXMLPaletteCoder.encodeDocument(Self.document(named: "Warm & cool"))
    #expect(String(decoding: written, as: UTF8.self).contains("<palette name=\"Warm &amp; cool\">"))
    #expect(try BasicXMLPaletteCoder.decodeDocument(written).name == "Warm & cool")
    let unnamed = BasicXMLPaletteCoder.encodeDocument(Self.document(named: nil))
    #expect(String(decoding: unnamed, as: UTF8.self).contains("<palette>\n"))
  }

  @Test("CorelDraw XML keeps the name attribute of the palette element")
  func corelXMLName() throws {
    let written = CorelXMLPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(try CorelXMLPaletteCoder.decodeDocument(written).name == "Warm")
  }

  @Test("Scribus reads the Name attribute of SCRIBUSCOLORS and writes it back")
  func scribusName() throws {
    let written = ScribusXMLPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(String(decoding: written, as: UTF8.self).contains("<SCRIBUSCOLORS Name=\"Warm\" >"))
    #expect(try ScribusXMLPaletteCoder.decodeDocument(written).name == "Warm")
    let lower = Data(
      "<?xml version=\"1.0\"?><SCOLORS name=\"Cool\"><COLOR RGB=\"#ff0000\" NAME=\"Red\"/></SCOLORS>"
        .utf8)
    #expect(try ScribusXMLPaletteCoder.decodeDocument(lower).name == "Cool")
  }

  @Test("Swatchbooker keeps the book title, which is the palette name")
  func swatchbookerName() throws {
    let written = SwatchbookerPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(try SwatchbookerPaletteCoder.decodeDocument(written).name == "Warm")
    let unnamed = try SwatchbookerPaletteCoder.decodeDocument(
      SwatchbookerPaletteCoder.encodeDocument(Self.document(named: nil)))
    #expect(unnamed.name == nil)
  }

  @Test("Autodesk Colour Book reads the book name, or the first page name when there is none")
  func autodeskName() throws {
    let entry =
      "<colorEntry><colorName>A</colorName><RGB8><red>1</red><green>2</green>"
      + "<blue>3</blue></RGB8></colorEntry>"
    let withBook = Data(
      "<colorBook><bookName>Book</bookName><colorPage name=\"Page\">\(entry)</colorPage></colorBook>"
        .utf8)
    let book = try AutodeskColorBookPaletteCoder.decodeDocument(withBook)
    #expect(book.name == "Book")
    #expect(book.colours == [PaletteColour(name: "A", red: 1, green: 2, blue: 3)])

    let withoutBook = Data(
      "<colorBook><colorPage name=\"Page\">\(entry)</colorPage></colorBook>".utf8)
    #expect(try AutodeskColorBookPaletteCoder.decodeDocument(withoutBook).name == "Page")

    let written = AutodeskColorBookPaletteCoder.encodeDocument(Self.document(named: nil))
    #expect(String(decoding: written, as: UTF8.self).contains("<bookName>Untitled</bookName>"))
  }

  @Test("DCP keeps the palette name")
  func dcpName() throws {
    let data = DCPPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(try DCPPaletteCoder.decodeDocument(data).name == "Warm")
    #expect(
      try DCPPaletteCoder.decodeDocument(DCPPaletteCoder.encodeDocument(Self.document(named: nil)))
        .name == nil)
  }

  @Test("JSON, the Simple Palette and Infinite Painter keep the palette name")
  func jsonFamilyNames() throws {
    let named = Self.document(named: "Warm")
    #expect(
      try JSONPaletteCoder.decodeDocument(JSONPaletteCoder.encodeDocument(named)).name == "Warm")
    #expect(
      try SimplePaletteCoder.decodeDocument(SimplePaletteCoder.encodeDocument(named)).name == "Warm"
    )
    #expect(
      try InfinitePainterPaletteCoder.decodeDocument(
        InfinitePainterPaletteCoder.encodeDocument(named)
      )
      .name == "Warm")

    let simple = String(
      decoding: SimplePaletteCoder.encodeDocument(Self.document(named: nil)), as: UTF8.self)
    #expect(simple.hasPrefix("{\n    \"name\": null,\n"))
    let painter = String(
      decoding: InfinitePainterPaletteCoder.encodeDocument(Self.document(named: nil)), as: UTF8.self
    )
    #expect(painter.hasSuffix("\"name\": \"\"\n}"))
  }

  @Test("Procreate names the palette after its first swatch set and writes the name back")
  func procreateName() throws {
    let data = ProcreateSwatchesPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(try ProcreateSwatchesPaletteCoder.decodeDocument(data).name == "Warm")
  }

  @Test("Krita names the colour set and writes the name attribute")
  func kritaName() throws {
    let data = KRITAPaletteCoder.encodeDocument(Self.document(named: "Warm"))
    #expect(try KRITAPaletteCoder.decodeDocument(data).name == "Warm")
  }

  @Test("Affinity Designer stores the name and writes Palette when there is none")
  func affinityName() throws {
    let named = try AFPaletteCoder.decodeDocument(
      AFPaletteCoder.encodeDocument(Self.document(named: "Warm")))
    #expect(named.name == "Warm")
    #expect(named.colours == [Self.red, Self.blue])
    let unnamed = try AFPaletteCoder.decodeDocument(
      AFPaletteCoder.encodeDocument(Self.document(named: nil)))
    #expect(unnamed.name == "Palette")
  }

  @Test("SK1 reads the set_name line and writes quotes in names as underscores")
  func sk1Name() throws {
    let text =
      "##sK1 palette\nPalette.Builder()\nset_name('Warm')\nset_source('x')\n"
      + "color(['RGB', [1.0, 0.0, 0.0], 1.0, 'Red'])\npalette_end()\n"
    let read = try SKPPaletteCoder.decodeDocument(Data(text.utf8))
    #expect(read.name == "Warm")
    #expect(read.colours == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])

    let written = String(
      decoding: SKPPaletteCoder.encodeDocument(
        PaletteDocument(name: "It's \"set\"", colours: [Self.red])), as: UTF8.self)
    #expect(written.contains("set_name('It_s _set_')\n"))
  }

  @Test("Swift export writes the palette name comment and one array per group")
  func swiftExportNameAndGroups() {
    let document = PaletteDocument(
      name: "Warm", colours: [Self.red],
      groups: [PaletteColourGroup(name: "Cool", colours: [Self.blue])])
    let text = String(decoding: SwiftPaletteCoder.encodeDocument(document), as: UTF8.self)
    #expect(text.hasPrefix("// Palette: Warm\nstruct ExportedPalettes {\n"))
    #expect(text.contains("   // Group (global)\n   static let group0: [CGColor] = ["))
    #expect(text.contains("   // Group (Cool)\n   static let group1: [CGColor] = ["))
    #expect(text.contains("red: 1.0000, green: 0.0000, blue: 0.0000, alpha: 1.0000), // Red"))
    #expect(text.contains("red: 0.0000, green: 0.0000, blue: 1.0000, alpha: 1.0000), // Blue"))
  }

  @Test("Kotlin export derives the package from the name and names the palette in its header")
  func kotlinExportName() {
    let named = String(
      decoding: KotlinPaletteCoder.encodeDocument(
        PaletteDocument(name: "Warm Set!", colours: [Self.red])), as: UTF8.self)
    #expect(named.hasPrefix("package warmset\n"))
    #expect(named.contains(" * Exported palette: Warm Set!\n"))

    let unnamed = String(
      decoding: KotlinPaletteCoder.encodeDocument(PaletteDocument(colours: [Self.red])),
      as: UTF8.self)
    #expect(unnamed.hasPrefix("package palette\n"))
    #expect(unnamed.contains(" * Exported palette: Untitled\n"))

    let digits = String(
      decoding: KotlinPaletteCoder.encodeDocument(PaletteDocument(name: "9lives", colours: [])),
      as: UTF8.self)
    #expect(digits.hasPrefix("package palette\n"))
  }

  @Test("A document with no name compares equal to the flat colours it wraps")
  func documentWrapsColours() {
    let document = PaletteDocument(colours: [Self.red, Self.blue])
    #expect(document.name == nil)
    #expect(document.allColours == [Self.red, Self.blue])
    #expect(PaletteDocument(name: "", colours: []).name == nil)
  }
}
