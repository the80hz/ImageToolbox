import Foundation

// MARK: - HEX

/// The hex text format (.hex): one colour per line as "#rrggbb" or "#rrggbbaa". A "; name" line
/// before a colour names it.
///
/// The Android coder reads each line as runs of "#" and hex digits. Any other character ends a run,
/// so several colours may share a line, and a word made of hex letters, such as "Dead", is a colour.
/// Runs with another digit count are skipped.
public enum HEXPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var colours: [PaletteColour] = []
    var pendingName: String?
    for line in PaletteText.lines(of: data) {
      let text = PaletteText.trimmed(line)
      if text.isEmpty { continue }
      if text.hasPrefix(";") {
        let comment = PaletteText.trimmed(text.dropFirst())
        if !comment.isEmpty { pendingName = comment }
        continue
      }
      for run in hexRuns(line) {
        guard let colour = PaletteHex.colour(run, name: pendingName, layout: .rgba) else {
          continue
        }
        colours.append(colour)
        pendingName = nil
      }
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// The maximal runs of "#" and hex digits in a line, in order.
  private static func hexRuns(_ line: Substring) -> [String] {
    var runs: [String] = []
    var current = ""
    for character in line {
      if character == "#" || character.isHexDigit {
        current.append(character)
      } else if !current.isEmpty {
        runs.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      runs.append(current)
    }
    return runs
  }

  /// Each colour with a "; name" line before it. Colours with alpha are written with 8 digits.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = ""
    for colour in colours {
      if let name = PaletteText.singleLine(colour.name) {
        text += "; \(name)\n"
      }
      let bytes =
        colour.alpha == 255
        ? [colour.red, colour.green, colour.blue]
        : [colour.red, colour.green, colour.blue, colour.alpha]
      text += "#" + PaletteText.hex(bytes) + "\n"
    }
    return Data(text.utf8)
  }
}

// MARK: - RGB and RGBA text

/// The RGB text format (.rgb): one colour per line as hex digits, with an optional "#" and an
/// optional name after the digits. Lines that are not colours are skipped. Alpha digits are ignored.
public enum RGBPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let colours = PaletteText.lines(of: data).compactMap { line in
      PaletteHex.leadingColour(String(line), layout: .rgb)
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// One "#rrggbb" colour per line, with the name after it. Lines are separated by CRLF, as in the
  /// Android coder.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let lines = colours.map { colour -> String in
      let hex = "#" + PaletteText.hex([colour.red, colour.green, colour.blue])
      guard let name = PaletteText.singleLine(colour.name) else { return hex }
      return hex + " " + name
    }
    return Data(lines.joined(separator: "\r\n").utf8)
  }
}

/// The RGBA text format (.rgba): one colour per line as "#rrggbbaa", with an optional name after
/// the digits. Colours with 3, 4, 6 or 8 digits are read, and any other line is an error.
public enum RGBAPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var colours: [PaletteColour] = []
    for line in PaletteText.lines(of: data) {
      let text = PaletteText.trimmed(line)
      if text.isEmpty { continue }
      guard let colour = PaletteHex.leadingColour(text, layout: .rgba) else {
        throw PaletteFormatError.invalidFormat
      }
      colours.append(colour)
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// One "#rrggbbaa" colour per line, with the name after it. Lines are separated by CRLF.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let lines = colours.map { colour -> String in
      let hex = "#" + PaletteText.hex([colour.red, colour.green, colour.blue, colour.alpha])
      guard let name = PaletteText.singleLine(colour.name) else { return hex }
      return hex + " " + name
    }
    return Data(lines.joined(separator: "\r\n").utf8)
  }
}
