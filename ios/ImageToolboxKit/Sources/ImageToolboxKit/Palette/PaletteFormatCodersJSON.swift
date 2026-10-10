import Foundation

// MARK: - JSON

/// The JSON palette format written by the Android app, which serialises its classes with
/// kotlinx.serialization.
///
/// The document has an optional "name", a "colors" list and an optional "groups" list, and each
/// group has an optional "name" and its own "colors". Group colours are read after the global
/// colours, in the same order as the Android coder. Each colour has a "colorSpace" of "RGB",
/// "CMYK", "Gray" or "LAB", and an optional "colorType" of "Global", "Spot" or "Normal". RGB, CMYK
/// and Gray components are in the range 0 to 1. LAB components are L from 0 to 100, then a and b,
/// converted to sRGB. Colours with an "alpha" value are read with that opacity.
public enum JSONPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: withoutBOM(data))
    } catch {
      throw PaletteFormatError.invalidFormat
    }
    let colours = try (document.colors ?? []).map { try makeColour($0) }
    let groups = try (document.groups ?? []).map { group in
      PaletteColourGroup(
        name: group.name ?? "", colours: try (group.colors ?? []).map { try makeColour($0) })
    }
    return PaletteDocument(name: document.name, colours: colours, groups: groups)
  }

  /// The palette laid out as the Android classes serialise it. The keys follow the order of the
  /// Kotlin properties, and a value equal to its default is left out: an empty name or group name,
  /// an empty list, the global colour type and an alpha of 1. Doubles keep a decimal point, as
  /// Kotlin prints them. Every object ends with an "id", which the Android classes fill with a new
  /// random UUID, and this writer does the same.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var fields: [String] = []
    if let name = document.name {
      fields.append("\"name\":" + PaletteJSON.quoted(name))
    }
    if !document.colours.isEmpty {
      fields.append("\"colors\":[" + document.colours.map(colourJSON).joined(separator: ",") + "]")
    }
    if !document.groups.isEmpty {
      fields.append("\"groups\":[" + document.groups.map(groupJSON).joined(separator: ",") + "]")
    }
    fields.append(idField)
    return Data(("{" + fields.joined(separator: ",") + "}").utf8)
  }

  private static func groupJSON(_ group: PaletteColourGroup) -> String {
    var fields = [idField]
    if !group.name.isEmpty {
      fields.append("\"name\":" + PaletteJSON.quoted(group.name))
    }
    if !group.colours.isEmpty {
      fields.append("\"colors\":[" + group.colours.map(colourJSON).joined(separator: ",") + "]")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func colourJSON(_ colour: PaletteColour) -> String {
    var fields: [String] = []
    if let name = colour.name {
      fields.append("\"name\":" + PaletteJSON.quoted(name))
    }
    if let typeName = colourTypeName(colour.colourType) {
      fields.append("\"colorType\":\"" + typeName + "\"")
    }
    fields.append("\"colorSpace\":\"RGB\"")
    let components = [colour.red, colour.green, colour.blue].map {
      PaletteJSON.number(PaletteMath.unit($0))
    }
    fields.append("\"colorComponents\":[" + components.joined(separator: ",") + "]")
    if colour.alpha != 255 {
      fields.append("\"alpha\":" + PaletteJSON.number(PaletteMath.unit(colour.alpha)))
    }
    fields.append(idField)
    return "{" + fields.joined(separator: ",") + "}"
  }

  /// The name of a colour type in the file, or nil for the global type, which is left out.
  private static func colourTypeName(_ type: PaletteColourType) -> String? {
    switch type {
    case .global: nil
    case .spot: "Spot"
    case .normal: "Normal"
    }
  }

  /// The "id" member with a new lowercase UUID, as Java prints it.
  private static var idField: String {
    "\"id\":\"" + UUID().uuidString.lowercased() + "\""
  }

  private static func makeColour(_ json: Colour) throws -> PaletteColour {
    let colourType = try makeColourType(json.colorType)
    let components = json.colorComponents.map { PaletteMath.clampUnit($0) }
    let alpha = json.alpha ?? 1
    switch json.colorSpace {
    case .rgb:
      guard components.count == 3 else { throw PaletteFormatError.invalidFormat }
      return PaletteMath.colour(
        name: json.name, red: components[0], green: components[1], blue: components[2],
        alpha: alpha
      ).withColourType(colourType)
    case .cmyk:
      guard components.count == 4 else { throw PaletteFormatError.invalidFormat }
      return PaletteMath.cmyk(
        name: json.name, cyan: components[0], magenta: components[1], yellow: components[2],
        black: components[3], alpha: alpha
      ).withColourType(colourType)
    case .gray:
      guard components.count == 1 else { throw PaletteFormatError.invalidFormat }
      return PaletteMath.grey(name: json.name, white: components[0], alpha: alpha)
        .withColourType(colourType)
    case .lab:
      // The components are not clamped to 0 to 1, unlike the values above.
      guard json.colorComponents.count == 3 else { throw PaletteFormatError.invalidFormat }
      let lab = PaletteLab.toSRGB(
        l: json.colorComponents[0], a: json.colorComponents[1], b: json.colorComponents[2])
      return PaletteColour(
        name: json.name, red: lab.red, green: lab.green, blue: lab.blue,
        alpha: PaletteMath.channel(alpha), colourType: colourType)
    }
  }

  /// The colour type named in the file. A missing type is the global type, and an unknown name is
  /// invalid, as the Android serialiser rejects it.
  private static func makeColourType(_ name: String?) throws -> PaletteColourType {
    switch name {
    case nil, "Global": .global
    case "Spot": .spot
    case "Normal": .normal
    default: throw PaletteFormatError.invalidFormat
    }
  }

  private static func withoutBOM(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    return bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(bytes.dropFirst(3)) : data
  }

  private struct Document: Codable {
    var name: String?
    var colors: [Colour]?
    var groups: [Group]?
  }

  private struct Group: Codable {
    var name: String?
    var colors: [Colour]?
  }

  private struct Colour: Codable {
    var name: String?
    var colorType: String?
    var colorSpace: ColourSpace
    var colorComponents: [Double]
    var alpha: Double?
  }

  private enum ColourSpace: String, Codable {
    case rgb = "RGB"
    case cmyk = "CMYK"
    case lab = "LAB"
    case gray = "Gray"
  }
}
