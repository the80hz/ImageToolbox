import Foundation

/// JSON text in the layout that kotlinx.serialization writes for the Android palette classes. The
/// writers build the text directly, because Foundation's encoder writes whole doubles without a
/// decimal point, leaves out null values and escapes slashes.
enum PaletteJSON {

  /// A double as Kotlin prints it: the shortest text that reads back to the same value, with a
  /// decimal point, such as "1.0" or "0.5".
  static func number(_ value: Double) -> String {
    "\(value)"
  }

  /// An optional string as JSON: quoted, or `null` when there is none.
  static func nullableString(_ text: String?) -> String {
    text.map(quoted) ?? "null"
  }

  /// A quoted JSON string with the escapes that kotlinx.serialization writes. The slash and
  /// characters above ASCII are written as they are.
  static func quoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case "\u{08}": result += "\\b"
      case "\u{0C}": result += "\\f"
      default:
        if scalar.value < 0x20 {
          result += String(format: "\\u%04x", scalar.value)
        } else {
          result.unicodeScalars.append(scalar)
        }
      }
    }
    return result + "\""
  }
}
