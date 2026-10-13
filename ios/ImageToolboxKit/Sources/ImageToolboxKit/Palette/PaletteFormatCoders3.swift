import Foundation

// Binary palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Adobe Color Book

/// The Adobe Color Book (.acb) binary format, as the Android coder reads it.
///
/// The file starts with "8BCB", a version, an identifier and four Pascal strings: the title,
/// prefix, suffix and description. Then come the colour count, the page size, the page selector
/// offset and the colour space code: 0 RGB, 2 CMYK, 7 LAB and 8 greyscale. Each colour is a
/// Pascal name, six ASCII characters of hex text and one byte per component. The Pascal strings
/// have a 32-bit big-endian count of UTF-16 units. Colours with neither a name nor a code are
/// skipped. The title is the palette name. A title that starts with "$$$" keeps only the text
/// after its last "=", as the Android coder does.
public enum ACBPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var reader = PaletteByteReader(data)
    guard try reader.ascii(4) == "8BCB" else { throw PaletteFormatError.invalidHeader }
    // The version and identifier are not checked, as in the Android coder.
    _ = try reader.uint16()
    _ = try reader.uint16()
    var title = try reader.pascalUTF16(.big, lengthWidth: 32)
    if title.hasPrefix("$$$") {
      let parts = title.split(separator: "=", omittingEmptySubsequences: false)
      title = parts.last.map(String.init) ?? title
    }
    for _ in 0..<3 {
      _ = try reader.pascalUTF16(.big, lengthWidth: 32)  // Prefix, suffix and description.
    }
    let count = Int(try reader.uint16())
    _ = try reader.uint16()  // Page size.
    _ = try reader.uint16()  // Page selector offset.

    let space = try reader.uint16()
    let componentCount: Int
    switch space {
    case 0, 7: componentCount = 3
    case 2: componentCount = 4
    case 8: componentCount = 1
    default: throw PaletteFormatError.unknownColourSpace(space)
    }

    var colours: [PaletteColour] = []
    for _ in 0..<count {
      let name = try reader.pascalUTF16(.big, lengthWidth: 32)
      let code = try reader.ascii(6)
      let channels = try reader.take(componentCount).map { Double($0) }
      if PaletteText.trimmed(name).isEmpty && PaletteText.trimmed(code).isEmpty { continue }
      colours.append(colour(space: space, channels: channels, name: name))
    }
    // The spot identifier is optional, so it is only skipped when present.
    reader.skipIfAvailable(8)

    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: title, colours: colours)
  }

  /// An RGB book with the colours named. The colour code is the hex value of the colour. Names
  /// that are empty are written as "Color", and an empty palette name as "Palette", as the Android
  /// coder does.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var writer = PaletteByteWriter()
    writer.ascii("8BCB")
    writer.uint16(1)
    writer.uint16(0)
    writer.pascalUTF16(document.name ?? "Palette", .big, lengthWidth: 32)
    for _ in 0..<3 {
      writer.pascalUTF16("", .big, lengthWidth: 32)
    }
    let colours = document.allColours
    writer.uint16(UInt16(min(colours.count, Int(UInt16.max))))
    writer.uint16(0)  // Page size.
    writer.uint16(0)  // Page selector offset.
    writer.uint16(0)  // RGB colour space.

    for colour in colours.prefix(Int(UInt16.max)) {
      writer.pascalUTF16(colour.name ?? "Color", .big, lengthWidth: 32)
      writer.ascii(PaletteText.hex([colour.red, colour.green, colour.blue], uppercase: true))
      writer.append([colour.red, colour.green, colour.blue])
    }
    return writer.data
  }

  /// A colour from the channels of one colour space. Components are scaled as the Android coder
  /// scales them: CMYK is inverted, and LAB uses L from 0 to 100 and a and b shifted by 128.
  private static func colour(space: UInt16, channels: [Double], name: String) -> PaletteColour {
    switch space {
    case 2:
      return PaletteMath.cmyk(
        name: name, cyan: (255 - channels[0]) / 255, magenta: (255 - channels[1]) / 255,
        yellow: (255 - channels[2]) / 255, black: (255 - channels[3]) / 255)
    case 7:
      let rgb = PaletteLab.toSRGB(
        l: channels[0] / 2.55, a: channels[1] - 128, b: channels[2] - 128)
      return PaletteColour(name: name, red: rgb.red, green: rgb.green, blue: rgb.blue)
    case 8:
      return PaletteMath.grey(name: name, white: channels[0] / 255)
    default:
      return PaletteMath.colour(
        name: name, red: channels[0] / 255, green: channels[1] / 255,
        blue: channels[2] / 255)
    }
  }
}

