import Foundation

// MARK: - Android colour resources (colors.xml)

/// The Android colour resource format: `<color name="...">#aarrggbb</color>` elements inside
/// `<resources>`. Names with spaces are written with underscores, as the Android coder does.
///
/// The Android coder reads colours as ARGB. Its hex parser shifts colours with 3 or 6 digits, which
/// this reader does not copy; see `PaletteHex.Layout.argb`.
public enum AndroidColorsXMLPaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let reader = AndroidColourResourceParser()
    guard PaletteXML.parse(data, delegate: reader), !reader.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return reader.colours
  }

  /// Each colour with its alpha, in uppercase. A colour without a name is called "color_" and its
  /// position.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
    for (index, colour) in colours.enumerated() {
      let name = (PaletteText.singleLine(colour.name) ?? "color_\(index)").replacingOccurrences(
        of: " ", with: "_")
      let hex = PaletteText.hex(
        [colour.alpha, colour.red, colour.green, colour.blue], uppercase: true)
      xml += "   <color name=\"\(PaletteXML.escaped(name))\">#\(hex)</color>\n"
    }
    xml += "</resources>\n"
    return Data(xml.utf8)
  }
}

private final class AndroidColourResourceParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []
  private var isInsideResources = false
  private var isInsideColour = false
  private var colourName: String?
  private var text = ""

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    text = ""
    switch PaletteXML.localName(elementName) {
    case "resources":
      isInsideResources = true
    case "color":
      isInsideColour = true
      colourName = attributeDict["name"]
    default:
      break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch PaletteXML.localName(elementName) {
    case "resources":
      isInsideResources = false
    case "color":
      if isInsideResources && isInsideColour {
        let name = colourName ?? "color_\(colours.count)"
        if let colour = PaletteHex.colour(PaletteText.trimmed(text), name: name, layout: .argb) {
          colours.append(colour)
        }
      }
      isInsideColour = false
      colourName = nil
    default:
      break
    }
    text = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }
}

// MARK: - Scribus

/// The Scribus swatch format: `<COLOR RGB="#rrggbb" NAME="..."/>` elements, or `CMYK` with eight
/// hex digits for cyan, magenta, yellow and black. Colours are read in file order. The palette name
/// is the `Name` attribute of the `SCRIBUSCOLORS` element, as the Android coder reads it.
public enum ScribusXMLPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let reader = ScribusColourParser()
    guard PaletteXML.parse(data, delegate: reader), !reader.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return PaletteDocument(name: reader.name, colours: reader.colours)
  }

  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var xml = "<?xml version=\"1.0\"?>\n<SCRIBUSCOLORS"
    if let name = document.name {
      xml += " Name=\"\(PaletteXML.escaped(name))\""
    }
    xml += " >\n"
    for colour in document.allColours {
      let hex = PaletteText.hex([colour.red, colour.green, colour.blue])
      xml += "<COLOR RGB=\"#\(hex)\""
      if let name = PaletteText.singleLine(colour.name) {
        xml += " NAME=\"\(PaletteXML.escaped(name))\""
      }
      xml += " />\n"
    }
    xml += "</SCRIBUSCOLORS>\n"
    return Data(xml.utf8)
  }
}

private final class ScribusColourParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []
  private(set) var name: String?

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    let element = elementName.lowercased()
    if element == "scribuscolors" || element == "scolors" {
      name = attributeDict["Name"] ?? attributeDict["name"] ?? ""
      return
    }
    guard element == "color" else { return }
    let name = attributeDict["NAME"] ?? attributeDict["name"]
    if let rgb = attributeDict["RGB"] ?? attributeDict["rgb"] {
      if let colour = PaletteHex.colour(rgb, name: name, layout: .rgb) {
        colours.append(colour)
      }
    } else if let cmyk = attributeDict["CMYK"] ?? attributeDict["cmyk"],
      let colour = PaletteHex.cmykColour(cmyk, name: name)
    {
      colours.append(colour)
    }
  }
}

// MARK: - OpenOffice (SOC)

/// The OpenOffice colour table (.soc): `<draw:color draw:name="..." draw:color="#rrggbb"/>`
/// elements inside `<office:color-table>`.
public enum OpenOfficePaletteCoder {

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let reader = OpenOfficeColourParser()
    guard PaletteXML.parse(data, delegate: reader), !reader.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return reader.colours
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + tableHeader + "\n"
    for colour in colours {
      let hex = PaletteText.hex([colour.red, colour.green, colour.blue], uppercase: true)
      let name = PaletteXML.escaped(colour.name ?? "")
      xml += "<draw:color draw:name=\"\(name)\" draw:color=\"#\(hex)\"/>\n"
    }
    xml += "</office:color-table>\n"
    return Data(xml.utf8)
  }

  /// The root element with the namespace declarations that the Android coder writes.
  private static let tableHeader = """
    <office:color-table xmlns:office="http://openoffice.org/2000/office" \
    xmlns:style="http://openoffice.org/2000/style" xmlns:text="http://openoffice.org/2000/text" \
    xmlns:table="http://openoffice.org/2000/table" xmlns:draw="http://openoffice.org/2000/drawing" \
    xmlns:fo="http://www.w3.org/1999/XSL/Format" xmlns:xlink="http://www.w3.org/1999/xlink" \
    xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="http://openoffice.org/2000/meta" \
    xmlns:number="http://openoffice.org/2000/datastyle" xmlns:svg="http://www.w3.org/2000/svg" \
    xmlns:chart="http://openoffice.org/2000/chart" xmlns:dr3d="http://openoffice.org/2000/dr3d" \
    xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="http://openoffice.org/2000/form" \
    xmlns:script="http://openoffice.org/2000/script">
    """
}

private final class OpenOfficeColourParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    guard elementName == "draw:color" else { return }
    let name = attributeDict["draw:name"]
    if let colour = PaletteHex.colour(
      attributeDict["draw:color"] ?? "", name: name, layout: .rgb)
    {
      colours.append(colour)
    }
  }
}
