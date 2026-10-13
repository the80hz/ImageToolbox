import CoreGraphics
import Foundation

/// Compresses a picture to one target with a chosen quality, or searches the quality that meets a
/// goal: the lowest quality whose SSIM reaches a target, or the highest quality whose file fits a
/// size limit. Quality is the 0...1 scale the converter uses.
public enum CompressionLab {

  public enum Search: Equatable, Sendable {
    case manual(quality: Double)
    /// The lowest quality whose SSIM is at least this value, from 0 to 1.
    case targetSSIM(Double)
    /// The highest quality whose file is at most this many bytes.
    case targetSize(bytes: Int)
  }

  public struct Trial: Equatable, Sendable {
    public let target: ConversionTarget
    public let quality: Double
    public let size: Int
    public let ssim: Double
    public let psnr: Double
    public let seconds: Double
  }

  /// Runs one target with the given search. Returns nil when the target cannot be written or no
  /// quality meets the goal.
  public static func run(_ image: CGImage, target: ConversionTarget, search: Search) -> Trial? {
    guard target.isAvailable, let original = RasterImage(image) else { return nil }
    let started = Date()

    let chosen: Double?
    switch search {
    case .manual(let quality):
      chosen = clamp(quality)
    case .targetSSIM(let goal):
      chosen = lowestQuality(meeting: { quality in
        guard let trial = encode(image, original, target, quality) else { return false }
        return trial.ssim >= goal
      })
    case .targetSize(let limit):
      chosen = highestQuality(fitting: { quality in
        guard let trial = encode(image, original, target, quality) else { return false }
        return trial.size <= limit
      })
    }
    guard let quality = chosen else { return nil }
    guard let result = encode(image, original, target, quality) else { return nil }
    let seconds = Date().timeIntervalSince(started)
    return Trial(
      target: target, quality: quality, size: result.size, ssim: result.ssim, psnr: result.psnr,
      seconds: seconds)
  }

  // MARK: - Helpers

  private struct Encoded {
    let size: Int
    let ssim: Double
    let psnr: Double
  }

  private static func encode(
    _ image: CGImage, _ original: RasterImage, _ target: ConversionTarget, _ quality: Double
  ) -> Encoded? {
    guard let data = try? FormatConverter.convert(image, to: target, quality: quality),
      let decoded = ImageCodec.decode(data), let raster = RasterImage(decoded),
      raster.width == original.width, raster.height == original.height
    else { return nil }
    return Encoded(
      size: data.count,
      ssim: QualityMetrics.ssim(original, raster),
      psnr: QualityMetrics.psnr(original, raster))
  }

  /// The lowest quality in 0.01...1 for which `accepts` holds, by bisection. Quality is assumed to
  /// rise with fidelity. Nil when even the highest quality fails.
  static func lowestQuality(meeting accepts: (Double) -> Bool) -> Double? {
    guard accepts(1) else { return nil }
    var low = 0.01
    var high = 1.0
    for _ in 0..<8 {
      let middle = (low + high) / 2
      if accepts(middle) { high = middle } else { low = middle }
    }
    return high
  }

  /// The highest quality in 0.01...1 for which `fits` holds, by bisection. Nil when even the lowest
  /// quality does not fit.
  static func highestQuality(fitting fits: (Double) -> Bool) -> Double? {
    guard fits(0.01) else { return nil }
    var low = 0.01
    var high = 1.0
    for _ in 0..<8 {
      let middle = (low + high) / 2
      if fits(middle) { low = middle } else { high = middle }
    }
    return low
  }

  private static func clamp(_ quality: Double) -> Double {
    min(max(quality, 0.01), 1)
  }
}
