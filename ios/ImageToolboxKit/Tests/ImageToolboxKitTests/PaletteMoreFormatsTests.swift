import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("LAB conversion and more palette file formats")
struct PaletteMoreFormatsTests {

  /// Named opaque colours, which the new formats store.
  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  private static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  private static func be16(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
  }

  private static func be32(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  /// UTF-16BE code units with the count and terminator that ASE uses for names.
  private static func aseName(_ name: String) -> [UInt8] {
    let units = Array(name.utf16)
    var bytes = Self.be16(UInt16(units.count + 1))
    for unit in units {
      bytes += Self.be16(unit)
    }
    return bytes + [0, 0]
  }

  private static func aseColour(_ name: String, model: String, values: [Float]) -> [UInt8] {
    var body = Self.aseName(name) + Array(model.utf8)
    for value in values {
      body += Self.be32(value.bitPattern)
    }
    body += Self.be16(0)  // Global colour type.
    return Self.be16(0x0001) + Self.be32(UInt32(body.count)) + body
  }

  /// An ACO swatch: colour space code, four 16-bit components.
  private static func acoSwatch(_ space: UInt16, _ components: [UInt16]) -> [UInt8] {
    var bytes = Self.be16(space)
    for component in components {
      bytes += Self.be16(component)
    }
    return bytes
  }

  /// An ACO version 2 name: UTF-16 count including the terminator, then the units.
  private static func acoName(_ name: String) -> [UInt8] {
    let units = Array(name.utf16)
    var bytes = Self.be32(UInt32(units.count + 1))
    for unit in units {
      bytes += Self.be16(unit)
    }
    return bytes + [0, 0]
  }

  // MARK: - LAB

  @Test("LAB white and black convert to the sRGB extremes")
  func labExtremes() {
    let white = PaletteLab.toSRGB(l: 100, a: 0, b: 0)
    #expect(white.red == 255 && white.green == 255 && white.blue == 255)
    let black = PaletteLab.toSRGB(l: 0, a: 0, b: 0)
    #expect(black.red == 0 && black.green == 0 && black.blue == 0)
  }

  @Test("sRGB white and black convert to the LAB neutral axis")
  func labFromSRGBExtremes() {
    let white = PaletteLab.fromSRGB(red: 255, green: 255, blue: 255)
    #expect(abs(white.l - 100) < 0.05)
    #expect(abs(white.a) < 0.05)
    #expect(abs(white.b) < 0.05)
    let black = PaletteLab.fromSRGB(red: 0, green: 0, blue: 0)
    #expect(abs(black.l) < 1e-9)
    #expect(abs(black.a) < 1e-9)
    #expect(abs(black.b) < 1e-9)
  }

  @Test("sRGB red converts to the D65 reference values")
  func labReferenceRed() {
    let red = PaletteLab.fromSRGB(red: 255, green: 0, blue: 0)
    #expect(abs(red.l - 53.24) < 0.1)
    #expect(abs(red.a - 80.09) < 0.5)
    #expect(abs(red.b - 67.20) < 0.5)
  }

  @Test("LAB round trip returns every channel within one unit")
  func labRoundTrip() {
    let colours: [(UInt8, UInt8, UInt8)] = [
      (255, 0, 0), (0, 255, 0), (0, 0, 255), (64, 128, 191), (200, 100, 50), (12, 34, 56),
      (128, 128, 128), (255, 255, 0), (10, 200, 220),
    ]
    for (red, green, blue) in colours {
      let lab = PaletteLab.fromSRGB(red: red, green: green, blue: blue)
      let back = PaletteLab.toSRGB(l: lab.l, a: lab.a, b: lab.b)
      #expect(abs(Int(back.red) - Int(red)) <= 1)
      #expect(abs(Int(back.green) - Int(green)) <= 1)
      #expect(abs(Int(back.blue) - Int(blue)) <= 1)
    }
  }

  @Test("ASE LAB colours are read as sRGB, with L read from 0 to 1 as in the Android coder")
  func aseLABColours() throws {
    var file = Array("ASEF".utf8) + Self.be16(1) + Self.be16(0) + Self.be32(3)
    file += Self.aseColour("White", model: "LAB ", values: [1, 0, 0])
    file += Self.aseColour("Black", model: "LAB ", values: [0, 0, 0])
    file += Self.aseColour("Red", model: "RGB ", values: [1, 0, 0])
    #expect(
      try ASEPaletteCoder.decode(Data(file)) == [
        PaletteColour(name: "White", red: 255, green: 255, blue: 255),
        PaletteColour(name: "Black", red: 0, green: 0, blue: 0),
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      ])
  }

