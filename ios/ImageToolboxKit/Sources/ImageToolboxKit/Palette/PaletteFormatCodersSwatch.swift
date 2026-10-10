import Foundation

// MARK: - Paint Shop Pro (JASC-PAL)

/// The Paint Shop Pro palette format (.pal, JASC-PAL): a header with the version "0100" and the
/// colour count, then "red green blue" lines. A "; name" line before a colour names it.
///
/// Channels above 255 are clamped, as in the Android coder. The header lines are compared exactly,
/// so a version line with trailing white space is rejected.
public enum PaintShopProPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let lines = PaletteText.lines(of: data)
    guard lines.count >= 3, lines[0].contains("JASC-PAL"), String(lines[1]) == "0100",
      Int(String(lines[2])) != nil
    else { throw PaletteFormatError.invalidFormat }

    var colours: [PaletteColour] = []
    var pendingName: String?
    for line in lines.dropFirst(3) {
      let text = PaletteText.trimmed(line)
      if text.isEmpty { continue }
      if text.hasPrefix(";") {
        let comment = PaletteText.trimmed(text.dropFirst())
        if !comment.isEmpty { pendingName = comment }
        continue
      }
      let fields = text.split(whereSeparator: \.isWhitespace)
      guard fields.count == 3, let colour = channelColour(fields, name: pendingName) else {
        continue
      }
      colours.append(colour)
      pendingName = nil
    }
    return colours
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = "JASC-PAL\n0100\n\(colours.count)\n"
    for colour in colours {
      if let name = PaletteText.singleLine(colour.name) {
        text += "; \(name)\n"
      }
      text += "\(colour.red) \(colour.green) \(colour.blue)\n"
    }
    return Data(text.utf8)
  }

  /// A colour from three whole-number channels, or nil when a field is not one.
  fileprivate static func channelColour(_ fields: [Substring], name: String?) -> PaletteColour? {
    let values = fields.compactMap(PaletteHex.decimal)
    guard values.count == 3 else { return nil }
    return PaletteMath.colour(
      name: name, red: Double(values[0]) / 255, green: Double(values[1]) / 255,
      blue: Double(values[2]) / 255)
  }
}

// MARK: - Homesite (HPL)

/// The Homesite palette format (.hpl): a "Palette" line, a "Version 4.0" line, a line of dashes,
/// then "red green blue" lines. A "; name" line before a colour names it.
///
/// As in the Android coder, the first three numbers of a colour line are read and any text after
/// them is ignored, so "1 2 3abc" is the colour 1, 2, 3.
public enum HPLPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let lines = PaletteText.lines(of: data)
    guard lines.count >= 2, lines[0].contains("Palette"), lines[1].contains("Version 4.0")
    else { throw PaletteFormatError.invalidFormat }

    var colours: [PaletteColour] = []
    var pendingName: String?
    for line in lines.dropFirst(3) {
      let text = PaletteText.trimmed(line)
      if text.isEmpty { continue }
      if text.hasPrefix(";") {
        let comment = PaletteText.trimmed(text.dropFirst())
        if !comment.isEmpty { pendingName = comment }
        continue
      }
      guard let values = leadingNumbers(line) else { continue }
      colours.append(
        PaletteMath.colour(
          name: pendingName, red: Double(values[0]) / 255, green: Double(values[1]) / 255,
          blue: Double(values[2]) / 255))
      pendingName = nil
    }
    return colours
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = "Palette\nVersion 4.0\n-----------\n"
    for colour in colours {
      if let name = PaletteText.singleLine(colour.name) {
        text += "; \(name)\n"
      }
      text += "\(colour.red) \(colour.green) \(colour.blue)\n"
    }
    return Data(text.utf8)
  }

  /// The first three numbers of a line, read as the Android regex `^\s*(\d+)\s+(\d+)\s+(\d+).*$`
  /// reads them. Each of the first two numbers is followed by white space, and the third may be
  /// followed by any text.
  private static func leadingNumbers(_ line: Substring) -> [Int]? {
    var rest = line.drop(while: \.isWhitespace)
    var values: [Int] = []
    for index in 0..<3 {
      let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
      guard let value = PaletteHex.decimal(digits) else { return nil }
      values.append(value)
      rest = rest.dropFirst(digits.count)
      if index < 2 {
        guard let next = rest.first, next.isWhitespace else { return nil }
        rest = rest.drop(while: \.isWhitespace)
      }
    }
    return values
  }
}

// MARK: - Skencil (SPL)

