import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Sketch

/// The Sketch palette (.sketchpalette) JSON format: a document with a "colors" list of RGBA
/// colours from 0 to 1. Each colour may have a "name". The version fields are written as "1.4".
public enum SketchPaletteCoder {

  private struct Document: Codable {
    let compatibleVersion: String
    let pluginVersion: String
    let colors: [Colour]
  }

  private struct Colour: Codable {
    let name: String?
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
  }

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: data)
    } catch {
      throw PaletteFormatError.invalidFormat
    }
    let colours = document.colors.map { colour in
      PaletteMath.colour(
        name: colour.name, red: colour.red, green: colour.green, blue: colour.blue,
        alpha: colour.alpha)
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return colours
  }

  /// The document with each colour's RGBA channels from 0 to 1 and its name, or null when it has
  /// none. The keys follow the Android classes, and nothing is indented, as in the Android coder.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    let items = colours.map { colour -> String in
      let name = PaletteJSON.nullableString(PaletteText.singleLine(colour.name))
      return "{\"name\":\(name)"
        + ",\"red\":\(PaletteJSON.number(PaletteMath.unit(colour.red)))"
        + ",\"green\":\(PaletteJSON.number(PaletteMath.unit(colour.green)))"
        + ",\"blue\":\(PaletteJSON.number(PaletteMath.unit(colour.blue)))"
        + ",\"alpha\":\(PaletteJSON.number(PaletteMath.unit(colour.alpha)))}"
    }
    let text =
      "{\"compatibleVersion\":\"1.4\",\"pluginVersion\":\"1.4\",\"colors\":["
      + items.joined(separator: ",") + "]}"
    return Data(text.utf8)
  }
}

// MARK: - Simple Color Palette

/// The Simple Color Palette (.color-palette) JSON format, from sindresorhus.com. Each colour has
/// "components" in extended linear sRGB: three values, and a fourth for alpha when it is not 1.
/// Components are rounded to four decimal places, and converted to sRGB when read.
public enum SimplePaletteCoder: PaletteDocumentCoder {

  private static let places = 4

  private struct Document: Codable {
    let name: String?
    let colors: [Colour]
  }

  private struct Colour: Codable {
    let name: String?
    let components: [Double]
  }

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: data)
    } catch {
      throw PaletteFormatError.invalidFormat
    }

    var colours: [PaletteColour] = []
    for colour in document.colors {
      let components = colour.components.map { PaletteMath.rounded($0, places: places) }
      guard (3...4).contains(components.count) else { continue }
      let alpha = components.count == 4 ? PaletteMath.clampUnit(components[3]) : 1
      colours.append(
        PaletteMath.colour(
          name: colour.name,
          red: PaletteMath.sRGB(fromLinear: components[0]),
          green: PaletteMath.sRGB(fromLinear: components[1]),
          blue: PaletteMath.sRGB(fromLinear: components[2]),
          alpha: alpha))
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: document.name, colours: colours)
  }

  /// Linear components of each colour, with alpha only when it is not opaque. The text is indented
  /// as kotlinx.serialization indents it, with four spaces a level, and a null name where the
  /// palette or a colour has none.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let colourTexts = document.allColours.map { colour -> String in
      let red = PaletteMath.unit(colour.red)
      let green = PaletteMath.unit(colour.green)
      let blue = PaletteMath.unit(colour.blue)
      var components = [red, green, blue].map {
        PaletteMath.rounded(PaletteMath.linear(fromSRGB: $0), places: places)
      }
      let alpha = PaletteMath.rounded(PaletteMath.unit(colour.alpha), places: places)
      if alpha != 1 {
        components.append(alpha)
      }
      let values = components.map { "                " + PaletteJSON.number($0) }
      let name = PaletteJSON.nullableString(PaletteText.singleLine(colour.name))
      return "        {\n"
        + "            \"name\": \(name),\n"
        + "            \"components\": [\n" + values.joined(separator: ",\n") + "\n"
        + "            ]\n        }"
    }
    let colourList =
      colourTexts.isEmpty ? "[]" : "[\n" + colourTexts.joined(separator: ",\n") + "\n    ]"
    let name = PaletteJSON.nullableString(document.name)
    return Data("{\n    \"name\": \(name),\n    \"colors\": \(colourList)\n}".utf8)
  }
}

// MARK: - Infinite Painter

/// The Infinite Painter (.clrs) JSON format: a "colors" list of signed 32-bit ARGB integers, with
/// an optional "name". Colours are read with their alpha. Written colours are opaque, as the
/// Android coder writes them.
public enum InfinitePainterPaletteCoder: PaletteDocumentCoder {

