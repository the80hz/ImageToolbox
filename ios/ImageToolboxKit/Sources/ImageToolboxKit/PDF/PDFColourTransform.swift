import CoreGraphics
import Foundation

/// How a colour is mixed with the page below it. These are the PDF blend modes that make sense for
/// a dark mode overlay.
public enum PDFBlendMode: String, CaseIterable, Sendable {
  case screen, multiply, overlay, darken, lighten, softLight, difference, exclusion
  case hue, saturation, color, luminosity

  var coreGraphics: CGBlendMode {
    switch self {
    case .screen: .screen
    case .multiply: .multiply
    case .overlay: .overlay
    case .darken: .darken
    case .lighten: .lighten
    case .softLight: .softLight
    case .difference: .difference
    case .exclusion: .exclusion
    case .hue: .hue
    case .saturation: .saturation
    case .color: .color
    case .luminosity: .luminosity
    }
  }
}

/// A colour of the dark mode.
public enum PDFDarkTheme: String, CaseIterable, Sendable {
  case warm, classic, graphite, midnight, blue, green, sepia, purple, burgundy, slate
  /// Inverts the colours and keeps the hues.
  case negative
  /// Uses the colour and blend mode that are set in the options.
  case custom

  /// The background colour of the theme. Nil for the themes that have none.
  var background: RGBA? {
    switch self {
    case .warm: RGBA(red: 0x2A, green: 0x25, blue: 0x22)
    case .classic: RGBA(red: 0, green: 0, blue: 0)
    case .graphite: RGBA(red: 0x20, green: 0x21, blue: 0x24)
    case .midnight: RGBA(red: 0x10, green: 0x18, blue: 0x20)
    case .blue: RGBA(red: 0x19, green: 0x1E, blue: 0x2D)
    case .green: RGBA(red: 0x19, green: 0x23, blue: 0x1E)
    case .sepia: RGBA(red: 0x2C, green: 0x24, blue: 0x1B)
    case .purple: RGBA(red: 0x24, green: 0x1B, blue: 0x2F)
    case .burgundy: RGBA(red: 0x2D, green: 0x18, blue: 0x1E)
    case .slate: RGBA(red: 0x1E, green: 0x29, blue: 0x33)
    case .negative, .custom: nil
    }
  }
}

/// Colour changes that apply to a whole page, drawn with PDF blend modes, so text and vector
/// graphics stay sharp and selectable. The pages are drawn again into a new document, so links,
/// form fields and outlines are not kept.
public enum PDFColourTransform {

  /// Settings of the dark mode.
  public struct DarkMode: Equatable, Sendable {
    public var theme: PDFDarkTheme
    /// The colour of the `custom` theme.
    public var customColour: RGBA
    /// How the colour of the `custom` theme is mixed with the page.
    public var customBlend: PDFBlendMode

    public init(
      theme: PDFDarkTheme = .warm, customColour: RGBA = RGBA(red: 0x20, green: 0x21, blue: 0x24),
      customBlend: PDFBlendMode = .screen
    ) {
      self.theme = theme
      self.customColour = customColour
      self.customBlend = customBlend
    }
  }

  private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

  /// The document with every colour turned into a grey of the same lightness. Pictures, text and
  /// vector graphics are all changed.
  public static func grayscale(_ data: Data) throws -> Data {
    try PDFSourcePages(data).overlay(pages: nil, backdrop: white) { _, size, context in
      fill(size, with: white, blend: .saturation, in: context)
    }
  }

  /// The document with light pages turned dark: the page is turned grey, inverted, and then mixed
  /// with the colour of the theme.
  public static func darkMode(_ data: Data, options: DarkMode = DarkMode()) throws -> Data {
    let theme = options.theme
    let overlayColour = theme == .custom ? options.customColour : theme.background
    let overlayBlend = theme == .custom ? options.customBlend.coreGraphics : CGBlendMode.screen
    return try PDFSourcePages(data).overlay(pages: nil, backdrop: white) { _, size, context in
      if theme != .negative {
        fill(size, with: white, blend: .saturation, in: context)
      }
      fill(size, with: white, blend: .difference, in: context)
      if let overlayColour {
        fill(size, with: overlayColour.cgColor(), blend: overlayBlend, in: context)
      }
    }
  }

  private static func fill(
    _ size: CGSize, with colour: CGColor, blend: CGBlendMode, in context: CGContext
  ) {
    context.saveGState()
    context.setBlendMode(blend)
    context.setFillColor(colour)
    context.fill(CGRect(origin: .zero, size: size))
    context.restoreGState()
  }
}
