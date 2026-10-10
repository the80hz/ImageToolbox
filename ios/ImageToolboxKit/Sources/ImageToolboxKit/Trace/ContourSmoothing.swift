import Foundation

/// Traces a picture into SVG with smooth outlines. `PixelTracer` gives the pixel-edge loops of each
/// colour. Each loop is smoothed by Chaikin corner cutting, except at its real corners, and written as
/// quadratic Bézier curves.
///
/// Corners: a vertex is a corner when both edges meeting at it are at least `minimumCornerEdge`
/// pixels long. Such a vertex is a real corner of the shape, such as a corner of a rectangle, so it
/// is kept sharp and never cut. Every other vertex belongs to a staircase of 1-pixel steps, and is cut.
///
/// Curves: the smooth points are control points of a uniform quadratic B-spline. The curve runs
/// through the midpoints of consecutive smooth points (`Q` with control `P[i]`). Where it meets a
/// corner, it runs straight to that corner, so the corner stays sharp. Each curve lies inside the
/// convex hull of its control points, so it never leaves the outline it came from.
public enum SmoothTracer {

  /// A point on the picture's grid. Y grows downwards, as in SVG.
  typealias Point = (x: Double, y: Double)

  /// Both edges at a vertex must be at least this long, in pixels, for the vertex to be a corner.
  static let minimumCornerEdge = 2.0

  /// A point of a loop. A corner is kept as it is, and the outline passes through it.
  struct Vertex {
    var point: Point
    var isCorner: Bool
  }

  /// One step of an outline after its start point: a straight line to a point, or a quadratic curve
  /// with a control point and an end point.
  enum Segment {
    case line(Point)
    case quad(Point, Point)
  }

  struct Outline {
    var start: Point
    var segments: [Segment]
  }

  /// The tolerance, in pixels, used when none is given. See `simplify`. At 0.5 the curves stay within
  /// about 0.97 of potrace's overlap on simple pictures, with 2 to 4 times its vertices. At 1.0 the
  /// overlap falls below 0.97, and at 0 there are 90 to 150 times as many vertices.
  public static let defaultTolerance = 0.5

  /// Reduces the picture to `colours` colours and writes one filled path per colour.
  /// See `svg(for:palette:iterations:tolerance:)`.
  public static func svg(
    for raster: RasterImage, colours: Int, iterations: Int = 2,
    tolerance: Double = SmoothTracer.defaultTolerance
  ) -> String {
    svg(
      for: raster, palette: PaletteExtractor.dominantColors(raster, count: colours),
      iterations: iterations, tolerance: tolerance)
  }

  /// Writes one filled path per palette colour. Each outline gets `iterations` rounds of Chaikin corner
  /// cutting, clamped to 0...4, then `simplify` with `tolerance`; a tolerance of 0 keeps every vertex.
  /// The viewBox and the even-odd fill rule are the same as in `PixelTracer`.
  public static func svg(
    for raster: RasterImage, palette: [RGBA], iterations: Int = 2,
    tolerance: Double = SmoothTracer.defaultTolerance
  ) -> String {
    let rounds = min(max(iterations, 0), 4)
    let masks = colourMasks(of: raster, palette: palette)

    var svg =
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(raster.width)\" "
      + "height=\"\(raster.height)\" viewBox=\"0 0 \(raster.width) \(raster.height)\">\n"
    for (colour, mask) in zip(palette, masks) {
      let loops = PixelTracer.contours(of: mask, width: raster.width, height: raster.height)
      guard !loops.isEmpty else { continue }
      svg += "  <path fill=\"\(hex(colour))\" fill-rule=\"evenodd\" d=\""
      svg += loops.map { loop in
        let smooth = chaikin(vertices(of: loop), rounds: rounds)
        return pathData(for: outline(of: simplify(smooth, tolerance: tolerance)))
      }.joined(separator: " ")
      svg += "\"/>\n"
    }
    svg += "</svg>\n"
    return svg
  }

