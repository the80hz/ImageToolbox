import Foundation

/// A palette with the structure that some formats keep: the palette name, the colours outside any
/// group and the groups with their colours.
///
/// Formats without that structure read into `colours` alone and write only `colours`. Groups are
/// read and written by the Adobe Swatch Exchange coder. The flat `decode` and `encode` functions of
/// the coders use `allColours`, which lists the same colours as the Android `Palette.allColors()`.
public struct PaletteDocument: Equatable, Sendable {
  /// The palette name, or nil when the format has none or the file leaves it empty.
  public let name: String?
  /// The colours outside any group, in file order.
  public let colours: [PaletteColour]
  /// The groups, in file order.
  public let groups: [PaletteColourGroup]

  public init(
    name: String? = nil, colours: [PaletteColour] = [], groups: [PaletteColourGroup] = []
  ) {
    self.name = name?.isEmpty == false ? name : nil
    self.colours = colours
    self.groups = groups
  }

  /// The colours outside any group, then the colours of each group in order.
  public var allColours: [PaletteColour] {
    colours + groups.flatMap(\.colours)
  }
}

/// A named group of colours. The name is empty when the file gives none.
public struct PaletteColourGroup: Equatable, Sendable {
  public let name: String
  public let colours: [PaletteColour]

  public init(name: String, colours: [PaletteColour]) {
    self.name = name
    self.colours = colours
  }
}

/// A palette coder that reads and writes a `PaletteDocument`. The flat functions are derived from
/// the document functions, so a coder implements only the document functions.
public protocol PaletteDocumentCoder {
  static func decodeDocument(_ data: Data) throws -> PaletteDocument
  static func encodeDocument(_ document: PaletteDocument) -> Data
}

extension PaletteDocumentCoder {
  /// The colours of the file, as `PaletteDocument.allColours`.
  public static func decode(_ data: Data) throws -> [PaletteColour] {
    try decodeDocument(data).allColours
  }

  /// The file for a flat list of colours, with no palette name and no groups.
  public static func encode(_ colours: [PaletteColour]) -> Data {
    encodeDocument(PaletteDocument(colours: colours))
  }
}
