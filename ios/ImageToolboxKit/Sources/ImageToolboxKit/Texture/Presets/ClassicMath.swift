import Foundation

/// `java.util.Random`, the generator the JH Labs filters draw their numbers from. `nextFloat`
/// and `nextInt` match the Java methods bit for bit, so a seeded filter draws the same numbers.
struct ClassicRandom {
  private static let multiplier: UInt64 = 0x5DEE_CE66D
  private static let mask: UInt64 = (1 << 48) - 1
  private var seed: UInt64

  init(seed: Int64) {
    self.seed = (UInt64(bitPattern: seed) ^ Self.multiplier) & Self.mask
  }

  /// `Random.setSeed(long)`.
  mutating func setSeed(_ seed: Int64) {
    self.seed = (UInt64(bitPattern: seed) ^ Self.multiplier) & Self.mask
  }

  private mutating func next(_ bits: Int) -> Int32 {
    seed = (seed &* Self.multiplier &+ 0xB) & Self.mask
    return Int32(truncatingIfNeeded: Int64(seed >> UInt64(48 - bits)))
  }

  /// `Random.nextInt()`: 32 random bits.
  mutating func nextInt() -> Int32 {
    next(32)
  }

  /// `Random.nextFloat()`: 24 random bits divided by 2^24, so a value in 0..<1.
  mutating func nextFloat() -> Float {
    Float(next(24)) / Float(1 << 24)
  }
}

/// A rotation of the picture by a filter's angle, as the `setAngle` of the JH Labs filters
/// builds it: the cosine and sine of the angle in float.
struct ClassicRotation: Sendable {
  let m00: Float
  let m01: Float
  let m10: Float
  let m11: Float

  init(angle: Float) {
    let cosine = cosf(angle)
    let sine = sinf(angle)
    m00 = cosine
    m01 = sine
    m10 = -sine
    m11 = cosine
  }

  /// The rotated coordinates of the pixel `(x, y)`, as `filterRGB` computes them.
  func apply(_ x: Int, _ y: Int) -> (x: Float, y: Float) {
    (m00 * Float(x) + m01 * Float(y), m10 * Float(x) + m11 * Float(y))
  }
}

/// The arithmetic of the JH Labs filters, which run in `float` and `int`. These helpers keep the
/// Java rules: `(int)` truncates toward zero and saturates, and the `int` overload of `lerp`
/// truncates its result.
enum ClassicMath {
  /// Java's `(int)` cast of a `double`.
  static func toInt(_ value: Double) -> Int {
    if value.isNaN { return 0 }
    if value >= Double(Int32.max) { return Int(Int32.max) }
    if value <= Double(Int32.min) { return Int(Int32.min) }
    return Int(value)
  }

  /// Java's `(int)` cast of a `float`.
  static func toInt(_ value: Float) -> Int {
    toInt(Double(value))
  }

  /// `ImageMath.clamp` for floats.
  static func clamp(_ x: Float, _ low: Float, _ high: Float) -> Float {
    x < low ? low : (x > high ? high : x)
  }

  /// `PixelUtils.clamp` for channels and other ints.
  static func clamp(_ x: Int, _ low: Int, _ high: Int) -> Int {
    x < low ? low : (x > high ? high : x)
  }

  /// `ImageMath.lerp` for floats.
  static func lerp(_ t: Float, _ a: Float, _ b: Float) -> Float {
    a + t * (b - a)
  }

  /// `ImageMath.lerp` for ints: `(int)(a + t * (b - a))`.
  static func lerp(_ t: Float, _ a: Int, _ b: Int) -> Int {
    toInt(Float(a) + t * Float(b - a))
  }

  /// `ImageMath.smoothStep`: a smooth ramp from 0 at `a` to 1 at `b`.
  static func smoothStep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    if x < a { return 0 }
    if x >= b { return 1 }
    let t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)
  }

  /// `ImageMath.mixColors`: blends two ARGB colours channel by channel.
  static func mixColours(_ t: Float, _ rgb1: Int, _ rgb2: Int) -> Int {
    let a = lerp(t, alpha(rgb1), alpha(rgb2))
    let r = lerp(t, red(rgb1), red(rgb2))
    let g = lerp(t, green(rgb1), green(rgb2))
    let b = lerp(t, blue(rgb1), blue(rgb2))
    return (a << 24) | (r << 16) | (g << 8) | b
  }

  static func alpha(_ argb: Int) -> Int {
    (argb >> 24) & 0xff
  }

  static func red(_ argb: Int) -> Int {
    (argb >> 16) & 0xff
  }

  static func green(_ argb: Int) -> Int {
    (argb >> 8) & 0xff
  }

  static func blue(_ argb: Int) -> Int {
    argb & 0xff
  }

  static func argb(_ alpha: Int, _ red: Int, _ green: Int, _ blue: Int) -> Int {
    (alpha << 24) | (red << 16) | (green << 8) | blue
  }
}
