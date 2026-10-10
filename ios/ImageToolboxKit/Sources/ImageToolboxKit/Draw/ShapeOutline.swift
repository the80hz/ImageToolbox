import CoreGraphics
import Foundation

/// The geometry of a shape in drawing units: the polygon that a fill covers and the polylines that
/// a brush strokes.
public struct ShapeOutline: Equatable, Sendable {
  /// The closed polygon that a filled shape covers. Nil for shapes with no interior.
  public var polygon: [CGPoint]?
  /// Polylines to stroke. A closed outline repeats its first point at its end.
  public var strokes: [[CGPoint]]

  /// The outline of `kind` dragged from `start` to `end`. `strokeWidth` is the brush diameter, which
  /// sets the length of the arrowheads.
  public static func make(
    _ kind: ShapeKind, from start: CGPoint, to end: CGPoint, options: ShapeOptions = ShapeOptions(),
    strokeWidth: Double
  ) -> ShapeOutline {
    let left = Double(min(start.x, end.x))
    let right = Double(max(start.x, end.x))
    let top = Double(min(start.y, end.y))
    let bottom = Double(max(start.y, end.y))
    let centre = (x: (left + right) / 2, y: (top + bottom) / 2)
    let width = right - left
    let height = bottom - top

    switch kind {
    case .line:
      return ShapeOutline(polygon: nil, strokes: [[start, end]])

    case .arrow:
      let heads = arrowheads(
        from: start, to: end, options: options, strokeWidth: strokeWidth, both: false)
      return ShapeOutline(polygon: nil, strokes: [[start, end]] + heads)

    case .doubleArrow:
      let heads = arrowheads(
        from: start, to: end, options: options, strokeWidth: strokeWidth, both: true)
      return ShapeOutline(polygon: nil, strokes: [[start, end]] + heads)

    case .rectangle:
      let corners = roundedRectangle(
        left: left, top: top, right: right, bottom: bottom,
        cornerRadius: options.cornerRadius, rotation: options.rotation, centre: centre)
      return closed(corners)

    case .ellipse:
      let outline = ellipse(centre: centre, radiusX: width / 2, radiusY: height / 2)
      return ShapeOutline(polygon: Array(outline.dropLast()), strokes: [outline])

    case .triangle:
      let corners = [
        start,
        CGPoint(x: end.x, y: start.y),
        CGPoint(x: (start.x + end.x) / 2, y: end.y),
      ]
      return closed(corners)

    case .polygon:
      let vertices = polygonVertices(
        centre: centre, width: width, height: height, options: options)
      return closed(vertices)

    case .star:
      let vertices = starVertices(
        centre: centre, width: width, height: height, options: options)
      return closed(vertices)
    }
  }

  // MARK: - Helpers

  private static func closed(_ corners: [CGPoint]) -> ShapeOutline {
    guard let first = corners.first else { return ShapeOutline(polygon: nil, strokes: []) }
    return ShapeOutline(polygon: corners, strokes: [corners + [first]])
  }

  /// A rectangle with its corners rounded by `cornerRadius` of the shorter side, turned by
  /// `rotation` about its centre.
  private static func roundedRectangle(
    left: Double, top: Double, right: Double, bottom: Double, cornerRadius: Double,
    rotation: Double, centre: (x: Double, y: Double)
  ) -> [CGPoint] {
    let radius = min(right - left, bottom - top) * cornerRadius
    guard radius > 0 else {
      return [(right, top), (right, bottom), (left, bottom), (left, top)].map {
        rotate(CGPoint(x: $0.0, y: $0.1), around: centre, degrees: rotation)
      }
    }
    let arcSteps = 8
    var points: [CGPoint] = []
    // Each corner is an arc centred at the corner's inset point, from one edge to the next.
    let corners: [(x: Double, y: Double, start: Double)] = [
      (right - radius, top + radius, -90),
      (right - radius, bottom - radius, 0),
      (left + radius, bottom - radius, 90),
      (left + radius, top + radius, 180),
    ]
    for corner in corners {
      for step in 0...arcSteps {
        let angle = (corner.start + 90 * Double(step) / Double(arcSteps)) * .pi / 180
        points.append(
          CGPoint(
            x: corner.x + radius * cos(angle), y: corner.y + radius * sin(angle)))
      }
    }
    return points.map { rotate($0, around: centre, degrees: rotation) }
  }