// MARK: - ColorPaletteCodable binary

/// The ColorPaletteCodable binary (.dcp) format: a little-endian file with a byte order mark,
/// a version, a Pascal palette name and groups of colours. The first group is the global colours,
/// and the others are `PaletteDocument.groups`.
///
/// Each group starts with the tag 0xEA, a name and a colour count. Each colour starts with the tag
/// 0xC0 and holds a name, a colour space code (1 CMYK, 2 RGB, 3 LAB, 4 grey), float components, an
/// alpha float and a colour type byte (1 global, 2 spot, 3 normal). Strings are Pascal UTF-16 with
/// a 16-bit count.
public enum DCPPaletteCoder: PaletteDocumentCoder {

  private static let byteOrderMark: UInt16 = 32156
  private static let version: UInt16 = 1
  private static let groupTag: UInt8 = 0xEA
  private static let colourTag: UInt8 = 0xC0

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var reader = PaletteByteReader(data)
    guard try reader.uint16(.little) == byteOrderMark else {
      throw PaletteFormatError.invalidHeader
    }
    guard try reader.uint16(.little) == version else { throw PaletteFormatError.invalidHeader }
    let name = try reader.pascalUTF16(.little)

    let groupCount = Int(try reader.uint16(.little))
    var groups: [PaletteColourGroup] = []
    for _ in 0..<groupCount {
      guard try reader.uint8() == groupTag else { throw PaletteFormatError.invalidFormat }
      let groupName = try reader.pascalUTF16(.little)
      let colourCount = Int(try reader.uint16(.little))
      var colours: [PaletteColour] = []
      for _ in 0..<colourCount {
        colours.append(try readColour(&reader))
      }
      groups.append(PaletteColourGroup(name: groupName, colours: colours))
    }
    // The first group is the global colours. A file with no colours at all is invalid.
    guard let global = groups.first, groups.contains(where: { !$0.colours.isEmpty }) else {
      throw PaletteFormatError.invalidFormat
    }
    return PaletteDocument(
      name: name, colours: global.colours, groups: Array(groups.dropFirst()))
  }

  /// The global colours as a group named "global", then each group of the document. The palette
  /// name is written as it is, empty when there is none.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var writer = PaletteByteWriter()
    writer.uint16(byteOrderMark, .little)
    writer.uint16(version, .little)
    writer.pascalUTF16(document.name ?? "", .little)
    let groups = [PaletteColourGroup(name: "global", colours: document.colours)] + document.groups
    writer.uint16(UInt16(min(groups.count, Int(UInt16.max))), .little)
    for group in groups.prefix(Int(UInt16.max)) {
      writer.uint8(groupTag)
      writer.pascalUTF16(group.name, .little)
      writer.uint16(UInt16(min(group.colours.count, Int(UInt16.max))), .little)
      for colour in group.colours.prefix(Int(UInt16.max)) {
        writeColour(colour, to: &writer)
      }
    }
    return writer.data
  }

  private static func writeColour(_ colour: PaletteColour, to writer: inout PaletteByteWriter) {
    writer.uint8(colourTag)
    writer.pascalUTF16(colour.name ?? "", .little)
    writer.uint8(2)  // RGB.
    writer.float32(PaletteMath.unit(colour.red), .little)
    writer.float32(PaletteMath.unit(colour.green), .little)
    writer.float32(PaletteMath.unit(colour.blue), .little)
    writer.float32(PaletteMath.unit(colour.alpha), .little)
    writer.uint8(colourTypeCode(colour.colourType))
  }

  /// The colour type byte: 1 global, 2 spot and 3 normal, as in the Android coder.
  private static func colourTypeCode(_ type: PaletteColourType) -> UInt8 {
    switch type {
    case .global: 1
    case .spot: 2
    case .normal: 3
    }
  }

  private static func readColour(_ reader: inout PaletteByteReader) throws -> PaletteColour {
    guard try reader.uint8() == colourTag else { throw PaletteFormatError.invalidFormat }
    let name = try reader.pascalUTF16(.little)
    let space = try reader.uint8()

    var values: [Double] = []
    let componentCount: Int
    switch space {
    case 1: componentCount = 4
    case 2, 3: componentCount = 3
    case 4: componentCount = 1
    default: throw PaletteFormatError.invalidFormat
    }
    for _ in 0..<componentCount {
      values.append(try reader.float32(.little))
    }
    let alpha = try reader.float32(.little)
    let colourType: PaletteColourType
    switch try reader.uint8() {
    case 1: colourType = .global
    case 2: colourType = .spot
    case 3: colourType = .normal
    default: throw PaletteFormatError.invalidFormat
    }

    let colour: PaletteColour
    switch space {
    case 1:
      colour = PaletteMath.cmyk(
        name: name, cyan: values[0], magenta: values[1], yellow: values[2], black: values[3],
        alpha: alpha)
    case 2:
      colour = PaletteMath.colour(
        name: name, red: values[0], green: values[1], blue: values[2], alpha: alpha)
    case 3:
      let rgb = PaletteLab.toSRGB(l: values[0], a: values[1], b: values[2])
      colour = PaletteColour(
        name: name, red: rgb.red, green: rgb.green, blue: rgb.blue,
        alpha: PaletteMath.channel(alpha))
    default:
      colour = PaletteMath.grey(name: name, white: values[0], alpha: alpha)
    }
    return colour.withColourType(colourType)
  }
}

