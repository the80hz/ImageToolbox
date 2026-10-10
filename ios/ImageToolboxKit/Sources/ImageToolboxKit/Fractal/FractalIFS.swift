import Foundation

/// The iterated function systems and the recursive shapes, drawn as the Android engine draws them.
/// A system is drawn by recursive subdivision of its maps: each composed map is applied to the box
/// of the attractor, and a piece is drawn at its centre once it is about a pixel wide. The
/// Heighway dragon, the Koch snowflake, the Pythagoras tree, the H-tree and the Hilbert curve are drawn by
/// recursive subdivision of their segments and squares, which stops at about 0.6 pixels.
enum FractalIFS {

  /// An affine map of the plane, (x, y) -> (a*x + b*y + e, c*x + d*y + f). The Android engine writes
  /// its maps as (xx, xy, yx, yy, tx, ty), which is the same order.
  struct AffineMap: Equatable, Sendable {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let e: Double
    let f: Double

    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
      self.a = a
      self.b = b
      self.c = c
      self.d = d
      self.e = e
      self.f = f
    }

    static let identity = AffineMap(1, 0, 0, 1, 0, 0)

    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
      (a * x + b * y + e, c * x + d * y + f)
    }

    /// The map self o other: `other` is applied first, then `self`.
    func composed(after other: AffineMap) -> AffineMap {
      AffineMap(
        a * other.a + b * other.c, a * other.b + b * other.d,
        c * other.a + d * other.c, c * other.b + d * other.d,
        a * other.e + b * other.f + e, c * other.e + d * other.f + f)
    }
  }

  /// An axis-aligned box of the plane: [x0, x1] x [y0, y1].
  struct Box: Equatable, Sendable {
    let x0: Double
    let x1: Double
    let y0: Double
    let y1: Double

    /// The smallest box that holds the image of this one under the map.
    func image(under map: AffineMap) -> Box {
      let corners = [
        map.apply(x0, y0), map.apply(x1, y0), map.apply(x0, y1), map.apply(x1, y1),
      ]
      return Box(
        x0: corners.map(\.0).min() ?? x0, x1: corners.map(\.0).max() ?? x1,
        y0: corners.map(\.1).min() ?? y0, y1: corners.map(\.1).max() ?? y1)
    }
  }

  /// The maps of a system and the box of its attractor, as the Android engine gives them.
  static func system(_ kind: EscapeTimeFractal.Kind) -> (maps: [AffineMap], box: Box) {
    switch kind {
    case .barnsleyFern:
      return (
        [
          AffineMap(0, 0, 0, 0.16, 0, 0),
          AffineMap(0.85, 0.04, -0.04, 0.85, 0, 1.6),
          AffineMap(0.2, -0.26, 0.23, 0.22, 0, 1.6),
          AffineMap(-0.15, 0.28, 0.26, 0.24, 0, 0.44),
        ],
        Box(x0: -2.19, x1: 2.66, y0: 0, y1: 10)
      )
    case .ifsDragon:
      return (
        [
          AffineMap(0.824_074, 0.281_428, -0.212_346, 0.864_198, -1.882_29, -0.110_607),
          AffineMap(0.088_272, 0.520_988, -0.463_889, -0.377_778, 0.785_36, 8.095_795),
        ],
        Box(x0: -3.1, x1: 3.1, y0: -0.7, y1: 9.2)
      )
    case .ifsTwig:
      return (
        [
          AffineMap(0.387, 0.43, 0.43, -0.387, 0.256, 0.522),
          AffineMap(0.441, -0.091, -0.009, -0.322, 0.4219, 0.5059),
          AffineMap(-0.468, 0.02, -0.113, 0.015, 0.4, 0.4),
        ],
        Box(x0: -0.05, x1: 1.05, y0: -0.05, y1: 1.05)
      )
    case .christmasTree:
      return (
        [
          AffineMap(0, -0.5, 0.5, 0, 0.5, 0),
          AffineMap(0, 0.5, -0.5, 0, 0.5, 0.5),
          AffineMap(0.5, 0, 0, 0.5, 0.25, 0.5),
        ],
        Box(x0: -0.05, x1: 1.05, y0: -0.05, y1: 1.05)
      )
    case .vicsekCross:
      // Five squares of a third the size, at the four corners of a square and at its centre.
      let third = 1.0 / 3
      let far = 2.0 / 3
      return (
        [
          AffineMap(third, 0, 0, third, -far, -far),
          AffineMap(third, 0, 0, third, far, -far),
          AffineMap(third, 0, 0, third, 0, 0),
          AffineMap(third, 0, 0, third, -far, far),
          AffineMap(third, 0, 0, third, far, far),
        ],
        Box(x0: -1.05, x1: 1.05, y0: -1.05, y1: 1.05)
      )
    default:
      preconditionFailure("\(kind) is not an iterated system")
    }
  }

  /// Draws the system by recursive subdivision. The maps are composed onto the identity, and a
  /// composed map is drawn once its image of the box is at most 0.75 pixels wide, or at depth 64.
  static func plotSystem(_ kind: EscapeTimeFractal.Kind, into canvas: inout DensityCanvas) {
    let (maps, box) = system(kind)
    subdivide(.identity, maps: maps, box: box, depth: 0, into: &canvas)
  }

  private static func subdivide(
    _ transform: AffineMap, maps: [AffineMap], box: Box, depth: Int,
    into canvas: inout DensityCanvas
  ) {
    let image = box.image(under: transform)
    guard canvas.overlaps(image) else { return }
    let size = max(image.x1 - image.x0, image.y1 - image.y0) * canvas.pixelsPerUnit
    if size <= 0.75 || depth >= 64 {
      canvas.add(real: (image.x0 + image.x1) / 2, imaginary: (image.y0 + image.y1) / 2)
      return
    }
    for map in maps {
      subdivide(
        transform.composed(after: map), maps: maps, box: box, depth: depth + 1, into: &canvas)
    }
  }

  /// The Heighway dragon: the segment from (-0.65, -0.15) to (0.65, -0.15) is split by the apex on
  /// its left, and each half is split again, down to depth 64 or about 0.6 pixels.
  static func plotHeighwayDragon(into canvas: inout DensityCanvas) {
    dragon(
      from: FractalComplex(-0.65, -0.15), to: FractalComplex(0.65, -0.15), depth: 64,
      into: &canvas)
  }

  private static func dragon(
    from start: FractalComplex, to end: FractalComplex, depth: Int,
    into canvas: inout DensityCanvas
  ) {
    let length = hypot(end.re - start.re, end.im - start.im)
    let middle = FractalComplex((start.re + end.re) / 2, (start.im + end.im) / 2)
    guard canvas.mayContainCircle(centre: middle, radius: length * 1.25) else { return }
    guard depth > 0, length * canvas.pixelsPerUnit > 0.6 else {
      drawSegment(start, end, into: &canvas)
      return
    }
    // The apex is the midpoint turned a half-length perpendicular to the segment.
    let dx = end.re - start.re
    let dy = end.im - start.im
    let apex = FractalComplex(middle.re + dy / 2, middle.im - dx / 2)
    dragon(from: start, to: apex, depth: depth - 1, into: &canvas)
    dragon(from: end, to: apex, depth: depth - 1, into: &canvas)
  }

  /// The Koch snowflake outline: a triangle with vertices (-0.84, -0.48), (0.84, -0.48) and
  /// (0, 0.975), whose sides are each replaced by the Koch curve, to depth 32 or about 0.6 pixels.
  static func plotKochSnowflake(into canvas: inout DensityCanvas) {
    let vertices = [
      FractalComplex(-0.84, -0.48), FractalComplex(0.84, -0.48), FractalComplex(0, 0.975),
    ]
    for index in 0..<3 {
      koch(
        from: vertices[index], to: vertices[(index + 1) % 3], depth: 32, into: &canvas)
    }
  }

  private static func koch(
    from start: FractalComplex, to end: FractalComplex, depth: Int,
    into canvas: inout DensityCanvas
  ) {
    let length = hypot(end.re - start.re, end.im - start.im)
    let middle = FractalComplex((start.re + end.re) / 2, (start.im + end.im) / 2)
    guard canvas.mayContainCircle(centre: middle, radius: length * 0.8) else { return }
    guard depth > 0, length * canvas.pixelsPerUnit > 0.6 else {
      drawSegment(start, end, into: &canvas)
      return
    }
    // A third of the side, and its middle third turned by -60 degrees to make the bump outwards.
    let delta = (1.0 / 3) * (end - start)
    let first = start + delta
    let third = start + 2 * delta
    let root3Half = 3.0.squareRoot() / 2
    let turned = FractalComplex(
      0.5 * delta.re + root3Half * delta.im, -root3Half * delta.re + 0.5 * delta.im)
    let peak = first + turned
    koch(from: start, to: first, depth: depth - 1, into: &canvas)
    koch(from: first, to: peak, depth: depth - 1, into: &canvas)
    koch(from: peak, to: third, depth: depth - 1, into: &canvas)
    koch(from: third, to: end, depth: depth - 1, into: &canvas)
  }

  /// The Pythagoras tree: a square on the base from (-0.34, -0.95) to (0.34, -0.95), and on the top
  /// edge of each square two squares, on the legs of an isosceles right triangle.
  static func plotPythagorasTree(into canvas: inout DensityCanvas) {
    square(
      from: FractalComplex(-0.34, -0.95), to: FractalComplex(0.34, -0.95), depth: 64,
      into: &canvas)
  }

  private static func square(
    from base: FractalComplex, to baseEnd: FractalComplex, depth: Int,
    into canvas: inout DensityCanvas
  ) {
    let edge = baseEnd - base
    let length = hypot(edge.re, edge.im)
    // The square stands on the outward side of its base, which is the edge turned by 90 degrees.
    let outward = FractalComplex(-edge.im, edge.re)
    let centre = FractalComplex(
      (base.re + baseEnd.re) / 2 + outward.re / 2, (base.im + baseEnd.im) / 2 + outward.im / 2)
    guard canvas.mayContainCircle(centre: centre, radius: length * 4) else { return }
    let topStart = base + outward
    let topEnd = baseEnd + outward
    drawSegment(base, baseEnd, into: &canvas)
    drawSegment(baseEnd, topEnd, into: &canvas)
    drawSegment(topEnd, topStart, into: &canvas)
    drawSegment(topStart, base, into: &canvas)
    guard depth > 1, length * canvas.pixelsPerUnit > 0.6 else { return }

    let top = topEnd - topStart
    let apex = FractalComplex(
      topStart.re + (top.re - top.im) / 2, topStart.im + (top.im + top.re) / 2)
    square(from: topStart, to: apex, depth: depth - 1, into: &canvas)
    square(from: apex, to: topEnd, depth: depth - 1, into: &canvas)
  }

  /// The H-tree, from the Android engine: a horizontal segment of half-length 0.72 about the origin. At
  /// each end sits an H-tree turned by a right angle, whose half-length is the parent's divided by the
  /// square root of 2. The recursion runs to the given depth, or stops at about 0.6 pixels.
  static func plotHTree(into canvas: inout DensityCanvas, depth: Int = 64) {
    hTree(
      centre: FractalComplex(0, 0), halfLength: 0.72, horizontal: true, depth: depth,
      into: &canvas)
  }

  private static func hTree(
    centre: FractalComplex, halfLength: Double, horizontal: Bool, depth: Int,
    into canvas: inout DensityCanvas
  ) {
    // The subtree lies within 4 half-lengths of its centre, so a circle of that radius bounds it.
    guard canvas.mayContainCircle(centre: centre, radius: halfLength * 4) else { return }
    let offset =
      horizontal ? FractalComplex(halfLength, 0) : FractalComplex(0, halfLength)
    let first = centre - offset
    let second = centre + offset
    drawSegment(first, second, into: &canvas)
    guard depth > 1, halfLength * 2 * canvas.pixelsPerUnit > 0.6 else { return }
    let child = halfLength / 2.0.squareRoot()
    hTree(
      centre: first, halfLength: child, horizontal: !horizontal, depth: depth - 1,
      into: &canvas)
    hTree(
      centre: second, halfLength: child, horizontal: !horizontal, depth: depth - 1,
      into: &canvas)
  }

  /// The Hilbert curve, from the Android engine: the curve of the given order on the square
  /// [-0.9, 0.9]^2, which the engine draws at order 32. Each cell is visited at its centre, and
  /// consecutive centres are joined. A cell outside the view breaks the path, so no segment crosses it.
  /// A cell is split while it is more than about 0.6 pixels wide.
  static func plotHilbertCurve(into canvas: inout DensityCanvas, order: Int = 32) {
    var previous: FractalComplex?
    hilbert(
      origin: FractalComplex(-0.9, -0.9), axisX: FractalComplex(1.8, 0),
      axisY: FractalComplex(0, 1.8), depth: order, previous: &previous, into: &canvas)
  }

  /// One cell of the curve, given by its corner and its two edge vectors. The four sub-cells are visited
  /// in the order that keeps the path continuous, and each has its own orientation.
  private static func hilbert(
    origin: FractalComplex, axisX: FractalComplex, axisY: FractalComplex, depth: Int,
    previous: inout FractalComplex?, into canvas: inout DensityCanvas
  ) {
    let corners = [origin, origin + axisX, origin + axisY, origin + axisX + axisY]
    let box = Box(
      x0: corners.map(\.re).min() ?? 0, x1: corners.map(\.re).max() ?? 0,
      y0: corners.map(\.im).min() ?? 0, y1: corners.map(\.im).max() ?? 0)
    guard canvas.overlaps(box) else {
      previous = nil
      return
    }
    let cell = max(hypot(axisX.re, axisX.im), hypot(axisY.re, axisY.im))
    guard depth > 0, cell * canvas.pixelsPerUnit > 0.6 else {
      let point = origin + 0.5 * (axisX + axisY)
      if let start = previous {
        drawSegment(start, point, into: &canvas)
      }
      previous = point
      return
    }
    let halfX = 0.5 * axisX
    let halfY = 0.5 * axisY
    hilbert(
      origin: origin, axisX: halfY, axisY: halfX, depth: depth - 1, previous: &previous,
      into: &canvas)
    hilbert(
      origin: origin + halfX, axisX: halfX, axisY: halfY, depth: depth - 1,
      previous: &previous, into: &canvas)
    hilbert(
      origin: origin + halfX + halfY, axisX: halfX, axisY: halfY, depth: depth - 1,
      previous: &previous, into: &canvas)
    hilbert(
      origin: origin + halfX + axisY, axisX: -1.0 * halfY, axisY: -1.0 * halfX,
      depth: depth - 1, previous: &previous, into: &canvas)
  }

  /// Draws the part of a segment inside the view, with about one sample per pixel, so the line has no
  /// gaps. The segment is clipped first, as the engine clips its lines, so the sampling covers only the
  /// visible part.
  private static func drawSegment(
    _ from: FractalComplex, _ to: FractalComplex, into canvas: inout DensityCanvas
  ) {
    guard let clipped = canvas.clip(from, to) else { return }
    let (start, end) = clipped
    let length = hypot(end.re - start.re, end.im - start.im)
    let count = max(1, Int((length * canvas.pixelsPerUnit).rounded(.up)))
    for index in 0...count {
      let t = Double(index) / Double(count)
      canvas.add(
        real: start.re + (end.re - start.re) * t, imaginary: start.im + (end.im - start.im) * t)
    }
  }
}