  private static func polygonVertices(
    centre: (x: Double, y: Double), width: Double, height: Double, options: ShapeOptions
  ) -> [CGPoint] {
    let count = options.sides
    let step = 360 / Double(count)
    let radiusX = options.isRegular ? min(width, height) / 2 : width / 2
    let radiusY = options.isRegular ? min(width, height) / 2 : height / 2
    return (0..<count).map { index in
      point(
        centre: centre, radiusX: radiusX, radiusY: radiusY,
        degrees: 90 + options.rotation + Double(index) * step)
    }
  }

  /// A star with `sides` points. Its vertices alternate between the outer and the inner radius.
  private static func starVertices(
    centre: (x: Double, y: Double), width: Double, height: Double, options: ShapeOptions
  ) -> [CGPoint] {
    let count = 2 * options.sides
    let step = 360 / Double(count)
    return (0..<count).map { index in
      let outer = index.isMultiple(of: 2)
      let degrees = 90 + options.rotation + Double(index) * step
      if options.isRegular {
        let radius = min(width, height) / 2 * (outer ? 1 : options.innerRatio)
        return point(centre: centre, radiusX: radius, radiusY: radius, degrees: degrees)
      }
      let ratio = outer ? 1 : options.innerRatio
      return point(
        centre: centre, radiusX: width / 2 * ratio, radiusY: height / 2 * ratio,
        degrees: degrees)
    }
  }

  /// Vertices on an ellipse, closed back on the first one. The chords are long enough that the
  /// polygon never strays more than about a quarter pixel from the curve, at any size.
  private static func ellipse(
    centre: (x: Double, y: Double), radiusX: Double, radiusY: Double
  ) -> [CGPoint] {
    let largest = max(radiusX, radiusY)
    let rawCount = (2 * Double.pi * (largest / 2).squareRoot()).rounded(.up)
    // The cap only guards against absurd sizes that would overflow Int.
    let count = Int(min(max(rawCount, 16), 1_048_576))
    return (0...count).map { index in
      let angle = 2 * Double.pi * Double(index) / Double(count)
      return CGPoint(
        x: centre.x + radiusX * cos(angle), y: centre.y + radiusY * sin(angle))
    }
  }

  /// The arms of one arrowhead at `tip`, or of two when `both` is set. Each arm is `arrowScale`
  /// brush diameters long, turned `arrowAngle` degrees away from the shaft.
  private static func arrowheads(
    from start: CGPoint, to end: CGPoint, options: ShapeOptions, strokeWidth: Double, both: Bool
  ) -> [[CGPoint]] {
    let shaftX = Double(end.x - start.x)
    let shaftY = Double(end.y - start.y)
    let length = (shaftX * shaftX + shaftY * shaftY).squareRoot()
    guard length > 0 else { return [] }
    let arm = strokeWidth * options.arrowScale
    let forward = (x: shaftX / length, y: shaftY / length)

    var heads: [[CGPoint]] = [
      head(tip: end, direction: forward, arm: arm, angle: options.arrowAngle)
    ]
    if both {
      heads.append(
        head(
          tip: start, direction: (-forward.x, -forward.y), arm: arm, angle: options.arrowAngle))
    }
    return heads
  }

  /// One arrowhead as a polyline: the left arm, the tip and the right arm.
  private static func head(
    tip: CGPoint, direction: (x: Double, y: Double), arm: Double, angle: Double
  ) -> [CGPoint] {
    let vector = (x: direction.x * arm, y: direction.y * arm)
    let left = turn(vector, by: angle)
    let right = turn(vector, by: -angle)
    return [
      CGPoint(x: tip.x + CGFloat(left.x), y: tip.y + CGFloat(left.y)),
      tip,
      CGPoint(x: tip.x + CGFloat(right.x), y: tip.y + CGFloat(right.y)),
    ]
  }

  private static func turn(_ vector: (x: Double, y: Double), by degrees: Double) -> (
    x: Double, y: Double
  ) {
    let radians = degrees * .pi / 180
    return (
      vector.x * cos(radians) - vector.y * sin(radians),
      vector.x * sin(radians) + vector.y * cos(radians)
    )
  }

  private static func point(
    centre: (x: Double, y: Double), radiusX: Double, radiusY: Double, degrees: Double
  ) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(
      x: centre.x + radiusX * cos(radians), y: centre.y + radiusY * sin(radians))
  }

  private static func rotate(
    _ point: CGPoint, around centre: (x: Double, y: Double), degrees: Double
  ) -> CGPoint {
    let radians = degrees * .pi / 180
    let dx = Double(point.x) - centre.x
    let dy = Double(point.y) - centre.y
    return CGPoint(
      x: centre.x + dx * cos(radians) - dy * sin(radians),
      y: centre.y + dx * sin(radians) + dy * cos(radians))
  }
}
