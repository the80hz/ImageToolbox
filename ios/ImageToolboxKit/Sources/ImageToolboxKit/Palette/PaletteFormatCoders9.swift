import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - CorelDraw XML

/// The CorelDraw XML palette: a "palette" with a "colors" section of "page" elements. Each "color"
/// has a colour space in "cs" ("CMYK", "RGB", "LAB", "GRAY") and comma-separated "tints". Colours
/// may also name a colour space defined in a "colorspaces" section, in which case the first colour
/// of that space is used. Colours outside a page are ignored. The "name" attribute of the palette
/// element is the palette name.
///
/// The page order follows the Android coder: the first unnamed page with no earlier colours
/// becomes the global colours, and named pages are kept after them. The page names are not kept.
public enum CorelXMLPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let parser = CorelColourParser()
    guard PaletteXML.parse(data, delegate: parser) else { throw PaletteFormatError.invalidFormat }
    let colours = parser.globalColours + parser.groupColours.flatMap { $0 }
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: parser.name, colours: colours)
  }

  /// One unnamed page with an RGB colour for each colour. Components are written with six decimal
  /// places, and the document gets a new GUID each time.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var xml = "<?xml version=\"1.0\"?>\n"
    xml += "<palette guid=\"\(UUID().uuidString.lowercased())\""
    if let name = document.name {
      xml += " name=\"\(PaletteXML.escaped(name))\""
    }
    xml += ">\n"
    xml += "<colors>\n"
    let colours = document.allColours
    if !colours.isEmpty {
      xml += "<page>"
      for colour in colours {
        xml += "<color"
        if let name = PaletteText.singleLine(colour.name) {
          xml += " name=\"\(PaletteXML.escaped(name))\""
        }
        let tints = [colour.red, colour.green, colour.blue].map {
          String(format: "%.6f", PaletteMath.unit($0))
        }
        xml += " cs=\"RGB\" tints=\"\(tints.joined(separator: ","))\"/>\n"
      }
      xml += "</page>\n"
    }
    xml += "</colors>\n"
    xml += "</palette>\n"
    return Data(xml.utf8)
  }
}

/// A colour from L, a and b, where L runs from 0 to 100 and a and b from -128 to 127.
private func labColour(name: String, l: Double, a: Double, b: Double) -> PaletteColour {
  let rgb = PaletteLab.toSRGB(l: l, a: a, b: b)
  return PaletteColour(name: name, red: rgb.red, green: rgb.green, blue: rgb.blue)
}

private final class CorelColourParser: NSObject, XMLParserDelegate {
  /// The palette name, from the "name" attribute of the palette element.
  private(set) var name: String?
  /// The colours of the global page, which is the first unnamed page.
  private(set) var globalColours: [PaletteColour] = []
  /// The colours of each named page, in file order.
  private(set) var groupColours: [[PaletteColour]] = []
  private var colourSpaces: [(name: String, colours: [PaletteColour])] = []
  private var isInColourSpaces = false
  private var page: (name: String, colours: [PaletteColour])?

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    switch PaletteXML.localName(elementName) {
    case "palette":
      if let value = attributeDict["name"], !value.isEmpty { name = value }
    case "colorspaces":
      isInColourSpaces = true
    case "cs":
      colourSpaces.append(((attributeDict["name"] ?? "").lowercased(), []))
    case "page":
      page = (attributeDict["name"] ?? "", [])
    case "color":
      addColour(attributes: attributeDict)
    default:
      break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch PaletteXML.localName(elementName) {
    case "page":
      finishPage()
    case "colorspaces":
      isInColourSpaces = false
    default:
      break
    }
  }

