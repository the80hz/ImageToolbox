import Foundation

// Helpers shared by the palette coders in PaletteFormatCoders3 to PaletteFormatCoders10. They are
// internal rather than private so that those files can share them. The helpers of the first two
// files are private to them and are not used here, so the names do not clash.

/// The order of the bytes in a multi-byte field.
enum PaletteByteOrder: Sendable {
  case big
  case little
}

/// Reads big- or little-endian fields from a palette file. Reads past the end throw `truncated`,
/// and a failed read leaves the position where it was.
struct PaletteByteReader {
  private let bytes: [UInt8]
  /// The index of the next byte to read.
  private(set) var position = 0

  init(_ data: Data) {
    bytes = [UInt8](data)
  }

  /// The number of bytes that are still unread.
  var remaining: Int { bytes.count - position }

  /// Reads `count` bytes.
  mutating func take(_ count: Int) throws -> [UInt8] {
    guard count >= 0, count <= remaining else { throw PaletteFormatError.truncated }
    let slice = Array(bytes[position..<position + count])
    position += count
    return slice
  }

  /// Moves forward by `count` bytes without reading them.
  mutating func skip(_ count: Int) throws {
    guard count >= 0, count <= remaining else { throw PaletteFormatError.truncated }
    position += count
  }

  /// Moves forward by `count` bytes when they exist, and returns false without moving otherwise.
  @discardableResult
  mutating func skipIfAvailable(_ count: Int) -> Bool {
    guard count >= 0, count <= remaining else { return false }
    position += count
    return true
  }

  /// Moves to an absolute position, which may be the end of the data.
  mutating func seek(to target: Int) throws {
    guard target >= 0, target <= bytes.count else { throw PaletteFormatError.truncated }
    position = target
  }

  /// The absolute index of the first occurrence of `pattern` at or after the position, or nil.
  func find(_ pattern: [UInt8]) -> Int? {
    guard !pattern.isEmpty, pattern.count <= remaining else { return nil }
    for start in position...(bytes.count - pattern.count)
    where bytes[start..<start + pattern.count].elementsEqual(pattern) {
      return start
    }
    return nil
  }

  /// Moves to the start of the next occurrence of `pattern`. The position does not change when
  /// the pattern is not found.
  mutating func seekToPattern(_ pattern: [UInt8]) throws {
    guard let index = find(pattern) else { throw PaletteFormatError.truncated }
    position = index
  }

  mutating func uint8() throws -> UInt8 {
    try take(1)[0]
  }

  mutating func uint16(_ order: PaletteByteOrder = .big) throws -> UInt16 {
    let value = try take(2)
    return order == .big
      ? UInt16(value[0]) << 8 | UInt16(value[1])
      : UInt16(value[1]) << 8 | UInt16(value[0])
  }

  mutating func uint32(_ order: PaletteByteOrder = .big) throws -> UInt32 {
    let value = try take(4)
    let ordered = order == .big ? value : Array(value.reversed())
    return ordered.reduce(0) { $0 << 8 | UInt32($1) }
  }

  mutating func int16(_ order: PaletteByteOrder = .big) throws -> Int16 {
    Int16(bitPattern: try uint16(order))
  }

  mutating func int32(_ order: PaletteByteOrder = .big) throws -> Int32 {
    Int32(bitPattern: try uint32(order))
  }

  mutating func float32(_ order: PaletteByteOrder = .big) throws -> Double {
    Double(Float(bitPattern: try uint32(order)))
  }

  /// ASCII text of `count` bytes. Bytes above 127 become replacement characters.
  mutating func ascii(_ count: Int) throws -> String {
    String(decoding: try take(count), as: UTF8.self)
  }

  /// ISO 8859-1 text of `count` bytes, where every byte is one character.
  mutating func latin1(_ count: Int) throws -> String {
    PaletteText.latin1(try take(count))
  }

  /// UTF-8 text of `count` bytes.
  mutating func utf8(_ count: Int) throws -> String {
    String(decoding: try take(count), as: UTF8.self)
  }

  /// A Pascal string of UTF-16 code units. The length is a count of code units, stored in
  /// `lengthWidth` bits (16 or 32) with the given byte order. Trailing zero units are removed.
  mutating func pascalUTF16(
    _ order: PaletteByteOrder, lengthWidth: Int = 16
  ) throws -> String {
    let length =
      lengthWidth == 32
      ? Int(try uint32(order))
      : Int(try uint16(order))
    return try utf16(length, order)
  }

  /// `units` UTF-16 code units, with trailing zero units removed.
  mutating func utf16(_ units: Int, _ order: PaletteByteOrder) throws -> String {
    let raw = try take(units * 2)
    var codes: [UInt16] = []
    codes.reserveCapacity(units)
    for index in stride(from: 0, to: raw.count, by: 2) {
      let high = order == .big ? raw[index] : raw[index + 1]
      let low = order == .big ? raw[index + 1] : raw[index]
      codes.append(UInt16(high) << 8 | UInt16(low))
    }
    while codes.last == 0 {
      codes.removeLast()
    }
    return String(decoding: codes, as: UTF16.self)
  }
}

/// Writes fields of a palette file in the chosen byte order.
struct PaletteByteWriter {
  private(set) var bytes: [UInt8] = []

