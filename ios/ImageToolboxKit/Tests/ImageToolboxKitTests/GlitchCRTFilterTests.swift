import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Glitch and gradient map")
struct GlitchCRTFilterTests {

  @Test("a glitch with repeats changes the picture")
  func glitchChangesPicture() async throws {
    let picture = FilterTestImages.gradient(width: 64, height: 48)
    let output = try await GlitchFilter(amount: 100, seed: 50, iterations: 20).apply(to: picture)
    #expect(output.width == 64 && output.height == 48)
    #expect(output.pixels != picture.pixels)
  }

  @Test("zero repeats only re-encodes the picture, so it stays close to the input")
  func glitchZeroRepeatsIsNearIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 32, height: 24)
    let output = try await GlitchFilter(amount: 20, seed: 15, iterations: 0).apply(to: picture)
    // JPEG at quality 100 is lossy, so the check is a mean difference, not equality.
    let total = zip(output.pixels, picture.pixels).reduce(0) { sum, pair in
      sum + abs(Int(pair.0) - Int(pair.1))
    }
    let mean = Double(total) / Double(picture.pixels.count)
    #expect(mean < 8)
  }

  @Test("extreme glitch settings keep the size on 1x1 and 5x3 pictures")
  func glitchExtremes() async throws {
    let pictures = [
      FilterTestImages.solid(width: 1, height: 1, red: 30, green: 120, blue: 200),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    let settings: [(amount: Int, seed: Int, iterations: Int)] = [
      (0, 0, 0), (0, 0, 100), (100, 100, 100), (100, 0, 1), (50, 100, 1),
    ]
    for picture in pictures {
      for setting in settings {
        let filter = GlitchFilter(
          amount: setting.amount, seed: setting.seed, iterations: setting.iterations)
        let output = try await filter.apply(to: picture)
        #expect(output.width == picture.width && output.height == picture.height)
      }
    }
  }

  @Test("the gradient map sends black to the first stop and white to the last")
  func gradientMapEndpoints() async throws {
    let black = FilterTestImages.solid(width: 1, height: 1, red: 0, green: 0, blue: 0)
    let white = FilterTestImages.solid(width: 1, height: 1, red: 255, green: 255, blue: 255)
    let darkOutput = try await GradientMapFilter(palette: "Spectral").apply(to: black)
    let lightOutput = try await GradientMapFilter(palette: "Spectral").apply(to: white)
    // Spectral starts at 0xFF9E0142 and ends at 0xFF5E4FA2.
    #expect(Array(darkOutput.pixels) == [0x9E, 0x01, 0x42, 255])
    #expect(Array(lightOutput.pixels) == [0x5E, 0x4F, 0xA2, 255])
  }

  @Test("a gradient map changes a varied picture")
  func gradientMapChangesPicture() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await GradientMapFilter(palette: "Spectral").apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("the gradient map keeps alpha and leaves fully transparent pixels empty")
  func gradientMapKeepsAlpha() async throws {
    let pixels: [UInt8] = [
      0, 0, 0, 0,
      100, 50, 25, 128,
    ]
    let picture = RasterImage(width: 2, height: 1, pixels: pixels)
    let output = try await GradientMapFilter(palette: "Spectral").apply(to: picture)
    #expect(output.pixels[0..<4] == [0, 0, 0, 0])
    #expect(output.pixels[7] == 128)
  }

  @Test("every palette runs on 1x1 and 5x3 pictures and keeps the size")
  func gradientMapExtremes() async throws {
    let pictures = [
      FilterTestImages.solid(width: 1, height: 1, red: 255, green: 0, blue: 0),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    #expect(!GradientPaletteTable.names.isEmpty)
    for name in GradientPaletteTable.names {
      for picture in pictures {
        let output = try await GradientMapFilter(palette: name).apply(to: picture)
        #expect(output.width == picture.width && output.height == picture.height)
      }
    }
  }
}
