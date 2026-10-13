import CoreGraphics
import Foundation
import Testing
import simd

@testable import ImageToolboxKit

@Suite("Multi-frame fusion and alignment")
struct FrameFusionTests {

  private static func frame(_ value: UInt8, width: Int = 16, height: Int = 16) -> RasterImage {
    RasterImage(
      width: width, height: height,
      pixels: [UInt8](repeating: 255, count: width * height * 4).enumerated().map { index, _ in
        index % 4 == 3 ? 255 : value
      })
  }

  private static func value(_ raster: RasterImage, x: Int, y: Int) -> Int {
    Int(raster.pixel(x: x, y: y).red)
  }

  @Test("fusion needs two to twelve frames of one size")
  func frameCountAndSizes() {
    #expect(FrameFusion.fuse([Self.frame(10)]) == nil)
    #expect(FrameFusion.fuse([Self.frame(10), Self.frame(10, width: 8)]) == nil)
    let many = (0..<13).map { _ in Self.frame(10) }
    #expect(FrameFusion.fuse(many) == nil)
  }

  @Test("the median of three frames is the middle value")
  func median() throws {
    let result = try #require(
      FrameFusion.fuse(
        [Self.frame(10), Self.frame(200), Self.frame(50)],
        params: FusionParams(mode: .median)))
    #expect(Self.value(result, x: 4, y: 4) == 50)
  }

  @Test("the median of two frames averages the two middle values")
  func medianOfTwo() throws {
    let result = try #require(
      FrameFusion.fuse(
        [Self.frame(0), Self.frame(100)], params: FusionParams(mode: .median)))
    #expect(Self.value(result, x: 4, y: 4) == 50)
  }

  @Test("a long exposure averages in linear light, so black and white make mid grey above 128")
  func longExposure() throws {
    let result = try #require(
      FrameFusion.fuse(
        [Self.frame(0), Self.frame(255)], params: FusionParams(mode: .longExposure)))
    // Linear 0.5 is about 188 in sRGB.
    #expect(abs(Self.value(result, x: 4, y: 4) - 188) <= 2)
  }

  @Test("light trails keep a bright value that stands out from the average")
  func lightTrails() throws {
    let result = try #require(
      FrameFusion.fuse(
        [Self.frame(0), Self.frame(255)], params: FusionParams(mode: .lightTrails)))
    let value = Self.value(result, x: 4, y: 4)
    #expect(value > 220 && value < 250)
  }

  @Test("motion trails with no strength return the newest frame")
  func motionTrailsNoStrength() throws {
    let result = try #require(
      FrameFusion.fuse(
        [Self.frame(0), Self.frame(255)],
        params: FusionParams(mode: .motionTrails, trailStrength: 0)))
    #expect(Self.value(result, x: 4, y: 4) >= 254)
  }

  @Test("focus stacking takes the sharp frame where the blurred frame is flat")
  func focusStack() throws {
    var checker = [UInt8](repeating: 255, count: 16 * 16 * 4)
    for y in 0..<16 {
      for x in 0..<16 {
        let value: UInt8 = (x + y) % 2 == 0 ? 0 : 255
        checker[(y * 16 + x) * 4] = value
        checker[(y * 16 + x) * 4 + 1] = value
        checker[(y * 16 + x) * 4 + 2] = value
      }
    }
    let sharp = RasterImage(width: 16, height: 16, pixels: checker)
    let flat = Self.frame(128)
    let result = try #require(
      FrameFusion.fuse(
        [flat, sharp], params: FusionParams(mode: .focus, focusRadius: 3)))
    #expect(Self.value(result, x: 0, y: 0) < 60)
    #expect(Self.value(result, x: 1, y: 0) > 200)
  }

  @Test("exposure fusion of identical frames returns the frame")
  func exposureOfIdenticalFrames() throws {
    let gradient = TestImages.image(width: 64, height: 64) { x, y in
      RGBA(red: UInt8(x * 4), green: UInt8(y * 4), blue: 90)
    }
    let raster = try #require(RasterImage(gradient))
    let result = try #require(
      FrameFusion.fuse(
        [raster, raster], params: FusionParams(mode: .exposure)))
    var largest = 0
    for index in 0..<(64 * 64) {
      largest = max(largest, abs(Int(result.pixels[index * 4]) - Int(raster.pixels[index * 4])))
    }
    #expect(largest <= 3)
  }

  @Test("settings are clamped and the focus radius is made odd")
  func normalisation() {
    let params = FusionParams(
      contrastWeight: -1, focusRadius: 4, focusStrength: 10, trailPersistence: 0
    ).normalized()
    #expect(params.contrastWeight == 0)
    #expect(params.focusRadius == 5)
    #expect(params.focusStrength == 6)
    #expect(params.trailPersistence == 0.1)
  }

  @Test("the largest all-valid rectangle is found in a mask with a hole")
  func largestRectangle() throws {
    var mask = [Bool](repeating: true, count: 9)
    mask[0] = false
    let rectangle = try #require(
      FrameAlignment.largestRectangle(in: mask, width: 3, height: 3))
    #expect(rectangle.width * rectangle.height == 6)
  }

  @Test("a warp by the identity homography leaves the frame unchanged")
  func identityWarp() throws {
    let source = Self.frame(77)
    let warped = try #require(
      FrameAlignment.warp(
        source, by: matrix_identity_double3x3, width: 16, height: 16))
    #expect(warped.valid.allSatisfy { $0 })
    #expect(Self.value(warped.raster, x: 5, y: 5) == 77)
  }

  @Test(
    "Vision finds a shift between two frames, and the aligned frame matches the first",
    arguments: [96, 256])
  func visionAlignment(size: Int) throws {
    var generator = SeededGenerator(seed: 42)
    var reference = [UInt8](repeating: 255, count: size * size * 4)
    for index in 0..<(size * size) {
      for channel in 0..<3 {
        reference[index * 4 + channel] = UInt8.random(in: 0...255, using: &generator)
      }
    }
    // The second frame shows the same texture, 6 px to the right and 4 px up.
    var moving = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
      for x in 0..<size {
        let sourceX = x - 6
        let sourceY = y + 4
        guard sourceX >= 0, sourceY < size else { continue }
        for channel in 0..<4 {
          moving[(y * size + x) * 4 + channel] = reference[(sourceY * size + sourceX) * 4 + channel]
        }
      }
    }
    let referenceImage = try #require(
      RasterImage(width: size, height: size, pixels: reference).toCGImage())
    let movingImage = try #require(
      RasterImage(width: size, height: size, pixels: moving).toCGImage())
    let aligned = try #require(
      FrameAlignment.align(
        [referenceImage, movingImage], cropToOverlap: false))

    // Away from the borders, the aligned frame should match the reference closely.
    var total = 0
    var samples = 0
    for y in 24..<(size - 24) {
      for x in 24..<(size - 24) {
        let index = (y * size + x) * 4
        total += abs(Int(reference[index]) - Int(aligned[1].pixels[index]))
        samples += 1
      }
    }
    let meanDifference = Double(total) / Double(samples)
    #expect(meanDifference < 20)
  }

  @Test("a warp by a translation moves the picture by that many pixels")
  func translationWarp() throws {
    var source = [UInt8](repeating: 0, count: 16 * 16 * 4)
    for index in 0..<(16 * 16) {
      source[index * 4] = index % 16 == 4 ? 200 : 0
      source[index * 4 + 1] = source[index * 4]
      source[index * 4 + 2] = source[index * 4]
      source[index * 4 + 3] = 255
    }
    let raster = RasterImage(width: 16, height: 16, pixels: source)
    let shift = simd_double3x3(
      simd_double3(1, 0, 0), simd_double3(0, 1, 0), simd_double3(3, 0, 1))
    let moved = try #require(FrameAlignment.warp(raster, by: shift, width: 16, height: 16))
    // A column at x = 4 in the source sits at x = 7 after the warp; x = 4 is now empty.
    #expect(Self.value(moved.raster, x: 7, y: 5) > 150)
    #expect(Self.value(moved.raster, x: 4, y: 5) < 50)
    #expect(!moved.valid[5 * 16 + 1])
  }
}
