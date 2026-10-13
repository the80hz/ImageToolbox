import Foundation

@testable import ImageToolboxKit

/// The original naive SSIM, kept in the test target as the reference for the vDSP implementation in
/// `QualityMetrics`. Same window, constants and border rule: edge samples are repeated.
///
/// The arithmetic is the naive arithmetic, term by term and in the same order, so the results are
/// bit-identical to the first version. Only the loop form differs: `while` loops over raw buffers.
/// In a debug build `for ... in` ranges cost about ten times more per iteration, which made a
/// 1000x700 call take minutes.
enum SSIMReference {

  static func ssim(_ first: RasterImage, _ second: RasterImage) -> Double {
    precondition(first.width == second.width && first.height == second.height)
    let c1 = 6.5025  // (0.01 * 255)²
    let c2 = 58.5225  // (0.03 * 255)²
    let kernel = gaussianKernel(size: 11, sigma: 1.5)
    var total = 0.0
    var count = 0
    for channel in 0..<4 {
      let a = plane(first, channel)
      let b = plane(second, channel)
      let muA = convolved(a, first.width, first.height, kernel)
      let muB = convolved(b, first.width, first.height, kernel)
      let aa = convolved(a.map { $0 * $0 }, first.width, first.height, kernel)
      let bb = convolved(b.map { $0 * $0 }, first.width, first.height, kernel)
      let ab = convolved(zip(a, b).map { $0 * $1 }, first.width, first.height, kernel)
      var index = 0
      while index < muA.count {
        let varianceA = aa[index] - muA[index] * muA[index]
        let varianceB = bb[index] - muB[index] * muB[index]
        let covariance = ab[index] - muA[index] * muB[index]
        let numerator = (2 * muA[index] * muB[index] + c1) * (2 * covariance + c2)
        let denominator =
          (muA[index] * muA[index] + muB[index] * muB[index] + c1)
          * (varianceA + varianceB + c2)
        total += numerator / denominator
        count += 1
        index += 1
      }
    }
    return count == 0 ? 1 : total / Double(count)
  }

  /// The original PSNR, copied so the test can pin the unchanged metric.
  static func psnr(_ first: RasterImage, _ second: RasterImage) -> Double {
    precondition(first.width == second.width && first.height == second.height)
    var squared = 0.0
    for index in first.pixels.indices {
      let difference = Double(first.pixels[index]) - Double(second.pixels[index])
      squared += difference * difference
    }
    let mse = squared / Double(first.pixels.count)
    guard mse > 0 else { return 100 }
    return 10 * log10(255 * 255 / mse)
  }

  private static func plane(_ raster: RasterImage, _ channel: Int) -> [Double] {
    (0..<(raster.width * raster.height)).map { Double(raster.pixels[$0 * 4 + channel]) }
  }

  private static func gaussianKernel(size: Int, sigma: Double) -> [Double] {
    let radius = size / 2
    let weights = (0..<size).map { index -> Double in
      let distance = Double(index - radius)
      return exp(-distance * distance / (2 * sigma * sigma))
    }
    let total = weights.reduce(0, +)
    return weights.map { $0 / total }
  }

  /// Separable convolution with the edge samples repeated at the borders: the horizontal pass
  /// first, then the vertical pass, each output summing the taps in kernel order.
  private static func convolved(
    _ values: [Double], _ width: Int, _ height: Int, _ kernel: [Double]
  ) -> [Double] {
    let radius = kernel.count / 2
    let taps = kernel.count
    let last = width - 1
    let lastRow = height - 1
    var horizontal = [Double](repeating: 0, count: values.count)
    var result = [Double](repeating: 0, count: values.count)
    values.withUnsafeBufferPointer { source in
      horizontal.withUnsafeMutableBufferPointer { target in
        kernel.withUnsafeBufferPointer { weights in
          var y = 0
          while y < height {
            let row = y * width
            var x = 0
            while x < width {
              var sum = 0.0
              var offset = 0
              while offset < taps {
                var sample = x + offset - radius
                if sample < 0 { sample = 0 }
                if sample > last { sample = last }
                sum += weights[offset] * source[row + sample]
                offset += 1
              }
              target[row + x] = sum
              x += 1
            }
            y += 1
          }
        }
      }
    }
    horizontal.withUnsafeBufferPointer { source in
      result.withUnsafeMutableBufferPointer { target in
        kernel.withUnsafeBufferPointer { weights in
          var y = 0
          while y < height {
            var x = 0
            while x < width {
              var sum = 0.0
              var offset = 0
              while offset < taps {
                var sample = y + offset - radius
                if sample < 0 { sample = 0 }
                if sample > lastRow { sample = lastRow }
                sum += weights[offset] * source[sample * width + x]
                offset += 1
              }
              target[y * width + x] = sum
              x += 1
            }
            y += 1
          }
        }
      }
    }
    return result
  }
}
