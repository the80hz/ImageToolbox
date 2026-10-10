import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Palette file formats")
struct PaletteFormatTests {

  /// Named opaque colours, which every format except ACT can store.
  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  /// The same colours without names, for comparing with formats that do not store names.
  private static func unnamed(_ colours: [PaletteColour]) -> [PaletteColour] {
    colours.map { PaletteColour(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
  }

  private static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  // MARK: - GIMP

  @Test("GIMP output has the same layout as the Android coder")
  func gimpLayout() {
    let data = GIMPPaletteCoder.encode([
      PaletteColour(name: "Primary\tRed", red: 255, green: 0, blue: 0)
    ])
    #expect(
      Self.text(data) == "GIMP Palette\nName: \nColumns: 0\n#Colors: 1\n255\t0\t0\tPrimary Red\n")
  }

  @Test("GIMP decoding skips metadata, invalid lines and a byte order mark")
  func gimpDecode() throws {
    let lines = [
      "GIMP Palette",
      "Name: Test",
      "Columns: 4",
      "# comment",
      "255\t0\t0\tRed",
      "0 256 0 Too bright",
      "  12   34  56   Blue Grey  ",
      "300 0 0",
    ]
    let data = Data(("\u{FEFF}" + lines.joined(separator: "\n")).utf8)
    #expect(
      try GIMPPaletteCoder.decode(data) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Blue Grey", red: 12, green: 34, blue: 56),
      ])
  }

  @Test("GIMP round trip keeps names")
  func gimpRoundTrip() throws {
    let data = GIMPPaletteCoder.encode(Self.sample)
    #expect(try GIMPPaletteCoder.decode(data) == Self.sample)
  }

  @Test("GIMP rejects a file without the header")
  func gimpHeader() {
    #expect(throws: PaletteFormatError.invalidFormat) {
      try GIMPPaletteCoder.decode(Data("255 0 0\n".utf8))
    }
  }

  // MARK: - Paint.NET

  @Test("Paint.NET decoding reads colour names and ignores file comments")
  func paintNETDecode() throws {
    let lines = [
      "; paint.net Palette File",
      "; Lines that start with a semicolon are comments",
      "; Colors are written as 8-digit hexadecimal numbers: aarrggbb",
      "; Palette Name: Demo",
      "; Red",
      "FFFF0000",
      "8000FF00",
      "FF0000FF",
    ]
    let data = Data(lines.joined(separator: "\r\n").utf8)
    #expect(
      try PaintNETPaletteCoder.decode(data) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0, alpha: 128),
        PaletteColour(red: 0, green: 0, blue: 255),
      ])
  }

  @Test("Paint.NET round trip keeps names and alpha")
  func paintNETRoundTrip() throws {
    let colours =
      Self.sample + [PaletteColour(name: "Glass", red: 1, green: 2, blue: 3, alpha: 128)]
    let data = PaintNETPaletteCoder.encode(colours)
    #expect(Self.text(data).contains("80010203\r\n"))
    #expect(try PaintNETPaletteCoder.decode(data) == colours)
  }

  // MARK: - CSV

  @Test("CSV decoding reads names, short hex forms and single-line lists")
  func csvDecode() throws {
    // The "x" of "0x0000ff" is dropped as a non-hex character, which leaves seven digits, so the
    // line is skipped, as in the Android coder.
    let records = "#ff0000, Red\n#0f0\n0x0000ff, Blue\n\n"
    #expect(
      try CSVPaletteCoder.decode(Data(records.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])

    let singleLine = "#ff0000, #00ff00"
    #expect(
      try CSVPaletteCoder.decode(Data(singleLine.utf8)) == [
        PaletteColour(red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
      ])
  }

  @Test("CSV round trip keeps names")
  func csvRoundTrip() throws {
    let data = CSVPaletteCoder.encode(Self.sample)
    #expect(Self.text(data).hasPrefix("#ff0000, Red\n#00ff00, Green\n"))
    #expect(try CSVPaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - Byte helpers for the binary formats

  private static func be16(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
  }

  private static func be32(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  /// UTF-16BE code units, with the count and terminator that ASE uses for names.
  private static func aseName(_ name: String) -> [UInt8] {
    let units = Array(name.utf16)
    var bytes = Self.be16(UInt16(units.count + 1))
    for unit in units {
      bytes += Self.be16(unit)
    }
    return bytes + [0, 0]
  }

  /// An ASE block: type, length, then the body.
  private static func aseBlock(_ type: UInt16, _ body: [UInt8]) -> [UInt8] {
    Self.be16(type) + Self.be32(UInt32(body.count)) + body
  }

  private static func aseColour(_ name: String, model: String, values: [Float]) -> [UInt8] {
    var body = Self.aseName(name) + Array(model.utf8)
    for value in values {
      body += Self.be32(value.bitPattern)
    }
    body += Self.be16(0)  // Global colour type.
    return Self.aseBlock(0x0001, body)
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

  // MARK: - ASE

  @Test("ASE decoding lists the global colours before the colours of groups, as Android does")
  func aseDecode() throws {
    var file = Array("ASEF".utf8)
    file += Self.be16(1)
    file += Self.be16(0)
    file += Self.be32(5)
    file += Self.aseBlock(0xC001, Self.aseName("Set"))
    file += Self.aseColour("Red", model: "RGB ", values: [1, 0, 0])
    file += Self.aseBlock(0xC002, [])
    file += Self.aseColour("Half", model: "Gray", values: [0.5])
    file += Self.aseColour("Cyan", model: "CMYK", values: [1, 0, 0, 0])
    #expect(
      try ASEPaletteCoder.decode(Data(file)) == [
        PaletteColour(name: "Half", red: 128, green: 128, blue: 128),
        PaletteColour(name: "Cyan", red: 0, green: 255, blue: 255),
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      ])
  }

  @Test("ASE rejects a bad signature and truncated data")
  func aseErrors() {
    let badSignature = Array("ASEX".utf8) + [0, 1, 0, 0, 0, 0, 0, 0]
    #expect(throws: PaletteFormatError.invalidHeader) {
      try ASEPaletteCoder.decode(Data(badSignature))
    }

    let truncated = Array("ASEF".utf8) + Self.be16(1) + Self.be16(0) + Self.be32(1)
    #expect(throws: PaletteFormatError.truncated) {
      try ASEPaletteCoder.decode(Data(truncated))
    }
  }

  @Test("ASE round trip keeps names and colours")
  func aseRoundTrip() throws {
    let data = ASEPaletteCoder.encode(Self.sample)
    #expect(data.prefix(4) == Data("ASEF".utf8))
    #expect(try ASEPaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - ACO

  @Test("ACO reads names from the version 2 section")
  func acoVersion2() throws {
    // Both sections hold one swatch, (255, 0, 128). Only version 2 has the name.
    let swatch = Self.acoSwatch(0, [0xFFFF, 0, 0x8080, 0])
    var file = Self.be16(1)
    file += Self.be16(1)
    file += swatch
    file += Self.be16(2)
    file += Self.be16(1)
    file += swatch
    file += Self.acoName("Red")
    #expect(
      try ACOPaletteCoder.decode(Data(file)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 128)
      ])
  }

  @Test("ACO reads a file that has only a version 1 section")
  func acoVersion1Only() throws {
    var file = Self.be16(1)
    file += Self.be16(3)
    file += Self.acoSwatch(2, [0, 0xFFFF, 0xFFFF, 0xFFFF])
    file += Self.acoSwatch(8, [5000, 0, 0, 0])
    file += Self.acoSwatch(1, [0, 0xFFFF, 0xFFFF, 0])
    #expect(
      try ACOPaletteCoder.decode(Data(file)) == [
        PaletteColour(red: 0, green: 255, blue: 255),
        PaletteColour(red: 128, green: 128, blue: 128),
        PaletteColour(red: 255, green: 0, blue: 0),
      ])
  }

  @Test("ACO round trip keeps names and colours")
  func acoRoundTrip() throws {
    let data = ACOPaletteCoder.encode(Self.sample)
    #expect(try ACOPaletteCoder.decode(data) == Self.sample)
  }

  // MARK: - ACT

  @Test("ACT encoding of one colour is the standard 772 bytes, as in the Android test")
  func actStandardSize() {
    let data = ACTPaletteCoder.encode([
      PaletteColour(name: "Named Color", red: 255, green: 0, blue: 0)
    ])
    #expect(data.count == 772)
    #expect(Array(data.prefix(3)) == [255, 0, 0])
    #expect(Array(data.suffix(4)) == [0, 1, 0xFF, 0xFF])
  }

  @Test("ACT decoding applies the colour count, the transparency index and the names")
  func actDecode() throws {
    var file: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255]
    file += [UInt8](repeating: 0, count: 768 - file.count)
    file += Self.be16(3)
    file += Self.be16(1)
    file += Array("; ACT_NAMES: Red|Green|Blue".utf8)
    #expect(
      try ACTPaletteCoder.decode(Data(file)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Green", red: 0, green: 255, blue: 0, alpha: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
  }

  @Test("ACT round trip keeps RGB values but not names or transparency")
  func actRoundTrip() throws {
    let colours = [
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 1, green: 2, blue: 3, alpha: 0),
      PaletteColour(red: 64, green: 128, blue: 191),
    ]
    let data = ACTPaletteCoder.encode(colours)
    #expect(data.count == 772)
    // The Android coder never writes the alpha channel, so the transparent colour comes back opaque.
    let opaque = colours.map { colour in
      PaletteColour(red: colour.red, green: colour.green, blue: colour.blue)
    }
    #expect(try ACTPaletteCoder.decode(data) == Self.unnamed(opaque))

    let full = ACTPaletteCoder.encode(Array(repeating: colours[2], count: 300))
    #expect(full.count == 768)
  }

  // MARK: - JSON

  @Test("JSON decoding handles RGB, CMYK, Gray and group colours")
  func jsonDecode() throws {
    let text =
      #"{"colors":[{"name":"Red","colorSpace":"RGB","colorComponents":[1.0,0.0,0.0]},"#
      + #"{"colorType":"Spot","colorSpace":"CMYK","colorComponents":[1.0,0.0,0.0,0.0],"alpha":0.5},"#
      + #"{"colorSpace":"Gray","colorComponents":[0.5]}],"#
      + #""groups":[{"name":"G","colors":[{"name":"Blue","colorSpace":"RGB","colorComponents":[0.0,0.0,1.0]}]}]}"#
    #expect(
      try JSONPaletteCoder.decode(Data(text.utf8)) == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 255, alpha: 128, colourType: .spot),
        PaletteColour(red: 128, green: 128, blue: 128),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
  }

  @Test("JSON rejects wrong component counts and invalid JSON")
  func jsonErrors() {
    let wrongCount = #"{"colors":[{"colorSpace":"RGB","colorComponents":[1.0]}]}"#
    #expect(throws: PaletteFormatError.invalidFormat) {
      try JSONPaletteCoder.decode(Data(wrongCount.utf8))
    }

    #expect(throws: PaletteFormatError.invalidFormat) {
      try JSONPaletteCoder.decode(Data("{".utf8))
    }
  }

  @Test("JSON round trip keeps names, colours and alpha")
  func jsonRoundTrip() throws {
    let colours =
      Self.sample + [PaletteColour(name: "Glass", red: 10, green: 20, blue: 30, alpha: 128)]
    let data = JSONPaletteCoder.encode(colours)
    #expect(try JSONPaletteCoder.decode(data) == colours)
  }

  // MARK: - Shared behaviour

  @Test("every decoder rejects empty input")
  func emptyInput() {
    let decoders: [(String, (Data) throws -> [PaletteColour])] = [
      ("GIMP", GIMPPaletteCoder.decode),
      ("Paint.NET", PaintNETPaletteCoder.decode),
      ("CSV", CSVPaletteCoder.decode),
      ("ASE", ASEPaletteCoder.decode),
      ("ACO", ACOPaletteCoder.decode),
      ("ACT", ACTPaletteCoder.decode),
      ("JSON", JSONPaletteCoder.decode),
    ]
    for (_, decode) in decoders {
      #expect(throws: (any Error).self) {
        try decode(Data())
      }
    }
  }
}
