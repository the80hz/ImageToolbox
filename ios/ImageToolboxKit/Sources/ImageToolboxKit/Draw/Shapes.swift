import CoreGraphics
import Foundation

/// The shapes that `ShapeRenderer` draws between two dragged points.
public enum ShapeKind: Hashable, Sendable, CaseIterable {
  /// Rectangle with the two points as opposite corners. `ShapeOptions` adds rotation and rounding.
  case rectangle
  /// Ellipse inscribed in the rectangle spanned by the two points.
  case ellipse
  /// Straight segment from the first point to the second.
  case line
  /// Triangle with its top edge from the first point across to the second, and its apex below the
  /// middle of that edge, at the height of the second point.
  case triangle
  /// Polygon inscribed in the rectangle spanned by the two points.
  case polygon
  /// Star inscribed in the rectangle spanned by the two points.
  case star
  /// Segment with an arrowhead at the second point.
  case arrow
  /// Segment with arrowheads at both ends.
  case doubleArrow
}

/// The parameters that shape an outline. The defaults give the plain shapes.
public struct ShapeOptions: Equatable, Sendable {
  /// Corners of a polygon, or points of a star, from 3 to 12.
  public var sides: Int
  /// Inner radius of a star as a fraction of the outer one, from 0.1 to 0.9.
  public var innerRatio: Double
  /// Whether a polygon or star keeps equal sides and angles. When false it stretches to fill the
  /// rectangle that the two points span.
  public var isRegular: Bool
  /// Rotation in degrees, clockwise on screen. Applies to rectangles, polygons and stars.
  public var rotation: Double
  /// Rounding of a rectangle's corners, from 0 (square) to 0.5 (fully round), as a fraction of
  /// the shorter side.
  public var cornerRadius: Double
  /// Angle between the two arms of an arrowhead, in degrees, from 30 to 170.
  public var arrowAngle: Double
  /// Length of an arrowhead arm as a multiple of the brush diameter, from 1 to 10.
  public var arrowScale: Double
  /// How the outline is broken into dashes or dots.
  public var lineStyle: LineStyle

  public init(
    sides: Int = 5, innerRatio: Double = 0.5, isRegular: Bool = false, rotation: Double = 0,
    cornerRadius: Double = 0, arrowAngle: Double = 150, arrowScale: Double = 3,
    lineStyle: LineStyle = .solid
  ) {
    self.sides = min(max(sides, 3), 12)
    self.innerRatio = min(max(innerRatio, 0.1), 0.9)
    self.isRegular = isRegular
    self.rotation = rotation.isFinite ? rotation : 0
    self.cornerRadius = min(max(cornerRadius, 0), 0.5)
    self.arrowAngle = min(max(arrowAngle, 30), 170)
    self.arrowScale = min(max(arrowScale, 1), 10)
    self.lineStyle = lineStyle
  }
}

/// Draws shapes with a brush.
///
/// An outline is a set of strokes, so it takes the brush's hardness, spacing, opacity and line
/// style. A filled closed shape covers the pixels whose centres lie inside its polygon, each with
/// the brush opacity and hard edges, and no outline is drawn. Lines and arrows have no interior,
/// so the `filled` flag has no effect on them.
public enum ShapeRenderer {

  public static func draw(
    _ kind: ShapeKind, from start: CGPoint, to end: CGPoint, filled: Bool, brush: Brush,
    options: ShapeOptions = ShapeOptions(), onto canvas: inout BrushCanvas
  ) {
    guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return }
    let outline = ShapeOutline.make(
      kind, from: start, to: end, options: options, strokeWidth: brush.radius * 2)

    if filled, let polygon = outline.polygon {
      let inside = LassoMask(polygon: polygon).mask(width: canvas.width, height: canvas.height)
      canvas.paint(inside, opacity: brush.opacity)
      return
    }
    for stroke in outline.strokes {
      canvas.stroke(through: stroke, brush: brush, style: options.lineStyle)
    }
  }
}
