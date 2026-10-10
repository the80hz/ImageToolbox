import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Histogram equalize filters")
struct HistogramFilterTests {

  /// Low contrast: red 100...(100 + width - 1), green 100...(100 + height - 1), blue 96.
  /// The full gradient already uses evenly spaced levels, so equalize leaves it unchanged;
  /// this picture has room to stretch.
  static func narrowRamp(width: Int, height: Int) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        pixels[index] = UInt8(100 + x)
        pixels[index + 1] = UInt8(100 + y)
        pixels[index + 2] = 96
        pixels[index + 3] = 255
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  @Test("equalize stretches a low-contrast picture, so the picture changes")
  func equalizeChangesRamp() async throws {
    let picture = Self.narrowRamp(width: 6, height: 4)
    let output = try await EqualizeFilter().apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("equalize leaves a single-colour picture unchanged")
  func equalizeSolidIsIdentity() async throws {
    let picture = FilterTestImages.solid(width: 4, height: 3, red: 100, green: 100, blue: 100)
    let output = try await EqualizeFilter().apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("equalize histogram changes a low-contrast picture and keeps a single colour")
  func equalizeHistogramProperties() async throws {
    let ramp = Self.narrowRamp(width: 6, height: 4)
    let changed = try await EqualizeHistogramFilter().apply(to: ramp)
    #expect(changed.pixels != ramp.pixels)

    let solid = FilterTestImages.solid(width: 4, height: 3, red: 30, green: 60, blue: 90)
    let unchanged = try await EqualizeHistogramFilter().apply(to: solid)
    #expect(unchanged.pixels == solid.pixels)
  }

  @Test("equalize keeps alpha")
  func equalizeKeepsAlpha() async throws {
    var pixels = FilterTestImages.gradient(width: 5, height: 3).pixels
    for index in stride(from: 3, to: pixels.count, by: 4) {
      pixels[index] = 128
    }
    let picture = RasterImage(width: 5, height: 3, pixels: pixels)
    let output = try await EqualizeHistogramFilter().apply(to: picture)
    #expect(stride(from: 3, to: output.pixels.count, by: 4).allSatisfy { output.pixels[$0] == 128 })
  }

  @Test("HSV equalize changes a gradient at 256 bins")
  func hsvChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await EqualizeHistogramHSVFilter(bins: 256).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("HSV equalize at 256 bins leaves a single-colour picture unchanged")
  func hsvSolidIsIdentityAt256Bins() async throws {
    let picture = FilterTestImages.solid(width: 4, height: 3, red: 100, green: 60, blue: 20)
    let output = try await EqualizeHistogramHSVFilter(bins: 256).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("HSV equalize keeps black pixels black")
  func hsvKeepsBlack() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 2, red: 0, green: 0, blue: 0)
    let output = try await EqualizeHistogramHSVFilter(bins: 2).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("pixelation with a 1x1 grid equals the whole-picture equalize")
  func pixelationOneCellMatchesWhole() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let whole = try await EqualizeHistogramFilter().apply(to: picture)
    let grid = try await EqualizeHistogramPixelationFilter(gridX: 1, gridY: 1).apply(to: picture)
    #expect(grid.pixels == whole.pixels)
  }

  @Test("pixelation with a 2x2 grid changes a gradient")
  func pixelationChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await EqualizeHistogramPixelationFilter(gridX: 2, gridY: 2).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("every equalize filter survives its extremes on a 1x1 and a 5x3 picture")
  func extremesKeepSize() async throws {
    let filters: [any Filter] = [
      EqualizeFilter(),
      EqualizeHistogramFilter(),
      EqualizeHistogramHSVFilter(bins: 2),
      EqualizeHistogramHSVFilter(bins: 256),
      EqualizeHistogramPixelationFilter(gridX: 1, gridY: 1),
      EqualizeHistogramPixelationFilter(gridX: 200, gridY: 200),
    ]
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for filter in filters {
        let output = try await filter.apply(to: picture)
        #expect(output.width == width && output.height == height)
        #expect(output.pixels.count == picture.pixels.count)
      }
    }
  }
}
