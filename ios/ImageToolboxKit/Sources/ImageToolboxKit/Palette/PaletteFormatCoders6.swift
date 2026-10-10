import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - CorelDraw V3

/// The CorelDraw version 3 palette (.pal) text format: one colour per line as a quoted name, then
/// cyan, magenta, yellow and black as percentages. Lines without a match are skipped.
public enum CorelDraw3PaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    var colours: [PaletteColour] = []
    for line in PaletteText.lines(of: data) {
      let text = PaletteText.trimmed(line)
      guard
        let match = text.firstMatch(
          of:
            /"(.*)"[ \t]*([0-9]*\.?[0-9]+)[ \t]*([0-9]*\.?[0-9]+)[ \t]*([0-9]*\.?[0-9]+)[ \t]*([0-9]*\.?[0-9]+)[ \t]*/
        ),
        let cyan = Double(match.output.2), let magenta = Double(match.output.3),
        let yellow = Double(match.output.4), let black = Double(match.output.5)
      else { continue }
      colours.append(
        PaletteMath.cmyk(
          name: String(match.output.1), cyan: cyan / 100, magenta: magenta / 100,
          yellow: yellow / 100, black: black / 100))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// One line per colour, with CMYK percentages rounded to whole numbers and CRLF line ends.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var text = ""
    for colour in colours {
      let cmyk = PaletteMath.rgbToCMYK(
        PaletteMath.unit(colour.red), PaletteMath.unit(colour.green),
        PaletteMath.unit(colour.blue))
      let percents = [cmyk.c, cmyk.m, cmyk.y, cmyk.k].map {
        Int(($0 * 100).rounded(.toNearestOrEven))
      }
      text += "\"\(colour.name ?? "")\"    \(percents[0])    \(percents[1])    \(percents[2])"
      text += "    \(percents[3])\r\n"
    }
    return Data(text.utf8)
  }
}

// MARK: - SK1

/// The SK1 palette (.skp) format: a "##sK1 palette" header, then Python-like lines. Colour lines
/// hold "color(['RGB', [r, g, b], alpha, 'name'])" with channels from 0 to 1. A "set_name('...')"
/// line gives the palette name, and the last non-empty one wins. Other lines are ignored.
public enum SKPPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let lines = PaletteText.lines(of: data)
    guard let header = lines.first, header.contains("##sK1 palette") else {
      throw PaletteFormatError.invalidFormat
    }

    var name: String?
    var colours: [PaletteColour] = []
    for line in lines.dropFirst() {
      let text = PaletteText.trimmed(line)
      if let nameMatch = text.firstMatch(of: /set_name\(.*?'(.*?)'\)/), !nameMatch.output.1.isEmpty
      {
        name = String(nameMatch.output.1)
      }
      guard
        let match = text.firstMatch(
          of:
            /color\(\['RGB', \[([0-9]+(?:\.[0-9]+)?), ([0-9]+(?:\.[0-9]+)?), ([0-9]+(?:\.[0-9]+)?)\], ([0-9]+(?:\.[0-9]+)?),.*?'(.*?)'/
        ),
        let red = Double(match.output.1), let green = Double(match.output.2),
        let blue = Double(match.output.3), let alpha = Double(match.output.4)
      else { continue }
      colours.append(
        PaletteMath.colour(
          name: String(match.output.5), red: red, green: green, blue: blue, alpha: alpha))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: name, colours: colours)
  }

  /// The header, the set-up lines and one colour line each. Quotes in the palette and colour names
  /// become underscores, as the Android coder writes them.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var text = "##sK1 palette\n"
    text += "Palette.Builder()\n"
    let paletteName = (document.name ?? "").map { $0 == "'" || $0 == "\"" ? "_" : String($0) }
      .joined()
    text += "set_name('\(paletteName)')\n"
    text += "set_source('ColorPaletteCodable')\n"
    text += "set_columns(4)\n"
    for colour in document.allColours {
      let name = (colour.name ?? "").map { $0 == "'" || $0 == "\"" ? "_" : String($0) }
        .joined()
      let red = PaletteMath.unit(colour.red)
      let green = PaletteMath.unit(colour.green)
      let blue = PaletteMath.unit(colour.blue)
      let alpha = PaletteMath.unit(colour.alpha)
      text += "color(['RGB', [\(red), \(green), \(blue)], \(alpha), '\(name)'])\n"
    }
    text += "palette_end()\n"
    return Data(text.utf8)
  }
}

