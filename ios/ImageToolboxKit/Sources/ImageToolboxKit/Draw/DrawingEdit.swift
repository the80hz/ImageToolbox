import CoreGraphics
import Foundation

/// What a brush stroke does to the picture.
public enum DrawingPaintKind: CaseIterable, Sendable {
  /// Ink in the drawing colour, over what is there.
  case pen
  /// Translucent ink. Overlaps inside one stroke do not add up.
  case highlighter
  /// A coloured glow around a white core.
  case neon
  /// Removes the picture under the stroke.
  case eraser
  /// Blurs the picture under the stroke.
  case blur
  /// Pixelates the picture under the stroke.
  case pixelate
}

/// A stroke and the brush it was drawn with. Points are in drawing units.
public struct DrawingStroke: Equatable, Sendable {
  public var points: [CGPoint]
  public let brush: Brush
  public let kind: DrawingPaintKind
  public let style: LineStyle

  public init(points: [CGPoint], brush: Brush, kind: DrawingPaintKind, style: LineStyle) {
    self.points = points
    self.brush = brush
    self.kind = kind
    self.style = style
  }
}

/// A drag of spray paint. Each point scatters `density` dots around it, within `radius`.
public struct DrawingSpray: Equatable, Sendable {
  public var points: [CGPoint]
  public let radius: Double
  public let density: Int
  public let dotSize: Double
  public let square: Bool
  /// Fixed when the drag starts, so that every render scatters the same dots.
  public let seed: UInt64

  public init(
    points: [CGPoint], radius: Double, density: Int, dotSize: Double, square: Bool, seed: UInt64
  ) {
    self.points = points
    self.radius = radius
    self.density = density
    self.dotSize = dotSize
    self.square = square
    self.seed = seed
  }
}

/// A shape dragged between two points. The end point moves while the drag lasts.
public struct DrawingShapeEdit: Equatable, Sendable {
  public let kind: ShapeKind
  public let start: CGPoint
  public var end: CGPoint
  public let filled: Bool
  public let brush: Brush
  public let options: ShapeOptions

  public init(
    kind: ShapeKind, start: CGPoint, end: CGPoint, filled: Bool, brush: Brush,
    options: ShapeOptions
  ) {
    self.kind = kind
    self.start = start
    self.end = end
    self.filled = filled
    self.brush = brush
    self.options = options
  }
}

/// A point the warp brush acted on, and how far the pointer moved to get there.
public struct DrawingWarpSample: Equatable, Sendable {
  public let centre: CGPoint
  public let direction: CGPoint

  public init(centre: CGPoint, direction: CGPoint) {
    self.centre = centre
    self.direction = direction
  }
}

/// One warp drag: every sample is applied in order with the same brush settings.
public struct DrawingWarpStroke: Equatable, Sendable {
  public var samples: [DrawingWarpSample]
  public let radius: Double
  public let strength: Double
  public let hardness: Double
  public let mode: WarpMode

  public init(
    samples: [DrawingWarpSample], radius: Double, strength: Double, hardness: Double,
    mode: WarpMode
  ) {
    self.samples = samples
    self.radius = radius
    self.strength = strength
    self.hardness = hardness
    self.mode = mode
  }
}

/// What a lasso does to the pixels inside its outline.
public enum DrawingLassoAction: Equatable, Sendable {
  /// Makes the pixels transparent.
  case clear
  /// Paints the pixels in the drawing colour at full opacity.
  case fill
}

/// Ink from committed PencilKit strokes, as alpha coverage of the box whose top-left corner is
/// (`x`, `y`) in drawing units. The colour is applied when the picture is rendered, so changing
/// the colour recolours these strokes too.
public struct DrawingPencilPatch: Equatable, Sendable {
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int
  /// Row-major alpha, one byte per pixel. It holds `width * height` bytes.
  public let coverage: [UInt8]

  public init(x: Int, y: Int, width: Int, height: Int, coverage: [UInt8]) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.coverage = coverage
  }

  /// The patch as premultiplied RGBA in `colour`, ready to be composited.
  public func raster(colour: (red: UInt8, green: UInt8, blue: UInt8)) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: coverage.count * 4)
    for (index, alpha) in coverage.enumerated() {
      let base = index * 4
      let value = Int(alpha)
      pixels[base] = UInt8((Int(colour.red) * value + 127) / 255)
      pixels[base + 1] = UInt8((Int(colour.green) * value + 127) / 255)
      pixels[base + 2] = UInt8((Int(colour.blue) * value + 127) / 255)
      pixels[base + 3] = alpha
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }
}

/// One change to the picture. A finished drag is one edit, and one undo step.
public enum DrawingEdit: Equatable, Sendable {
  case stroke(DrawingStroke)
  case shape(DrawingShapeEdit)
  case spray(DrawingSpray)
  /// A paint bucket click: fills the area under `point` that matches within `tolerance`.
  case flood(at: CGPoint, tolerance: Double)
  case lasso(polygon: [CGPoint], action: DrawingLassoAction)
  case heal(centres: [CGPoint], radius: Double)
  case warp(DrawingWarpStroke)
  /// PencilKit strokes that were committed.
  case pencil(DrawingPencilPatch)
}
