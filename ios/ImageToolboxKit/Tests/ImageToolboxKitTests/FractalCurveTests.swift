import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Fractal recursive shapes: the H-tree, the Hilbert curve and the clipped lines")
struct FractalCurveTests {

  /// A square canvas of 220 pixels over the view of span 2.2 about the origin. One unit is 100 pixels, so
  /// the point (x, y) lies in column (x + 1.1) * 100 and row (1.1 - y) * 100.
  private static func canvas(kind: EscapeTimeFractal.Kind = .hTree) -> DensityCanvas {
    DensityCanvas(
      width: 220, height: 220,
      settings: EscapeTimeFractal.Settings(
        kind: kind, centreReal: 0, centreImaginary: 0, span: 2.2))
  }

  /// Whether the pixel that holds the point (x, y) has a hit.
  private static func isLit(_ canvas: DensityCanvas, _ x: Double, _ y: Double) -> Bool {
    let column = Int(((x + 1.1) * 100).rounded())
    let row = Int(((1.1 - y) * 100).rounded())
    return canvas.hits[row * canvas.width + column] > 0
  }

  @Test("the H-tree's root is the segment of half-length 0.72 through the origin")
  func hTreeRoot() {
    var canvas = Self.canvas()
    FractalIFS.plotHTree(into: &canvas, depth: 1)
    #expect(Self.isLit(canvas, 0, 0))
    #expect(Self.isLit(canvas, 0.7, 0))
    #expect(!Self.isLit(canvas, 0.9, 0), "the root ends at 0.72")
    // At depth 1 nothing is drawn above the root.
    #expect(!Self.isLit(canvas, 0, 0.4))
  }

  @Test(
    "the H-tree's stubs stand at the ends of the root, with half-length 0.72 / sqrt 2, at depth 2")
  func hTreeStubs() {
    var canvas = Self.canvas()
    FractalIFS.plotHTree(into: &canvas, depth: 2)
    // The stubs are vertical segments at x = +/-0.72 that run from y = -0.509 to 0.509.
    #expect(Self.isLit(canvas, 0.72, 0.4))
    #expect(Self.isLit(canvas, -0.72, -0.4))
    // The grandchildren are not drawn yet, so the point beyond the stub's end is dark.
    #expect(!Self.isLit(canvas, 1.0, 0.509))
  }

  @Test("the H-tree's grandchildren run from x = 0.36 to 1.08 at depth 3")
  func hTreeGrandchildren() {
    var canvas = Self.canvas()
    FractalIFS.plotHTree(into: &canvas, depth: 3)
    // A grandchild is centred at (0.72, 0.72 / sqrt 2) with half-length 0.36.
    let height = 0.72 / 2.0.squareRoot()
    #expect(Self.isLit(canvas, 0.4, height))
    #expect(Self.isLit(canvas, 1.0, height))
    #expect(Self.isLit(canvas, 1.0, -height))
    #expect(!Self.isLit(canvas, 0.2, height))
  }

  @Test(
    "the H-tree's tips reach 2 x 0.72 = 1.44, past the default view's 1.1, as the engine draws it")
  func hTreeReach() {
    // A view of span 4.4 over 440 pixels keeps the scale at 100 pixels per unit.
    var canvas = DensityCanvas(
      width: 440, height: 440,
      settings: EscapeTimeFractal.Settings(
        kind: .hTree, centreReal: 0, centreImaginary: 0, span: 4.4))
    FractalIFS.plotHTree(into: &canvas)
    var farthest = 0.0
    for row in 0..<canvas.height {
      for column in 0..<canvas.width where canvas.hits[row * canvas.width + column] > 0 {
        farthest = max(farthest, abs((Double(column) + 0.5) / 100 - 2.2))
      }
    }
    #expect(farthest > 1.3 && farthest < 1.5, "reaches \(farthest)")
  }

