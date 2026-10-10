import Foundation

// Palette formats ported from the Android palette module. The helpers they use are in
// PaletteCodingSupport.swift.

// MARK: - Basic XML

/// The basic XML palette: a "palette" element with "color" children. The "palette" element may have
/// a "name" attribute, which is the palette name. A colour has a "name", and either a "hex"
/// attribute (RGBA hex digits) or "r", "g", "b" and an optional "a" from 0 to 255. A "hex"
/// attribute that is not valid skips the colour, as in the Android coder.
public enum BasicXMLPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let parser = BasicColourParser()
    guard PaletteXML.parse(data, delegate: parser), !parser.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return PaletteDocument(name: parser.name, colours: parser.colours)
  }

  /// The palette name on the "palette" element when there is one, then each colour with its name,
  /// its RGBA hex digits and its channels as decimal numbers.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var xml = "<?xml version=\"1.0\"?>\n<palette"
    if let name = document.name {
      xml += " name=\"\(PaletteXML.escaped(name))\""
    }
    xml += ">\n"
    for colour in document.allColours {
      xml += "<color"
      if let name = colour.name {
        xml += " name=\"\(PaletteXML.escaped(name))\""
      }
      let hex = PaletteText.hex([colour.red, colour.green, colour.blue, colour.alpha])
      xml += " hex=\"\(hex)\""
      xml += " r=\"\(colour.red)\" g=\"\(colour.green)\" b=\"\(colour.blue)\""
      xml += " a=\"\(colour.alpha)\" />\n"
    }
    xml += "</palette>\n"
    return Data(xml.utf8)
  }
}

private final class BasicColourParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []
  private(set) var name: String?

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    if PaletteXML.localName(elementName) == "palette" {
      name = attributeDict["name"]
      return
    }
    guard PaletteXML.localName(elementName) == "color" else { return }
    let name = attributeDict["name"]

    if let hex = attributeDict["hex"] {
      guard let channels = PaletteMath.hexChannels(hex), channels.count >= 3 else { return }
      colours.append(
        PaletteColour(
          name: name, red: channels[0], green: channels[1], blue: channels[2],
          alpha: channels.count == 4 ? channels[3] : 255))
    } else if let red = Int(attributeDict["r"] ?? ""), let green = Int(attributeDict["g"] ?? ""),
      let blue = Int(attributeDict["b"] ?? "")
    {
      let alpha = Int(attributeDict["a"] ?? "") ?? 255
      colours.append(
        PaletteMath.colour(
          name: name, red: Double(red) / 255, green: Double(green) / 255,
          blue: Double(blue) / 255, alpha: Double(alpha) / 255))
    }
  }
}

// MARK: - Autodesk Color Book

/// The Autodesk Color Book (.acb) XML format: a "colorBook" with "colorPage" elements, each holding
/// "colorEntry" elements with a "colorName" and red, green and blue values from 0 to 255.
/// Colours outside a page are ignored, and the page names are not kept, except that the name of
/// the first page with colours is the palette name when the book has no "bookName". The palette
/// name is the "bookName", and it is written as "Untitled" when the palette has none.
public enum AutodeskColorBookPaletteCoder: PaletteDocumentCoder {

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    let parser = AutodeskColourParser()
    guard PaletteXML.parse(data, delegate: parser), !parser.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return PaletteDocument(name: parser.name, colours: parser.colours)
  }

  /// One page with every colour, each with its name and its RGB values.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<colorBook>\n"
    xml += "   <bookName>\(PaletteXML.escaped(document.name ?? "Untitled"))</bookName>\n"
    xml += "   <majorVersion>1</majorVersion>\n"
    xml += "   <minorVersion>0</minorVersion>\n"
    let colours = document.allColours
    if !colours.isEmpty {
      xml += "   <colorPage>\n"
    }
    for colour in colours {
      let name = PaletteXML.escaped(PaletteText.singleLine(colour.name) ?? "Color")
      xml += "      <colorEntry>\n"
      xml += "         <colorName>\(name)</colorName>\n"
      xml += "         <RGB8>\n"
      xml += "            <red>\(colour.red)</red>\n"
      xml += "            <green>\(colour.green)</green>\n"
      xml += "            <blue>\(colour.blue)</blue>\n"
      xml += "         </RGB8>\n"
      xml += "      </colorEntry>\n"
    }
    if !colours.isEmpty {
      xml += "   </colorPage>\n"
    }
    xml += "</colorBook>\n"
    return Data(xml.utf8)
  }
}

