import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

/// Builds a small raster from code, so the tests need no binary fixtures.
private func makeRaster(
  width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> RGBA
) throws -> RasterImage {
  try #require(RasterImage(TestImages.image(width: width, height: height, pixel: pixel)))
}

@Suite("Shapes drawn with the brush")
struct ShapeRendererTests {

  @Test("an outlined rectangle covers its corners and not its centre")
  func outlinedRectangle() {
    var canvas = BrushCanvas(width: 60, height: 50)
    ShapeRenderer.draw(
      .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 40), filled: false,
      brush: Brush(radius: 2, hardness: 1), onto: &canvas)
    #expect(canvas.coverage[10 * 60 + 10] > 0.99)
    #expect(canvas.coverage[39 * 60 + 49] > 0.99)
    #expect(canvas.coverage[25 * 60 + 30] == 0)
  }

  @Test("a filled rectangle covers its centre")
  func filledRectangle() {
    var canvas = BrushCanvas(width: 60, height: 50)
    ShapeRenderer.draw(
      .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 40), filled: true,
      brush: Brush(radius: 2, hardness: 1), onto: &canvas)
    #expect(canvas.coverage[25 * 60 + 30] > 0.99)
    #expect(canvas.coverage[5 * 60 + 5] == 0)
  }

  @Test("a filled ellipse covers its centre and not its corner")
  func filledEllipse() {
    var canvas = BrushCanvas(width: 60, height: 50)
    ShapeRenderer.draw(
      .ellipse, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 40), filled: true,
      brush: Brush(radius: 2, hardness: 1), onto: &canvas)
    #expect(canvas.coverage[25 * 60 + 30] > 0.99)
    #expect(canvas.coverage[11 * 60 + 11] == 0)
  }

  @Test("a diagonal line covers a point on it and not one off it")
  func diagonalLine() {
    var canvas = BrushCanvas(width: 30, height: 30)
    ShapeRenderer.draw(
      .line, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 20), filled: false,
      brush: Brush(radius: 1, hardness: 1), onto: &canvas)
    #expect(canvas.coverage[10 * 30 + 10] > 0.99)
    #expect(canvas.coverage[5 * 30 + 20] == 0)
  }
}

@Suite("Lasso selections")
struct LassoTests {

  private let triangle = [CGPoint(x: 10, y: 5), CGPoint(x: 30, y: 5), CGPoint(x: 20, y: 35)]

  @Test("a triangle mask contains its centre and not the image corners")
  func triangleMask() {
    let mask = LassoMask(polygon: triangle).mask(width: 40, height: 40)
    #expect(mask.count == 40 * 40)
    #expect(mask[15 * 40 + 20])
    #expect(!mask[0])
    #expect(!mask[39 * 40])
  }

  @Test("cutting keeps the inside of the polygon and makes the rest transparent")
  func cutOutside() throws {
    let picture = try makeRaster(width: 40, height: 40) { _, _ in
      RGBA(red: 200, green: 100, blue: 50)
    }
    let cut = LassoMask.cut(picture, polygon: triangle)
    #expect(cut.pixel(x: 20, y: 15) == RGBA(red: 200, green: 100, blue: 50))
    #expect(cut.pixel(x: 0, y: 0).alpha == 0)
  }

  @Test("filling recolours the inside of the polygon and leaves the outside alone")
  func fillInside() throws {
    let picture = try makeRaster(width: 40, height: 40) { _, _ in
      RGBA(red: 50, green: 50, blue: 50)
    }
    let filled = LassoMask.fill(picture, polygon: triangle, with: (255, 0, 0))
    #expect(filled.pixel(x: 20, y: 15) == RGBA(red: 255, green: 0, blue: 0))
    #expect(filled.pixel(x: 0, y: 0) == RGBA(red: 50, green: 50, blue: 50))
  }
}

@Suite("Spot healing")
struct SpotHealingTests {

  @Test("a dark spot on a light background turns light")
  func darkSpot() throws {
    let picture = try makeRaster(width: 21, height: 21) { x, y in
      x == 10 && y == 10
        ? RGBA(red: 20, green: 20, blue: 20) : RGBA(red: 200, green: 200, blue: 200)
    }
    let healed = SpotHealing.heal(picture, at: CGPoint(x: 10.5, y: 10.5), radius: 2)
    #expect(picture.pixel(x: 10, y: 10).red == 20)
    #expect(healed.pixel(x: 10, y: 10).red == 200)
    #expect(healed.pixel(x: 0, y: 0) == RGBA(red: 200, green: 200, blue: 200))
  }
}

@Suite("Warp brush")
struct WarpBrushTests {

  @Test("pushing moves a bright stripe along the direction of the stroke")
  func pushMovesStripe() throws {
    let picture = try makeRaster(width: 40, height: 20) { x, _ in
      (19...21).contains(x)
        ? RGBA(red: 255, green: 255, blue: 255) : RGBA(red: 0, green: 0, blue: 0)
    }
    let warped = WarpBrush.push(
      picture, at: CGPoint(x: 20.5, y: 10.5), direction: CGPoint(x: 6, y: 0), radius: 10,
      strength: 1)
    // The stripe moved right: the pixel to its right is now bright, the one to its left is not.
    #expect(warped.pixel(x: 23, y: 10).red > 200)
    #expect(warped.pixel(x: 17, y: 10).red < 50)
    #expect(warped.pixel(x: 0, y: 0) == picture.pixel(x: 0, y: 0))
  }
}
