import Foundation

/// How two pages are judged to differ. Each metric marks the pixels whose error passes the
/// tolerance. The formulas follow the Android app's image comparison, which runs on OpenCV.
public enum PDFComparisonMetric: String, CaseIterable, Sendable {
  /// The largest difference of the channels of a pixel.
  case absoluteError
  /// The mean difference of the channels of a pixel.
  case meanAbsoluteError
  /// The root of the mean squared difference of the channels of a pixel.
  case rootMeanSquaredError
  /// The root mean squared error blurred in a Gaussian window, so that regions that lower the
  /// peak signal-to-noise ratio are marked.
  case peakSignalToNoiseRatio
  /// Structural similarity in a Gaussian window for each channel. The weakest channel counts.
  case structuralSimilarity
  /// Local normalised cross-correlation in a Gaussian window for each channel. The weakest
  /// channel counts.
  case normalizedCrossCorrelation
}

/// The per-pixel masks of the comparison metrics, on the RGBA pixels of two equal-sized pictures.
enum PDFPixelMetric {

  /// Gaussian window size and sigma, as the Android app uses them.
  private static let windowSize = 11
  private static let sigma: Float = 1.5
  /// SSIM constants for values in 0...255: (0.01 * 255)^2 and (0.03 * 255)^2.
  private static let ssimC1: Float = 6.5025
  private static let ssimC2: Float = 58.5225
  private static let epsilon: Float = 1e-6

  /// One flag for each pixel: true when the pixel differs. `tolerance` is a share from 0 to 1 of
  /// the full scale: a channel error above `tolerance * 255` differs for the error metrics, and a
  /// similarity below `1 - tolerance` differs for SSIM. NCC uses `1 - 2 * tolerance`.
  static func differences(
    _ first: RasterImage, _ second: RasterImage, metric: PDFComparisonMetric, tolerance: Double
  ) -> [Bool] {
    let limit = Float(tolerance * 255)
    let a = channels(of: first)
    let b = channels(of: second)
    let count = first.width * first.height
    switch metric {
    case .absoluteError:
      return (0..<count).map { pixel in
        (0..<4).contains { abs(a[$0][pixel] - b[$0][pixel]) > limit }
      }
    case .meanAbsoluteError:
      return (0..<count).map { pixel in
        (0..<4).reduce(Float(0)) { $0 + abs(a[$1][pixel] - b[$1][pixel]) } / 4 > limit
      }
    case .rootMeanSquaredError:
      return squaredMean(a, b).map { sqrt($0) > limit }
    case .peakSignalToNoiseRatio:
      let blurred = blur(squaredMean(a, b), width: first.width, height: first.height)
      return blurred.map { sqrt(max($0, 0)) > limit }
    case .structuralSimilarity:
      let maps = (0..<4).map {
        ssimMap(a[$0], b[$0], width: first.width, height: first.height)
      }
      let minimum = 1 - Float(tolerance)
      return (0..<count).map { pixel in maps.contains { $0[pixel] < minimum } }
    case .normalizedCrossCorrelation:
      let maps = (0..<4).map {
        nccMap(a[$0], b[$0], width: first.width, height: first.height)
      }
      let minimum = 1 - 2 * Float(tolerance)
      return (0..<count).map { pixel in maps.contains { $0[pixel] < minimum } }
    }
  }

  /// The four channels of a picture as planes of values from 0 to 255, red, green, blue, alpha.
  private static func channels(of image: RasterImage) -> [[Float]] {
    let count = image.width * image.height
    return (0..<4).map { channel in
      (0..<count).map { Float(image.pixels[$0 * 4 + channel]) }
    }
  }

  /// The mean of the squared channel differences of each pixel.
  private static func squaredMean(_ a: [[Float]], _ b: [[Float]]) -> [Float] {
    (0..<a[0].count).map { pixel in
      (0..<4).reduce(Float(0)) { sum, channel in
        let difference = a[channel][pixel] - b[channel][pixel]
        return sum + difference * difference
      } / 4
    }
  }