private final class AutodeskColourParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []
  /// The palette name: the "bookName", or the name of the first page with colours.
  private(set) var name: String?
  private var isInPage = false
  private var pageName: String?
  private var pageStartCount = 0
  private var entryName: String?
  private var red: Int?
  private var green: Int?
  private var blue: Int?
  private var text = ""

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    text = ""
    switch PaletteXML.localName(elementName) {
    case "colorpage":
      isInPage = true
      pageName = attributeDict["name"]
      pageStartCount = colours.count
    case "colorentry", "pagecolor":
      clearEntry()
    default:
      break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let content = PaletteText.trimmed(text)
    switch PaletteXML.localName(elementName) {
    case "bookname":
      if !content.isEmpty { name = content }
    case "colorname":
      if !content.isEmpty { entryName = content }
    case "red":
      red = channelValue(content)
    case "green":
      green = channelValue(content)
    case "blue":
      blue = channelValue(content)
    case "colorentry", "pagecolor":
      if isInPage, let red, let green, let blue {
        colours.append(
          PaletteColour(
            name: entryName, red: UInt8(red), green: UInt8(green), blue: UInt8(blue)))
      }
      clearEntry()
    case "colorpage":
      // The first page with colours names the palette when the book has no name.
      if pageStartCount == 0, colours.count > 0, name == nil, let pageName, !pageName.isEmpty {
        name = pageName
      }
      isInPage = false
    default:
      break
    }
    text = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  private func clearEntry() {
    entryName = nil
    red = nil
    green = nil
    blue = nil
  }

  /// A channel value clamped to 0 through 255, or nil when the text is not a whole number.
  private func channelValue(_ text: String) -> Int? {
    guard let value = Int(text) else { return nil }
    return min(max(value, 0), 255)
  }
}

// MARK: - SVG

/// The SVG palette: one "rect" element per colour, with a "fill" of "#rrggbb" or "rgb(r, g, b)" or
/// "rgba(r, g, b, a)", an optional "fill-opacity" and an optional "id" as the name. Rectangles
/// without a usable fill are skipped.
///
/// Written files lay the swatches out in rows of 40 by 40 pixels within a 600 pixel width.
public enum SVGPaletteCoder {

  private static let swatchSize = 40.0
  private static let gap = 1.0
  private static let inset = 4.0
  private static let maximumWidth = 600.0

  public static func decode(_ data: Data) throws -> [PaletteColour] {
    let parser = SVGRectParser()
    guard PaletteXML.parse(data, delegate: parser), !parser.colours.isEmpty else {
      throw PaletteFormatError.invalidFormat
    }
    return parser.colours
  }

  public static func encode(_ colours: [PaletteColour]) -> Data {
    var x = inset
    var y = inset
    var rects = ""
    for colour in colours {
      let hex = "#" + PaletteText.hex([colour.red, colour.green, colour.blue], uppercase: true)
      rects += "      <rect x=\"\(number(x))\" y=\"\(number(y))\" "
      rects += "width=\"\(number(swatchSize))\" height=\"\(number(swatchSize))\" "
      if let name = PaletteText.singleLine(colour.name) {
        rects += "id=\"\(PaletteXML.escaped(name))\" "
      }
      rects += "fill=\"\(hex)\" fill-opacity=\"\(number(PaletteMath.unit(colour.alpha)))\""
      rects += " />\n"

      x += swatchSize + gap
      if x + swatchSize + inset > maximumWidth {
        y += swatchSize + gap
        x = inset
      }
    }

    let height = y + inset + swatchSize
    var svg = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
    svg += "\t<svg xmlns=\"http://www.w3.org/2000/svg\" "
    svg += "xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" "
    svg += "viewBox=\"0 0 \(number(maximumWidth)) \(number(height))\" xml:space=\"preserve\">\n"
    svg += rects
    svg += "</svg>\n"
    return Data(svg.utf8)
  }

  /// A number with at most three decimal places, written as `DecimalFormat("#.###")` writes it.
  /// A value below one has no leading zero, so 0.5 is written as ".5".
  private static func number(_ value: Double) -> String {
    PaletteText.decimal(value, maximumFractionDigits: 3, keepLeadingZero: false)
  }
}

private final class SVGRectParser: NSObject, XMLParserDelegate {
  private(set) var colours: [PaletteColour] = []

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    guard elementName.lowercased() == "rect", let fill = attributeDict["fill"], !fill.isEmpty
    else { return }
    let opacity = attributeDict["fill-opacity"].flatMap { Double($0) } ?? 1
    let name = attributeDict["id"]

    if fill.hasPrefix("#") {
      guard let channels = PaletteMath.hexChannels(fill), channels.count >= 3 else { return }
      colours.append(
        PaletteMath.colour(
          name: name, red: PaletteMath.unit(channels[0]), green: PaletteMath.unit(channels[1]),
          blue: PaletteMath.unit(channels[2]), alpha: opacity))
    } else if fill.hasPrefix("rgb"),
      let match = fill.firstMatch(
        of: /rgba?\(([0-9]+),\s*([0-9]+),\s*([0-9]+)(?:,\s*([0-9.]+))?\)/)
    {
      let red = Double(Int(match.output.1) ?? 0) / 255
      let green = Double(Int(match.output.2) ?? 0) / 255
      let blue = Double(Int(match.output.3) ?? 0) / 255
      let alpha = match.output.4.flatMap { Double($0) } ?? opacity
      colours.append(
        PaletteMath.colour(name: name, red: red, green: green, blue: blue, alpha: alpha))
    }
  }
}
