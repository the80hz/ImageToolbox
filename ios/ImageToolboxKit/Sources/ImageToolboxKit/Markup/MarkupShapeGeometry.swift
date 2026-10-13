import CoreGraphics
import Foundation

/// Outlines of the shapes, in top-left pixel coordinates. The renderer and the hit test both use
/// these paths, so a shape is picked where it is drawn.
///
/// The geometry follows the Android markup editor: a filled arrow has a head made of two angled
/// sides, a regular polygon or star is inscribed in a circle that is centred on the frame, and
/// angles are measured from the top of the frame, clockwise on screen.
enum MarkupShapeGeometry {
  /// The outline of `kind` inside `frame`. `strokeWidth` only sizes the heads of line arrows.
  static func path(
    kind: MarkupLayer.Content.ShapeKind, frame: CGRect, strokeWidth: Double,
    style: MarkupShapeStyle
  ) -> CGPath {
    let rect = frame.standardized
    let end = CGPoint(x: frame.origin.x + frame.size.width, y: frame.origin.y + frame.size.height)
    switch kind {
    case .rectangle:
      return roundedRectangle(rect, style: style)
    case .ellipse:
      return CGPath(ellipseIn: rect, transform: nil)
    case .line:
      return polyline([frame.origin, end], closed: false)
    case .arrow:
      return filledArrow(rect, doubleHeaded: false, style: style)
    case .doubleArrow:
      return filledArrow(rect, doubleHeaded: true, style: style)
    case .lineArrow:
      return lineArrow(
        from: frame.origin, to: end, strokeWidth: strokeWidth, doubleHeaded: false, style: style)
    case .doubleLineArrow:
      return lineArrow(
        from: frame.origin, to: end, strokeWidth: strokeWidth, doubleHeaded: true, style: style)
    case .triangle:
      return polyline(
        [
          CGPoint(x: rect.midX, y: rect.minY),
          CGPoint(x: rect.maxX, y: rect.maxY),
          CGPoint(x: rect.minX, y: rect.maxY),
        ], closed: true)
    case .polygon:
      return polyline(polygonVertices(rect, style: style), closed: true)
    case .star:
      return polyline(starVertices(rect, style: style), closed: true)
    }
  }

  // MARK: - Rectangles

  /// A rectangle with rounded corners, turned around its centre. The corner radius is a fraction
  /// of the shorter side, limited to half of it.
  private static func roundedRectangle(_ rect: CGRect, style: MarkupShapeStyle) -> CGPath {
    let radius = min(rect.width, rect.height) * CGFloat(clamp(style.cornerRadius, 0, 0.5))
    var turn = rotation(by: style.rotationDegrees, about: CGPoint(x: rect.midX, y: rect.midY))
    return CGPath(
      roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: &turn)
  }

  /// A transform that turns points around `centre` by `degrees`, clockwise on screen. In
  /// top-left coordinates the usual rotation matrix turns clockwise. It is written out, because
  /// composing translations and rotations with `CGAffineTransform` methods is easy to get wrong.
  private static func rotation(by degrees: Double, about centre: CGPoint) -> CGAffineTransform {
    let angle = CGFloat(degrees * .pi / 180)
    let cosine = cos(angle)
    let sine = sin(angle)
    return CGAffineTransform(
      a: cosine, b: sine, c: -sine, d: cosine,
      tx: centre.x - cosine * centre.x + sine * centre.y,
      ty: centre.y - sine * centre.x - cosine * centre.y)
  }

  // MARK: - Polygons and stars

  /// Corners of a polygon. A regular polygon uses the shorter half side as its radius, otherwise
  /// the corners sit on the frame's ellipse, which touches all four sides.
  private static func polygonVertices(_ rect: CGRect, style: MarkupShapeStyle) -> [CGPoint] {
    let count = max(style.vertices, 3)
    let step = 2 * CGFloat.pi / CGFloat(count)
    return ellipsePoints(
      in: rect, count: count, innerRatio: nil, start: startAngle(style), step: step,
      isRegular: style.isRegular)
  }

  /// Points of a star: outer points alternate with inner points. The inner radius is a fraction
  /// of the outer one.
  private static func starVertices(_ rect: CGRect, style: MarkupShapeStyle) -> [CGPoint] {
    let points = max(style.vertices, 3) * 2
    let step = 2 * CGFloat.pi / CGFloat(points)
    return ellipsePoints(
      in: rect, count: points, innerRatio: CGFloat(clamp(style.innerRadiusRatio, 0, 1)),
      start: startAngle(style), step: step, isRegular: style.isRegular)
  }

