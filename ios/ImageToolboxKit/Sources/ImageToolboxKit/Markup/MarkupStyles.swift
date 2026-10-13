import CoreGraphics
import Foundation

/// Decoration, alignment, background and outline of a text layer. The default is plain text.
public struct MarkupTextStyle: Equatable, Sendable {
  public enum Decoration: CaseIterable, Equatable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
  }

  /// Where each line sits inside the text block. `start` is the left edge for left-to-right text.
  public enum Alignment: CaseIterable, Equatable, Sendable {
    case start
    case centre
    case end
  }

  /// A stroke drawn around every glyph, in addition to the fill. `width` is in base-image pixels.
  public struct Outline: Equatable, Sendable {
    public var colour: MarkupColour
    public var width: Double

    public init(colour: MarkupColour, width: Double) {
      self.colour = colour
      self.width = max(width, 0)
    }
  }

  public var decorations: Set<Decoration>
  public var alignment: Alignment
  /// A fill behind the whole text block, rotated with the text. Nil draws no background.
  public var backgroundColour: MarkupColour?
  public var outline: Outline?

  public init(
    decorations: Set<Decoration> = [],
    alignment: Alignment = .start,
    backgroundColour: MarkupColour? = nil,
    outline: Outline? = nil
  ) {
    self.decorations = decorations
    self.alignment = alignment
    self.backgroundColour = backgroundColour
    self.outline = outline
  }

  /// Turns the decoration on when it is off, and off when it is on.
  public mutating func toggleDecoration(_ decoration: Decoration) {
    if !decorations.insert(decoration).inserted { decorations.remove(decoration) }
  }

  /// Adds a white background behind the text, or removes it.
  public mutating func toggleBackground() {
    backgroundColour = backgroundColour == nil ? .white : nil
  }

  /// Adds a white outline of `width` pixels around the glyphs, or removes it.
  public mutating func toggleOutline(width: Double) {
    outline = outline == nil ? Outline(colour: .white, width: width) : nil
  }
}

/// Geometry options of a shape. Each shape kind reads only the fields it needs, and every value is
/// clamped to its range when the shape is drawn.
public struct MarkupShapeStyle: Equatable, Sendable {
  /// Turn of a rectangle, polygon or star, in degrees, clockwise on screen around the frame centre.
  public var rotationDegrees: Double
  /// Corner radius of a rectangle, as a fraction of its shorter side, from 0 to 0.5.
  public var cornerRadius: Double
  /// Number of corners of a polygon, or of points of a star. Values below 3 are raised to 3.
  public var vertices: Int
  /// Inner radius of a star as a fraction of its outer radius, from 0 to 1.
  public var innerRadiusRatio: Double
  /// A regular polygon or star is inscribed in a circle. Otherwise it fills its frame.
  public var isRegular: Bool
  /// Size of an arrow head, from 0.5 to 8. The default matches the Android editor.
  public var arrowSizeScale: Double
  /// Angle between the two sides of an arrow head, from 100 to 175 degrees.
  public var arrowAngle: Double
  /// A linear gradient that replaces the fill colour of a filled closed shape. Nil fills with the
  /// solid fill colour. Other shapes ignore it.
  public var fillGradient: MarkupGradient?

  public init(
    rotationDegrees: Double = 0,
    cornerRadius: Double = 0,
    vertices: Int = 5,
    innerRadiusRatio: Double = 0.5,
    isRegular: Bool = false,
    arrowSizeScale: Double = 3,
    arrowAngle: Double = 150,
    fillGradient: MarkupGradient? = nil
  ) {
    self.rotationDegrees = rotationDegrees
    self.cornerRadius = cornerRadius
    self.vertices = vertices
    self.innerRadiusRatio = innerRadiusRatio
    self.isRegular = isRegular
    self.arrowSizeScale = arrowSizeScale
    self.arrowAngle = arrowAngle
    self.fillGradient = fillGradient
  }
}

/// A drop shadow under a layer, drawn with Core Graphics shadow settings. Offsets and blur are in
/// base-image pixels. Positive `offsetX` moves the shadow right and positive `offsetY` moves it down
/// the screen. Flips of the layer do not change that. Values are clamped when the layer is rendered.
public struct MarkupShadow: Equatable, Sendable, Codable {
  public var colour: MarkupColour
  /// Opacity of the shadow, from 0 (invisible) to 1. It multiplies the opacity of the layer.
  /// Values outside that range are clamped by the initialiser and when the layer is rendered.
  public var alpha: Double
  public var offsetX: Double
  public var offsetY: Double
  /// Blur radius from 0, a hard edge, to 100 pixels.
  public var blurRadius: Double

  /// The shadow of the Android editor: opaque black, 6 pixels down, with a 12 pixel blur.
  public init(
    colour: MarkupColour = MarkupColour(red: 0, green: 0, blue: 0),
    alpha: Double = 1,
    offsetX: Double = 0,
    offsetY: Double = 6,
    blurRadius: Double = 12
  ) {
    self.colour = colour
    self.alpha = min(max(alpha, 0), 1)
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.blurRadius = blurRadius
  }
}

/// A linear gradient between two colours. `angleDegrees` is the direction in which the colour
/// changes, measured clockwise on screen: 0 runs from left to right, and 90 from top to bottom.
/// The gradient spans the shape's frame, and the shape clips it.
public struct MarkupGradient: Equatable, Sendable, Codable {
  public var startColour: MarkupColour
  public var endColour: MarkupColour
  public var angleDegrees: Double

  public init(startColour: MarkupColour, endColour: MarkupColour, angleDegrees: Double = 90) {
    self.startColour = startColour
    self.endColour = endColour
    self.angleDegrees = angleDegrees
  }
}

/// How a layer combines with the layers below it. The names follow Compose's `BlendMode`, which the
/// Android editor uses. `Dst` is not offered, because Core Graphics has no mode that keeps only the
/// destination.
public enum MarkupBlendMode: CaseIterable, Equatable, Sendable {
  case srcOver
  case src
  case clear
  case dstOver
  case srcIn
  case dstIn
  case srcOut
  case dstOut
  case srcAtop
  case dstAtop
  case xor
  case plus
  case screen
  case overlay
  case darken
  case lighten
  case colorDodge
  case colorBurn
  case hardLight
  case softLight
  case difference
  case exclusion
  case multiply
  case hue
  case saturation
  case color
  case luminosity

  var cgBlendMode: CGBlendMode {
    switch self {
    case .srcOver: .normal
    case .src: .copy
    case .clear: .clear
    case .dstOver: .destinationOver
    case .srcIn: .sourceIn
    case .dstIn: .destinationIn
    case .srcOut: .sourceOut
    case .dstOut: .destinationOut
    case .srcAtop: .sourceAtop
    case .dstAtop: .destinationAtop
    case .xor: .xor
    case .plus: .plusLighter
    case .screen: .screen
    case .overlay: .overlay
    case .darken: .darken
    case .lighten: .lighten
    case .colorDodge: .colorDodge
    case .colorBurn: .colorBurn
    case .hardLight: .hardLight
    case .softLight: .softLight
    case .difference: .difference
    case .exclusion: .exclusion
    case .multiply: .multiply
    case .hue: .hue
    case .saturation: .saturation
    case .color: .color
    case .luminosity: .luminosity
    }
  }
}
