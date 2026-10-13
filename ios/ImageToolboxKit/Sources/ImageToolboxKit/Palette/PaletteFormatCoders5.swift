import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Affinity

/// The Affinity Designer (.afpalette) binary format.
///
/// The file starts with a byte order mark, then a Latin 1 name, a "VlaP" section with the colour
/// count and one "rloC" record per colour. Each record has a six-byte gap and a four-byte colour
/// type: "ABGR" (three floats), "ABAL" (LAB, three 16-bit values), "KYMC" (four floats), "ALSH"
/// (HSL, three floats) or "YARG" (one grey float). The colour data is found by searching for its
/// markers, as the Android coder does, so the reader accepts the markers in either byte order.
/// Names are UTF-8 in an optional "VNaP" section after the colours.
public enum AFPaletteCoder: PaletteDocumentCoder {

  private static let byteOrderMarks: [UInt32] = [0x414B_FF00, 0x00FF_4B41]
  private static let recordMarker: [UInt8] = Array("rloC".utf8)

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var reader = PaletteByteReader(data)
    let name = try readHeader(&reader)

    let colourCount = Int(try reader.uint32(.little))
    var colours: [PaletteColour] = []
    for _ in 0..<colourCount {
      do {
        colours.append(try readRecord(&reader))
      } catch PaletteFormatError.unknownColourModel(let type) {
        throw PaletteFormatError.unknownColourModel(type)
      } catch {
        // A record that cannot be read ends the colours, but only after the first one.
        if colours.isEmpty { throw PaletteFormatError.invalidFormat }
        break
      }
    }

