import CoreGraphics
import Foundation

/// An RGB colour with components in 0...1. Transparency belongs to the layer's `opacity`.
public struct MarkupColour: Equatable, Sendable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
  }

  public static let white = MarkupColour(red: 1, green: 1, blue: 1)

  /// sRGB Core Graphics colour, fully opaque.
  var cgColor: CGColor {
    CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
  }

  /// A component as a byte, clamped so that out-of-range values cannot trap.
  var bytes: (red: UInt8, green: UInt8, blue: UInt8) {
    func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
    return (byte(red), byte(green), byte(blue))
  }
}

/// One element of a `MarkupDocument`. A layer holds exactly one piece of content.
///
/// Geometry uses the pixels of the base image, with the origin at the top-left corner and y
/// growing downwards. See `MarkupDocument` for details.
public struct MarkupLayer: Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var isVisible: Bool
  /// Layer opacity. Values outside 0...1 are clamped when the layer is rendered.
  public var opacity: Double
  public var content: Content
  /// Mirrors the layer left to right around the centre of its content.
  public var isFlippedHorizontally: Bool
  /// Mirrors the layer top to bottom around the centre of its content.
  public var isFlippedVertically: Bool
  /// A locked layer cannot be moved, edited, hidden or removed through `MarkupDocument`. Its lock
  /// can always be changed.
  public var isLocked: Bool
  public var blendMode: MarkupBlendMode
  /// Corner radius of pictures and text backgrounds, from 0 to 50 percent of the shorter side.
  /// Other content ignores it.
  public var cornerRadiusPercent: Int
  /// Number of text lines that are drawn, or nil for all of them. Other content ignores it.
  public var visibleLineCount: Int?
  /// Drop shadow under the layer's content, or nil for none. It is drawn for every kind of content.
  public var shadow: MarkupShadow?

  public init(
    id: UUID = UUID(),
    name: String,
    content: Content,
    isVisible: Bool = true,
    opacity: Double = 1,
    isFlippedHorizontally: Bool = false,
    isFlippedVertically: Bool = false,
    isLocked: Bool = false,
    blendMode: MarkupBlendMode = .srcOver,
    cornerRadiusPercent: Int = 0,
    visibleLineCount: Int? = nil,
    shadow: MarkupShadow? = nil
  ) {
    self.id = id
    self.name = name
    self.content = content
    self.isVisible = isVisible
    self.opacity = min(max(opacity, 0), 1)
    self.isFlippedHorizontally = isFlippedHorizontally
    self.isFlippedVertically = isFlippedVertically
    self.isLocked = isLocked
    self.blendMode = blendMode
    self.cornerRadiusPercent = min(max(cornerRadiusPercent, 0), 50)
    self.visibleLineCount = visibleLineCount.map { max($0, 1) }
    self.shadow = shadow
  }

  public enum Content: Equatable, Sendable {
    /// Text laid out with CoreText. `fontSize` is in base-image pixels. `origin` is the top-left
    /// corner of the text block before rotation. `rotation` is in radians, clockwise on screen,
    /// around `origin`. Newlines start new lines. `wrapWidth` is the widest a line may be, in
    /// pixels: lines break at word boundaries to fit it. Nil, or a width of zero or less, leaves
    /// only the newlines as line breaks. `style` adds decorations, alignment, a background and an
    /// outline.
    case text(
      string: String, fontName: String, fontSize: Double, colour: MarkupColour,
      origin: CGPoint, rotation: Double, wrapWidth: Double? = nil,
      style: MarkupTextStyle = MarkupTextStyle())

    /// A raster sticker, scaled to fill `frame`.
    case sticker(raster: RasterImage, frame: CGRect)

    /// A raster picture, scaled to fill `frame`. It is drawn like a sticker. It is kept apart
    /// because a picture is a photo, and the editor places it larger than a sticker.
    case image(raster: RasterImage, frame: CGRect)

    /// A shape. `frame` is its bounding box, except for lines, which run from `frame.origin` to
    /// `frame.origin + frame.size`. A closed shape is filled when `fillColour` is set and stroked
    /// when `strokeWidth` is positive. An open shape, such as a line, is only stroked. `style`
    /// holds rotation, corner radius, polygon and arrow options.
    case shape(
      kind: ShapeKind, frame: CGRect, strokeWidth: Double, strokeColour: MarkupColour,
      fillColour: MarkupColour?, style: MarkupShapeStyle = MarkupShapeStyle())

    /// A brush stroke through `points`, stamped with `BrushCanvas.stroke(through:)`.
    case stroke(points: [CGPoint], brush: Brush, colour: MarkupColour)

    public enum ShapeKind: CaseIterable, Equatable, Sendable {
      case rectangle
      case ellipse
      case line
      /// A filled arrow pointing right, with its head at the far side of `frame`.
      case arrow
      case doubleArrow
      /// A stroked line with a head at its far end.
      case lineArrow
      case doubleLineArrow
      case triangle
      case polygon
      case star

      /// Whether the shape encloses an area. Open shapes are only stroked.
      public var isClosed: Bool {
        switch self {
        case .line, .lineArrow, .doubleLineArrow: false
        default: true
        }
      }
    }

    // RasterImage is not Equatable, so the picture cases compare their pixels by hand.
    public static func == (lhs: Content, rhs: Content) -> Bool {
      switch (lhs, rhs) {
      case (
        let .text(string1, font1, size1, colour1, origin1, rotation1, wrap1, style1),
        let .text(string2, font2, size2, colour2, origin2, rotation2, wrap2, style2)
      ):
        return string1 == string2 && font1 == font2 && size1 == size2 && colour1 == colour2
          && origin1 == origin2 && rotation1 == rotation2 && wrap1 == wrap2 && style1 == style2
      case (let .sticker(raster1, frame1), let .sticker(raster2, frame2)),
        (let .image(raster1, frame1), let .image(raster2, frame2)):
        return frame1 == frame2 && raster1.width == raster2.width
          && raster1.height == raster2.height && raster1.pixels == raster2.pixels
      case (
        let .shape(kind1, frame1, width1, stroke1, fill1, style1),
        let .shape(kind2, frame2, width2, stroke2, fill2, style2)
      ):
        return kind1 == kind2 && frame1 == frame2 && width1 == width2 && stroke1 == stroke2
          && fill1 == fill2 && style1 == style2
      case (let .stroke(points1, brush1, colour1), let .stroke(points2, brush2, colour2)):
        return points1 == points2 && brush1 == brush2 && colour1 == colour2
      default:
        return false
      }
    }
  }
}