/// The Skencil palette format (.spl): a "##Sketch RGBPalette 0" line, then "red green blue name"
/// lines with channels from 0 to 1. The name is optional.
///
/// As in the Android regex, white space must follow the third channel, so a line of three numbers
/// with nothing after them is skipped. Numbers are decimals such as "0.5", ".5" or "1".
public enum SkencilPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let lines = PaletteText.lines(of: data)
    guard let header = lines.first, header.contains("##Sketch RGBPalette 0") else {
      throw PaletteFormatError.invalidFormat
    }
    return lines.dropFirst().compactMap { colour($0) }
  }

  /// Each channel with six decimals, then the name. Channels are written from 0 to 1.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = "##Sketch RGBPalette 0\n"
    for colour in colours {
      let channels = [colour.red, colour.green, colour.blue].map {
        String(format: "%.6f", Double($0) / 255)
      }
      text += channels.joined(separator: " ")
      if let name = PaletteText.singleLine(colour.name) {
        text += " " + name
      }
      text += "\n"
    }
    return Data(text.utf8)
  }

  /// The colour of one line, or nil when the line does not hold three numbers and white space.
  private static func colour(_ line: Substring) -> PaletteColour? {
    var rest = line.drop(while: \.isWhitespace)
    var channels: [Double] = []
    for _ in 0..<3 {
      let token = rest.prefix(while: { $0.isASCII && ($0.isNumber || $0 == ".") })
      guard isDecimal(token), let value = Double(token) else { return nil }
      channels.append(value)
      rest = rest.dropFirst(token.count)
      guard let next = rest.first, next.isWhitespace else { return nil }
      rest = rest.drop(while: \.isWhitespace)
    }
    return PaletteMath.colour(
      name: PaletteText.trimmed(rest), red: channels[0], green: channels[1], blue: channels[2])
  }

  /// Digits with at most one point, which needs a digit after it, as the Android pattern
  /// `\d*\.?\d+` and `\d+` describe.
  private static func isDecimal(_ token: Substring) -> Bool {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    switch parts.count {
    case 1: return !parts[0].isEmpty
    case 2: return !parts[1].isEmpty
    default: return false
    }
  }
}

// MARK: - Corel Painter

/// The Corel Painter swatch format: a fixed block of ROWS, COLS, WIDTH, HEIGHT, TEXTHEIGHT and
/// SPACING lines, then one "R: r, G: g, B: b  HV: x, SV: y, VV: z  name" line per colour. Channels
/// are 0 to 255, and the hue, saturation and value fields are not kept.
public enum CorelPainterPaletteCoder {

  private static let headerKeys = ["ROWS", "COLS", "WIDTH", "HEIGHT", "TEXTHEIGHT", "SPACING"]

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    // As in the Android coder, the text must start with "ROWS " before any byte order mark is
    // removed, so a file with a byte order mark is rejected.
    guard String(decoding: data, as: UTF8.self).hasPrefix("ROWS ") else {
      throw PaletteFormatError.invalidFormat
    }
    let lines = PaletteText.lines(of: data).map { String($0) }
    guard lines.count >= 7,
      zip(headerKeys, lines).allSatisfy({ pair in pair.1.hasPrefix(pair.0) })
    else {
      throw PaletteFormatError.invalidFormat
    }

    var colours: [PaletteColour] = []
    for line in lines.dropFirst(6) {
      guard
        let match = PaletteText.trimmed(line).firstMatch(
          of:
            /[ \t]*R[ \t]*:[ \t]*([0-9]*\.?[0-9]+)[ \t,]*G[ \t]*:[ \t]*([0-9]*\.?[0-9]+)[ \t,]*B[ \t]*:[ \t]*([0-9]*\.?[0-9]+)[ \t,]*(?:HV[ \t]*:[ \t]*[0-9]*\.?[0-9]+[ \t,]*)?(?:SV[ \t]*:[ \t]*[0-9]*\.?[0-9]+[ \t,]*)?(?:VV[ \t]*:[ \t]*[0-9]*\.?[0-9]+[ \t,]*)?(.*)/
        ),
        let red = Int(String(match.output.1)), let green = Int(String(match.output.2)),
        let blue = Int(String(match.output.3))
      else { continue }
      colours.append(
        PaletteMath.colour(
          name: PaletteText.trimmed(match.output.4), red: Double(red) / 255,
          green: Double(green) / 255, blue: Double(blue) / 255))
    }
    return colours
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = "ROWS 12\nCOLS 22\nWIDTH 16\nHEIGHT 16\nTEXTHEIGHT 0\nSPACING 1\n"
    for colour in colours {
      text +=
        "R: \(colour.red), G:\(colour.green), B:\(colour.blue)  HV:0.00, SV:0.00, VV:0.00"
      if let name = PaletteText.singleLine(colour.name) {
        text += "  " + name
      }
      text += "\n"
    }
    return Data(text.utf8)
  }
}
