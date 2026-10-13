/// One colour of a palette file: 8-bit sRGB with an optional name and colour type.
///
/// Colours in other colour spaces are converted to sRGB when they are decoded. The palette name
/// and the groups are kept by `PaletteDocument`, in the formats that store them.
public struct PaletteColour: Equatable, Sendable {
  /// The colour name, or nil when the file has none. An empty name is stored as nil.
  public let name: String?
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8
  /// 255 is opaque. Formats without transparency always decode to 255.
  public let alpha: UInt8
  /// The colour type. Only the Adobe Swatch Exchange format stores it; other formats read `global`.
  public let colourType: PaletteColourType

  public init(
    name: String? = nil, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255,
    colourType: PaletteColourType = .global
  ) {
    self.name = name?.isEmpty == false ? name : nil
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
    self.colourType = colourType
  }

  /// The same colour with another colour type.
  func withColourType(_ type: PaletteColourType) -> PaletteColour {
    PaletteColour(name: name, red: red, green: green, blue: blue, alpha: alpha, colourType: type)
  }
}

/// The type of a colour, as the Adobe Swatch Exchange format stores it.
public enum PaletteColourType: Equatable, Sendable {
  /// A colour that belongs to the palette itself. The default.
  case global
  /// A spot colour, printed with its own ink.
  case spot
  /// A process colour, printed with the process inks.
  case normal
}