  @Test("ACO LAB swatches are read as sRGB, with a and b read as signed values")
  func acoLABColours() throws {
    var file = Self.be16(1) + Self.be16(3)
    file += Self.acoSwatch(7, [10000, 0, 0, 0])
    file += Self.acoSwatch(7, [5000, UInt16(bitPattern: Int16(-12800)), 0, 0])
    file += Self.acoSwatch(7, [0, 0, 0, 0])
    let colours = try ACOPaletteCoder.decode(Data(file))
    #expect(colours.count == 3)
    #expect(colours[0] == PaletteColour(red: 255, green: 255, blue: 255))
    // L 50 with a -128 is a strong green, so green is the largest channel.
    #expect(colours[1].green > colours[1].red && colours[1].green > colours[1].blue)
    #expect(colours[2] == PaletteColour(red: 0, green: 0, blue: 0))
  }

  @Test("ACO LAB names in the version 2 section are kept")
  func acoLABVersion2() throws {
    let white = Self.acoSwatch(7, [10000, 0, 0, 0])
    var file = Self.be16(1) + Self.be16(1) + white
    file += Self.be16(2) + Self.be16(1) + white + Self.acoName("Paper")
    #expect(
      try ACOPaletteCoder.decode(Data(file)) == [
        PaletteColour(name: "Paper", red: 255, green: 255, blue: 255)
      ])
  }

  @Test("JSON LAB colours are read as sRGB and keep their names, groups and alpha")
  func jsonLABColours() throws {
    let text =
      #"{"colors":[{"name":"White","colorSpace":"LAB","colorComponents":[100,0,0]},"#
      + #"{"colorSpace":"LAB","colorComponents":[100,0,0],"alpha":0.5}],"#
      + #""groups":[{"colors":[{"name":"Black","colorSpace":"LAB","colorComponents":[0,0,0]}]}]}"#
    #expect(
      try JSONPaletteCoder.decode(Data(text.utf8)) == [
        PaletteColour(name: "White", red: 255, green: 255, blue: 255),
        PaletteColour(red: 255, green: 255, blue: 255, alpha: 128),
        PaletteColour(name: "Black", red: 0, green: 0, blue: 0),
      ])
  }

  @Test("JSON rejects LAB colours with the wrong component count")
  func jsonLABErrors() {
    let text = #"{"colors":[{"colorSpace":"LAB","colorComponents":[50.0,0.0]}]}"#
    #expect(throws: PaletteFormatError.invalidFormat) {
      try JSONPaletteCoder.decode(Data(text.utf8))
    }
  }

  // MARK: - HEX

  @Test("HEX reads names from comment lines, several colours per line and alpha")
  func hexDecode() throws {
    #expect(
      try HEXPaletteCoder.decode(Data("; Red\n#ff0000\n#00ff0080 #0f0\n".utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0, alpha: 128),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
  }

  @Test("HEX round trip keeps names and alpha")
  func hexRoundTrip() throws {
    let colours =
      Self.sample + [PaletteColour(name: "Glass", red: 10, green: 20, blue: 30, alpha: 128)]
    let data = HEXPaletteCoder.encode(colours)
    #expect(Self.text(data).contains("; Accent\n#4080bf\n"))
    #expect(try HEXPaletteCoder.decode(data) == colours)
  }

  // MARK: - RGB and RGBA text

  @Test("RGB reads optional hashes, names and CRLF lines, and ignores alpha digits")
  func rgbDecode() throws {
    #expect(
      try RGBPaletteCoder.decode(Data("#ff0000 Red\r\n00ff00\r\n0000ffaa Blue".utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
  }

  @Test("RGB round trip keeps names, and each colour is written as #rrggbb")
  func rgbRoundTrip() throws {
    let data = RGBPaletteCoder.encode(Self.sample)
    #expect(Self.text(data).hasPrefix("#ff0000 Red\r\n#00ff00 Green\r\n"))
    #expect(try RGBPaletteCoder.decode(data) == Self.sample)
  }

  @Test("RGBA reads alpha from eight digits and rejects lines that are not colours")
  func rgbaDecode() throws {
    #expect(
      try RGBAPaletteCoder.decode(Data("ff000080 Red\n00ff00ff\n".utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0, alpha: 128),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try RGBAPaletteCoder.decode(Data("ff0000\nzz\n".utf8))
    }
  }

  @Test("RGBA round trip keeps names and alpha")
  func rgbaRoundTrip() throws {
    let colours =
      Self.sample + [PaletteColour(name: "Glass", red: 10, green: 20, blue: 30, alpha: 128)]
    let data = RGBAPaletteCoder.encode(colours)
    #expect(Self.text(data).hasSuffix("#0a141e80 Glass"))
    #expect(try RGBAPaletteCoder.decode(data) == colours)
  }

  // MARK: - Paint Shop Pro, Homesite, Skencil and Corel Painter

  @Test("Paint Shop Pro reads the JASC-PAL header, names and CRLF lines")
  func jascDecode() throws {
    let file = "JASC-PAL\r\n0100\r\n2\r\n; Red\r\n255 0 0\r\n0 0 255\r\n"
    #expect(
      try PaintShopProPaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 0, blue: 255),
      ])
    let data = PaintShopProPaletteCoder.encode(Self.sample)
    #expect(Self.text(data).hasPrefix("JASC-PAL\n0100\n4\n; Red\n255 0 0\n"))
    #expect(try PaintShopProPaletteCoder.decode(data) == Self.sample)
  }

  @Test("Homesite reads the three header lines, names and colours")
  func hplDecode() throws {
    let file = "Palette\nVersion 4.0\n-----------\n; Red\n255 0 0\n0 128 0\n"
    #expect(
      try HPLPaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 128, blue: 0),
      ])
    let data = HPLPaletteCoder.encode(Self.sample)
    #expect(try HPLPaletteCoder.decode(data) == Self.sample)
  }

  @Test("Skencil reads channels from 0 to 1 and an optional name")
  func skencilDecode() throws {
    // As in the Android regex, white space must follow the third channel, so the line without it
    // is skipped.
    let file = "##Sketch RGBPalette 0\n1.000000 0.000000 0.000000 Red\n0.5 0.5 0.5 \n0.5 0.5 0.5\n"
    #expect(
      try SkencilPaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 128, green: 128, blue: 128),
      ])
    let data = SkencilPaletteCoder.encode(Self.sample)
    #expect(Self.text(data).hasPrefix("##Sketch RGBPalette 0\n1.000000 0.000000 0.000000 Red\n"))
    #expect(try SkencilPaletteCoder.decode(data) == Self.sample)
  }

  @Test("Corel Painter reads the fixed header and the colour lines with their names")
  func corelPainterDecode() throws {
    let file =
      "ROWS 12\nCOLS 22\nWIDTH 16\nHEIGHT 16\nTEXTHEIGHT 0\nSPACING 1\n"
      + "R: 255, G:0, B:0  HV:0.00, SV:0.00, VV:0.00  Red\n"
      + "R: 64, G:128, B:191\n"
    #expect(
      try CorelPainterPaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 64, green: 128, blue: 191),
      ])
    let data = CorelPainterPaletteCoder.encode(Self.sample)
    #expect(try CorelPainterPaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - Android colours, Scribus and OpenOffice XML

  @Test("Android colors.xml reads the reference resource from the Android compatibility test")
  func androidColorsReference() throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <resources>
        <color name="accent">#80FF0000</color>
      </resources>
      """
    #expect(
      try AndroidColorsXMLPaletteCoder.decode(Data(xml.utf8)) == [
        PaletteColour(name: "accent", red: 255, green: 0, blue: 0, alpha: 128)
      ])
  }

  @Test("Android colors.xml round trip keeps names and alpha")
  func androidColorsRoundTrip() throws {
    let colours = Self.sample + [PaletteColour(name: "Glass", red: 1, green: 2, blue: 3, alpha: 9)]
    let data = AndroidColorsXMLPaletteCoder.encode(colours)
    #expect(Self.text(data).contains("<color name=\"Red\">#FFFF0000</color>"))
    #expect(try AndroidColorsXMLPaletteCoder.decode(data) == colours)
  }

  @Test("Scribus reads RGB and CMYK colours, and decodes escaped names")
  func scribusDecode() throws {
    let file = """
      <?xml version="1.0"?>
      <SCRIBUSCOLORS Name="Demo" >
      <COLOR RGB="#ff0000" NAME="Red" />
      <COLOR CMYK="#ff000000" NAME="Cyan" />
      </SCRIBUSCOLORS>
      """
    #expect(
      try ScribusXMLPaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Cyan", red: 0, green: 255, blue: 255),
      ])

    let colours = Self.sample + [PaletteColour(name: "A & <B>", red: 1, green: 2, blue: 3)]
    #expect(try ScribusXMLPaletteCoder.decode(ScribusXMLPaletteCoder.encode(colours)) == colours)
  }

  @Test("OpenOffice colour table reads draw:color elements and writes uppercase hex")
  func openOfficeDecode() throws {
    let file = """
      <?xml version="1.0" encoding="UTF-8"?>
      <office:color-table xmlns:office="http://openoffice.org/2000/office" xmlns:draw="http://openoffice.org/2000/drawing">
      <draw:color draw:name="Red" draw:color="#FF0000"/>
      <draw:color draw:name="Accent" draw:color="#4080BF"/>
      </office:color-table>
      """
    #expect(
      try OpenOfficePaletteCoder.decode(Data(file.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
      ])

    let data = OpenOfficePaletteCoder.encode(Self.sample)
    #expect(Self.text(data).contains("<draw:color draw:name=\"Accent\" draw:color=\"#4080BF\"/>"))
    // The namespace declarations are one line, with a space between each attribute.
    #expect(
      Self.text(data).contains("xmlns:office=\"http://openoffice.org/2000/office\" xmlns:style="))
    #expect(Self.text(data).contains("xmlns:script=\"http://openoffice.org/2000/script\">\n"))
    #expect(try OpenOfficePaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - VGA

  @Test("VGA 18-bit expands 6-bit channels and reads the names header")
  func vga18Decode() throws {
    let file = Data(Array("; Names: Red, Green\n".utf8) + [63, 0, 0, 0, 63, 0])
    #expect(
      try VGA18BitPaletteCoder.decode(file) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try VGA18BitPaletteCoder.decode(Data([64, 0, 0]))
    }
    #expect(throws: PaletteFormatError.invalidFormat) {
      try VGA18BitPaletteCoder.decode(Data([0, 0, 0, 0]))
    }
  }

  @Test("VGA 18-bit round trip keeps the position of unnamed colours")
  func vga18RoundTrip() throws {
    // Each channel is a 6-bit value expanded to 8 bits, so the round trip is exact.
    let colours = [
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 85, blue: 170),
      PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    ]
    let data = VGA18BitPaletteCoder.encode(colours)
    #expect(Self.text(data).hasPrefix("; Names: Red, , Blue\n"))
    #expect(try VGA18BitPaletteCoder.decode(data) == colours)
  }

  @Test("VGA 24-bit round trip keeps names and RGB values")
  func vga24RoundTrip() throws {
    let data = VGA24BitPaletteCoder.encode(Self.sample)
    #expect(data.count == 12 + "; Names: Red, Green, Blue, Accent\n".utf8.count)
    #expect(try VGA24BitPaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - Source code (export only)

  @Test("Swift export writes the colours as colour literals with their names")
  func swiftExport() {
    let text = Self.text(SwiftPaletteCoder.encode(Self.sample))
    #expect(text.hasPrefix("struct ExportedPalettes {\n"))
    #expect(text.contains("static let group0: [CGColor] = ["))
    #expect(
      text.contains(
        " #colorLiteral(red: 1.0000, green: 0.0000, blue: 0.0000, alpha: 1.0000), // Red"))
  }

  @Test("Kotlin export writes constants, the global group and all colours")
  func kotlinExport() {
    let colours = Self.sample + [PaletteColour(name: "1st colour", red: 1, green: 2, blue: 3)]
    let text = Self.text(KotlinPaletteCoder.encode(colours))
    #expect(text.contains("val Red: Color = Color(0xFFFF0000)"))
    #expect(text.contains("val Accent: Color = Color(0xFF4080BF)"))
    #expect(text.contains("val _1st_colour: Color = Color(0xFF010203)"))
    #expect(text.contains("val group0: List<Color> = listOf("))
    #expect(text.contains("val allColors: List<Color> = listOf("))
  }

  // MARK: - Shared behaviour

  @Test("every new decoder rejects empty input")
  func emptyInput() {
    let decoders: [(String, (Data) throws -> [PaletteColour])] = [
      ("HEX", HEXPaletteCoder.decode),
      ("RGB", RGBPaletteCoder.decode),
      ("RGBA", RGBAPaletteCoder.decode),
      ("JASC", PaintShopProPaletteCoder.decode),
      ("HPL", HPLPaletteCoder.decode),
      ("Skencil", SkencilPaletteCoder.decode),
      ("Corel Painter", CorelPainterPaletteCoder.decode),
      ("Android colors", AndroidColorsXMLPaletteCoder.decode),
      ("Scribus", ScribusXMLPaletteCoder.decode),
      ("OpenOffice", OpenOfficePaletteCoder.decode),
      ("VGA 18-bit", VGA18BitPaletteCoder.decode),
      ("VGA 24-bit", VGA24BitPaletteCoder.decode),
      ("ASE", ASEPaletteCoder.decode),
      ("ACO", ACOPaletteCoder.decode),
      ("JSON", JSONPaletteCoder.decode),
    ]
    for (_, decode) in decoders {
      #expect(throws: (any Error).self) {
        try decode(Data())
      }
    }
  }
}