// MARK: - Microsoft RIFF palette

/// The Microsoft RIFF palette (.pal) format: a "RIFF" chunk of type "PAL ", holding a "data"
/// chunk with a version, a 16-bit entry count and 4-byte entries (red, green, blue, unused).
///
/// The Android coder also writes an optional "name" chunk after the entries, with the colour names
/// separated by line feeds. It is read when present, and it is written when a colour has a name.
public enum RIFFPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var reader = PaletteByteReader(data)
    guard try reader.ascii(4) == "RIFF" else { throw PaletteFormatError.invalidFormat }
    _ = try reader.int32(.little)  // The file size is not checked.
    guard try reader.ascii(4) == "PAL " else { throw PaletteFormatError.invalidFormat }
    guard try reader.ascii(4) == "data" else { throw PaletteFormatError.invalidFormat }
    _ = try reader.int32(.little)
    _ = try reader.int16(.little)  // Palette version.

    let entryCount = Int(try reader.int16(.little))
    var colours: [PaletteColour] = []
    for _ in 0..<max(entryCount, 0) {
      let entry = try reader.take(4)
      colours.append(PaletteColour(red: entry[0], green: entry[1], blue: entry[2]))
    }
    readNames(&reader, into: &colours)

    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// The entries, then a "name" chunk when some colour has a name. Each name is followed by the
  /// next one after a line feed. Line breaks inside a name are replaced by spaces.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let used = Array(colours.prefix(Int(UInt16.max)))
    let names = used.map { PaletteText.singleLine($0.name) ?? "" }
    let hasNames = names.contains { !$0.isEmpty }
    let nameBytes = hasNames ? Array(names.joined(separator: "\n").utf8) : []
    let padding = hasNames && nameBytes.count % 2 != 0 ? 1 : 0
    let nameChunkSize = hasNames ? 8 + nameBytes.count + padding : 0

    let dataChunkSize = 4 + used.count * 4
    let fileSizeMinusEight = 4 + (8 + dataChunkSize) + nameChunkSize

    var writer = PaletteByteWriter()
    writer.ascii("RIFF")
    writer.int32(Int32(fileSizeMinusEight), .little)
    writer.ascii("PAL ")
    writer.ascii("data")
    writer.int32(Int32(dataChunkSize), .little)
    writer.uint16(3, .little)  // Palette version.
    writer.uint16(UInt16(used.count), .little)
    for colour in used {
      writer.append([colour.red, colour.green, colour.blue, 0])
    }
    if hasNames {
      writer.ascii("name")
      writer.uint32(UInt32(nameBytes.count), .little)
      writer.append(nameBytes)
      if padding == 1 {
        writer.uint8(0)
      }
    }
    return writer.data
  }

  /// Reads the optional name chunk. Nothing changes when the chunk is missing or cut short.
  private static func readNames(
    _ reader: inout PaletteByteReader, into colours: inout [PaletteColour]
  ) {
    guard (try? reader.ascii(4)) == "name", let size = try? reader.int32(.little), size >= 0,
      let raw = try? reader.take(Int(size))
    else { return }

    var text = String(decoding: raw, as: UTF8.self)
    while text.hasSuffix("\0") {
      text.removeLast()
    }
    for (index, name) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
    where index < colours.count && !name.isEmpty {
      let colour = colours[index]
      colours[index] = PaletteColour(
        name: String(name), red: colour.red, green: colour.green, blue: colour.blue,
        alpha: colour.alpha)
    }
  }
}
