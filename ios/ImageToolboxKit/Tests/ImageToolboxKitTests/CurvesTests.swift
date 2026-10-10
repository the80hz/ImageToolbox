import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Tone curves, rendering, histogram and waveform")
struct CurvesTests {

  @Test("the identity curve maps every byte to itself")
  func identityTable() {
    let table = ToneCurve.identity.lookupTable()
    #expect(table.count == 256)
    #expect(table == (0...255).map { UInt8($0) })
  }

  @Test("the curve starts and ends at the heights of its first and last points")
  func endpoints() {
    let curve = ToneCurve(points: [CurvePoint(x: 0, y: 0.2), CurvePoint(x: 1, y: 0.9)])
    let table = curve.lookupTable()
    #expect(table[0] == 51)
    #expect(table[255] == 230)
  }

  @Test("the curve passes through its control points")
  func passesThroughPoints() {
    let curve = ToneCurve(points: [
      CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.8), CurvePoint(x: 1, y: 1),
    ])
    #expect(abs(curve.value(at: 0.5) - 0.8) < 1e-9)
  }

  @Test("a monotone curve never overshoots between points")
  func noOvershoot() {
    let curve = ToneCurve(points: [
      CurvePoint(x: 0, y: 0), CurvePoint(x: 0.4, y: 0.8),
      CurvePoint(x: 0.6, y: 0.8), CurvePoint(x: 1, y: 1),
    ])
    let plateau = (0...40).map { curve.value(at: 0.4 + Double($0) * 0.005) }
    #expect(plateau.allSatisfy { abs($0 - 0.8) < 1e-9 })
  }

  @Test("a curve through increasing points is non-decreasing in every byte")
  func monotoneTable() {
    let curve = ToneCurve(points: [
      CurvePoint(x: 0, y: 0), CurvePoint(x: 0.2, y: 0.05), CurvePoint(x: 0.5, y: 0.9),
      CurvePoint(x: 0.55, y: 0.91), CurvePoint(x: 1, y: 1),
    ])
    let table = curve.lookupTable()
    #expect(zip(table, table.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test("unsorted, out-of-range and duplicate points are normalised")
  func normalisation() {
    let curve = ToneCurve(points: [
      CurvePoint(x: 0.7, y: 1.4), CurvePoint(x: 0.3, y: -0.2), CurvePoint(x: 0.3, y: 0.25),
    ])
    #expect(curve.points.map(\.x) == [0, 0.3, 0.7, 1])
    #expect(curve.points.last?.y == 1)
    #expect(curve.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
  }

  @Test("moving a point keeps it between its neighbours and endpoints on their edges")
  func movingPoint() {
    let curve = ToneCurve(points: [
      CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.5), CurvePoint(x: 1, y: 1),
    ])
    let dragged = curve.movingPoint(at: 1, to: CurvePoint(x: 2, y: 0.7))
    #expect(dragged.points[1].x == 1 - ToneCurve.minimumGap)
    #expect(dragged.points[1].y == 0.7)

    let edge = curve.movingPoint(at: 0, to: CurvePoint(x: 0.4, y: 0.3))
    #expect(edge.points[0].x == 0)
    #expect(edge.points[0].y == 0.3)
  }

  @Test("adding and removing points respects the gap and keeps the endpoints")
  func addAndRemove() {
    let curve = ToneCurve.identity.addingPoint(x: 0.5, y: 0.8)
    #expect(curve.points.count == 3)
    #expect(curve.addingPoint(x: 0.505, y: 0.1) == curve)
    #expect(curve.removingPoint(at: 0) == curve)
    #expect(curve.removingPoint(at: 2) == curve)
    #expect(curve.removingPoint(at: 1).points.count == 2)
  }

  @Test("the master curve applies after each channel curve")
  func masterAfterChannel() {
    let invert = ToneCurve(points: [CurvePoint(x: 0, y: 1), CurvePoint(x: 1, y: 0)])
    let halfRed = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.5)])
    let tables = CurveSet(master: invert, red: halfRed).lookupTables()
    // Red: 200 becomes 100 through the channel curve, then 155 through the master curve.
    #expect(tables.red[200] == 155)
    // Green has only the master curve: 200 becomes 55.
    #expect(tables.green[200] == 55)
  }

  @Test("rendering changes colour on straight values and keeps alpha")
  func rendererKeepsAlpha() throws {
    let source = TestImages.image(width: 4, height: 4) { _, _ in
      RGBA(red: 100, green: 50, blue: 25, alpha: 128)
    }
    let invert = ToneCurve(points: [CurvePoint(x: 0, y: 1), CurvePoint(x: 1, y: 0)])
    let output = try #require(
      CurveRenderer.apply(source, curves: CurveSet(master: invert)))
    let raster = try #require(RasterImage(output))
    let pixel = raster.pixel(x: 1, y: 1)
    #expect(pixel.alpha == 128)
    // Straight colour of the source is about (199, 99, 50), so its inverse is about (56, 156, 205).
    #expect(abs(Int(pixel.red) - 56) <= 3)
    #expect(abs(Int(pixel.green) - 156) <= 3)
    #expect(abs(Int(pixel.blue) - 205) <= 3)
  }

  @Test("histogram counts each channel and luminance level of the picture")
  func histogram() throws {
    let solid = TestImages.solid(RGBA(red: 40, green: 160, blue: 90), width: 4, height: 4)
    let histogram = try #require(ImageHistogram(solid))
    #expect(histogram.red[40] == 16)
    #expect(histogram.green[160] == 16)
    #expect(histogram.blue[90] == 16)
    // Rec. 601 luma of (40, 160, 90) is 116.14, so it falls in bin 116.
    #expect(histogram.luminance[116] == 16)
    #expect(histogram.luminance.reduce(0, +) == 16)
  }

  @Test("transparent pixels are left out of the histogram")
  func histogramSkipsTransparent() throws {
    let image = TestImages.image(width: 2, height: 2) { x, _ in
      x == 0 ? RGBA(red: 0, green: 0, blue: 0, alpha: 0) : RGBA(red: 255, green: 255, blue: 255)
    }
    let histogram = try #require(ImageHistogram(image))
    #expect(histogram.luminance.reduce(0, +) == 2)
    #expect(histogram.luminance[255] == 2)
  }
}