  var data: Data { Data(bytes) }

  mutating func append(_ values: [UInt8]) {
    bytes += values
  }

  /// The ASCII bytes of `text`, with characters above 127 written as "?".
  mutating func ascii(_ text: String) {
    bytes += text.utf8.map { $0 < 0x80 ? $0 : 0x3F }
  }

  mutating func uint8(_ value: UInt8) {
    bytes.append(value)
  }

  mutating func uint16(_ value: UInt16, _ order: PaletteByteOrder = .big) {
    let pair = [UInt8(value >> 8), UInt8(value & 0xFF)]
    bytes += order == .big ? pair : Array(pair.reversed())
  }

  mutating func uint32(_ value: UInt32, _ order: PaletteByteOrder = .big) {
    let four = [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
    bytes += order == .big ? four : Array(four.reversed())
  }

  mutating func int32(_ value: Int32, _ order: PaletteByteOrder = .big) {
    uint32(UInt32(bitPattern: value), order)
  }

  /// A 32-bit float of a value in the range 0 to 1.
  mutating func float32(_ value: Double, _ order: PaletteByteOrder = .little) {
    uint32(Float(value).bitPattern, order)
  }

  /// The UTF-16 units of `text` behind a count of units. The count is written in `lengthWidth`
  /// bits. Text longer than the count allows is cut.
  mutating func pascalUTF16(
    _ text: String, _ order: PaletteByteOrder, lengthWidth: Int = 16
  ) {
    let limit = lengthWidth == 32 ? Int(UInt32.max) : Int(UInt16.max)
    let units = Array(text.utf16.prefix(limit))
    if lengthWidth == 32 {
      uint32(UInt32(units.count), order)
    } else {
      uint16(UInt16(units.count), order)
    }
    for unit in units {
      uint16(unit, order)
    }
  }
}

/// Text helpers for the palette formats.
enum PaletteText {

  /// The lines of a text file, read as UTF-8, without a leading byte order mark.
  static func lines(of data: Data) -> [Substring] {
    var text = String(decoding: data, as: UTF8.self)
    if text.unicodeScalars.first == "\u{FEFF}" {
      text.unicodeScalars.removeFirst()
    }
    return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
  }

  /// The text without white space at either end.
  static func trimmed<S: StringProtocol>(_ text: S) -> String {
    String(text).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The text on one line. Line breaks, tabs and the extra separators become single spaces. Returns
  /// nil when nothing is left.
  static func singleLine(_ text: String?, extraSeparators: Set<Character> = []) -> String? {
    guard let text else { return nil }
    let words = text.split(whereSeparator: {
      $0.isNewline || $0 == "\t" || extraSeparators.contains($0)
    })
    let joined = trimmed(words.joined(separator: " "))
    return joined.isEmpty ? nil : joined
  }

  /// The text without its trailing zero characters, which pad fixed-length names.
  static func trimmedNulls(_ text: String) -> String {
    var result = text
    while result.hasSuffix("\0") {
      result.removeLast()
    }
    return result
  }

  /// Characters of ISO 8859-1 bytes, one character per byte.
  static func latin1(_ bytes: [UInt8]) -> String {
    String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
  }

  /// ISO 8859-1 bytes of `text`. Characters above U+00FF become "?".
  static func latin1Bytes(_ text: String) -> [UInt8] {
    text.utf16.map { $0 <= 0xFF ? UInt8($0) : 0x3F }
  }

  /// Lowercase or uppercase hexadecimal text of `bytes`, two digits each.
  static func hex(_ bytes: [UInt8], uppercase: Bool = false) -> String {
    bytes.map { byte in
      let digits = String(byte, radix: 16, uppercase: uppercase)
      return digits.count == 1 ? "0" + digits : digits
    }.joined()
  }

  /// A decimal number written with at most `maximumFractionDigits` digits after the point, with
  /// trailing zeros removed. Rounding is to the nearest value, with ties to even, as in
  /// `DecimalFormat`. The integer part keeps its zero when `keepLeadingZero` is true.
  static func decimal(
    _ value: Double, maximumFractionDigits: Int, keepLeadingZero: Bool = true
  ) -> String {
    var text = String(format: "%.\(maximumFractionDigits)f", value)
    if text.contains(".") {
      while text.hasSuffix("0") {
        text.removeLast()
      }
      if text.hasSuffix(".") {
        text.removeLast()
      }
    }
    if text == "-0" {
      text = "0"
    }
    if !keepLeadingZero, text.hasPrefix("0."), text.count > 2 {
      text.removeFirst()
    }
    return text
  }
}

/// XML helpers for the palette formats. Element names are compared without any prefix, in
/// lowercase, as the Android coders do.
enum PaletteXML {

  /// Runs an XML parser over `data`. Namespaces are not processed, so names keep their prefixes.
  /// Returns false when the document is not well formed.
  static func parse(_ data: Data, delegate: XMLParserDelegate) -> Bool {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.delegate = delegate
    return parser.parse()
  }

  /// The local part of a name without its prefix, in lowercase.
  static func localName(_ elementName: String) -> String {
    String(elementName.split(separator: ":").last ?? "").lowercased()
  }

  /// The text with the five XML special characters escaped.
  static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
