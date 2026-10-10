import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Colour waveform and vectorscope")
struct ColourScopeTests {

  @Test("a white picture lights the top of the waveform, and black lights the bottom")
  func waveformLevels() throws {
    let white = TestImages.solid(RGBA(red: 255, green: 255, blue: 255), width: 8, height: 8)
    let whiteScope = try #require(
      ColourScopeRenderer.render(
        white, scope: .waveform, width: 256, height: 256))
    let whiteRaster = try #require(RasterImage(whiteScope))
    #expect(whiteRaster.pixel(x: 0, y: 0).green > 200)
    #expect(whiteRaster.pixel(x: 0, y: 255).green < 60)

    let black = TestImages.solid(RGBA(red: 0, green: 0, blue: 0), width: 8, height: 8)
    let blackScope = try #require(
      ColourScopeRenderer.render(
        black, scope: .waveform, width: 256, height: 256))
    let blackRaster = try #require(RasterImage(blackScope))
    #expect(blackRaster.pixel(x: 0, y: 255).green > 200)
    #expect(blackRaster.pixel(x: 0, y: 0).green < 60)
  }

  @Test("a red picture draws the waveform in red, not in the other channel colours")
  func waveformColour() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 8, height: 8)
    let scope = try #require(
      ColourScopeRenderer.render(
        red, scope: .waveform, width: 256, height: 256))
    let raster = try #require(RasterImage(scope))
    let top = raster.pixel(x: 0, y: 0)
    #expect(top.red > top.green + 80)
  }

  @Test("a grey picture sits in the centre of the vectorscope")
  func vectorscopeCentre() throws {
    let grey = TestImages.solid(RGBA(red: 128, green: 128, blue: 128), width: 8, height: 8)
    let scope = try #require(
      ColourScopeRenderer.render(
        grey, scope: .vectorscope, width: 384, height: 384))
    let raster = try #require(RasterImage(scope))
    // Chroma (0, 0) is cell (192, 192) of the 384-cell grid.
    #expect(raster.pixel(x: 192, y: 192).green > 120)
  }

  @Test("a red picture is placed on the vectorscope's red side, in red")
  func vectorscopeRed() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 8, height: 8)
    let scope = try #require(
      ColourScopeRenderer.render(
        red, scope: .vectorscope, width: 384, height: 384))
    let raster = try #require(RasterImage(scope))
    // Red has Cb = -0.169 and Cr = +0.5, so it sits at column 127 and the top row.
    let pixel = raster.pixel(x: 127, y: 0)
    #expect(pixel.red > 150)
    #expect(pixel.green < 100)
  }

  @Test("hue groups separate primary colours and send greys to the neutral group")
  func hueGroups() {
    #expect(ColourScopeRenderer.hueGroup(red: 128, green: 128, blue: 128) == 18)
    #expect(ColourScopeRenderer.hueGroup(red: 255, green: 0, blue: 0) == 0)
    #expect(ColourScopeRenderer.hueGroup(red: 0, green: 255, blue: 0) == 6)
    #expect(ColourScopeRenderer.hueGroup(red: 0, green: 0, blue: 255) == 12)
  }

  @Test("density buckets rise with the count and an empty cell has none")
  func densityBuckets() {
    #expect(ColourScopeRenderer.densityBucket(0, peak: 10) == nil)
    let low = ColourScopeRenderer.densityBucket(1, peak: 1000)
    let high = ColourScopeRenderer.densityBucket(1000, peak: 1000)
    #expect(high == 5)
    #expect((low ?? 0) < (high ?? 0))
  }
}
