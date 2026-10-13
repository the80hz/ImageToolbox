import Foundation

// Binary palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Xara

/// The Xara palette (.jcw) binary format: "JCW", a version byte, a little-endian colour count, a
/// colour space code and the length of each name. Each colour holds four 16-bit values and a
/// fixed-length name. The values run from 0 to 10000 and are read as RGB, CMYK or HSB.
///
/// Codes 1, 8, 9 are CMYK, 2, 10, 11 are RGB and 3, 12, 13 are HSB. Codes 9, 11 and 13 are spot
/// colours, which are read the same way. A colour without a name is called "c" and its index.
public enum JCWPaletteCoder {

  private enum Model {
    case cmyk
    case rgb
    case hsb
  }

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var reader = PaletteByteReader(data)
    guard try reader.ascii(3) == "JCW" else { throw PaletteFormatError.invalidHeader }
    // The version is not checked, as in the Android coder.
    _ = try reader.uint8()
    let count = Int(try reader.uint16(.little))

    let code = try reader.uint8()
    let model: Model
    switch code {
    case 1, 8, 9: model = .cmyk
    case 2, 10, 11: model = .rgb
    case 3, 12, 13: model = .hsb
    default: throw PaletteFormatError.invalidFormat
    }
    let nameLength = Int(try reader.uint8())

    var colours: [PaletteColour] = []
    for index in 0..<count {
      var values: [Double] = []
      for _ in 0..<4 {
        values.append(Double(min(try reader.uint16(.little), 10000)) / 10000)
      }
      let name = PaletteText.trimmedNulls(try reader.latin1(nameLength))
      let colourName = name.isEmpty ? "c\(index)" : name
      colours.append(colour(model: model, values: values, name: colourName))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// RGB colours with 14-byte names. Each channel is written as a 16-bit value from 0 to 10000,
  /// truncated as the Android coder truncates it.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var writer = PaletteByteWriter()
    writer.ascii("JCW")
    writer.uint8(1)
    writer.uint16(UInt16(min(colours.count, Int(UInt16.max))), .little)
    writer.uint8(10)  // RGB.
    writer.uint8(14)  // Name length.

    for colour in colours.prefix(Int(UInt16.max)) {
      for channel in [colour.red, colour.green, colour.blue] {
        writer.uint16(UInt16(PaletteMath.unit(channel) * 10000), .little)
      }
      writer.uint16(0, .little)
      let name = PaletteText.latin1Bytes(colour.name ?? "").prefix(14)
      writer.append(Array(name) + [UInt8](repeating: 0, count: 14 - name.count))
    }
    return writer.data
  }

  private static func colour(model: Model, values: [Double], name: String) -> PaletteColour {
    switch model {
    case .rgb:
      return PaletteMath.colour(
        name: name, red: values[0], green: values[1], blue: values[2])
    case .cmyk:
      return PaletteMath.cmyk(
        name: name, cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
    case .hsb:
      let rgb = PaletteMath.hsbToRGB(
        hue: values[0], saturation: values[1], brightness: values[2])
      return PaletteMath.colour(name: name, red: rgb.0, green: rgb.1, blue: rgb.2)
    }
  }
}

// MARK: - Corel Palette

/// The Corel Palette (.cpl) binary format, read in the layouts the Android coder knows.
///
/// The file starts with a big-endian version. Version 0xDCDC has an ASCII name, and versions
/// 0xCCBC and 0xCCDC have none. Other versions start with a table of header entries, which give
/// the name, the palette type and the colour count by offset. Each colour record has a model code
/// that selects CMYK, RGB or grey components. Version 0xCDBC, 0xCDDC and 0xCDDD records can hold
/// a second colour for the same name, and 0xCDDD records carry 12 bytes of row and column data.
///
/// Encoded files use version 0xDCDC with the BGR model 5, which has a Latin 1 name, and the palette
/// name in the header, "Palette" when the palette has none.
public enum CPLPaletteCoder: PaletteDocumentCoder {

  /// The components of one colour record, before the colour name is read.
  private enum Components {
    /// CMYK components from 0 to 1.
    case cmyk(Double, Double, Double, Double)
    case rgb(Double, Double, Double)
    case grey(Double)
  }

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var reader = PaletteByteReader(data)
    let version = try reader.uint16()
    var numberOfColours = 0
    var paletteType: UInt16 = 0
    var name: String?

