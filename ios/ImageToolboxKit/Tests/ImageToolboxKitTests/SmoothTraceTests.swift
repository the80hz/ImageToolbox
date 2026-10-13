import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Smooth tracing to SVG")
struct SmoothTraceTests {

  private typealias Point = SmoothTracer.Point
  private typealias Vertex = SmoothTracer.Vertex

  /// The four corners of a square with the given side, all marked as corners.
  private static func square(_ side: Double) -> [Vertex] {
    let corners: [Point] = [(0, 0), (side, 0), (side, side), (0, side)]
    return corners.map { Vertex(point: $0, isCorner: true) }
  }

  /// The loop of a diamond 8 pixels across. Its sides are staircases of 1-pixel steps.
  private static func diamondLoop() -> PixelTracer.Loop {
    let mask = (0..<64).map { index -> Bool in
      let x = index % 8
      let y = index / 8
      return abs(2 * x - 7) + abs(2 * y - 7) <= 8
    }
    return PixelTracer.contours(of: mask, width: 8, height: 8).first ?? []
  }

  private static func points(of vertices: [Vertex]) -> [Point] {
    vertices.map(\.point)
  }

  /// Area of a closed polygon by the shoelace formula.
  private static func area(_ points: [Point]) -> Double {
    var sum = 0.0
    for index in points.indices {
      let a = points[index]
      let b = points[(index + 1) % points.count]
      sum += a.x * b.y - b.x * a.y
    }
    return abs(sum) / 2
  }

  /// The mean of the points, which is the centre of a symmetric loop.
  private static func centroid(_ points: [Point]) -> Point {
    let count = Double(points.count)
    return (
      points.reduce(0) { $0 + $1.x } / count,
      points.reduce(0) { $0 + $1.y } / count
    )
  }

  private static func curveCount(_ outline: SmoothTracer.Outline) -> Int {
    outline.segments.filter { segment in
      if case .quad = segment { return true }
      return false
    }.count
  }

  /// Points along an outline: `steps` samples per curve, and the end of each line, including the
  /// closing line back to the start.
  private static func samples(of outline: SmoothTracer.Outline, steps: Int = 16) -> [Point] {
    var cursor = outline.start
    var result: [Point] = []
    for segment in outline.segments {
      switch segment {
      case .line(let end):
        result.append(end)
        cursor = end
      case .quad(let control, let end):
        for step in 1...steps {
          let t = Double(step) / Double(steps)
          let u = 1 - t
          result.append(
            (
              u * u * cursor.x + 2 * t * u * control.x + t * t * end.x,
              u * u * cursor.y + 2 * t * u * control.y + t * t * end.y
            ))
        }
        cursor = end
      }
    }
    result.append(outline.start)
    return result
  }