  /// Marks the corners of a loop. Edge lengths are measured on the pixel grid.
  static func vertices(of loop: PixelTracer.Loop) -> [Vertex] {
    let count = loop.count
    return loop.indices.map { index in
      let previous = loop[(index + count - 1) % count]
      let current = loop[index]
      let next = loop[(index + 1) % count]
      let incoming = hypot(Double(current.x - previous.x), Double(current.y - previous.y))
      let outgoing = hypot(Double(next.x - current.x), Double(next.y - current.y))
      return Vertex(
        point: (Double(current.x), Double(current.y)),
        isCorner: incoming >= minimumCornerEdge && outgoing >= minimumCornerEdge)
    }
  }

  /// `vertices` after `rounds` of corner cutting. A smooth vertex is replaced by two points, at 1/4 and
  /// 3/4 of the way along each of its two edges, so its corner is cut and the new points stay on the
  /// old edges. A corner is kept as it is.
  static func chaikin(_ vertices: [Vertex], rounds: Int) -> [Vertex] {
    var current = vertices
    for _ in 0..<max(rounds, 0) {
      let count = current.count
      guard count > 0 else { break }
      var next: [Vertex] = []
      next.reserveCapacity(count * 2)
      for index in current.indices {
        let vertex = current[index]
        if vertex.isCorner {
          next.append(vertex)
          continue
        }
        let previous = current[(index + count - 1) % count].point
        let following = current[(index + 1) % count].point
        next.append(Vertex(point: between(previous, vertex.point, 0.75), isCorner: false))
        next.append(Vertex(point: between(vertex.point, following, 0.25), isCorner: false))
      }
      current = next
    }
    return current
  }

  /// Douglas-Peucker simplification of a closed loop. A vertex is dropped when it lies within `tolerance`
  /// pixels of the chord between the kept vertices around it, so a staircase becomes a few long runs.
  /// Corners are fixed anchors. A loop without corners is cut at its first vertex and at the vertex
  /// farthest from it. The result keeps at least three vertices, otherwise the input is returned.
  static func simplify(_ vertices: [Vertex], tolerance: Double) -> [Vertex] {
    let count = vertices.count
    guard count > 3, tolerance > 0 else { return vertices }

    var anchors = vertices.indices.filter { vertices[$0].isCorner }
    if anchors.isEmpty {
      let origin = vertices[0].point
      let far =
        vertices.indices.max { a, b in
          distance(vertices[a].point, origin) < distance(vertices[b].point, origin)
        } ?? 0
      anchors = Array(Set([0, far])).sorted()
    }

    var keep = [Bool](repeating: false, count: count)
    for anchor in anchors { keep[anchor] = true }
    for (position, start) in anchors.enumerated() {
      let end = anchors[(position + 1) % anchors.count]
      var length = (end - start + count) % count
      if length == 0 { length = count }
      let run = (0...length).map { (start + $0) % count }
      keepFarthest(run, of: vertices, tolerance: tolerance, keep: &keep)
    }

    let result = vertices.indices.filter { keep[$0] }.map { vertices[$0] }
    return result.count >= 3 ? result : vertices
  }

  /// The outline through the vertices, with the curve choice described above. A closed outline starts
  /// at its first vertex if that is a corner. Otherwise it starts at the midpoint of the closing edge,
  /// which lies on the curve, because a smooth point is a control point and is not on the curve.
  static func outline(of vertices: [Vertex]) -> Outline {
    let count = vertices.count
    guard count > 0 else { return Outline(start: (0, 0), segments: []) }
    let first = vertices[0]
    let start = first.isCorner ? first.point : midpoint(vertices[count - 1].point, first.point)

    var segments: [Segment] = []
    for index in vertices.indices {
      let vertex = vertices[index]
      if vertex.isCorner {
        if index > 0 { segments.append(.line(vertex.point)) }
        continue
      }
      let previous = vertices[(index + count - 1) % count]
      let next = vertices[(index + 1) % count]
      // After a corner the outline is at the corner, so it runs straight to the entry midpoint.
      // The entry midpoint lies on the edge that leads into this smooth point.
      if index > 0 && previous.isCorner {
        segments.append(.line(midpoint(previous.point, vertex.point)))
      }
      segments.append(.quad(vertex.point, midpoint(vertex.point, next.point)))
    }
    return Outline(start: start, segments: segments)
  }