  /// Points on the frame's ellipse, or on its inscribed circle when regular. With `innerRatio`,
  /// every odd point is pulled in to that fraction of the radius, which makes a star.
  private static func ellipsePoints(
    in rect: CGRect, count: Int, innerRatio: CGFloat?, start: CGFloat, step: CGFloat,
    isRegular: Bool
  ) -> [CGPoint] {
    let radiusX = isRegular ? min(rect.width, rect.height) / 2 : rect.width / 2
    let radiusY = isRegular ? min(rect.width, rect.height) / 2 : rect.height / 2
    return (0..<count).map { index in
      var scale: CGFloat = 1
      if let innerRatio, index % 2 == 1 { scale = innerRatio }
      let angle = start + CGFloat(index) * step
      return CGPoint(
        x: rect.midX + radiusX * scale * cos(angle),
        y: rect.midY + radiusY * scale * sin(angle))
    }
  }

  /// The first corner points at the top of the frame, then turns by the rotation.
  private static func startAngle(_ style: MarkupShapeStyle) -> CGFloat {
    CGFloat((style.rotationDegrees - 90) * .pi / 180)
  }

  // MARK: - Arrows

  /// A filled arrow that points right. Its head is `width` times a length that grows with the
  /// size scale, and its angle sets how far the head sides open.
  private static func filledArrow(
    _ rect: CGRect, doubleHeaded: Bool, style: MarkupShapeStyle
  ) -> CGPath {
    let width = rect.width
    let height = rect.height
    let centreY = rect.midY
    let angle = CGFloat(clamp(style.arrowAngle, 100, 175)) * .pi / 180
    let normalised = (CGFloat(clamp(style.arrowSizeScale, 0.5, 8)) - 0.5) / 7.5
    let headLength = width * (0.22 + normalised * 0.28)
    let headBack = abs(cos(angle)) * headLength
    let tipHalf = min(height / 2, abs(sin(angle)) * headLength)
    let shaftHalf = max(min(height * 0.24, tipHalf * 0.55), height * 0.12)
    let left = rect.minX
    let right = rect.maxX

    if doubleHeaded {
      let safeBack = min(headBack, width / 2.5)
      let leftBack = left + safeBack
      let rightBack = right - safeBack
      return polyline(
        [
          CGPoint(x: left, y: centreY),
          CGPoint(x: leftBack, y: centreY - tipHalf),
          CGPoint(x: leftBack, y: centreY - shaftHalf),
          CGPoint(x: rightBack, y: centreY - shaftHalf),
          CGPoint(x: rightBack, y: centreY - tipHalf),
          CGPoint(x: right, y: centreY),
          CGPoint(x: rightBack, y: centreY + tipHalf),
          CGPoint(x: rightBack, y: centreY + shaftHalf),
          CGPoint(x: leftBack, y: centreY + shaftHalf),
          CGPoint(x: leftBack, y: centreY + tipHalf),
        ], closed: true)
    }
    let back = right - min(headBack, width * 0.6)
    return polyline(
      [
        CGPoint(x: left, y: centreY - shaftHalf),
        CGPoint(x: back, y: centreY - shaftHalf),
        CGPoint(x: back, y: centreY - tipHalf),
        CGPoint(x: right, y: centreY),
        CGPoint(x: back, y: centreY + tipHalf),
        CGPoint(x: back, y: centreY + shaftHalf),
        CGPoint(x: left, y: centreY + shaftHalf),
      ], closed: true)
  }

  /// A straight line with a head at its far end, and at its start when `doubleHeaded`. Each head
  /// is two sides from the tip, opened by the arrow angle. The head is at most half the line,
  /// a third when both ends have one.
  private static func lineArrow(
    from start: CGPoint, to end: CGPoint, strokeWidth: Double, doubleHeaded: Bool,
    style: MarkupShapeStyle
  ) -> CGPath {
    let path = CGMutablePath()
    path.move(to: start)
    path.addLine(to: end)
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 0 else { return path }

    let divisor: CGFloat = doubleHeaded ? 3 : 2
    let scale = CGFloat(clamp(style.arrowSizeScale, 0.5, 8))
    let headLength = min(length / divisor, max(CGFloat(strokeWidth), 2) * scale * 2)
    let angle = CGFloat(clamp(style.arrowAngle, 100, 175)) * .pi / 180
    let forward = atan2(dy, dx)
    addHead(to: path, tip: end, direction: forward, length: headLength, angle: angle)
    if doubleHeaded {
      addHead(to: path, tip: start, direction: forward + .pi, length: headLength, angle: angle)
    }
    return path
  }

  /// Two rays from `tip`. Each ray is `angle` away from `direction`, the way the head points.
  private static func addHead(
    to path: CGMutablePath, tip: CGPoint, direction: CGFloat, length: CGFloat, angle: CGFloat
  ) {
    for turn in [angle, -angle] {
      let ray = direction + turn
      path.move(to: tip)
      path.addLine(to: CGPoint(x: tip.x + cos(ray) * length, y: tip.y + sin(ray) * length))
    }
  }

  // MARK: - Helpers

  private static func polyline(_ points: [CGPoint], closed: Bool) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    if closed { path.closeSubpath() }
    return path
  }

  private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
  }
}
