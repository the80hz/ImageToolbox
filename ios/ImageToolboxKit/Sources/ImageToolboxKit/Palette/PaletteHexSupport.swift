import Foundation

// Hex colour helpers for the text and XML palette formats. They follow the Android `PaletteColor`
// hex constructors, which keep only the hex digits of a string and read the channels by format.

enum PaletteHex {

  /// How the channels of a hex colour are ordered.
  enum Layout {
    /// Red, green and blue. Alpha digits are ignored.
    case rgb
    /// Red, green, blue and alpha. Colours without alpha are opaque.
    case rgba
    /// Alpha, red, green and blue, as in Android colour resources. The Android coder shifts colours
    /// with 3 or 6 digits, so these are read as red, green and blue instead.
    case argb
  }

  /// The channels of hex digits with 3, 4, 6 or 8 digits. Short forms repeat each digit, and the
  /// result has four channels only for 4 and 8 digits. Returns nil for any other digit count.
  static func channels(_ digits: String) -> [UInt8]? {
    let values = digits.compactMap(\.hexDigitValue)
    guard values.count == digits.count else { return nil }
    switch values.count {
    case 3, 4:
      return values.map { UInt8($0 * 17) }
    case 6, 8:
      return stride(from: 0, to: values.count, by: 2).map {
        UInt8(values[$0] << 4 | values[$0 + 1])
      }
    default:
      return nil
    }
  }

  /// A colour from hex text. Characters that are not hex digits, such as "#", are ignored.
  static func colour(_ text: String, name: String?, layout: Layout) -> PaletteColour? {
    guard let channels = channels(text.filter(\.isHexDigit)) else { return nil }
    let hasAlpha = channels.count == 4
    switch layout {
    case .rgb:
      return PaletteColour(
        name: name, red: channels[0], green: channels[1], blue: channels[2])
    case .rgba:
      return PaletteColour(
        name: name, red: channels[0], green: channels[1], blue: channels[2],
        alpha: hasAlpha ? channels[3] : 255)
    case .argb:
      guard hasAlpha else {
        return PaletteColour(
          name: name, red: channels[0], green: channels[1], blue: channels[2])
      }
      return PaletteColour(
        name: name, red: channels[1], green: channels[2], blue: channels[3], alpha: channels[0])
    }
  }

  /// A colour from eight hex digits of cyan, magenta, yellow and black, as the Android CMYK hex
  /// constructor reads them. Other digit counts are rejected.
  static func cmykColour(_ text: String, name: String?) -> PaletteColour? {
    let digits = text.filter(\.isHexDigit)
    guard digits.count == 8, let channels = channels(digits), channels.count == 4 else {
      return nil
    }
    let rgb = PaletteMath.cmykToRGB(
      Double(channels[0]) / 255, Double(channels[1]) / 255, Double(channels[2]) / 255,
      Double(channels[3]) / 255)
    return PaletteMath.colour(name: name, red: rgb.0, green: rgb.1, blue: rgb.2)
  }

  /// The colour at the start of a line of an RGB or RGBA text file, with the name after it. An
  /// optional "#" and white space may come first. Like the Android regex, at most eight digits are
  /// taken, and the rest of the line is the name. Returns nil when no hex digits start the line.
  static func leadingColour(_ line: String, layout: Layout) -> PaletteColour? {
    var body = Substring(PaletteText.trimmed(line))
    if body.hasPrefix("#") {
      body.removeFirst()
    }
    body = body.drop(while: \.isWhitespace)
    let digits = body.prefix(while: \.isHexDigit).prefix(8)
    let name = PaletteText.trimmed(body.dropFirst(digits.count))
    return colour(String(digits), name: name, layout: layout)
  }

  /// A decimal number of ASCII digits that fits in 32 bits, as the Android `toIntOrNull` reads it.
  static func decimal(_ text: Substring) -> Int? {
    guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int32(text).map(Int.init)
  }
}
