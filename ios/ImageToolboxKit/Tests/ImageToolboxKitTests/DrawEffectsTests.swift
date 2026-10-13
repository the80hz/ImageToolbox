import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

/// Opaque pictures built from code. Their premultiplied and straight values are the same.
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

private func coverage(width: Int, height: Int, _ value: (_ x: Int, _ y: Int) -> Double) -> [Double]
{
  (0..<(width * height)).map { index in value(index % width, index / width) }
}

@Suite("Draw effects under a brush coverage")
struct DrawEffectsTests {

  @Test("erasing removes the picture in proportion to the coverage")
  func eraseScalesByCoverage() {
    let white = opaqueRaster(width: 4, height: 1) { _, _ in RGBA(red: 255, green: 255, blue: 255) }
    let cover = [0.0, 0.5, 1.0, 0.0]
    let erased = RegionEffects.erase(white, coverage: cover)
    #expect(erased.pixel(x: 0, y: 0).alpha == 255)
    #expect(abs(Int(erased.pixel(x: 1, y: 0).alpha) - 128) <= 1)
    #expect(erased.pixel(x: 2, y: 0).alpha == 0)
    #expect(erased.pixel(x: 3, y: 0).alpha == 255)
  }

  @Test("a highlighter stroke is painted at its opacity, not at full strength")
  func highlighterOpacity() {
    let blank = RasterImage(width: 2, height: 1, pixels: [UInt8](repeating: 0, count: 8))
    let painted = RegionEffects.paint(
      blank, coverage: [1, 0], colour: (255, 0, 0), opacity: RegionEffects.highlighterOpacity)
    let expectedAlpha = Int((255 * RegionEffects.highlighterOpacity).rounded())
    #expect(abs(Int(painted.pixel(x: 0, y: 0).alpha) - expectedAlpha) <= 1)
    // The stored red is premultiplied by that alpha. The straight colour read back is full red.
    #expect(abs(Int(painted.pixels[0]) - expectedAlpha) <= 1)
    #expect(painted.pixel(x: 0, y: 0).red == 255)
    #expect(painted.pixel(x: 1, y: 0).alpha == 0)
  }

  @Test("overlapping stamps saturate at full coverage, so a highlighter stroke has one opacity")
  func overlappingStampsSaturate() {
    var canvas = BrushCanvas(width: 30, height: 12)
    canvas.stroke(
      through: [CGPoint(x: 5, y: 6), CGPoint(x: 25, y: 6)],
      brush: Brush(radius: 3, hardness: 1, opacity: 1, spacing: 0.05))
    // Many stamps overlap along the centre line, yet the coverage never exceeds one.
    #expect(canvas.coverage.allSatisfy { $0 <= 1 })
    #expect(canvas.coverage[6 * 30 + 15] > 0.999)
  }

  @Test("blur softens an edge and leaves uncovered pixels alone")
  func blurSoftensCoveredEdge() {
    let edge = opaqueRaster(width: 20, height: 3) { x, _ in
      x < 10 ? RGBA(red: 0, green: 0, blue: 0) : RGBA(red: 255, green: 255, blue: 255)
    }
    let cover = coverage(width: 20, height: 3) { x, _ in x >= 4 && x <= 15 ? 1 : 0 }
    let blurred = RegionEffects.blur(edge, coverage: cover, radius: 3)
    let atEdge = Int(blurred.pixel(x: 9, y: 1).red)
    #expect(atEdge > 40 && atEdge < 215)
    // Outside the coverage the picture is unchanged.
    #expect(blurred.pixel(x: 0, y: 1) == edge.pixel(x: 0, y: 1))
    #expect(blurred.pixel(x: 19, y: 1) == edge.pixel(x: 19, y: 1))
  }

  @Test("a flat picture stays flat under blur")
  func blurKeepsFlatPicture() {
    let flat = opaqueRaster(width: 12, height: 12) { _, _ in RGBA(red: 90, green: 40, blue: 200) }
    let cover = coverage(width: 12, height: 12) { _, _ in 1 }
    let blurred = RegionEffects.blur(flat, coverage: cover, radius: 4)
    #expect(blurred.pixel(x: 6, y: 6) == RGBA(red: 90, green: 40, blue: 200))
  }

  @Test("pixelation averages each block and keeps block boundaries")
  func pixelateAveragesBlocks() {
    let ramp = opaqueRaster(width: 8, height: 4) { x, _ in
      RGBA(red: UInt8(x * 30), green: 0, blue: 0)
    }
    let cover = coverage(width: 8, height: 4) { _, _ in 1 }
    let pixelated = RegionEffects.pixelate(ramp, coverage: cover, block: 4, preBlur: 0)
    // The first block holds red values 0, 30, 60 and 90, so its mean is 45 everywhere in it.
    #expect(abs(Int(pixelated.pixel(x: 0, y: 0).red) - 45) <= 1)
    #expect(pixelated.pixel(x: 3, y: 3).red == pixelated.pixel(x: 0, y: 0).red)
    #expect(pixelated.pixel(x: 4, y: 0).red != pixelated.pixel(x: 0, y: 0).red)
  }

  @Test("neon glows around a stroke and keeps the core white")
  func neonGlowAndWhiteCore() {
    let blank = opaqueRaster(width: 200, height: 200) { _, _ in RGBA(red: 0, green: 0, blue: 0) }
    // A band 20 pixels thick, so its centre is solid white and the glow shows above and below it.
    let band = coverage(width: 200, height: 200) { x, y in
      (90..<110).contains(y) && (50..<150).contains(x) ? 1 : 0
    }
    let lit = RegionEffects.neon(blank, coverage: band, colour: (0, 200, 255))
    #expect(lit.pixel(x: 100, y: 100) == RGBA(red: 255, green: 255, blue: 255))
    // Just above the band the glow is coloured, and it fades with distance.
    let near = lit.pixel(x: 100, y: 86)
    #expect(near.blue > 20)
    #expect(near.green > near.red)
    #expect(lit.pixel(x: 100, y: 0).blue < near.blue)
  }

  @Test("neon, erase and pixelation leave the picture alone where there is no coverage")
  func noCoverageNoChange() {
    let picture = opaqueRaster(width: 6, height: 6) { x, y in
      RGBA(red: UInt8(x * 40), green: UInt8(y * 40), blue: 77)
    }
    let none = coverage(width: 6, height: 6) { _, _ in 0 }
    #expect(
      RegionEffects.neon(picture, coverage: none, colour: (255, 0, 0)).pixels == picture.pixels)
    #expect(RegionEffects.erase(picture, coverage: none).pixels == picture.pixels)
    #expect(
      RegionEffects.pixelate(picture, coverage: none, block: 2, preBlur: 1).pixels == picture.pixels
    )
  }
}