  /// The closed SVG path of an outline, closed with `Z`.
  static func pathData(for outline: Outline) -> String {
    var text = "M\(number(outline.start.x)) \(number(outline.start.y))"
    for segment in outline.segments {
      switch segment {
      case .line(let end):
        text += " L\(number(end.x)) \(number(end.y))"
      case .quad(let control, let end):
        text += " Q\(number(control.x)) \(number(control.y)) \(number(end.x)) \(number(end.y))"
      }
    }
    return text + " Z"
  }

  // MARK: - Helpers

  private static func colourMasks(of raster: RasterImage, palette: [RGBA]) -> [[Bool]] {
    var masks = [[Bool]](
      repeating: [Bool](repeating: false, count: raster.width * raster.height),
      count: palette.count)
    let straight = raster.straightRGBA()
    for index in 0..<(raster.width * raster.height) where raster.pixels[index * 4 + 3] > 0 {
      let nearest = nearestColour(
        red: straight[index * 4], green: straight[index * 4 + 1], blue: straight[index * 4 + 2],
        palette: palette)
      masks[nearest][index] = true
    }
    return masks
  }

  /// The point the given fraction of the way from `a` to `b`.
  private static func between(_ a: Point, _ b: Point, _ fraction: Double) -> Point {
    (a.x + (b.x - a.x) * fraction, a.y + (b.y - a.y) * fraction)
  }

  private static func midpoint(_ a: Point, _ b: Point) -> Point {
    ((a.x + b.x) / 2, (a.y + b.y) / 2)
  }

  private static func distance(_ a: Point, _ b: Point) -> Double {
    hypot(a.x - b.x, a.y - b.y)
  }

  /// Distance from `p` to the segment from `a` to `b`. A zero-length segment is a point.
  private static func segmentDistance(_ p: Point, _ a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return distance(p, a) }
    let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
    return distance(p, (a.x + t * dx, a.y + t * dy))
  }

  /// Douglas-Peucker over `run`, whose first and last entries are kept vertices. Marks in `keep` the
  /// vertices that lie farther than `tolerance` from the chord of their span.
  private static func keepFarthest(
    _ run: [Int], of vertices: [Vertex], tolerance: Double, keep: inout [Bool]
  ) {
    var spans: [(first: Int, last: Int)] = [(0, run.count - 1)]
    while let span = spans.popLast() {
      guard span.last > span.first + 1 else { continue }
      let a = vertices[run[span.first]].point
      let b = vertices[run[span.last]].point
      var worst = span.first + 1
      var worstDistance = -1.0
      for index in (span.first + 1)..<span.last {
        let d = segmentDistance(vertices[run[index]].point, a, b)
        if d > worstDistance {
          worst = index
          worstDistance = d
        }
      }
      if worstDistance > tolerance {
        keep[run[worst]] = true
        spans.append((span.first, worst))
        spans.append((worst, span.last))
      }
    }
  }

  private static func number(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static func nearestColour(red: UInt8, green: UInt8, blue: UInt8, palette: [RGBA]) -> Int {
    var best = 0
    var bestDistance = Int.max
    for (index, colour) in palette.enumerated() {
      let dr = Int(red) - Int(colour.red)
      let dg = Int(green) - Int(colour.green)
      let db = Int(blue) - Int(colour.blue)
      let distance = dr * dr + dg * dg + db * db
      if distance < bestDistance {
        bestDistance = distance
        best = index
      }
    }
    return best
  }

  private static func hex(_ colour: RGBA) -> String {
    let parts = [colour.red, colour.green, colour.blue].map { String(format: "%02x", $0) }
    return "#" + parts.joined()
  }
}
