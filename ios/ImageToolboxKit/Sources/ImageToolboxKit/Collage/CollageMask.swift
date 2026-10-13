import CoreGraphics
import Foundation

/// The shape every collage cell is clipped to. The shapes are the ones the Android collage offers: the plain
/// cell, a circle, a regular hexagon and a heart, plus an ellipse that fills the cell. The corner radius rounds
/// the corners of polygon shapes the way the Android "corners" slider does.
///
/// All paths are in top-left coordinates, like the cells they are made from.
public struct CollageMask: Equatable, Sendable {

  public enum Shape: CaseIterable, Hashable, Sendable {
    /// The cell itself. With a corner radius its corners are rounded.
    case rectangle
    /// The ellipse inscribed in the cell.
    case ellipse
    /// The largest circle that fits the cell, centred in it.
    case circle
    /// A regular hexagon with points to the left and right, fitted into the cell and centred in it.
    case hexagon
    /// The heart of the Android collage, fitted into the cell and centred in it.
    case heart
  }

  public var shape: Shape
  /// Radius in pixels that rounds the corners of the rectangle and the hexagon. Zero keeps them sharp.
  /// It is limited per corner, so neighbouring corners never overlap.
  public var cornerRadius: Double

  public init(shape: Shape = .rectangle, cornerRadius: Double = 0) {
    self.shape = shape
    self.cornerRadius = max(cornerRadius, 0)
  }

  /// The plain cell with sharp corners.
  public static let none = CollageMask()

  /// Whether the mask leaves the cell as it is.
  public var isIdentity: Bool {
    shape == .rectangle && cornerRadius <= 0
  }

  /// The same mask with its corner radius multiplied by `factor`, for a canvas drawn at another size.
  public func scaled(by factor: Double) -> CollageMask {
    CollageMask(shape: shape, cornerRadius: cornerRadius * factor)
  }

  /// The mask shape for `cell`. It can reach outside a cell that is not a rectangle, such as a triangle,
  /// because the shape is fitted to the bounding box of the cell. Use `outline(in:)` for the visible part.
  public func path(in cell: CGPath) -> CGPath {
    let box = cell.boundingBox
    switch shape {
    case .rectangle:
      guard cornerRadius > 0, let points = Self.polygonPoints(of: cell) else { return cell }
      return Self.roundedPolygon(points, radius: cornerRadius)
    case .ellipse:
      return CGPath(ellipseIn: box, transform: nil)
    case .circle:
      let side = min(box.width, box.height)
      return CGPath(
        ellipseIn: CGRect(
          x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side),
        transform: nil)
    case .hexagon:
      return Self.roundedPolygon(Self.hexagonPoints(in: box), radius: cornerRadius)
    case .heart:
      return Self.heartPath(in: box)
    }
  }

  /// The visible part of the cell: the mask shape clipped to the cell. A rectangular cell needs no clipping,
  /// because every shape lies inside its bounding box.
  public func outline(in cell: CGPath) -> CGPath {
    let mask = path(in: cell)
    guard shape != .rectangle, !cell.isRect(nil) else { return mask }
    let clipped = cell.intersection(mask)
    return clipped.isEmpty ? mask : clipped
  }

  // MARK: - Shapes

  /// A regular hexagon centred in `box`, as wide or as tall as the box allows. Its corners are at angle 0, 60
  /// and so on, which is the Android orientation.
  static func hexagonPoints(in box: CGRect) -> [CGPoint] {
    let radius = min(box.width / 2, box.height / 3.0.squareRoot())
    return (0..<6).map { index in
      let angle = Double(index) * Double.pi / 3
      return CGPoint(
        x: box.midX + radius * cos(angle), y: box.midY + radius * sin(angle))
    }
  }

