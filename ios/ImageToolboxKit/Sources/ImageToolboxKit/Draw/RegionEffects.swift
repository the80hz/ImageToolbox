import CoreGraphics
import Foundation

/// Paint layers and picture effects that act only where a brush coverage is.
///
/// Coverage is one value per pixel from 0 to 1, row by row from the top, as `BrushCanvas` holds it.
/// Pictures are premultiplied RGBA, as `RasterImage` holds them.
public enum RegionEffects {
  /// Opacity of a highlighter stroke. Overlaps inside one stroke do not add up, because the
  /// coverage of the stroke is taken first and only then given this opacity.
  public static let highlighterOpacity = 0.4
  /// Radius of the neon glow in drawing units, as Android's default.
  public static let neonGlowRadius = 35
  /// Opacity of the neon glow at its strongest, as Android's default.
  public static let neonGlowOpacity = 0.8
  /// Blur radius of the privacy brush in drawing units.
  public static let privacyBlurRadius = 20
  /// Block size of the pixelation brush in drawing units.
  public static let pixelBlock = 36

  /// Puts `colour` over the picture where `coverage` is, scaled by `opacity`, with the "over" rule.
  public static func paint(
    _ raster: RasterImage, coverage: [Double], colour: (red: UInt8, green: UInt8, blue: UInt8),
    opacity: Double
  ) -> RasterImage {
    guard coverage.count == raster.width * raster.height else { return raster }
    var pixels = raster.pixels
    let scale = min(max(opacity, 0), 1)
    let source = [Double(colour.red), Double(colour.green), Double(colour.blue), 255]
    for index in coverage.indices {
      let alpha = min(max(coverage[index], 0), 1) * scale
      guard alpha > 0 else { continue }
      let base = index * 4
      for channel in 0..<4 {
        let value = source[channel] * alpha + Double(pixels[base + channel]) * (1 - alpha)
        pixels[base + channel] = clampedByte(value)
      }
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: pixels)
  }

  /// Removes the picture where `coverage` is: each channel is scaled by `1 - coverage`.
  public static func erase(_ raster: RasterImage, coverage: [Double]) -> RasterImage {
    guard coverage.count == raster.width * raster.height else { return raster }
    var pixels = raster.pixels
    for index in coverage.indices {
      let keep = 1 - min(max(coverage[index], 0), 1)
      guard keep < 1 else { continue }
      let base = index * 4
      for channel in 0..<4 {
        pixels[base + channel] = clampedByte(Double(pixels[base + channel]) * keep)
      }
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: pixels)
  }

  /// Blurs the picture under `coverage` with a box blur of `radius` pixels, applied three times.
  public static func blur(_ raster: RasterImage, coverage: [Double], radius: Int) -> RasterImage {
    let blurred = boxBlur(
      raster.pixels.map { Float($0) }, width: raster.width, height: raster.height, channels: 4,
      radius: radius)
    return mix(raster, blurred, coverage: coverage)
  }

  /// Pixelates the picture under `coverage`. The picture is first blurred by `preBlur` pixels, so
  /// the blocks average smooth colours, as Android's pixelation does.
  public static func pixelate(
    _ raster: RasterImage, coverage: [Double], block: Int, preBlur: Int
  ) -> RasterImage {
    let width = raster.width
    let height = raster.height
    let smooth = boxBlur(
      raster.pixels.map { Float($0) }, width: width, height: height, channels: 4, radius: preBlur)
    let size = max(block, 1)
    var blocks = smooth
    for top in stride(from: 0, to: height, by: size) {
      for left in stride(from: 0, to: width, by: size) {
        let bottom = min(top + size, height)
        let right = min(left + size, width)
        var sums = [Float](repeating: 0, count: 4)
        for y in top..<bottom {
          for x in left..<right {
            for channel in 0..<4 {
              sums[channel] += smooth[(y * width + x) * 4 + channel]
            }
          }
        }
        let count = Float((bottom - top) * (right - left))
        for y in top..<bottom {
          for x in left..<right {
            for channel in 0..<4 {
              blocks[(y * width + x) * 4 + channel] = sums[channel] / count
            }
          }
        }
      }
    }
    return mix(raster, blocks, coverage: coverage)
  }

  /// The neon stroke: a coloured glow around the coverage, then a white core on top of it.
  public static func neon(
    _ raster: RasterImage, coverage: [Double], colour: (red: UInt8, green: UInt8, blue: UInt8)
  ) -> RasterImage {
    let glow = blurCoverage(
      coverage, width: raster.width, height: raster.height, radius: neonGlowRadius)
    let lit = paint(raster, coverage: glow, colour: colour, opacity: neonGlowOpacity)
    return paint(lit, coverage: coverage, colour: (255, 255, 255), opacity: 1)
  }

  /// A box blur of one coverage map, for the glow of a stroke.
  public static func blurCoverage(
    _ coverage: [Double], width: Int, height: Int, radius: Int
  ) -> [Double] {
    guard coverage.count == width * height else { return coverage }
    let blurred = boxBlur(
      coverage.map { Float($0) }, width: width, height: height, channels: 1, radius: radius)
    return blurred.map { Double($0) }
  }

  // MARK: - Helpers

  /// Moves each pixel of `raster` towards `values` by its coverage.
  private static func mix(
    _ raster: RasterImage, _ values: [Float], coverage: [Double]
  ) -> RasterImage {
    guard coverage.count == raster.width * raster.height, values.count == raster.pixels.count
    else { return raster }
    var pixels = raster.pixels
    for index in coverage.indices {
      let weight = Float(min(max(coverage[index], 0), 1))
      guard weight > 0 else { continue }
      let base = index * 4
      for channel in 0..<4 {
        let original = Float(pixels[base + channel])
        let value = original + (values[base + channel] - original) * weight
        pixels[base + channel] = clampedByte(Double(value))
      }
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: pixels)
  }

  /// Three box blurs along rows and columns. `channels` values are stored per pixel.
  private static func boxBlur(
    _ input: [Float], width: Int, height: Int, channels: Int, radius: Int
  ) -> [Float] {
    guard radius > 0, width > 0, height > 0 else { return input }
    var source = input
    var target = input
    for _ in 0..<3 {
      for y in 0..<height {
        for channel in 0..<channels {
          blurLine(
            source, into: &target, start: y * width * channels + channel, stride: channels,
            count: width, radius: radius)
        }
      }
      swap(&source, &target)
      for x in 0..<width {
        for channel in 0..<channels {
          blurLine(
            source, into: &target, start: x * channels + channel, stride: width * channels,
            count: height, radius: radius)
        }
      }
      swap(&source, &target)
    }
    return source
  }

  /// One line of a box blur with a running sum. Samples past either end repeat the edge value.
  private static func blurLine(
    _ source: [Float], into target: inout [Float], start: Int, stride: Int, count: Int,
    radius: Int
  ) {
    let window = Float(2 * radius + 1)
    var sum: Float = 0
    for offset in -radius...radius {
      sum += source[start + stride * clampIndex(offset, count)]
    }
    for index in 0..<count {
      target[start + stride * index] = sum / window
      sum -= source[start + stride * clampIndex(index - radius, count)]
      sum += source[start + stride * clampIndex(index + radius + 1, count)]
    }
  }

  private static func clampIndex(_ value: Int, _ count: Int) -> Int {
    min(max(value, 0), count - 1)
  }

  private static func clampedByte(_ value: Double) -> UInt8 {
    UInt8(min(max(value.rounded(), 0), 255))
  }
}