  private func addColour(attributes: [String: String]) {
    let space = attributes["cs"]?.lowercased() ?? ""
    let name = attributes["name"] ?? ""
    let components = (attributes["tints"] ?? "").split(separator: ",").compactMap {
      Double(PaletteText.trimmed($0))
    }

    let colour: PaletteColour?
    switch space {
    case "cmyk":
      colour =
        components.count < 4
        ? nil
        : PaletteMath.cmyk(
          name: name, cyan: components[0], magenta: components[1], yellow: components[2],
          black: components[3])
    case "rgb":
      colour =
        components.count < 3
        ? nil
        : PaletteMath.colour(
          name: name, red: components[0], green: components[1], blue: components[2])
    case "lab":
      colour =
        components.count < 3
        ? nil
        : labColour(
          name: name, l: components[0] * 100, a: components[1] * 256 - 128,
          b: components[2] * 256 - 128)
    case "gray", "grey":
      colour = components.isEmpty ? nil : PaletteMath.grey(name: name, white: components[0])
    default:
      // A colour space defined earlier in the file: its first colour is the template.
      colour = colourSpaces.first(where: { $0.name == space })?.colours.first.map {
        PaletteColour(name: name, red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
      }
    }
    guard let colour else { return }

    if isInColourSpaces {
      if !colourSpaces.isEmpty {
        colourSpaces[colourSpaces.count - 1].colours.append(colour)
      }
    } else if page != nil {
      page?.colours.append(colour)
    }
  }

  private func finishPage() {
    guard let finished = page, !finished.colours.isEmpty else {
      page = nil
      return
    }
    if finished.name.isEmpty && globalColours.isEmpty && groupColours.isEmpty {
      globalColours += finished.colours
    } else if !finished.name.isEmpty {
      groupColours.append(finished.colours)
    } else {
      globalColours += finished.colours
    }
    page = nil
  }
}

// MARK: - Swatchbooker

/// The Swatchbooker (.sbz) format: a zip archive holding "swatchbook.xml". Colours are in
/// "materials", each with a title, an identifier and "values" in a model: RGB (with an optional
/// alpha), Lab, CMYK, GRAY, HSV or HSL. The "book" lists the swatches by material, and the colours
/// are read in that order, with any colour that the book does not list after them. The title of
/// the book, a "dc:title" outside the materials, is the palette name.
public enum SwatchbookerPaletteCoder: PaletteDocumentCoder {

  private static let entryName = "swatchbook.xml"

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    guard
      let entry = try? ZipReader.entries(in: data, include: { $0.lowercased() == entryName })
        .first
    else { throw PaletteFormatError.invalidFormat }

    let parser = SwatchBookParser()
    guard PaletteXML.parse(entry.data, delegate: parser) else {
      throw PaletteFormatError.invalidFormat
    }
    let colours = parser.orderedColours()
    guard !colours.isEmpty else { throw PaletteFormatError.invalidFormat }
    return PaletteDocument(name: parser.name, colours: colours)
  }

  /// One RGB material per colour, with the colours listed in the book in the same order. The book
  /// title is the palette name, empty when there is none.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    xml += "<SwatchBook xmlns=\"http://www.selapa.net/swatchbook/1.0/\""
    xml += " xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
    xml += "  <metadata>\n    <dc:title>\(PaletteXML.escaped(document.name ?? ""))</dc:title>\n"
    xml += "  </metadata>\n"
    xml += "  <materials>\n"
    let colours = document.allColours
    for (index, colour) in colours.enumerated() {
      let values = [colour.red, colour.green, colour.blue, colour.alpha].map {
        "\(PaletteMath.unit($0))"
      }
      xml += "    <color usage=\"standard\">\n"
      xml += "      <metadata>\n"
      xml += "        <dc:title>\(PaletteXML.escaped(colour.name ?? ""))</dc:title>\n"
      xml += "        <dc:identifier>color_\(index)</dc:identifier>\n"
      xml += "      </metadata>\n"
      xml += "      <values model=\"RGB\">\n"
      xml += "        \(values.joined(separator: " "))\n"
      xml += "      </values>\n"
      xml += "    </color>\n"
    }
    xml += "  </materials>\n"
    xml += "  <book>\n"
    for index in colours.indices {
      xml += "    <swatch material=\"color_\(index)\"/>\n"
    }
    xml += "  </book>\n"
    xml += "</SwatchBook>\n"

