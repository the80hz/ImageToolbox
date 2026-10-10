import Foundation

/// Why a palette file could not be read.
public enum PaletteFormatError: Error, Equatable, Sendable {
  /// The file does not start with the signature of its format.
  case invalidHeader
  /// The file ends before the data it declares is complete.
  case truncated
  /// The file is structurally wrong, for example it contains no colours.
  case invalidFormat
  /// An ASE block type that the format does not define.
  case unknownBlockType(UInt16)
  /// An ASE colour model other than CMYK, RGB, LAB or Gray.
  case unknownColourModel(String)
  /// An ASE colour type other than global, spot or normal.
  case unknownColourType(UInt16)
  /// An ACB colour space code that the format does not define.
  case unknownColourSpace(UInt16)
}

// MARK: - GIMP

/// The GIMP palette (.gpl) text format.
///
/// The file starts with a "GIMP Palette" line, followed by "R G B name" lines with channel values
/// from 0 to 255. The "Name:" line gives the palette name, and the last one in the file wins. The
/// "Columns:" line and comment lines are accepted and not kept. Like the Android coder, lines with
/// invalid channel values are skipped.
public enum GIMPPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let lines = textLines(data)
    guard let header = lines.first, trimmed(header).lowercased() == "gimp palette" else {
      throw PaletteFormatError.invalidFormat
    }
    var name: String?
    var colours: [PaletteColour] = []
    for line in lines.dropFirst() {
      let text = trimmed(line)
      if startsWithIgnoringCase(text, "name:") {
        name = trimmed(text.dropFirst("name:".count))
        continue
      }
      let isMetadata =
        text.isEmpty || text.hasPrefix("#") || startsWithIgnoringCase(text, "columns:")
      if isMetadata { continue }

      let fields = text.split(maxSplits: 3, whereSeparator: \.isWhitespace)
      guard fields.count >= 3,
        let red = decimalChannel(fields[0]),
        let green = decimalChannel(fields[1]),
        let blue = decimalChannel(fields[2])
      else { continue }
      let colourName = fields.count == 4 ? trimmed(fields[3]) : nil
      colours.append(PaletteColour(name: colourName, red: red, green: green, blue: blue))
    }
    return PaletteDocument(name: name, colours: colours)
  }

  /// The header with the palette name, which is empty when the palette has none, as in the
  /// Android coder. Line breaks and tabs in the name become spaces.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let colours = document.allColours
    var text =
      "GIMP Palette\nName: \(singleLine(document.name ?? ""))\nColumns: 0\n"
      + "#Colors: \(colours.count)\n"
    for colour in colours {
      text += "\(colour.red)\t\(colour.green)\t\(colour.blue)"
      if let name = colour.name.map({ singleLine($0) }), !name.isEmpty {
        text += "\t" + name
      }
      text += "\n"
    }
    return Data(text.utf8)
  }

  /// One to three ASCII digits that form a value from 0 to 255.
  private static func decimalChannel(_ text: Substring) -> UInt8? {
    guard (1...3).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      return nil
    }
    return UInt8(text)
  }
}

// MARK: - Paint.NET

/// The Paint.NET palette (.txt) format.
///
/// Each colour is an 8-digit hexadecimal number in aarrggbb order. The comment line directly
/// before a colour gives its name. Comments that describe the file itself are not names. A
/// "Palette Name:" or "Palette:" comment gives the palette name, and the last non-blank one wins.
public enum PaintNETPaletteCoder: PaletteDocumentCoder {

  /// Comment text that describes the file rather than a colour.
  private static let fileCommentFragments = [
    "paint.net", "Colors are written", "Downloaded", "Description", "Colors",
  ]

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var colours: [PaletteColour] = []
    var name: String?
    var pendingName: String?
    for line in textLines(data) {
      let text = trimmed(line)
      if text.isEmpty { continue }

      if text.hasPrefix(";") {
        let comment = trimmed(text.dropFirst())
        let isPaletteName =
          startsWithIgnoringCase(comment, "palette name")
          || startsWithIgnoringCase(comment, "palette:")
        if isPaletteName {
          // As in the Android coder, the text after the first colon is the name, or the whole
          // comment when it has no colon.
          let value =
            comment.firstIndex(of: ":").map { trimmed(comment[comment.index(after: $0)...]) }
            ?? trimmed(comment)
          if !value.isEmpty { name = value }
          continue
        }
        if !comment.isEmpty && !fileCommentFragments.contains(where: { comment.contains($0) }) {
          pendingName = comment
        }
        continue
      }

      // Like the Android coder, any other line must have exactly eight characters.
      guard text.utf16.count == 8 else { throw PaletteFormatError.invalidFormat }
      guard text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { continue }
      colours.append(
        PaletteColour(
          name: pendingName,
          red: UInt8(truncatingIfNeeded: value >> 16),
          green: UInt8(truncatingIfNeeded: value >> 8),
          blue: UInt8(truncatingIfNeeded: value),
          alpha: UInt8(truncatingIfNeeded: value >> 24)
        )
      )
      pendingName = nil
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: name, colours: colours)
  }

  /// The paint.net header, then the palette name comment when there is a name, and an optional
  /// colour name comment and an aarrggbb line for each colour. As in the Android coder, the header
  /// lines end with line feeds and the other lines with CRLF.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var text =
      "; paint.net Palette File\n"
      + "; Lines that start with a semicolon are comments\n"
      + "; Colors are written as 8-digit hexadecimal numbers: aarrggbb\n"
    if let name = document.name.map({ singleLine($0) }), !name.isEmpty {
      text += "; Palette Name: \(name)\r\n"
    }
    for colour in document.allColours {
      if let name = colour.name.map({ singleLine($0) }), !name.isEmpty {
        text += "; \(name)\r\n"
      }
      let value =
        UInt32(colour.alpha) << 24 | UInt32(colour.red) << 16 | UInt32(colour.green) << 8
        | UInt32(colour.blue)
      text += hexDigits(value, width: 8, uppercase: true) + "\r\n"
    }
    return Data(text.utf8)
  }
}