// MARK: - Image

/// An image palette: a PNG with one 32 by 32 pixel swatch per colour, in a row. Colour names are
/// appended after the PNG data, after the IEND chunk, as a line "; IMAGE_NAMES: " with the names
/// separated by "|". Reading takes the centre pixel of each swatch, so any PNG or JPEG whose
/// swatches are 32 pixels wide can be read. Only the PNG written here has names.
public enum ImagePaletteCoder {

  private static let swatchSize = 32
  /// The IEND chunk type and its CRC, which end a PNG file.
  private static let endOfPNG: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
  private static let namesPrefix = "; IMAGE_NAMES: "

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    guard let image = ImageCodec.decode(data), let raster = RasterImage(image) else {
      throw PaletteFormatError.invalidFormat
    }
    let count = raster.width / swatchSize
    guard count > 0 else { throw PaletteFormatError.invalidFormat }

    let pixels = raster.straightRGBA()
    let names = embeddedNames(in: [UInt8](data))
    var colours: [PaletteColour] = []
    for index in 0..<count {
      let offset = (index * swatchSize + swatchSize / 2) * 4
      colours.append(
        PaletteColour(
          name: index < names.count ? names[index] : nil,
          red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2],
          alpha: pixels[offset + 3]))
    }
    return colours
  }

  /// A PNG with one swatch per colour, followed by the names line. The names line is empty when
  /// there are no colours.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    guard !colours.isEmpty else { return Data() }
    let width = colours.count * swatchSize
    var pixels = [UInt8](repeating: 0, count: width * swatchSize * 4)
    for (index, colour) in colours.enumerated() {
      // Core Graphics works with premultiplied pixels, so the channels are scaled by alpha.
      let alpha = Double(colour.alpha) / 255
      let premultiplied = [colour.red, colour.green, colour.blue].map {
        UInt8((Double($0) * alpha).rounded())
      }
      for y in 0..<swatchSize {
        for x in index * swatchSize..<(index + 1) * swatchSize {
          let offset = (y * width + x) * 4
          pixels[offset] = premultiplied[0]
          pixels[offset + 1] = premultiplied[1]
          pixels[offset + 2] = premultiplied[2]
          pixels[offset + 3] = colour.alpha
        }
      }
    }

    let raster = RasterImage(width: width, height: swatchSize, pixels: pixels)
    guard let image = raster.toCGImage(),
      let png = ImageCodec.encode(image, typeIdentifier: "public.png", lossy: false)
    else { return Data() }

    // The names are written as they are, except that a line break becomes a space, since it would
    // end the names line.
    let names = colours.map { colour in
      String((colour.name ?? "").map { $0.isNewline ? " " : $0 })
    }.joined(separator: "|")
    var output = png
    output.append(Data("\n\(namesPrefix)\(names)\n".utf8))
    return output
  }

  /// The names after the IEND chunk, or an empty list when the file has none.
  private static func embeddedNames(in bytes: [UInt8]) -> [String?] {
    guard let end = indexOf(endOfPNG, in: bytes), end + endOfPNG.count < bytes.count else {
      return []
    }
    let text = String(decoding: bytes[(end + endOfPNG.count)...], as: UTF8.self)
    guard text.hasPrefix("\n\(namesPrefix)") else { return [] }
    guard
      let line = text.split(whereSeparator: \.isNewline).first(where: {
        $0.hasPrefix(namesPrefix)
      })
    else { return [] }
    let list = PaletteText.trimmed(line.dropFirst(namesPrefix.count))
    return list.split(separator: "|", omittingEmptySubsequences: false).map {
      let name = String($0)
      return name.isEmpty ? nil : name
    }
  }

  private static func indexOf(_ pattern: [UInt8], in bytes: [UInt8]) -> Int? {
    guard !pattern.isEmpty, pattern.count <= bytes.count else { return nil }
    for start in 0...(bytes.count - pattern.count)
    where bytes[start..<start + pattern.count].elementsEqual(pattern) {
      return start
    }
    return nil
  }
}