    switch version {
    case 0xDCDC:
      let nameLength = Int(try reader.uint8())
      if nameLength > 0 {
        name = try reader.ascii(nameLength)
      }
      numberOfColours = Int(try reader.uint16(.little))
    case 0xCCBC, 0xCCDC:
      numberOfColours = Int(try reader.uint16(.little))
    default:
      let headerCount = Int(try reader.int32(.little))
      var offsets: [Int] = []
      for _ in 0..<max(headerCount, 0) {
        _ = try reader.int32(.little)  // Header identifier.
        offsets.append(Int(try reader.int32(.little)))
      }
      if let nameOffset = offsets.first {
        try reader.seek(to: nameOffset)
        let nameLength = Int(try reader.uint8())
        if nameLength > 0 {
          if version == 0xCDDC {
            name = try reader.latin1(nameLength)
          } else {
            name = try reader.utf16(nameLength, .little)
          }
        }
      }
      if offsets.count > 1 {
        try reader.seek(to: offsets[1])
        paletteType = try reader.uint16(.little)
      }
      if offsets.count > 2 {
        try reader.seek(to: offsets[2])
        numberOfColours = Int(try reader.uint16(.little))
        try reader.seek(to: offsets[2] + 2)
      }
    }

    let hasSecondColour =
      [0xCDBC, 0xCDDC, 0xCDDD].contains(version) && paletteType < 38 && paletteType != 5
      && paletteType != 16
    var colours: [PaletteColour] = []
    for _ in 0..<numberOfColours {
      if hasSecondColour {
        _ = try reader.uint32(.little)
      }
      let model = try reader.uint16(.little)
      try reader.skip(2)
      let first = try readComponents(&reader, model: model)

      var second: Components?
      if hasSecondColour {
        let secondModel = try reader.uint16(.little)
        second = try readComponents(&reader, model: secondModel)
      }

      let nameLength = Int(try reader.uint8())
      var name = ""
      if nameLength > 0 {
        if [0xCDDC, 0xDCDC, 0xCCDC].contains(version) {
          name = try reader.latin1(nameLength)
        } else {
          name = try reader.utf16(nameLength, .little)
        }
      }

      for components in [first, second] {
        if let components {
          colours.append(colour(components, name: name))
        }
      }
      if version == 0xCDDD {
        try reader.skip(12)  // Row and column, as three 32-bit values.
      }
    }

    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: name, colours: colours)
  }

  /// The header with the palette name, then the BGR model 5 records. The palette name is "Palette"
  /// when the palette has none. Names are Latin 1 and are cut to 255 bytes.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var writer = PaletteByteWriter()
    writer.uint16(0xDCDC)
    let paletteName = Array(PaletteText.latin1Bytes(document.name ?? "Palette").prefix(255))
    writer.uint8(UInt8(paletteName.count))
    writer.append(paletteName)
    let colours = document.allColours
    writer.uint16(UInt16(min(colours.count, Int(UInt16.max))), .little)

    for colour in colours.prefix(Int(UInt16.max)) {
      writer.uint16(5, .little)  // BGR fractions.
      writer.append([0, 0, 0, 0, 0, 0])  // Two unused bytes and four unknown bytes.
      writer.append([colour.blue, colour.green, colour.red, 0])
      let name = PaletteText.latin1Bytes(colour.name ?? "").prefix(255)
      writer.uint8(UInt8(name.count))
      writer.append(Array(name))
    }
    return writer.data
  }

  /// Reads the components of one model, and skips the rest of its record. Unknown models skip
  /// eight bytes and give no colour.
  private static func readComponents(
    _ reader: inout PaletteByteReader, model: UInt16
  ) throws -> Components? {
    switch model {
    case 2:
      // CMYK percentages.
      try reader.skip(4)
      let values = try reader.take(4).map { Double($0) / 100 }
      return .cmyk(values[0], values[1], values[2], values[3])
    case 3, 17:
      // CMYK fractions.
      try reader.skip(4)
      let values = try reader.take(4).map { Double($0) / 255 }
      return .cmyk(values[0], values[1], values[2], values[3])
    case 4:
      // CMY fractions, with no black. The Android coder reads a fourth byte and ignores it.
      try reader.skip(4)
      let values = try reader.take(4).map { Double($0) / 255 }
      return .cmyk(values[0], values[1], values[2], 0)
    case 5, 21:
      // BGR fractions.
      try reader.skip(4)
      let bgr = try reader.take(3).map { Double($0) / 255 }
      try reader.skip(1)
      return .rgb(bgr[2], bgr[1], bgr[0])
    case 9:
      // Grey, stored as the ink amount of black.
      try reader.skip(4)
      let black = Int(try reader.uint8())
      try reader.skip(3)
      return .grey(Double(255 - black) / 255)
    default:
      try reader.skip(8)
      return nil
    }
  }

  private static func colour(_ components: Components, name: String) -> PaletteColour {
    switch components {
    case .cmyk(let cyan, let magenta, let yellow, let black):
      return PaletteMath.cmyk(
        name: name, cyan: cyan, magenta: magenta, yellow: yellow, black: black)
    case .rgb(let red, let green, let blue):
      return PaletteMath.colour(name: name, red: red, green: green, blue: blue)
    case .grey(let white):
      return PaletteMath.grey(name: name, white: white)
    }
  }
}
