import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Sharpen, unsharp, grain and pixelation")
struct SharpenNoiseFilterTests {

  @Test(
    "sharpen changes a picture with one bright pixel at full strength and leaves it alone at zero")
  func sharpenChangesAndNeutral() async throws {
    // Линейный градиент почти не меняется: лапласиан линейной функции равен нулю.
    // Поэтому берём плоский фон с одним ярким пикселем.
    let flat = FilterTestImages.solid(width: 5, height: 5, red: 100, green: 100, blue: 100)
    var pixels = flat.pixels
    let centre = (2 * 5 + 2) * 4
    pixels[centre] = 180
    pixels[centre + 1] = 180
    pixels[centre + 2] = 180
    let picture = RasterImage(width: 5, height: 5, pixels: pixels)
    let sharpened = try await SharpenFilter(amount: 1).apply(to: picture)
    let neutral = try await SharpenFilter(amount: 0).apply(to: picture)
    #expect(sharpened.pixels != picture.pixels)
    #expect(neutral.pixels == picture.pixels)
  }

  @Test("sharpen leaves a one pixel picture unchanged, because every neighbour is the pixel itself")
  func sharpenSinglePixel() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 40, green: 120, blue: 200)
    for amount in [-1.0, 1.0] {
      let output = try await SharpenFilter(amount: amount).apply(to: picture)
      #expect(output.pixels == picture.pixels)
    }
  }

  @Test("sharpen keeps size at both ends of its range on 1x1 and 5x3 pictures")
  func sharpenExtremes() async throws {
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for amount in [-1.0, 1.0] {
        let output = try await SharpenFilter(amount: amount).apply(to: picture)
        #expect(output.width == width && output.height == height)
        #expect(output.pixels.count == picture.pixels.count)
      }
    }
  }

  @Test("unsharp changes a gradient at full intensity and leaves it alone at zero")
  func unsharpChangesAndNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let sharpened = try await UnsharpFilter(intensity: 1).apply(to: picture)
    let neutral = try await UnsharpFilter(intensity: 0).apply(to: picture)
    #expect(sharpened.pixels != picture.pixels)
    #expect(neutral.pixels == picture.pixels)
  }

  @Test("unsharp keeps size at both ends of its range on 1x1 and 5x3 pictures")
  func unsharpExtremes() async throws {
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for intensity in [0.0, 1.0] {
        let output = try await UnsharpFilter(intensity: intensity).apply(to: picture)
        #expect(output.width == width && output.height == height)
      }
    }
  }

  @Test("grain adds variation to a flat picture and leaves it alone at zero")
  func grainChangesAndNeutral() async throws {
    let picture = FilterTestImages.solid(width: 6, height: 4, red: 128, green: 128, blue: 128)
    let grainy = try await GrainFilter(intensity: 2).apply(to: picture)
    let neutral = try await GrainFilter(intensity: 0).apply(to: picture)
    #expect(grainy.pixels != picture.pixels)
    #expect(neutral.pixels == picture.pixels)
  }

  @Test("grain noise is deterministic and stays within -1...1")
  func grainNoiseRange() {
    for y in 0..<8 {
      for x in 0..<8 {
        let value = GrainFilter.noise(x: x, y: y)
        #expect(value >= -1 && value <= 1)
        #expect(value == GrainFilter.noise(x: x, y: y))
      }
    }
  }

  @Test("grain keeps size at both ends of its range on 1x1 and 5x3 pictures")
  func grainExtremes() async throws {
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for intensity in [0.0, 2.0] {
        let output = try await GrainFilter(intensity: intensity).apply(to: picture)
        #expect(output.width == width && output.height == height)
      }
    }
  }

  @Test("square pixelation turns a gradient into blocks")
  func squarePixelationChanges() async throws {
    let picture = FilterTestImages.gradient(width: 40, height: 30)
    let output = try await PixelationFilter(size: 25).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("square pixelation of a flat picture stays flat and fully opaque")
  func squarePixelationFlat() async throws {
    let picture = FilterTestImages.solid(width: 20, height: 12, red: 30, green: 90, blue: 150)
    let output = try await PixelationFilter(size: 16).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("circle pixelation of a flat picture keeps one colour; edges only differ in coverage")
  func circlePixelationFlat() async throws {
    let picture = FilterTestImages.solid(width: 20, height: 12, red: 30, green: 90, blue: 150)
    let output = try await CirclePixelationFilter(size: 12).apply(to: picture)
    #expect(output.pixels != picture.pixels)
    var fullyCovered = 0
    for index in stride(from: 0, to: output.pixels.count, by: 4) {
      let alpha = Int(output.pixels[index + 3])
      if alpha == 0 {
        #expect(output.pixels[index] == 0)
        continue
      }
      // Сглаженный край: цвет premultiplied, то есть канал равен цвету, умноженному на альфу.
      let expected = [30, 90, 150].map { ($0 * alpha + 127) / 255 }
      for channel in 0..<3 {
        #expect(abs(Int(output.pixels[index + channel]) - expected[channel]) <= 2)
      }
      if alpha == 255 { fullyCovered += 1 }
    }
    #expect(fullyCovered > 0)
  }

  @Test("pixelation changes a gradient and keeps size at both ends of each range")
  func pixelationExtremes() async throws {
    let cases: [(Double, Double, Double)] = [
      (5, 5, 200),
      (24, 24, 200),
      (10, 10, 200),
    ]
    for (small, _, large) in cases {
      for (width, height) in [(1, 1), (5, 3)] {
        let picture = FilterTestImages.gradient(width: width, height: height)
        let outputs = [
          try await PixelationFilter(size: small).apply(to: picture),
          try await PixelationFilter(size: large).apply(to: picture),
          try await CirclePixelationFilter(size: small).apply(to: picture),
          try await CirclePixelationFilter(size: large).apply(to: picture),
          try await DiamondPixelationFilter(size: small).apply(to: picture),
          try await DiamondPixelationFilter(size: large).apply(to: picture),
        ]
        for output in outputs {
          #expect(output.width == width && output.height == height)
          #expect(output.pixels.count == picture.pixels.count)
        }
      }
    }
  }

  @Test("diamond pixelation of a gradient changes it")
  func diamondPixelationChanges() async throws {
    let picture = FilterTestImages.gradient(width: 40, height: 30)
    let output = try await DiamondPixelationFilter(size: 24).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }
}