    readNames(&reader, into: &colours)
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: name, colours: colours)
  }

  /// The byte order mark, the palette name and the colour count, then the colours. The name is
  /// "Palette" when the palette has none, and the colour names are written after the colours.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var writer = PaletteByteWriter()
    writer.uint32(byteOrderMarks[0], .little)
    writer.uint32(11, .little)
    writer.append([0x50, 0x6C, 0x43, 0x4E])  // The NClP marker, written in reverse.
    var nameWriter = PaletteByteWriter()
    nameWriter.ascii(document.name ?? "Palette")
    writer.uint32(UInt32(nameWriter.bytes.count), .little)
    writer.append(nameWriter.bytes)
    let colours = document.allColours
    writer.append([0x50, 0x61, 0x6C, 0x56])  // The VlaP marker, written in reverse.
    writer.uint32(UInt32(min(colours.count, Int(UInt32.max))), .little)

    for colour in colours {
      writer.append(recordMarker)
      writer.append([0, 0, 0, 0, 0, 0])
      writer.append(Array("ABGR".utf8))
      writer.append(Array("Dloc_".utf8))
      writer.float32(PaletteMath.unit(colour.red), .little)
      writer.float32(PaletteMath.unit(colour.green), .little)
      writer.float32(PaletteMath.unit(colour.blue), .little)
    }

    writer.append([0x50, 0x61, 0x4E, 0x56])  // The VNaP marker, written in reverse.
    writer.uint32(0, .little)
    writer.uint32(UInt32(colours.count), .little)
    for colour in colours {
      let colourName = Array((colour.name ?? "Color").utf8)
      writer.uint32(UInt32(colourName.count), .little)
      writer.append(colourName)
    }
    return writer.data
  }

  /// Checks the byte order mark and returns the palette name. When the mark is not one of the known
  /// values, the NClP marker is searched for instead, and the reader is placed after it.
  private static func readHeader(_ reader: inout PaletteByteReader) throws -> String? {
    let hasMark = (try? reader.uint32(.little)).map { byteOrderMarks.contains($0) } ?? false
    if !hasMark {
      try reader.seek(to: 0)
      let little: [UInt8] = [0x4E, 0x43, 0x6C, 0x50]
      let reversed: [UInt8] = [0x50, 0x6C, 0x43, 0x4E]
      guard let found = reader.find(little) ?? reader.find(reversed) else {
        throw PaletteFormatError.invalidHeader
      }
      try reader.seek(to: found + 4)
    }

    // The NClP marker is searched for from the current position, in either byte order.
    if let found = reader.find([0x4E, 0x43, 0x6C, 0x50]) ?? reader.find([0x50, 0x6C, 0x43, 0x4E]) {
      try reader.seek(to: found + 4)
    } else {
      throw PaletteFormatError.invalidFormat
    }

    let nameLength = Int(try reader.uint32(.little))
    var name: String?
    if nameLength > 0 {
      name = try? reader.ascii(nameLength)
    }

    guard
      let vlap = reader.find([0x56, 0x6C, 0x61, 0x50]) ?? reader.find([0x50, 0x61, 0x6C, 0x56])
    else { throw PaletteFormatError.invalidFormat }
    try reader.seek(to: vlap + 4)
    return name
  }

  /// Reads one "rloC" record and returns its colour.
  private static func readRecord(_ reader: inout PaletteByteReader) throws -> PaletteColour {
    guard let marker = reader.find(recordMarker) else { throw PaletteFormatError.truncated }
    try reader.seek(to: marker + 4)
    reader.skipIfAvailable(6)
    let type = try reader.ascii(4)

    switch type {
    case "ABGR":
      skipPast("Dloc_", in: &reader)
      let red = try reader.float32(.little)
      let green = try reader.float32(.little)
      let blue = try reader.float32(.little)
      return PaletteMath.colour(name: nil, red: red, green: green, blue: blue)
    case "ABAL":
      skipPast("<loc_", in: &reader)
      let lightness = Double(try reader.uint16(.little)) / 65535 * 100
      let aStar = Double(try reader.uint16(.little)) / 65535 * 256 - 128
      let bStar = Double(try reader.uint16(.little)) / 65535 * 256 - 128
      let rgb = PaletteLab.toSRGB(l: lightness, a: aStar, b: bStar)
      return PaletteColour(name: nil, red: rgb.red, green: rgb.green, blue: rgb.blue)
    case "KYMC":
      skipPast("Hloc_", in: &reader)
      let cyan = try reader.float32(.little)
      let magenta = try reader.float32(.little)
      let yellow = try reader.float32(.little)
      let black = try reader.float32(.little)
      return PaletteMath.cmyk(
        name: nil, cyan: cyan, magenta: magenta, yellow: yellow, black: black)
    case "ALSH":
      skipPast("Dloc_", in: &reader)
      let hue = try reader.float32(.little)
      let saturation = try reader.float32(.little)
      let lightness = try reader.float32(.little)
      let rgb = PaletteMath.hslToRGB(hue: hue, saturation: saturation, lightness: lightness)
      return PaletteMath.colour(name: nil, red: rgb.0, green: rgb.1, blue: rgb.2)
    case "YARG":
      skipPast("<loc_", in: &reader)
      let white = try reader.float32(.little)
      return PaletteMath.grey(name: nil, white: white)
    default:
      throw PaletteFormatError.unknownColourModel(type)
    }
  }

  /// Moves past the next occurrence of `marker`. The position does not change when it is absent,
  /// because the Android coder ignores a missing marker here.
  private static func skipPast(_ marker: String, in reader: inout PaletteByteReader) {
    let bytes = Array(marker.utf8)
    guard let found = reader.find(bytes) else { return }
    try? reader.seek(to: found + bytes.count)
  }

  /// Reads the names in the "VNaP" section, one for each colour from the start. A name that
  /// cannot be read ends the names.
  private static func readNames(
    _ reader: inout PaletteByteReader, into colours: inout [PaletteColour]
  ) {
    guard
      let section = reader.find([0x56, 0x4E, 0x61, 0x50]) ?? reader.find([0x50, 0x61, 0x4E, 0x56])
    else { return }
    do {
      try reader.seek(to: section + 4)
      _ = try reader.uint32(.little)
      let nameCount = Int(try reader.uint32(.little))
      for index in 0..<min(nameCount, colours.count) {
        let length = Int(try reader.uint32(.little))
        let name = try reader.utf8(length)
        let colour = colours[index]
        colours[index] = PaletteColour(
          name: name, red: colour.red, green: colour.green, blue: colour.blue,
          alpha: colour.alpha)
      }
    } catch {
      // The names are optional, so the colours are kept as they are.
    }
  }
}

// MARK: - CLF (Lab colours)

