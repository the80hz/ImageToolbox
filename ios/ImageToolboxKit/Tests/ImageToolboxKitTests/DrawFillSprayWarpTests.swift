import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

/// Opaque pictures built from code, where the premultiplied and straight values are the same.
private func opaqueRaster(
  width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> RGBA
) -> RasterImage {
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  for y in 0..<height {
    for x in 0..<width {
      let colour = pixel(x, y)
      let index = (y * width + x) * 4
      pixels[index] = colour.red
      pixels[index + 1] = colour.green
      pixels[index + 2] = colour.blue
      pixels[index + 3] = colour.alpha
    }
  }
  return RasterImage(width: width, height: height, pixels: pixels)
}

@Suite("Draw paint bucket, spray and warp modes")
struct DrawFillSprayWarpTests {

  // MARK: - Paint bucket

  @Test("the bucket fills the area inside a wall and stops at the wall")
  func bucketStopsAtWall() {
    let room = opaqueRaster(width: 20, height: 10) { x, _ in
      x == 10 ? RGBA(red: 0, green: 0, blue: 0) : RGBA(red: 255, green: 255, blue: 255)
    }
    let filled = FloodFill.fill(
      room, at: CGPoint(x: 2, y: 2), tolerance: 0, colour: (255, 0, 0))
    #expect(filled.pixel(x: 5, y: 5) == RGBA(red: 255, green: 0, blue: 0))
    #expect(filled.pixel(x: 15, y: 5) == RGBA(red: 255, green: 255, blue: 255))
    #expect(filled.pixel(x: 10, y: 5) == RGBA(red: 0, green: 0, blue: 0))
  }

  @Test("tolerance decides whether a slightly different neighbour joins the fill")
  func bucketTolerance() {
    let row = opaqueRaster(width: 20, height: 1) { x, _ in
      let value: UInt8 = x < 10 ? 100 : 110
      return RGBA(red: value, green: value, blue: value)
    }
    let strict = FloodFill.fill(
      row, at: CGPoint(x: 0, y: 0), tolerance: 0.02, colour: (255, 0, 0))
    #expect(strict.pixel(x: 9, y: 0).red == 255)
    #expect(strict.pixel(x: 10, y: 0).red == 110)

    let loose = FloodFill.fill(
      row, at: CGPoint(x: 0, y: 0), tolerance: 0.05, colour: (255, 0, 0))
    #expect(loose.pixel(x: 15, y: 0).red == 255)
  }

  @Test("a point outside the picture changes nothing")
  func bucketOutside() {
    let picture = opaqueRaster(width: 4, height: 4) { _, _ in RGBA(red: 9, green: 9, blue: 9) }
    let same = FloodFill.fill(
      picture, at: CGPoint(x: -1, y: 0), tolerance: 1, colour: (255, 0, 0))
    #expect(same.pixels == picture.pixels)
  }

  // MARK: - Spray

  @Test("the same seed scatters the same dots, and another seed scatters others")
  func sprayIsDeterministic() {
    let points = [CGPoint(x: 30, y: 30), CGPoint(x: 40, y: 32)]
    var first = BrushCanvas(width: 80, height: 60)
    var again = BrushCanvas(width: 80, height: 60)
    var other = BrushCanvas(width: 80, height: 60)
    Spray.draw(
      points: points, radius: 8, density: 20, dotSize: 2, square: false, seed: 7, onto: &first)
    Spray.draw(
      points: points, radius: 8, density: 20, dotSize: 2, square: false, seed: 7, onto: &again)
    Spray.draw(
      points: points, radius: 8, density: 20, dotSize: 2, square: false, seed: 8, onto: &other)
    #expect(first.coverage == again.coverage)
    #expect(first.coverage != other.coverage)
  }

  @Test("spray dots stay inside the spray radius of their point")
  func sprayStaysInRadius() {
    var canvas = BrushCanvas(width: 100, height: 100)
    let centre = CGPoint(x: 50, y: 50)
    Spray.draw(
      points: [centre], radius: 5, density: 60, dotSize: 2, square: false, seed: 3, onto: &canvas)
    var painted = 0
    for index in canvas.coverage.indices where canvas.coverage[index] > 0 {
      painted += 1
      let x = Double(index % 100) + 0.5
      let y = Double(index / 100) + 0.5
      #expect(hypot(x - 50, y - 50) <= 5 + 1.5)
    }
    #expect(painted > 0)
  }

  @Test("square spray dots are solid squares of the dot size")
  func squareSprayDots() {
    var canvas = BrushCanvas(width: 40, height: 40)
    Spray.draw(
      points: [CGPoint(x: 20, y: 20)], radius: 3, density: 1, dotSize: 4, square: true, seed: 1,
      onto: &canvas)
    let covered = canvas.coverage.filter { $0 > 0 }
    #expect(covered.allSatisfy { $0 == 1 })
    #expect((9...25).contains(covered.count))
  }

