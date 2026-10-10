import Foundation

// The VGA palettes and the source code exports share the helpers below, which are private to this
// file. The other palette formats use the shared helpers in PaletteText, PaletteXML and PaletteHex.

/// Splits the optional "; Names:" header that the VGA coders write before their colour bytes.
/// Returns the names, with nil for empty entries, and the bytes after the header.
private func vgaNamesAndBody(_ data: Data) -> (names: [String?], body: Data) {
  let prefix = Array("; Names: ".utf8)
  let bytes = [UInt8](data)
  guard bytes.starts(with: prefix), let newline = bytes.firstIndex(of: 0x0A) else {
    return ([], data)
  }
  let header = String(decoding: bytes[prefix.count..<newline], as: UTF8.self)
  let names: [String?] = header.components(separatedBy: ", ").map { name in
    let text = PaletteText.trimmed(name)
    return text.isEmpty ? nil : text
  }
  return (names, Data(bytes[(newline + 1)...]))
}

/// The VGA header with the names of the colours, or no header when no colour has a name. Names
/// keep their positions, so an unnamed colour is an empty entry. The Android writer leaves unnamed
/// colours out of its list, which moves the later names onto the wrong colours when the file is read
/// back, so this layout differs from it on purpose. Android reads this layout correctly.
private func vgaHeader(_ colours: [PaletteColour]) -> Data {
  let names = colours.map { PaletteText.singleLine($0.name, extraSeparators: [","]) ?? "" }
  guard names.contains(where: { !$0.isEmpty }) else { return Data() }
  return Data("; Names: \(names.joined(separator: ", "))\n".utf8)
}

// MARK: - VGA palettes

/// The 18-bit VGA palette (.vga18): three bytes per colour, each channel from 0 to 63. An optional
/// "; Names: " line before the bytes names the colours, separated by ", ".
public enum VGA18BitPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let (names, body) = vgaNamesAndBody(data)
    let bytes = [UInt8](body)
    guard !bytes.isEmpty, bytes.count % 3 == 0, bytes.allSatisfy({ $0 <= 63 }) else {
      throw PaletteFormatError.invalidFormat
    }
    return stride(from: 0, to: bytes.count, by: 3).map { index in
      PaletteColour(
        name: index / 3 < names.count ? names[index / 3] : nil,
        red: scaled(bytes[index]), green: scaled(bytes[index + 1]),
        blue: scaled(bytes[index + 2]))
    }
  }

  /// The colours scaled to 6 bits, with the names header when a colour has a name.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var data = vgaHeader(colours)
    for colour in colours {
      data.append(contentsOf: [colour.red, colour.green, colour.blue].map(unscaled))
    }
    return data
  }

  /// A 6-bit channel expanded to 8 bits.
  private static func scaled(_ value: UInt8) -> UInt8 {
    UInt8((Double(value) / 63 * 255).rounded())
  }

  /// An 8-bit channel reduced to 6 bits.
  private static func unscaled(_ value: UInt8) -> UInt8 {
    UInt8((Double(value) / 255 * 63).rounded())
  }
}

/// The 24-bit VGA palette (.vga24): three bytes per colour, red, green and blue. An optional
/// "; Names: " line before the bytes names the colours, as in the 18-bit format.
public enum VGA24BitPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let (names, body) = vgaNamesAndBody(data)
    let bytes = [UInt8](body)
    guard !bytes.isEmpty, bytes.count % 3 == 0 else { throw PaletteFormatError.invalidFormat }
    return stride(from: 0, to: bytes.count, by: 3).map { index in
      PaletteColour(
        name: index / 3 < names.count ? names[index / 3] : nil,
        red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2])
    }
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var data = vgaHeader(colours)
    for colour in colours {
      data.append(contentsOf: [colour.red, colour.green, colour.blue])
    }
    return data
  }
}

// MARK: - Source code (export only)