    let entry = ZipWriter.Entry(name: entryName, data: Data(xml.utf8))
    return (try? ZipWriter.archive([entry])) ?? Data()
  }
}

private final class SwatchBookParser: NSObject, XMLParserDelegate {
  private var colours: [PaletteColour] = []
  /// The title of the book, which is the last "dc:title" outside the materials.
  private(set) var name: String?
  /// The colour index of each identifier. A later colour with the same identifier replaces it.
  private var indexByIdentifier: [String: Int] = [:]
  /// The material identifiers in the order the book lists them.
  private var bookOrder: [String] = []
  private var stack: [String] = []
  private var title: String?
  private var identifier: String?
  private var model: String?
  private var components: [Double] = []
  private var text = ""

  /// The colours in book order, then any colour that the book does not list, in file order.
  func orderedColours() -> [PaletteColour] {
    var used = Set<Int>()
    var ordered: [PaletteColour] = []
    for reference in bookOrder {
      guard let index = indexByIdentifier[reference], !used.contains(index) else { continue }
      used.insert(index)
      ordered.append(colours[index])
    }
    for (index, colour) in colours.enumerated() where !used.contains(index) {
      ordered.append(colour)
    }
    return ordered
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    text = ""
    stack.append(elementName)
    let local = elementName.lowercased()
    if local == "color" && isInside("materials") {
      title = nil
      identifier = nil
      model = nil
      components = []
    } else if local == "values" {
      model = attributeDict["model"] ?? attributeDict["MODEL"] ?? attributeDict["Model"]
      components = []
    } else if local == "swatch" && isInside("book"), let material = attributeDict["material"] {
      bookOrder.append(PaletteText.trimmed(material))
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let content = PaletteText.trimmed(text)
    let local = elementName.lowercased()
    switch local {
    case "dc:title":
      if isInside("materials") {
        title = content
      } else {
        name = content
      }
    case "dc:identifier":
      identifier = content
    case "values":
      components = content.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
    case "color" where isInside("materials"):
      addColour()
    default:
      break
    }
    if !stack.isEmpty {
      stack.removeLast()
    }
    text = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  private func isInside(_ element: String) -> Bool {
    stack.contains { $0.lowercased() == element }
  }

  private func addColour() {
    let name = title ?? identifier ?? "Color \(colours.count + 1)"
    guard let colour = colour(model: model, values: components, name: name) else { return }
    indexByIdentifier[identifier ?? "color_\(colours.count)"] = colours.count
    colours.append(colour)
  }

  /// A colour from the values of its model, with the model name ignored in case.
  private func colour(model: String?, values: [Double], name: String) -> PaletteColour? {
    switch (model ?? "").uppercased() {
    case "RGB" where values.count >= 3:
      return PaletteMath.colour(
        name: name, red: values[0], green: values[1], blue: values[2],
        alpha: values.count >= 4 ? values[3] : 1)
    case "LAB" where values.count >= 3:
      return labColour(name: name, l: values[0], a: values[1], b: values[2])
    case "CMYK" where values.count >= 4:
      return PaletteMath.cmyk(
        name: name, cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
    case "GRAY" where !values.isEmpty:
      return PaletteMath.grey(name: name, white: values[0])
    case "HSV" where values.count >= 3:
      let rgb = PaletteMath.hsbToRGB(hue: values[0], saturation: values[1], brightness: values[2])
      return PaletteMath.colour(name: name, red: rgb.0, green: rgb.1, blue: rgb.2)
    case "HSL" where values.count >= 3:
      let rgb = PaletteMath.hslToRGB(hue: values[0], saturation: values[1], lightness: values[2])
      return PaletteMath.colour(name: name, red: rgb.0, green: rgb.1, blue: rgb.2)
    default:
      return nil
    }
  }
}
