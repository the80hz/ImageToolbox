import Accelerate
import Foundation

/// Image quality metrics as the Android app computes them: SSIM with an 11x11 Gaussian window (sigma
/// 1.5), averaged over the RGBA channels, and PSNR from the global mean squared error.
public enum QualityMetrics {

  /// The structural similarity of two pictures of the same size, from -1 to 1 (1 means identical).
  public static func ssim(_ first: RasterImage, _ second: RasterImage) -> Double {
    precondition(first.width == second.width && first.height == second.height)
    let c1 = 6.5025  // (0.01 * 255)²
    let c2 = 58.5225  // (0.03 * 255)²
    let width = first.width
    let height = first.height
    guard width * height > 0 else { return 1 }
    let kernel = gaussianKernel(size: 11, sigma: 1.5)
    let radius = kernel.count / 2
    var total = 0.0
    for channel in 0..<4 {
      let a = paddedPlane(first, channel, radius: radius)
      let b = paddedPlane(second, channel, radius: radius)
      let muA = blur(a, width, height, kernel)
      let muB = blur(b, width, height, kernel)
      let aa = blur(square(a), width, height, kernel)
      let bb = blur(square(b), width, height, kernel)
      let ab = blur(product(a, b), width, height, kernel)
      total += structuralSum(muA, muB, aa, bb, ab, c1: c1, c2: c2)
    }
    return total / Double(4 * width * height)
  }

  /// The peak signal-to-noise ratio in decibels over the RGBA channels. Identical pictures give 100.
  public static func psnr(_ first: RasterImage, _ second: RasterImage) -> Double {
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

  // MARK: - Helpers

  private static func gaussianKernel(size: Int, sigma: Double) -> [Double] {
    let radius = size / 2
    let weights = (0..<size).map { index -> Double in
      let distance = Double(index - radius)
      return exp(-distance * distance / (2 * sigma * sigma))
    }
    let total = weights.reduce(0, +)
    return weights.map { $0 / total }
  }

  /// One channel as doubles, with `radius` samples repeated at each border. The window then never
  /// reads outside the array, and the border rule matches the naive reference: edge samples repeat.
  /// Requires a non-empty picture.
  private static func paddedPlane(_ raster: RasterImage, _ channel: Int, radius: Int) -> [Double] {
    let width = raster.width
    let height = raster.height
    let paddedWidth = width + 2 * radius
    let paddedHeight = height + 2 * radius
    var padded = [Double](repeating: 0, count: paddedWidth * paddedHeight)
    raster.pixels.withUnsafeBufferPointer { pixels in
      padded.withUnsafeMutableBufferPointer { target in
        for row in 0..<paddedHeight {
          let sourceRow = min(max(row - radius, 0), height - 1)
          let out = target.baseAddress! + row * paddedWidth
          // Pixels are 4 bytes apart, so the stride picks out this channel.
          vDSP_vfltu8D(
            pixels.baseAddress! + sourceRow * width * 4 + channel, 4,
            out + radius, 1, vDSP_Length(width))
          for column in 0..<radius {
            out[column] = out[radius]
            out[radius + width + column] = out[radius + width - 1]
          }
        }
      }
    }
    return padded
  }

  private static func square(_ values: [Double]) -> [Double] {
    var result = [Double](repeating: 0, count: values.count)
    vDSP_vsqD(values, 1, &result, 1, vDSP_Length(values.count))
    return result
  }

  private static func product(_ first: [Double], _ second: [Double]) -> [Double] {
    var result = [Double](repeating: 0, count: first.count)
    vDSP_vmulD(first, 1, second, 1, &result, 1, vDSP_Length(first.count))
    return result
  }

  /// Separable Gaussian blur of a padded plane (see `paddedPlane`). Returns `width * height` values.
  /// The rows are convolved first, then the rows are summed with one tap at a time, so every pass
  /// runs over whole rows in vDSP.
  private static func blur(
    _ padded: [Double], _ width: Int, _ height: Int, _ kernel: [Double]
  ) -> [Double] {
    let paddedWidth = width + kernel.count - 1
    let paddedHeight = height + kernel.count - 1
    var rows = [Double](repeating: 0, count: paddedHeight * width)
    padded.withUnsafeBufferPointer { source in
      rows.withUnsafeMutableBufferPointer { target in
        for row in 0..<paddedHeight {
          vDSP_convD(
            source.baseAddress! + row * paddedWidth, 1,
            kernel, 1,
            target.baseAddress! + row * width, 1,
            vDSP_Length(width), vDSP_Length(kernel.count))
        }
      }
    }
    var result = [Double](repeating: 0, count: width * height)
    rows.withUnsafeBufferPointer { source in
      result.withUnsafeMutableBufferPointer { target in
        kernel.withUnsafeBufferPointer { weights in
          for y in 0..<height {
            let out = target.baseAddress! + y * width
            for tap in 0..<weights.count {
              // out += weights[tap] * the row `tap` below this one in the padded rows.
              vDSP_vsmaD(
                source.baseAddress! + (y + tap) * width, 1,
                weights.baseAddress! + tap,
                out, 1,
                out, 1,
                vDSP_Length(width))
            }
          }
        }
      }
    }
    return result
  }

  /// The sum of the SSIM map over one channel, from the blurred means, second moments and cross
  /// moment.
  private static func structuralSum(
    _ muA: [Double], _ muB: [Double], _ aa: [Double], _ bb: [Double], _ ab: [Double],
    c1: Double, c2: Double
  ) -> Double {
    var total = 0.0
    for index in muA.indices {
      let meanA = muA[index]
      let meanB = muB[index]
      let varianceA = aa[index] - meanA * meanA
      let varianceB = bb[index] - meanB * meanB
      let covariance = ab[index] - meanA * meanB
      let numerator = (2 * meanA * meanB + c1) * (2 * covariance + c2)
      let denominator =
        (meanA * meanA + meanB * meanB + c1)
        * (varianceA + varianceB + c2)
      total += numerator / denominator
    }
    return total
  }
}