/// The CLF text format: one colour per line as "name", then L, a and b separated by tabs. Decimal
/// commas are accepted. Lines that do not have four tab-separated fields, or whose values are not
/// numbers, are skipped. The colours are LAB, converted to sRGB.
public enum CLFPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var colours: [PaletteColour] = []
    for line in PaletteText.lines(of: data) {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 4 else { continue }
      let values = fields[1...3].map {
        Double(PaletteText.trimmed($0.replacingOccurrences(of: ",", with: "."))) ?? .nan
      }
      guard values.allSatisfy(\.isFinite) else { continue }
      let rgb = PaletteLab.toSRGB(l: values[0], a: values[1], b: values[2])
      colours.append(
        PaletteColour(name: String(fields[0]), red: rgb.red, green: rgb.green, blue: rgb.blue))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// One line per colour, with the name "Color" when the colour has none. The values are printed
  /// as java.lang.Double.toString prints them, as the Android coder does.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let lines = colours.map { colour -> String in
      let name = colour.name.map(tabsAndLineBreaksAsSpaces) ?? "Color"
      let lab = PaletteLab.fromSRGB(red: colour.red, green: colour.green, blue: colour.blue)
      let values = [lab.l, lab.a, lab.b].map(javaDoubleText)
      return "\(name)\t\(values[0])\t\(values[1])\t\(values[2])"
    }
    return Data(lines.joined(separator: "\n").utf8)
  }
}

/// The name with each tab and line break replaced by a space, so that the line keeps its four
/// fields. The Android coder writes the name unchanged, which would break such a line.
private func tabsAndLineBreaksAsSpaces(_ name: String) -> String {
  String(name.map { $0 == "\t" || $0.isNewline ? " " : $0 })
}

/// The text that java.lang.Double.toString gives for `value`: the shortest digits that read back
/// to the same value, in plain notation for magnitudes from 1e-3 up to 1e7, and otherwise in the
/// form "1.5E-5".
private func javaDoubleText(_ value: Double) -> String {
  if value.isNaN { return "NaN" }
  if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
  let sign = value.sign == .minus ? "-" : ""
  guard value != 0 else { return sign + "0.0" }

  // Swift prints the same shortest digits in its own notation, which is read back here.
  let parts = "\(abs(value))".split(separator: "e")
  let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
  let fraction = parts[0].split(separator: ".", omittingEmptySubsequences: false)
  var digits = fraction.map { String($0) }.joined()
  // The decimal point comes after `point` digits of `digits`.
  var point = fraction[0].count + exponent
  while digits.hasPrefix("0") {
    digits.removeFirst()
    point -= 1
  }
  while digits.hasSuffix("0") {
    digits.removeLast()
  }

  if abs(value) >= 1e-3 && abs(value) < 1e7 {
    if point <= 0 {
      return sign + "0." + String(repeating: "0", count: -point) + digits
    }
    if point >= digits.count {
      return sign + digits + String(repeating: "0", count: point - digits.count) + ".0"
    }
    let split = digits.index(digits.startIndex, offsetBy: point)
    return sign + String(digits[..<split]) + "." + String(digits[split...])
  }
  let rest = String(digits.dropFirst())
  return sign + String(digits.prefix(1)) + "." + (rest.isEmpty ? "0" : rest) + "E\(point - 1)"
}

// MARK: - KOffice

/// The KOffice colour table (.colors): a "KDE RGB Palette" line, then "r g b" lines with 0 to 255
/// channels and an optional name after a tab or a space. Lines that do not start with three
/// numbers are skipped.
public enum KOfficePaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let lines = PaletteText.lines(of: data)
    guard let header = lines.first, header.contains("KDE RGB Palette") else {
      throw PaletteFormatError.invalidFormat
    }

    var colours: [PaletteColour] = []
    for line in lines.dropFirst() {
      guard
        let match = String(line).firstMatch(
          of: /^\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)(.*)$/),
        let red = Int(match.output.1), let green = Int(match.output.2),
        let blue = Int(match.output.3)
      else { continue }
      colours.append(
        PaletteColour(
          name: PaletteText.trimmed(match.output.4),
          red: UInt8(min(red, 255)), green: UInt8(min(green, 255)), blue: UInt8(min(blue, 255))))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// The header, then "r g b" with the name after a tab when the colour has one.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = "KDE RGB Palette\n"
    for colour in colours {
      text += "\(colour.red)\t\(colour.green)\t\(colour.blue)"
      if let name = PaletteText.singleLine(colour.name) {
        text += "\t" + name
      }
      text += "\n"
    }
    return Data(text.utf8)
  }
}
