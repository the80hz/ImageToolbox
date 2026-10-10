import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("SSIM with vDSP against the naive reference")
struct QualityMetricsTests {

  /// Random RGBA samples from a fixed seed, so every run compares the same pixels.
  static func randomPicture(width: Int, height: Int, seed: UInt64) -> RasterImage {
    var generator = SeededGenerator(seed: seed)
    let pixels = (0..<(width * height * 4)).map { _ in
      UInt8(truncatingIfNeeded: generator.next())
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// `picture` with every sample moved by a seeded amount from -24 to 24, clamped to the byte range.
  static func nearby(_ picture: RasterImage, seed: UInt64) -> RasterImage {
    var generator = SeededGenerator(seed: seed)
    let pixels = picture.pixels.map { value -> UInt8 in
      let shift = Int(generator.next() % 49) - 24
      return UInt8(min(max(Int(value) + shift, 0), 255))
    }
    return RasterImage(width: picture.width, height: picture.height, pixels: pixels)
  }

  /// Smooth colour ramps with a flat blue channel and opaque alpha: large areas of near-zero
  /// variance, where the SSIM denominator relies on its constant.
  static func gradient(width: Int, height: Int) -> RasterImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        pixels[index] = UInt8(x * 255 / max(width - 1, 1))
        pixels[index + 1] = UInt8(y * 255 / max(height - 1, 1))
        pixels[index + 2] = 128
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// `picture` with every byte raised by `amount`, clamped to 255. Alpha is 255 in the gradient, so
  /// it stays opaque.
  static func lifted(_ picture: RasterImage, by amount: Int) -> RasterImage {
    let pixels = picture.pixels.map { UInt8(min(Int($0) + amount, 255)) }
    return RasterImage(width: picture.width, height: picture.height, pixels: pixels)
  }

  /// Named pairs of one size: unrelated random pictures, a random picture against a nearby copy,
  /// and a smooth gradient against a lifted copy.
  static func pairs(
    width: Int, height: Int
  ) -> [(name: String, first: RasterImage, second: RasterImage)] {
    let random = randomPicture(width: width, height: height, seed: 1)
    let ramp = gradient(width: width, height: height)
    return [
      ("random", random, randomPicture(width: width, height: height, seed: 2)),
      ("random, nearby", random, nearby(random, seed: 3)),
      ("gradient, lifted", ramp, lifted(ramp, by: 5)),
    ]
  }

  /// True when `fast` is within 1e-9 relative of `reference`. Differences below 1e-15 absolute
  /// count as agreement, so a reference that is exactly zero still works.
  static func agrees(_ fast: Double, _ reference: Double) -> Bool {
    let difference = abs(fast - reference)
    return difference < 1e-15 || difference <= 1e-9 * abs(reference)
  }

  @Test("SSIM agrees with the naive reference within 1e-9 relative on small pictures")
  func matchesReferenceSmall() {
    // Pictures smaller than the 11x11 window: only the edge repetition rule decides the result.
    for (width, height) in [(1, 1), (4, 3), (7, 5), (33, 47)] {
      for pair in Self.pairs(width: width, height: height) {
        let fast = QualityMetrics.ssim(pair.first, pair.second)
        let reference = SSIMReference.ssim(pair.first, pair.second)
        #expect(
          Self.agrees(fast, reference),
          "\(width)x\(height) \(pair.name): fast \(fast), reference \(reference)")
      }
    }
  }

  @Test("SSIM agrees with the naive reference on the same pictures, 256x256 and 1000x700")
  func matchesNaiveReferenceLarge() {
    // The reference runs live on the same pictures as the fast path. In a debug build a 1000x700
    // reference call takes several seconds (see SSIMReference), so this test is the slow one.
    for (width, height) in [(256, 256), (1000, 700)] {
      for pair in Self.pairs(width: width, height: height) {
        let fast = QualityMetrics.ssim(pair.first, pair.second)
        let reference = SSIMReference.ssim(pair.first, pair.second)
        #expect(
          Self.agrees(fast, reference),
          "\(width)x\(height) \(pair.name): fast \(fast), reference \(reference)")
      }
    }
  }

  @Test("identical pictures give SSIM 1 and PSNR 100, at every size")
  func identical() {
    for (width, height) in [(1, 1), (33, 47), (256, 256), (1000, 700)] {
      let picture = Self.randomPicture(width: width, height: height, seed: 4)
      #expect(abs(QualityMetrics.ssim(picture, picture) - 1) < 1e-9, "\(width)x\(height)")
      #expect(QualityMetrics.psnr(picture, picture) == 100)
    }
  }

  @Test("an empty picture gives SSIM 1, as before")
  func empty() {
    let picture = RasterImage(width: 0, height: 0, pixels: [])
    #expect(QualityMetrics.ssim(picture, picture) == 1)
  }

  @Test("PSNR is unchanged: it equals the original formula and the known value for MSE 1")
  func psnrUnchanged() {
    let first = Self.randomPicture(width: 33, height: 47, seed: 5)
    let second = Self.nearby(first, seed: 6)
    #expect(QualityMetrics.psnr(first, second) == SSIMReference.psnr(first, second))

    // Every sample off by one gives a mean squared error of 1: 10 * log10(255² / 1).
    let base = Self.randomPicture(width: 16, height: 9, seed: 7)
    let shifted = RasterImage(
      width: base.width, height: base.height,
      pixels: base.pixels.map { $0 == 255 ? 254 : $0 + 1 })
    let expected = 10 * log10(255.0 * 255.0)
    #expect(abs(QualityMetrics.psnr(base, shifted) - expected) < 1e-9)
  }
}