  /// The local structural similarity of one channel, from 0 to 1.
  private static func ssimMap(_ x: [Float], _ y: [Float], width: Int, height: Int) -> [Float] {
    let meanX = blur(x, width: width, height: height)
    let meanY = blur(y, width: width, height: height)
    let varianceX = blur(x.map { $0 * $0 }, width: width, height: height)
    let varianceY = blur(y.map { $0 * $0 }, width: width, height: height)
    let covariance = blur(zip(x, y).map { $0 * $1 }, width: width, height: height)
    return (0..<x.count).map { index in
      let muX = meanX[index]
      let muY = meanY[index]
      let sigmaX = max(varianceX[index] - muX * muX, 0)
      let sigmaY = max(varianceY[index] - muY * muY, 0)
      let cov = covariance[index] - muX * muY
      let numerator = (2 * muX * muY + ssimC1) * (2 * cov + ssimC2)
      let denominator =
        (muX * muX + muY * muY + ssimC1) * (sigmaX + sigmaY + ssimC2) + epsilon
      return min(max(numerator / denominator, 0), 1)
    }
  }

  /// The local normalised cross-correlation of one channel, from -1 to 1. Where both windows are
  /// flat, correlation is undefined, so the similarity of their means stands in for it.
  private static func nccMap(_ x: [Float], _ y: [Float], width: Int, height: Int) -> [Float] {
    let meanX = blur(x, width: width, height: height)
    let meanY = blur(y, width: width, height: height)
    let varianceX = blur(x.map { $0 * $0 }, width: width, height: height)
    let varianceY = blur(y.map { $0 * $0 }, width: width, height: height)
    let covariance = blur(zip(x, y).map { $0 * $1 }, width: width, height: height)
    return (0..<x.count).map { index in
      let muX = meanX[index]
      let muY = meanY[index]
      let sigmaX = max(varianceX[index] - muX * muX, 0)
      let sigmaY = max(varianceY[index] - muY * muY, 0)
      let cov = covariance[index] - muX * muY
      let denominator = (sigmaX * sigmaY).squareRoot()
      let value: Float
      if denominator <= epsilon {
        value = min(max(1 - abs(muX - muY) / 255, 0), 1)
      } else {
        value = cov / (denominator + epsilon)
      }
      return min(max(value, -1), 1)
    }
  }

  /// A Gaussian blur of one plane, separable, with the window shrunk for a small picture. Pixels
  /// past the edge take the value of the pixel mirrored at the edge, as OpenCV does by default.
  private static func blur(_ plane: [Float], width: Int, height: Int) -> [Float] {
    let kernelX = gaussianKernel(size: oddWindow(width))
    let kernelY = gaussianKernel(size: oddWindow(height))
    let halfX = kernelX.count / 2
    let halfY = kernelY.count / 2
    var horizontal = [Float](repeating: 0, count: plane.count)
    for y in 0..<height {
      for x in 0..<width {
        var sum: Float = 0
        for k in 0..<kernelX.count {
          sum += kernelX[k] * plane[y * width + mirrored(x + k - halfX, width)]
        }
        horizontal[y * width + x] = sum
      }
    }
    var output = [Float](repeating: 0, count: plane.count)
    for y in 0..<height {
      for x in 0..<width {
        var sum: Float = 0
        for k in 0..<kernelY.count {
          sum += kernelY[k] * horizontal[mirrored(y + k - halfY, height) * width + x]
        }
        output[y * width + x] = sum
      }
    }
    return output
  }

  /// The window for a side of `length` pixels: the Android window size, shrunk to the picture and
  /// made odd.
  static func oddWindow(_ length: Int) -> Int {
    let capped = min(windowSize, max(1, length))
    return capped % 2 == 0 ? capped - 1 : capped
  }

  /// A normalised Gaussian of `size` taps with the window's sigma.
  static func gaussianKernel(size: Int) -> [Float] {
    let centre = Float(size - 1) / 2
    let taps = (0..<size).map { index -> Float in
      let offset = Float(index) - centre
      return exp(-offset * offset / (2 * sigma * sigma))
    }
    let total = taps.reduce(0, +)
    return taps.map { $0 / total }
  }

  /// The index of `index` inside 0..<`count`, mirrored at the edges without repeating the edge
  /// pixel (OpenCV's BORDER_REFLECT_101).
  private static func mirrored(_ index: Int, _ count: Int) -> Int {
    guard count > 1 else { return 0 }
    var value = index
    while value < 0 || value >= count {
      value = value < 0 ? -value : 2 * (count - 1) - value
    }
    return value
  }
}
