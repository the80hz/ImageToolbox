import Foundation

/// `BrushedMetalFilter` of the native code: each pixel takes a highlight that follows the row and
/// a random offset from `java.util.Random(0)`, drawn row by row. The picture is then blurred along
/// each row over `2 * radius + 1` pixels, with the edges repeated and the sums divided in integers.
/// The Android app uses the monochrome form, where one offset serves all three channels.
enum ClassicBrushedMetal {
  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let base = preset.colours.first.map { Int($0) } ?? 0xFF88_8888
    let radius = max(ClassicMath.toInt(preset.value("radius", fallback: 10)), 0)
    let amount = Float(preset.value("amount", fallback: 0.1)) * 255
    let shine = Float(preset.value("shine", fallback: 0.1))
    let monochrome = preset.value("monochrome", fallback: 1) != 0
    var random = ClassicRandom(seed: 0)
    var pixels = [Int](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        let highlight = 255 * shine * sinf(2 * ClassicNative.pi * Float(x) / Float(width))
        let first = (random.nextFloat() * 2 - 1) * amount
        var second = first
        var third = first
        if !monochrome {
          second = (random.nextFloat() * 2 - 1) * amount
          third = (random.nextFloat() * 2 - 1) * amount
        }
        pixels[y * width + x] = ClassicMath.argb(
          0xff,
          channel(Float(ClassicMath.red(base)) + highlight + first),
          channel(Float(ClassicMath.green(base)) + highlight + second),
          channel(Float(ClassicMath.blue(base)) + highlight + third))
      }
    }
    return radius > 0 ? blurRows(pixels, width: width, height: height, radius: radius) : pixels
  }

  /// `(int)` of the sum, clamped to a channel.
  private static func channel(_ value: Float) -> Int {
    ClassicMath.clamp(ClassicMath.toInt(value), 0, 255)
  }

  /// `box_blur_exact` with a horizontal radius only: each row is averaged over a window that
  /// repeats its edge pixels, and every channel is divided by the window size in integers.
  private static func blurRows(_ pixels: [Int], width: Int, height: Int, radius: Int) -> [Int] {
    let size = 2 * radius + 1
    var output = pixels
    for y in 0..<height {
      let row = Array(pixels[(y * width)..<((y + 1) * width)])
      var sums = [0, 0, 0, 0]
      for offset in -radius...radius {
        accumulate(&sums, row[min(max(offset, 0), width - 1)], sign: 1)
      }
      for x in 0..<width {
        output[y * width + x] = ClassicMath.argb(
          sums[0] / size, sums[1] / size, sums[2] / size, sums[3] / size)
        accumulate(&sums, row[min(x + radius + 1, width - 1)], sign: 1)
        accumulate(&sums, row[max(x - radius, 0)], sign: -1)
      }
    }
    return output
  }

  private static func accumulate(_ sums: inout [Int], _ colour: Int, sign: Int) {
    sums[0] += sign * ClassicMath.alpha(colour)
    sums[1] += sign * ClassicMath.red(colour)
    sums[2] += sign * ClassicMath.green(colour)
    sums[3] += sign * ClassicMath.blue(colour)
  }
}