  @Test("the H-tree is drawn the same at any iteration budget, since the engine ignores it")
  func hTreeIgnoresIterations() throws {
    let low = EscapeTimeFractal.Settings(
      kind: .hTree, centreReal: 0, centreImaginary: 0, span: 2.2, maxIterations: 16)
    let high = EscapeTimeFractal.Settings(
      kind: .hTree, centreReal: 0, centreImaginary: 0, span: 2.2, maxIterations: 2000)
    let first = try #require(EscapeTimeFractal.render(low, width: 96, height: 96))
    let second = try #require(EscapeTimeFractal.render(high, width: 96, height: 96))
    #expect(first.pixels == second.pixels)
  }

  @Test("the order-1 Hilbert curve joins the four quarter centres in a U")
  func hilbertOrderOne() {
    var canvas = Self.canvas(kind: .hilbertCurve)
    FractalIFS.plotHilbertCurve(into: &canvas, order: 1)
    // The centres are (-0.45, -0.45), (0.45, -0.45), (0.45, 0.45) and (-0.45, 0.45), so the path
    // is the bottom, right and top sides of the square of half-side 0.45.
    #expect(Self.isLit(canvas, 0, -0.45))
    #expect(Self.isLit(canvas, 0.45, 0))
    #expect(Self.isLit(canvas, 0, 0.45))
    // The centre and the open left side are not on the curve.
    #expect(!Self.isLit(canvas, 0, 0))
    #expect(!Self.isLit(canvas, -0.45, 0))
  }

  @Test("the Hilbert curve of order 32 keeps visible structure at deep zoom")
  func hilbertDeepZoom() {
    let settings = EscapeTimeFractal.Settings(
      kind: .hilbertCurve, centreReal: 0, centreImaginary: 0, span: 2.2 / pow(2, 20))
    var canvas = DensityCanvas(width: 96, height: 96, settings: settings)
    FractalIFS.plotHilbertCurve(into: &canvas)
    let occupied = canvas.hits.filter { $0 > 0 }.count
    #expect(occupied > 96, "occupied pixels: \(occupied)")
  }

  @Test("the H-tree and the Hilbert curve render lit pictures through the public renderer")
  func rendersLit() throws {
    for kind in [EscapeTimeFractal.Kind.hTree, .hilbertCurve] {
      let view = kind.defaultView
      let settings = EscapeTimeFractal.Settings(
        kind: kind, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
        span: view.span)
      let image = try #require(EscapeTimeFractal.render(settings, width: 64, height: 64))
      let lit = stride(from: 0, to: image.pixels.count, by: 4).filter {
        image.pixels[$0] | image.pixels[$0 + 1] | image.pixels[$0 + 2] != 0
      }.count
      #expect(lit > 50, "\(kind) draws \(lit) pixels")
    }
  }

  @Test("a segment is clipped to the view, and a segment outside the view is dropped")
  func clipping() throws {
    let canvas = Self.canvas()
    let across = try #require(canvas.clip(FractalComplex(-2, 0), FractalComplex(2, 0)))
    #expect(abs(across.0.re + 1.1) < 1e-12 && across.0.im == 0)
    #expect(abs(across.1.re - 1.1) < 1e-12 && across.1.im == 0)
    let diagonal = try #require(canvas.clip(FractalComplex(-2, -2), FractalComplex(2, 2)))
    #expect(abs(diagonal.0.re + 1.1) < 1e-12 && abs(diagonal.0.im + 1.1) < 1e-12)
    #expect(abs(diagonal.1.re - 1.1) < 1e-12 && abs(diagonal.1.im - 1.1) < 1e-12)
    #expect(canvas.clip(FractalComplex(5, 5), FractalComplex(6, 6)) == nil)
    // A segment inside the view keeps its ends.
    let inside = try #require(canvas.clip(FractalComplex(0.1, 0.2), FractalComplex(0.5, -0.4)))
    #expect(abs(inside.0.re - 0.1) < 1e-12 && abs(inside.0.im - 0.2) < 1e-12)
    #expect(abs(inside.1.re - 0.5) < 1e-12 && abs(inside.1.im + 0.4) < 1e-12)
  }
}