/// Swift source (.swift) with the colours as `#colorLiteral` values in one struct. Like the Android
/// app, this format is only written. The palette name is a "// Palette:" comment when there is one,
/// and each group is a static array named after its position, with the global colours first.
public enum SwiftPaletteCoder {

  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var text = ""
    if let name = document.name {
      text += "// Palette: \(name)\n"
    }
    text += "struct ExportedPalettes {\n"
    let groups = [PaletteColourGroup(name: "global", colours: document.colours)] + document.groups
    for (index, group) in groups.enumerated() {
      text += groupText(group, index: index)
    }
    text += "}\n"
    return Data(text.utf8)
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    encodeDocument(PaletteDocument(colours: colours))
  }

  /// The array of one group with a comment for each colour name, or nothing when the group has no
  /// colours.
  private static func groupText(_ group: PaletteColourGroup, index: Int) -> String {
    guard !group.colours.isEmpty else { return "" }
    var text = "   // Group (\(group.name))\n   static let group\(index): [CGColor] = ["
    for (position, colour) in group.colours.enumerated() {
      if position % 8 == 0 {
        text += "\n     "
      }
      let literal =
        "#colorLiteral(red: \(format(colour.red)), green: \(format(colour.green)), "
        + "blue: \(format(colour.blue)), alpha: \(format(colour.alpha)))"
      let comment = PaletteText.singleLine(colour.name).map { " // \($0)" } ?? ""
      text += " \(literal),\(comment)"
    }
    text += "\n   ]\n\n"
    return text
  }

  /// A channel from 0 to 1 with four decimals.
  private static func format(_ value: UInt8) -> String {
    String(format: "%.4f", Double(value) / 255)
  }
}

/// Kotlin source (.kt) for Jetpack Compose with the colours as `Color(0xAARRGGBB)` constants. Like
/// the Android app, this format is only written. The palette name gives the package name and the
/// header comment, and each group is listed after the individual constants.
public enum KotlinPaletteCoder {

  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let colours = document.allColours
    var text = "package \(packageName(document.name))\n\n"
    text += "import androidx.compose.ui.graphics.Color\n\n"
    text += "/**\n * Exported palette: \(document.name ?? "Untitled")\n"
    text += " * Total colors: \(colours.count)\n */\n"
    text += "object ExportedPalette {\n\n"
    if !colours.isEmpty {
      text += "    // Individual color constants\n"
      for (index, colour) in colours.enumerated() {
        let name = PaletteText.singleLine(colour.name).map(kotlinIdentifier) ?? "color\(index)"
        text += "    val \(name): Color = \(colorLiteral(colour))\n"
      }
      text += "\n"

      let groups = [PaletteColourGroup(name: "global", colours: document.colours)] + document.groups
      for (index, group) in groups.enumerated() where !group.colours.isEmpty {
        let identifier =
          group.name.isEmpty || group.name == "global"
          ? "group\(index)" : kotlinIdentifier(group.name)
        text += "    // Group: \(group.name)\n    val \(identifier): List<Color> = listOf(\n"
        text += colourList(group.colours)
        text += "    )\n\n"
      }

      text += "    /**\n     * All colors from all groups\n     */\n"
      text += "    val allColors: List<Color> = listOf(\n"
      text += colourList(colours)
      text += "    )\n"
    }
    text += "}\n"
    return Data(text.utf8)
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    encodeDocument(PaletteDocument(colours: colours))
  }

  /// The package name the Android coder derives from the palette name: its lowercase letters and
  /// digits, or "palette" when nothing is left or the first character is not a letter.
  private static func packageName(_ name: String?) -> String {
    guard let name else { return "palette" }
    let characters = name.lowercased().filter {
      ("a"..."z").contains($0) || ("0"..."9").contains($0)
    }
    guard let first = characters.first, first.isLetter else { return "palette" }
    return characters
  }

  private static func colourList(_ colours: [PaletteColour]) -> String {
    colours.enumerated().map { index, colour in
      "        \(colorLiteral(colour))" + (index < colours.count - 1 ? "," : "") + "\n"
    }.joined()
  }

  private static func colorLiteral(_ colour: PaletteColour) -> String {
    let hex = PaletteText.hex(
      [colour.alpha, colour.red, colour.green, colour.blue], uppercase: true)
    return "Color(0x\(hex))"
  }

  /// A name made of ASCII letters, digits and underscores. Like the Android coder, each UTF-16 unit
  /// that is not one of them becomes an underscore, so a character outside the BMP gives two. A
  /// leading digit gets an underscore.
  private static func kotlinIdentifier(_ name: String) -> String {
    var identifier = ""
    for unit in name.utf16 {
      let isAllowed =
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit)
        || (0x61...0x7A).contains(unit) || unit == 0x5F
      identifier.append(isAllowed ? Character(Unicode.Scalar(UInt8(unit))) : "_")
    }
    guard let first = identifier.first, first.isNumber else { return identifier }
    return "_" + identifier
  }
}