// MARK: - CSV

/// The CSV palette format: one colour per line as "#rrggbb", optionally followed by ", name".
///
/// A single line of comma-separated colours is also accepted, and its colours have no names.
/// Hex colours may have 3, 4, 6 or 8 digits. Any other character in a field is ignored, including
/// the "x" of a "0x" prefix, as in the Android coder, which strips every character that is not a
/// hex digit. A "0x" colour therefore has one digit more than its hex value and is skipped when
/// that makes a count the coder does not accept.
public enum CSVPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var records: [[String]] = []
    for line in textLines(data) where !trimmed(line).isEmpty {
      records.append(
        line.split(separator: ",", omittingEmptySubsequences: false).map { trimmed($0) })
    }
    guard !records.isEmpty else { throw PaletteFormatError.invalidFormat }

    let colours: [PaletteColour]
    if records.count == 1 {
      colours = records[0].compactMap { parseHexColour($0, name: nil) }
    } else {
      colours = records.compactMap { record in
        parseHexColour(record[0], name: record.count > 1 ? record[1] : nil)
      }
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// One "#rrggbb" line per colour. The alpha channel is not written.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = ""
    for colour in colours {
      let value = UInt32(colour.red) << 16 | UInt32(colour.green) << 8 | UInt32(colour.blue)
      text += "#" + hexDigits(value, width: 6, uppercase: false)
      if let name = colour.name.map({ singleLine($0, extraSeparators: [","]) }), !name.isEmpty {
        text += ", " + name
      }
      text += "\n"
    }
    return Data(text.utf8)
  }

  /// Parses a hex colour with 3, 4, 6 or 8 digits. Returns nil for any other digit count.
  private static func parseHexColour(_ text: String, name: String?) -> PaletteColour? {
    let digits = text.compactMap(\.hexDigitValue).map { UInt8($0) }
    switch digits.count {
    case 3:
      return PaletteColour(
        name: name, red: digits[0] * 17, green: digits[1] * 17, blue: digits[2] * 17)
    case 4:
      return PaletteColour(
        name: name, red: digits[0] * 17, green: digits[1] * 17, blue: digits[2] * 17,
        alpha: digits[3] * 17)
    case 6:
      return PaletteColour(
        name: name, red: digits[0] << 4 | digits[1], green: digits[2] << 4 | digits[3],
        blue: digits[4] << 4 | digits[5])
    case 8:
      return PaletteColour(
        name: name, red: digits[0] << 4 | digits[1], green: digits[2] << 4 | digits[3],
        blue: digits[4] << 4 | digits[5], alpha: digits[6] << 4 | digits[7])
    default:
      return nil
    }
  }
}

// MARK: - Shared helpers

/// Reads text as UTF-8 and removes a leading byte order mark, which the Android coders also remove.
private func textLines(_ data: Data) -> [Substring] {
  var text = String(decoding: data, as: UTF8.self)
  if text.unicodeScalars.first == "\u{FEFF}" {
    text.unicodeScalars.removeFirst()
  }
  return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
}

private func trimmed(_ text: some StringProtocol) -> String {
  String(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func startsWithIgnoringCase(_ text: String, _ prefix: String) -> Bool {
  text.lowercased().hasPrefix(prefix.lowercased())
}

/// Joins the lines of `text` with single spaces, so that the result fits on one line of a file.
/// Tabs, line breaks and the extra separators are replaced by spaces.
private func singleLine(_ text: String, extraSeparators: Set<Character> = []) -> String {
  let words = text.split(whereSeparator: {
    $0.isNewline || $0 == "\t" || extraSeparators.contains($0)
  })
  return trimmed(words.joined(separator: " "))
}

/// Lowercase or uppercase hexadecimal digits of `value`, padded with zeros to `width`.
private func hexDigits(_ value: UInt32, width: Int, uppercase: Bool) -> String {
  let digits = String(value, radix: 16, uppercase: uppercase)
  return String(repeating: "0", count: max(0, width - digits.count)) + digits
}
