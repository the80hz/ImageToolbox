import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Krita

/// The Krita palette (.kpl) format: a zip archive with a "mimetype" entry, "colorset.xml" and
/// "profiles.xml". The colour set holds "ColorSetEntry" elements with an "sRGB", "CMYK", "Lab" or
/// "gray" value and a "Position" of row and column. Entries inside a "Group" are kept after the
/// global entries. Entries are sorted by position. The "name" of the colour set is the palette name.
public enum KRITAPaletteCoder: PaletteDocumentCoder {

  private static let mimeType = "application/x-krita-palette"

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let entry = try? ZipReader.entries(
      in: data,
      include: {
        let name = $0.lowercased()
        return name == "colorset.xml" || name.hasSuffix("/colorset.xml")
      }
    ).first
    guard let xml = entry?.data else { throw PaletteFormatError.invalidFormat }

    let parser = ColorsetParser()
    guard PaletteXML.parse(xml, delegate: parser) else { throw PaletteFormatError.invalidFormat }
    let colours =
      parser.globalEntries.sortedByPosition()
      + parser.groups.flatMap { $0.sortedByPosition() }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: parser.name, colours: colours)
  }

  /// A zip with the stored "mimetype" entry first, then the colour set and the profiles. The colour
  /// set has one row-major grid of entries, with as many columns as the square root of the count
  /// rounds up to.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    let entries = [
      ZipWriter.Entry(name: "mimetype", data: Data(mimeType.utf8)),
      ZipWriter.Entry(name: "colorset.xml", data: Data(colorsetXML(document).utf8)),
      ZipWriter.Entry(
        name: "profiles.xml",
        data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Profiles/>\n".utf8)),
    ]
    // The Android coder stores the mimetype entry without compression. The archive writer has no
    // per-entry method, so every entry is stored; the text entries are larger but read the same.
    return (try? ZipWriter.archive(entries, options: ZipWriter.Options(method: .stored))) ?? Data()
  }

  private static func colorsetXML(_ document: PaletteDocument) -> String {
    let colours = document.allColours
    let columns = max(1, Int(ceil(sqrt(Double(max(colours.count, 1))))))
    let rows = colours.isEmpty ? 0 : Int(ceil(Double(colours.count) / Double(columns)))

    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    let name = PaletteXML.escaped(document.name ?? "")
    xml += "<Colorset name=\"\(name)\" comment=\"\" columns=\"\(columns)\" rows=\"\(rows)\""
    xml += " readonly=\"false\" version=\"1.0\">\n"
    for (index, colour) in colours.enumerated() {
      let name = PaletteXML.escaped(PaletteText.singleLine(colour.name) ?? "")
      let identifier = "global_\(index + 1)"
      xml += "  <ColorSetEntry name=\"\(name)\" id=\"\(identifier)\" bitdepth=\"F32\""
      xml += " spot=\"false\">\n"
      xml += "    <sRGB r=\"\(formatUnit(colour.red))\" g=\"\(formatUnit(colour.green))\""
      xml += " b=\"\(formatUnit(colour.blue))\"/>\n"
      xml += "    <Position row=\"\(index / columns)\" column=\"\(index % columns)\"/>\n"
      xml += "  </ColorSetEntry>\n"
    }
    xml += "</Colorset>\n"
    return xml
  }

  /// A channel from 0 to 1 with up to six decimal places, as the Android `DecimalFormat` writes it.
  private static func formatUnit(_ channel: UInt8) -> String {
    PaletteText.decimal(PaletteMath.unit(channel), maximumFractionDigits: 6)
  }
}

/// A colour with its position in the colour set.
private struct PositionedColour {
  let row: Int
  let column: Int
  let index: Int
  let colour: PaletteColour
}

extension Array where Element == PositionedColour {
  /// The colours in row and then column order. Entries at the same position keep their order.
  fileprivate func sortedByPosition() -> [PaletteColour] {
    sorted {
      ($0.row, $0.column, $0.index) < ($1.row, $1.column, $1.index)
    }.map(\.colour)
  }
}

private final class ColorsetParser: NSObject, XMLParserDelegate {
  /// The name of the colour set, from its "name" attribute.
  private(set) var name: String?
  private(set) var globalEntries: [PositionedColour] = []
  private(set) var groups: [[PositionedColour]] = []
  private var currentGroup: [PositionedColour]?
  private var entryName = ""
  private var entryColour: PaletteColour?
  private var entryRow = Int.max
  private var entryColumn = Int.max

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    switch PaletteXML.localName(elementName) {
    case "colorset":
      if let value = attributeDict["name"], !value.isEmpty { name = value }
    case "group":
      currentGroup = []
    case "colorsetentry":
      entryName = attributeDict["name"] ?? ""
      entryColour = nil
      entryRow = Int.max
      entryColumn = Int.max
    case "position":
      entryRow = attributeDict["row"].flatMap { Int($0) } ?? Int.max
      entryColumn = attributeDict["column"].flatMap { Int($0) } ?? Int.max
    case "srgb", "rgb":
      entryColour = rgbColour(attributeDict)
    case "cmyk":
      entryColour = cmykColour(attributeDict)
    case "lab":
      entryColour = labColour(attributeDict)
    case "gray":
      entryColour = greyColour(attributeDict)
    default:
      break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch PaletteXML.localName(elementName) {
    case "colorsetentry":
      if let colour = entryColour {
        let positioned = PositionedColour(
          row: entryRow, column: entryColumn,
          index: currentGroup?.count ?? globalEntries.count, colour: colour)
        if currentGroup != nil {
          currentGroup?.append(positioned)
        } else {
          globalEntries.append(positioned)
        }
      }
      entryColour = nil
      entryName = ""
      entryRow = Int.max
      entryColumn = Int.max
    case "group":
      if let group = currentGroup, !group.isEmpty {
        groups.append(group)
      }
      currentGroup = nil
    default:
      break
    }
  }

  private func rgbColour(_ attributes: [String: String]) -> PaletteColour? {
    guard let red = channel(attributes["r"]), let green = channel(attributes["g"]),
      let blue = channel(attributes["b"])
    else { return nil }
    return PaletteMath.colour(
      name: entryName, red: red, green: green, blue: blue)
  }

  private func cmykColour(_ attributes: [String: String]) -> PaletteColour? {
    guard let cyan = channel(attributes["c"]), let magenta = channel(attributes["m"]),
      let yellow = channel(attributes["y"]), let black = channel(attributes["k"])
    else { return nil }
    return PaletteMath.cmyk(
      name: entryName, cyan: cyan, magenta: magenta, yellow: yellow, black: black)
  }

  private func labColour(_ attributes: [String: String]) -> PaletteColour? {
    guard let lightness = Double(attributes["L"] ?? attributes["l"] ?? ""),
      let aStar = Double(attributes["a"] ?? ""), let bStar = Double(attributes["b"] ?? "")
    else { return nil }
    let rgb = PaletteLab.toSRGB(l: lightness, a: aStar, b: bStar)
    return PaletteColour(name: entryName, red: rgb.red, green: rgb.green, blue: rgb.blue)
  }

  private func greyColour(_ attributes: [String: String]) -> PaletteColour? {
    guard let white = channel(attributes["g"] ?? attributes["gray"]) else { return nil }
    return PaletteMath.grey(name: entryName, white: white)
  }

  /// A unit value clamped to 0 through 1, or nil when the text is not a number.
  private func channel(_ text: String?) -> Double? {
    guard let text, let value = Double(text) else { return nil }
    return PaletteMath.clampUnit(value)
  }
}
