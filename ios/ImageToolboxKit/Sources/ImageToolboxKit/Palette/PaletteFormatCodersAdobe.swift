import Foundation

// MARK: - Adobe Photoshop swatches

/// The Adobe Photoshop swatch (.aco) format.
///
/// The file holds a version 1 section, which has no names, followed by a version 2 section that
/// repeats the colours with names. The version 2 section is used when present. A file with only a
/// version 1 section is read as well. Encoded files contain both sections.
///
/// A version 2 name is written as the Android coder writes it: a 32-bit big-endian count of UTF-16
/// units, then the units, with no zero terminator. The reader also accepts a terminator.
public enum ACOPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var reader = PaletteByteReader(data)
    var version1: [PaletteColour] = []
    var version2: [PaletteColour] = []
    for version: UInt16 in 1...2 {
      guard let declared = try? reader.uint16(), declared == version else {
        // The version 2 section may be missing after a version 1 section.
        if version == 2 && !version1.isEmpty { return version1 }
        throw PaletteFormatError.invalidFormat
      }
      let count = Int(try reader.uint16())
      var colours: [PaletteColour] = []
      for _ in 0..<count {
        let space = try reader.uint16()
        var components: [UInt16] = []
        for _ in 0..<4 {
          components.append(try reader.uint16())
        }
        var name: String?
        if version == 2 {
          name = try reader.pascalUTF16(.big, lengthWidth: 32)
        }
        colours.append(makeColour(space: space, components: components, name: name))
      }
      if version == 1 {
        version1 = colours
      } else {
        version2 = colours
      }
    }
    let colours = version2.isEmpty ? version1 : version2
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// Writes both sections as RGB swatches. Names are written in the version 2 section.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let count = min(colours.count, Int(UInt16.max))
    var writer = PaletteByteWriter()
    for version: UInt16 in 1...2 {
      writer.uint16(version)
      writer.uint16(UInt16(count))
      for colour in colours.prefix(count) {
        writer.uint16(0)  // RGB colour space.
        // 65535 is 255 * 257, so each 8-bit channel maps exactly to a 16-bit value. This is the
        // value the Android coder computes from the same colour.
        writer.uint16(UInt16(colour.red) * 257)
        writer.uint16(UInt16(colour.green) * 257)
        writer.uint16(UInt16(colour.blue) * 257)
        writer.uint16(0)
        if version == 2 {
          writer.pascalUTF16(colour.name ?? "", .big, lengthWidth: 32)
        }
      }
    }
    return writer.data
  }

  /// The colour of one swatch. An unknown colour space gives a half-transparent red named
  /// "Unsupported Colorspace", as in the Android coder, instead of an error.
  private static func makeColour(
    space: UInt16,
    components: [UInt16],
    name: String?
  ) -> PaletteColour {
    let values = components.map { Double($0) / 65535 }
    switch space {
    case 0:
      return PaletteMath.colour(name: name, red: values[0], green: values[1], blue: values[2])
    case 1:
      let rgb = PaletteMath.hsbToRGB(hue: values[0], saturation: values[1], brightness: values[2])
      return PaletteMath.colour(name: name, red: rgb.0, green: rgb.1, blue: rgb.2)
    case 2:
      // The swatch stores inverted ink values, where 65535 means no ink.
      return PaletteMath.cmyk(
        name: name, cyan: 1 - values[0], magenta: 1 - values[1], yellow: 1 - values[2],
        black: 1 - values[3])
    case 7:
      // L is stored from 0 to 10000, and a and b are signed, each divided by 100. The Android
      // coder reads a and b as unsigned, which gives wrong colours for negative values. This
      // reader keeps the sign, so the two coders agree for every non-negative a and b.
      let rgb = PaletteLab.toSRGB(
        l: Double(components[0]) / 100,
        a: Double(Int16(bitPattern: components[1])) / 100,
        b: Double(Int16(bitPattern: components[2])) / 100)
      return PaletteColour(name: name, red: rgb.red, green: rgb.green, blue: rgb.blue)
    case 8:
      return PaletteMath.grey(name: name, white: Double(components[0]) / 10000)
    default:
      return PaletteColour(
        name: "Unsupported Colorspace", red: 255, green: 0, blue: 0,
        alpha: PaletteMath.channel(0.5))
    }
  }
}

// MARK: - Adobe Colour Table

/// The Adobe Colour Table (.act) format: 256 RGB entries, optionally followed by a colour count
/// and a transparency index.
///
/// The Android coder also reads a non-standard "; ACT_NAMES: " comment line with names separated
/// by "|". Encoded files do not contain names, as in the Android coder.
public enum ACTPaletteCoder {

  private static let tableSize = 768
  private static let noTransparency: UInt16 = 0xFFFF
  /// The names comment starts with this marker. The names begin after the first 13 characters,
  /// which is how the Android coder cuts them.
  private static let namesMarker = "; ACT_NAMES:"
  private static let namesPrefixLength = "; ACT_NAMES: ".count

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let bytes = [UInt8](data)
    guard bytes.count >= tableSize else { throw PaletteFormatError.truncated }

    var count = 256
    var transparentIndex: Int?
    var position = tableSize
    // A colour count from 1 to 255 shortens the table. Other values are ignored.
    if bytes.count >= position + 2 {
      let value = Int(Int16(bitPattern: uint16(bytes, at: position)))
      if (1..<256).contains(value) { count = value }
      position += 2
    }
    if bytes.count >= position + 2 {
      let index = Int(Int16(bitPattern: uint16(bytes, at: position)))
      if (0..<count).contains(index) { transparentIndex = index }
      position += 2
    }

    var names = [String?](repeating: nil, count: count)
    let trailingText = String(decoding: bytes[position...], as: UTF8.self)
    if let line = trailingText.split(whereSeparator: \.isNewline).first(where: {
      $0.hasPrefix(namesMarker)
    }) {
      let list = PaletteText.trimmed(line.dropFirst(namesPrefixLength))
      let parts = list.split(separator: "|", omittingEmptySubsequences: false)
      for (index, part) in parts.enumerated() where index < count && !part.isEmpty {
        names[index] = String(part)
      }
    }

    return (0..<count).map { index in
      PaletteColour(
        name: names[index],
        red: bytes[index * 3],
        green: bytes[index * 3 + 1],
        blue: bytes[index * 3 + 2],
        alpha: index == transparentIndex ? 0 : 255
      )
    }
  }

  /// The first 256 colours, padded with black. When there are fewer than 256 colours, a count and
  /// the index 0xFFFF follow the table. As in the Android coder, the alpha channel is not written,
  /// so no transparency index is written either.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let table = Array(colours.prefix(256))
    var bytes: [UInt8] = []
    for colour in table {
      bytes += [colour.red, colour.green, colour.blue]
    }
    bytes += [UInt8](repeating: 0, count: (256 - table.count) * 3)

    if table.count < 256 {
      bytes += [UInt8(table.count >> 8), UInt8(table.count & 0xFF)]
      bytes += [UInt8(noTransparency >> 8), UInt8(noTransparency & 0xFF)]
    }
    return Data(bytes)
  }

  private static func uint16(_ bytes: [UInt8], at position: Int) -> UInt16 {
    UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1])
  }
}
