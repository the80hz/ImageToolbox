import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Compression lab: quality metrics and quality search")
struct CompressionLabTests {

  private static func gradient(_ size: Int) -> CGImage {
    TestImages.image(width: size, height: size) { x, y in
      RGBA(
        red: UInt8(x * 255 / max(size - 1, 1)), green: UInt8(y * 255 / max(size - 1, 1)), blue: 120)
    }
  }

  @Test("SSIM of a picture with itself is 1, and PSNR is capped at 100")
  func identical() throws {
    let raster = try #require(RasterImage(Self.gradient(32)))
    #expect(abs(QualityMetrics.ssim(raster, raster) - 1) < 1e-9)
    #expect(QualityMetrics.psnr(raster, raster) == 100)
  }

  @Test("a damaged picture scores lower SSIM and a finite PSNR")
  func damaged() throws {
    let original = try #require(RasterImage(Self.gradient(32)))
    var pixels = original.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      pixels[index] = 255 - pixels[index]
    }
    let damaged = RasterImage(width: 32, height: 32, pixels: pixels)
    let ssim = QualityMetrics.ssim(original, damaged)
    #expect(ssim < 0.9)
    let psnr = QualityMetrics.psnr(original, damaged)
    #expect(psnr < 100 && psnr > 0)
  }

  @Test("the lossless PNG trial reaches SSIM 1 at the requested size")
  func losslessTrial() throws {
    let trial = try #require(
      CompressionLab.run(Self.gradient(32), target: .png, search: .manual(quality: 0.5)))
    #expect(abs(trial.ssim - 1) < 1e-9)
    #expect(trial.size > 0)
  }

  @Test("a quality search finds a JPEG that reaches the SSIM target")
  func ssimTarget() throws {
    let trial = try #require(
      CompressionLab.run(Self.gradient(64), target: .jpeg, search: .targetSSIM(0.95)))
    #expect(trial.ssim >= 0.95)
  }

  @Test("a size search keeps the file within the limit")
  func sizeTarget() throws {
    let limit = 3_000
    let trial = try #require(
      CompressionLab.run(Self.gradient(64), target: .jpeg, search: .targetSize(bytes: limit)))
    #expect(trial.size <= limit)
  }

  @Test("bisection returns the boundary of a monotone condition")
  func bisection() throws {
    let lowest = try #require(CompressionLab.lowestQuality(meeting: { $0 >= 0.6 }))
    #expect(abs(lowest - 0.6) < 0.01)
    let highest = try #require(CompressionLab.highestQuality(fitting: { $0 <= 0.4 }))
    #expect(abs(highest - 0.4) < 0.01)
  }
}
