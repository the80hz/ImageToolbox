import Foundation

/// The native code of the Android JH Labs fork (`src/main/rust/jhlabs/src/lib.rs` in
/// ImageToolboxLibs, Apache-2.0). The Android app runs that code for every JH Labs filter: the
/// Java classes only keep the parameters, which the code reads through their getters. These
/// helpers port the `f32` steps and the tables that the code shares.
enum ClassicNative {
  /// The seed of the Perlin table of the native code (`perlin_noise()`). Every preset and every
  /// run reads the same table, so no native picture depends on the seed of its preset.
  static let tableSeed: Int64 = 0x4a48_4c61_6273

  /// The Perlin table of the native code.
  static let table = ClassicNoise(seed: tableSeed)

  /// `f32::consts::PI`, rounded to the nearest float. `Float.pi` in Swift is the float below it.
  static let pi: Float = 3.14159265358979323846

  /// `mix_colors`: blends two ARGB colours by `amount`, clamped to 0...1, channel by channel in
  /// float. Each channel is truncated toward zero and clamped to 0...255.
  static func mix(_ amount: Float, _ first: Int, _ second: Int) -> Int {
    let amount = ClassicMath.clamp(amount, 0, 1)
    let inverse = 1 - amount
    return ClassicMath.argb(
      channel(
        Float(ClassicMath.alpha(first)) * inverse + Float(ClassicMath.alpha(second)) * amount),
      channel(
        Float(ClassicMath.red(first)) * inverse + Float(ClassicMath.red(second)) * amount),
      channel(
        Float(ClassicMath.green(first)) * inverse + Float(ClassicMath.green(second)) * amount),
      channel(
        Float(ClassicMath.blue(first)) * inverse + Float(ClassicMath.blue(second)) * amount))
  }

  /// `clamp(value as i32)` of the native code.
  private static func channel(_ value: Float) -> Int {
    ClassicMath.clamp(ClassicMath.toInt(value), 0, 255)
  }

  /// `f32::fract`: `x - trunc(x)`, so a negative input has a negative fraction.
  static func fract(_ value: Float) -> Float {
    value - value.rounded(.towardZero)
  }

  /// `powi(8)`: the square taken three times, as the compiler expands it.
  static func eighth(_ value: Float) -> Float {
    let square = value * value
    let fourth = square * square
    return fourth * fourth
  }

  /// `GrayscaleColormap.getColor`: `(int)(v * 255)` clamped to 0...255, as an opaque grey.
  static func grey(_ value: Float) -> Int {
    let n = ClassicMath.clamp(ClassicMath.toInt(value * 255), 0, 255)
    return ClassicMath.argb(0xff, n, n, n)
  }

  /// Fills a picture of ARGB pixels, row 0 first, with the colour of each pixel.
  static func draw(width: Int, height: Int, _ shade: (Int, Int) -> Int) -> [Int] {
    var pixels = [Int](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        pixels[y * width + x] = shade(x, y)
      }
    }
    return pixels
  }
}