  /// The Android heart, a path of quadratic curves in the unit square, scaled to fit `box` and centred.
  static func heartPath(in box: CGRect) -> CGPath {
    let unit = CGMutablePath()
    unit.move(to: CGPoint(x: 0, y: 0.25))
    unit.addQuadCurve(to: CGPoint(x: 0.25, y: 0), control: CGPoint(x: 0, y: 0))
    unit.addQuadCurve(to: CGPoint(x: 0.5, y: 0.25), control: CGPoint(x: 0.5, y: 0))
    unit.addQuadCurve(to: CGPoint(x: 0.75, y: 0), control: CGPoint(x: 0.5, y: 0))
    unit.addQuadCurve(to: CGPoint(x: 1, y: 0.25), control: CGPoint(x: 1, y: 0))
    unit.addQuadCurve(to: CGPoint(x: 0.75, y: 0.75), control: CGPoint(x: 1, y: 0.5))
    unit.addLine(to: CGPoint(x: 0.5, y: 1))
    unit.addLine(to: CGPoint(x: 0.25, y: 0.75))
    unit.addQuadCurve(to: CGPoint(x: 0, y: 0.25), control: CGPoint(x: 0, y: 0.5))
    unit.closeSubpath()

    let bounds = unit.boundingBox
    let scale = min(box.width / bounds.width, box.height / bounds.height)
    var transform = CGAffineTransform(translationX: box.midX, y: box.midY)
      .scaledBy(x: scale, y: scale)
      .translatedBy(x: -bounds.midX, y: -bounds.midY)
    return unit.copy(using: &transform) ?? unit
  }

  // MARK: - Polygons

  /// The corners of a path that is a single closed polygon of straight lines. Nil for curves and for paths
  /// with several parts.
  static func polygonPoints(of path: CGPath) -> [CGPoint]? {
    var points: [CGPoint] = []
    var isPolygon = true
    var parts = 0
    path.applyWithBlock { element in
      switch element.pointee.type {
      case .moveToPoint:
        parts += 1
        points.append(element.pointee.points[0])
      case .addLineToPoint:
        points.append(element.pointee.points[0])
      case .closeSubpath:
        break
      default:
        isPolygon = false
      }
    }
    guard isPolygon, parts == 1 else { return nil }

    // Drop repeated points, including a last point that closes the shape on the first.
    var corners: [CGPoint] = []
    for point in points where corners.last != point {
      corners.append(point)
    }
    if corners.count > 1, corners.first == corners.last { corners.removeLast() }
    return corners.count >= 3 ? corners : nil
  }

  /// A closed path through `points` with every corner replaced by a circular arc of `radius`. The radius is
  /// reduced at a corner where the arc would need more than half of either neighbouring side.
  static func roundedPolygon(_ points: [CGPoint], radius: Double) -> CGPath {
    let path = CGMutablePath()
    let count = points.count
    guard count >= 3 else { return path }
    guard radius > 0 else {
      path.addLines(between: points)
      path.closeSubpath()
      return path
    }

    var started = false
    for index in 0..<count {
      let corner = points[index]
      let previous = points[(index + count - 1) % count]
      let next = points[(index + 1) % count]
      let toPrevious = CGVector(dx: previous.x - corner.x, dy: previous.y - corner.y)
      let toNext = CGVector(dx: next.x - corner.x, dy: next.y - corner.y)
      let previousLength = hypot(toPrevious.dx, toPrevious.dy)
      let nextLength = hypot(toNext.dx, toNext.dy)
      guard previousLength > 0, nextLength > 0 else { continue }

      // The angle between the two sides at the corner. An angle of 0 or pi has no corner to round.
      let cosine =
        (toPrevious.dx * toNext.dx + toPrevious.dy * toNext.dy) / (previousLength * nextLength)
      let angle = acos(min(max(cosine, -1), 1))
      let tangent = tan(angle / 2)
      guard angle > 1e-4, angle < Double.pi - 1e-4, tangent > 0 else {
        if started { path.addLine(to: corner) } else { path.move(to: corner) }
        started = true
        continue
      }

      // The arc touches each side at `reach` from the corner, which is `radius / tan(angle / 2)`.
      let reach = min(radius / tangent, previousLength / 2, nextLength / 2)
      let start = CGPoint(
        x: corner.x + toPrevious.dx / previousLength * reach,
        y: corner.y + toPrevious.dy / previousLength * reach)
      let end = CGPoint(
        x: corner.x + toNext.dx / nextLength * reach,
        y: corner.y + toNext.dy / nextLength * reach)
      if started { path.addLine(to: start) } else { path.move(to: start) }
      started = true
      path.addArc(tangent1End: corner, tangent2End: end, radius: reach * tangent)
    }
    path.closeSubpath()
    return path
  }
}