  @Test("the random source stays in range and is roughly even")
  func randomSourceRange() {
    var random = DrawRandom(seed: 42)
    let values = (0..<2000).map { _ in random.next() }
    #expect(values.allSatisfy { $0 >= 0 && $0 < 1 })
    let mean = values.reduce(0, +) / Double(values.count)
    #expect(abs(mean - 0.5) < 0.03)
  }

  // MARK: - Warp modes

  /// A picture whose red channel rises from left to right, 6 per column.
  private let ramp = opaqueRaster(width: 40, height: 3) { x, _ in
    RGBA(red: UInt8(x * 6), green: 0, blue: 0)
  }

  @Test("grow pulls the content under the brush outwards, so the right side darkens")
  func growPullsOutwards() {
    let grown = WarpBrush.warp(
      ramp, at: CGPoint(x: 20, y: 1.5), direction: CGPoint(x: 1, y: 0), radius: 10, strength: 1,
      mode: .grow)
    #expect(grown.pixel(x: 24, y: 1).red < ramp.pixel(x: 24, y: 1).red - 3)
  }

  @Test("shrink pulls the content inwards, so the right side brightens")
  func shrinkPullsInwards() {
    let shrunk = WarpBrush.warp(
      ramp, at: CGPoint(x: 20, y: 1.5), direction: CGPoint(x: 1, y: 0), radius: 10, strength: 1,
      mode: .shrink)
    #expect(shrunk.pixel(x: 24, y: 1).red > ramp.pixel(x: 24, y: 1).red + 3)
  }

  @Test("swirls turn the content in opposite directions")
  func swirlsOppose() {
    let picture = opaqueRaster(width: 40, height: 40) { x, y in
      RGBA(red: UInt8((x * 37 + y * 91) % 256), green: 0, blue: 0)
    }
    let clockwise = WarpBrush.warp(
      picture, at: CGPoint(x: 20, y: 20), direction: .zero, radius: 12, strength: 1,
      mode: .swirlClockwise)
    let counter = WarpBrush.warp(
      picture, at: CGPoint(x: 20, y: 20), direction: .zero, radius: 12, strength: 1,
      mode: .swirlCounterclockwise)
    #expect(clockwise.pixels != picture.pixels)
    #expect(counter.pixels != picture.pixels)
    #expect(clockwise.pixels != counter.pixels)
  }

  @Test("zero strength changes nothing in any mode")
  func zeroStrengthIsNoOp() {
    for mode in WarpMode.allCases {
      let result = WarpBrush.warp(
        ramp, at: CGPoint(x: 20, y: 1.5), direction: CGPoint(x: 4, y: 0), radius: 10,
        strength: 0, mode: mode)
      #expect(result.pixels == ramp.pixels)
    }
  }

  @Test("push is the default warp, with a soft edge")
  func pushMatchesWarpDefault() {
    let picture = opaqueRaster(width: 40, height: 20) { x, _ in
      (19...21).contains(x)
        ? RGBA(red: 255, green: 255, blue: 255) : RGBA(red: 0, green: 0, blue: 0)
    }
    let direction = CGPoint(x: 6, y: 0)
    let centre = CGPoint(x: 20.5, y: 10.5)
    let legacy = WarpBrush.push(picture, at: centre, direction: direction, radius: 10, strength: 1)
    let explicit = WarpBrush.warp(
      picture, at: centre, direction: direction, radius: 10, strength: 1, hardness: 0,
      mode: .push)
    #expect(legacy.pixels == explicit.pixels)
  }

  @Test("a harder brush moves the pixels near its edge further than a soft one")
  func hardnessMovesEdgePixels() {
    let picture = opaqueRaster(width: 40, height: 20) { x, _ in
      (19...21).contains(x)
        ? RGBA(red: 255, green: 255, blue: 255) : RGBA(red: 0, green: 0, blue: 0)
    }
    let centre = CGPoint(x: 20.5, y: 10.5)
    let direction = CGPoint(x: 6, y: 0)
    let soft = WarpBrush.warp(
      picture, at: centre, direction: direction, radius: 10, strength: 1, hardness: 0, mode: .push)
    let hard = WarpBrush.warp(
      picture, at: centre, direction: direction, radius: 10, strength: 1, hardness: 1, mode: .push)
    // At x = 23 the soft brush barely moves the pixel, so it still samples the bright stripe. The
    // hard brush moves it the full six pixels, into the dark.
    #expect(soft.pixel(x: 23, y: 10).red > 128)
    #expect(hard.pixel(x: 23, y: 10).red < 128)
  }
}