  private struct Document: Codable {
    let colors: [Int32]
    let name: String?
  }

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: data)
    } catch {
      throw PaletteFormatError.invalidFormat
    }
    guard !document.colors.isEmpty else { throw PaletteFormatError.invalidFormat }
    let colours = document.colors.map { value in
      let argb = UInt32(bitPattern: value)
      return PaletteColour(
        red: UInt8((argb >> 16) & 0xFF), green: UInt8((argb >> 8) & 0xFF),
        blue: UInt8(argb & 0xFF), alpha: UInt8(argb >> 24))
    }
    return PaletteDocument(name: document.name, colours: colours)
  }

  /// The colours as opaque signed ARGB values, indented as kotlinx.serialization indents them, and
  /// the palette name, empty when there is none.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let values = document.allColours.map { colour -> String in
      let argb: UInt32 =
        0xFF00_0000 | UInt32(colour.red) << 16 | UInt32(colour.green) << 8 | UInt32(colour.blue)
      return "        " + String(Int32(bitPattern: argb))
    }
    let colourList =
      values.isEmpty ? "[]" : "[\n" + values.joined(separator: ",\n") + "\n    ]"
    let name = PaletteJSON.quoted(document.name ?? "")
    return Data("{\n    \"colors\": \(colourList),\n    \"name\": \(name)\n}".utf8)
  }
}

// MARK: - Procreate

/// The Procreate swatches (.swatches) format: a zip archive holding "Swatches.json". The JSON is a
/// list of palettes, each with a name and swatches. A swatch has a hue, saturation and brightness
/// from 0 to 1, an optional name and an alpha that defaults to 1. A single palette object is also
/// accepted.
public enum ProcreateSwatchesPaletteCoder: PaletteDocumentCoder {

  private static let entryName = "Swatches.json"

  private struct Palette: Codable {
    let name: String
    let swatches: [Swatch?]
  }

  private struct Swatch: Codable {
    let name: String?
    let hue: Double
    let saturation: Double
    let brightness: Double
    let alpha: Double?
  }

  /// The palette name is the name of the first palette that has swatches, as the Android coder
  /// takes it. The swatches of every palette are read in order.
  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let entries: [ZipReader.Entry]
    do {
      entries = try ZipReader.entries(in: data) { $0 == entryName }
    } catch {
      throw PaletteFormatError.invalidFormat
    }
    guard let json = entries.first?.data else { throw PaletteFormatError.invalidFormat }

    let palettes: [Palette]
    if let list = try? JSONDecoder().decode([Palette].self, from: json) {
      palettes = list
    } else if let single = try? JSONDecoder().decode(Palette.self, from: json) {
      palettes = [single]
    } else {
      throw PaletteFormatError.invalidFormat
    }

    let named = palettes.first { palette in palette.swatches.contains { $0 != nil } }
    let colours = palettes.flatMap { palette in
      palette.swatches.compactMap { swatch -> PaletteColour? in
        guard let swatch else { return nil }
        let rgb = PaletteMath.hsbToRGB(
          hue: swatch.hue, saturation: swatch.saturation, brightness: swatch.brightness)
        return PaletteMath.colour(
          name: swatch.name, red: rgb.0, green: rgb.1, blue: rgb.2, alpha: swatch.alpha ?? 1)
      }
    }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: named?.name, colours: colours)
  }

  /// One palette with every colour as an HSB swatch, named as the palette. The swatch keys follow
  /// the Android classes: a null name when a colour has none, and the optional fields written as
  /// null.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let swatches = document.allColours.map { colour -> String in
      let hsb = PaletteMath.rgbToHSB(
        PaletteMath.unit(colour.red), PaletteMath.unit(colour.green),
        PaletteMath.unit(colour.blue))
      let name = PaletteJSON.nullableString(PaletteText.singleLine(colour.name))
      return "{\"name\":\(name)"
        + ",\"hue\":\(PaletteJSON.number(hsb.hue))"
        + ",\"saturation\":\(PaletteJSON.number(hsb.saturation))"
        + ",\"brightness\":\(PaletteJSON.number(hsb.brightness))"
        + ",\"alpha\":\(PaletteJSON.number(PaletteMath.unit(colour.alpha)))"
        + ",\"colorSpace\":null,\"origin\":null,\"colorModel\":null,\"colorProfile\":null"
        + ",\"version\":null,\"components\":null}"
    }
    let name = PaletteJSON.quoted(document.name ?? "")
    let json = "[{\"name\":\(name),\"swatches\":[" + swatches.joined(separator: ",") + "]}]"
    let entry = ZipWriter.Entry(name: entryName, data: Data(json.utf8))
    return (try? ZipWriter.archive([entry])) ?? Data()
  }
}