  /// Distance from `point` to the nearest edge of the closed polygon `loop`.
  private static func distance(from point: Point, toEdgesOf loop: [Point]) -> Double {
    var best = Double.infinity
    for index in loop.indices {
      let a = loop[index]
      let b = loop[(index + 1) % loop.count]
      let dx = b.x - a.x
      let dy = b.y - a.y
      let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy), 0), 1)
      best = min(best, hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy)))
    }
    return best
  }

  @Test(
    "an 8x8 square keeps its four corners, so its outline is straight and its area stays within 5%")
  func squareKeepsItsCorners() {
    for rounds in 0...2 {
      #expect(SmoothTracer.chaikin(Self.square(8), rounds: rounds).count == 4)
    }
    let smoothed = SmoothTracer.chaikin(Self.square(8), rounds: 2)
    #expect(smoothed.allSatisfy { $0.isCorner })
    let outline = SmoothTracer.outline(of: smoothed)
    #expect(Self.curveCount(outline) == 0)

    let shape = Self.points(of: smoothed)
    #expect(abs(Self.area(shape) - 64) / 64 <= 0.05)
    let centre = Self.centroid(shape)
    #expect(abs(centre.x - 4) < 1e-9 && abs(centre.y - 4) < 1e-9)
  }

  @Test("a vertex is a corner only when both of its edges are at least 2 pixels long")
  func cornerRule() {
    let block = PixelTracer.contours(of: [Bool](repeating: true, count: 16), width: 4, height: 4)
    #expect(SmoothTracer.vertices(of: block.first ?? []).allSatisfy { $0.isCorner })
    #expect(SmoothTracer.vertices(of: Self.diamondLoop()).allSatisfy { !$0.isCorner })
  }

  @Test("a stepped outline gets more points after two rounds, and its area stays within 5%")
  func steppedOutlineGrows() {
    let loop = Self.diamondLoop()
    let vertices = SmoothTracer.vertices(of: loop)
    let smoothed = SmoothTracer.chaikin(vertices, rounds: 2)
    #expect(smoothed.count > vertices.count)
    let before = Self.area(loop.map { (x: Double($0.x), y: Double($0.y)) })
    let after = Self.area(Self.points(of: smoothed))
    #expect(abs(after - before) / before <= 0.05)
  }

  @Test("a stepped outline is smoothed into curves, and deviates half a pixel or less on average")
  func steppedOutlineDeviation() {
    let loop = Self.diamondLoop()
    let original = loop.map { (x: Double($0.x), y: Double($0.y)) }
    let outline = SmoothTracer.outline(
      of: SmoothTracer.chaikin(SmoothTracer.vertices(of: loop), rounds: 2))
    #expect(Self.curveCount(outline) > 0)
    let samples = Self.samples(of: outline)
    let deviations = samples.map { Self.distance(from: $0, toEdgesOf: original) }
    #expect(deviations.reduce(0, +) / Double(deviations.count) <= 0.5)
  }

  @Test("a solid square becomes straight lines, with no curves")
  func svgSquareHasNoCurves() throws {
    let image = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 4, height: 4)
    let svg = SmoothTracer.svg(for: try #require(RasterImage(image)), colours: 1)
    #expect(svg.contains(" L"))
    #expect(!svg.contains(" Q"))
    #expect(svg.contains("fill=\"#ff0000\""))
  }

  @Test(
    "a stepped shape becomes quadratic curves, with the even-odd rule and the picture's viewBox")
  func svgCurvesAndFillRule() throws {
    let image = TestImages.image(width: 8, height: 8) { x, y in
      abs(2 * x - 7) + abs(2 * y - 7) <= 8
        ? RGBA(red: 255, green: 0, blue: 0) : RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    }
    let svg = SmoothTracer.svg(for: try #require(RasterImage(image)), colours: 1)
    #expect(svg.contains(" Q"))
    #expect(svg.contains(" Z\""))
    #expect(svg.contains("fill-rule=\"evenodd\""))
    #expect(svg.contains("viewBox=\"0 0 8 8\""))
  }

  @Test("two colours give two paths, one for each colour")
  func twoColoursTwoPaths() throws {
    let halves = TestImages.image(width: 8, height: 4) { x, _ in
      x < 4 ? RGBA(red: 255, green: 0, blue: 0) : RGBA(red: 0, green: 0, blue: 255)
    }
    let svg = SmoothTracer.svg(for: try #require(RasterImage(halves)), colours: 2)
    #expect(svg.contains("#ff0000"))
    #expect(svg.contains("#0000ff"))
    #expect(svg.components(separatedBy: "<path").count == 3)
  }

  @Test("a fully transparent picture gives an SVG without paths, and does not fail")
  func transparentPicture() {
    let raster = RasterImage(width: 4, height: 4, pixels: [UInt8](repeating: 0, count: 4 * 4 * 4))
    let svg = SmoothTracer.svg(for: raster, colours: 3)
    #expect(!svg.contains("<path"))
    #expect(svg.contains("viewBox=\"0 0 4 4\""))
  }

  /// The loop of a filled disc of the given radius, centred on a pixel corner of a square picture.
  private static func discLoop(radius: Int) -> PixelTracer.Loop {
    let side = 2 * radius + 4
    let centre = Double(side) / 2
    let mask = (0..<(side * side)).map { index -> Bool in
      let x = Double(index % side) + 0.5 - centre
      let y = Double(index / side) + 0.5 - centre
      return x * x + y * y <= Double(radius * radius)
    }
    return PixelTracer.contours(of: mask, width: side, height: side).first ?? []
  }

  @Test("simplifying a stepped disc drops most vertices, and every vertex stays within 1 pixel")
  func simplifiedDiscStaysWithinTolerance() {
    let vertices = SmoothTracer.vertices(of: Self.discLoop(radius: 20))
    let simplified = SmoothTracer.simplify(vertices, tolerance: 1)
    #expect(simplified.count >= 3)
    #expect(simplified.count * 3 < vertices.count)
    let polygon = Self.points(of: simplified)
    for vertex in vertices {
      #expect(Self.distance(from: vertex.point, toEdgesOf: polygon) <= 1 + 1e-9)
    }
  }

  @Test("simplifying keeps the four corners of a block, and drops nothing else")
  func simplifiedBlockKeepsCorners() {
    let mask = [Bool](repeating: true, count: 12 * 6)
    let loop = PixelTracer.contours(of: mask, width: 12, height: 6).first ?? []
    let simplified = SmoothTracer.simplify(SmoothTracer.vertices(of: loop), tolerance: 1)
    #expect(simplified.count == 4)
    #expect(simplified.allSatisfy { $0.isCorner })
  }

  @Test("a tolerance of zero keeps every vertex")
  func zeroToleranceKeepsEverything() {
    let vertices = SmoothTracer.vertices(of: Self.discLoop(radius: 8))
    #expect(SmoothTracer.simplify(vertices, tolerance: 0).count == vertices.count)
  }

  @Test("a looser tolerance writes fewer curves, and a palette colour without pixels gets no path")
  func svgToleranceAndPalette() throws {
    let disc = TestImages.image(width: 44, height: 44) { x, y in
      let dx = Double(x) + 0.5 - 22
      let dy = Double(y) + 0.5 - 22
      return dx * dx + dy * dy <= 400
        ? RGBA(red: 255, green: 0, blue: 0) : RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    }
    let raster = try #require(RasterImage(disc))
    let red = RGBA(red: 255, green: 0, blue: 0)
    let blue = RGBA(red: 0, green: 0, blue: 255)
    func curves(_ svg: String) -> Int { svg.components(separatedBy: " Q").count - 1 }

    let exact = SmoothTracer.svg(for: raster, palette: [red, blue], iterations: 2, tolerance: 0)
    let loose = SmoothTracer.svg(for: raster, palette: [red, blue], iterations: 2, tolerance: 1)
    #expect(curves(loose) * 2 < curves(exact))
    #expect(loose.contains("fill=\"#ff0000\""))
    #expect(!loose.contains("#0000ff"))
  }
}
