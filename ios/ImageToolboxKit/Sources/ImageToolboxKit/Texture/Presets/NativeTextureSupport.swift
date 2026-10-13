import Foundation

/// The helpers of the Android native texture code (`TextureMath.h`), in `Float` with the same
/// operand order. `std::max` and `std::min` return the second operand on ties, as in C++.
enum NativeTextureMath {
  static func clamp01(_ value: Float) -> Float {
    clamp(value, 0, 1)
  }

  /// `std::clamp`.
  static func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
    value < low ? low : (high < value ? high : value)
  }

  /// `std::max` on floats.
  static func maxOf(_ a: Float, _ b: Float) -> Float {
    a < b ? b : a
  }

  /// `std::min` on floats.
  static func minOf(_ a: Float, _ b: Float) -> Float {
    b < a ? b : a
  }

  static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    if edge0 == edge1 { return value < edge0 ? 0 : 1 }
    let t = clamp01((value - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
  }

  static func fract(_ value: Float) -> Float {
    value - floor(value)
  }

  static func contrast(_ value: Float, _ amount: Float) -> Float {
    clamp01((value - 0.5) * maxOf(amount, 0) + 0.5)
  }

  /// Blends two ARGB colours channel by channel, with the amount clamped to 0...1.
  static func mixColor(_ from: UInt32, _ to: UInt32, _ amount: Float) -> UInt32 {
    let t = clamp01(amount)
    func channel(_ shift: UInt32) -> UInt32 {
      let av = Float((from >> shift) & 0xFF)
      let bv = Float((to >> shift) & 0xFF)
      return UInt32(Int((av + (bv - av) * t).rounded())) << shift
    }
    return channel(24) | channel(16) | channel(8) | channel(0)
  }

  /// Converts ARGB to the byte order of an Android `ARGB_8888` bitmap pixel.
  static func argbToBitmapRgba(_ color: UInt32) -> UInt32 {
    (color & 0xFF00_FF00) | ((color & 0x00FF_0000) >> 16) | ((color & 0x0000_00FF) << 16)
  }

  /// A pseudo-random value in 0..<1 that depends on a point and a seed.
  static func hash(_ x: Float, _ y: Float, _ seed: Int32) -> Float {
    let value = sin(x * 127.1 + y * 311.7 + Float(seed) * 0.0137) * 43758.5453
    return fract(value)
  }

  /// A parameter by index, or `fallback` when it is missing or not finite.
  static func parameter(_ values: [Float], _ index: Int, _ fallback: Float) -> Float {
    guard index < values.count, values[index].isFinite else { return fallback }
    return values[index]
  }

  /// A colour by index, or `fallback` when it is missing.
  static func color(_ colors: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    index < colors.count ? colors[index] : fallback
  }
}

/// The shared noise fields of the native textures (`NoiseBank` in the Android code): one fractal
/// base, a finer detail layer, two domain-warp fields and cellular fields, all seeded from one
/// seed with fixed offsets.
final class NativeNoiseBank {
  private var base: FastNoiseLite
  private var detail: FastNoiseLite
  private var warpX: FastNoiseLite
  private var warpY: FastNoiseLite
  private var cells: FastNoiseLite
  private var cells2: FastNoiseLite
  private var cellValue: FastNoiseLite

  init(seed: Int32) {
    base = Self.fractal(seed &+ 0, .openSimplex2S, octaves: 5, gain: 0.52)
    detail = Self.fractal(seed &+ 1013, .perlin, octaves: 3, gain: 0.55)
    warpX = Self.fractal(seed &+ 2027, .openSimplex2, octaves: 3, gain: 0.5)
    warpY = Self.fractal(seed &+ 4093, .openSimplex2, octaves: 3, gain: 0.5)
    cells = Self.cellular(seed &+ 8191, .distance2Sub)
    cells2 = Self.cellular(seed &+ 12289, .distance2Sub)
    cellValue = Self.cellular(seed &+ 16381, .cellValue)
  }

  private static func fractal(
    _ seed: Int32, _ type: FastNoiseLite.NoiseType, octaves: Int, gain: Float
  ) -> FastNoiseLite {
    var noise = FastNoiseLite(seed: seed)
    noise.frequency = 1
    noise.noiseType = type
    noise.fractalType = .fbm
    noise.octaves = octaves
    noise.lacunarity = 2
    noise.gain = gain
    return noise
  }

  private static func cellular(
    _ seed: Int32, _ returnType: FastNoiseLite.CellularReturnType
  ) -> FastNoiseLite {
    var noise = FastNoiseLite(seed: seed)
    noise.frequency = 1
    noise.noiseType = .cellular
    noise.cellularDistanceFunction = .euclidean
    noise.cellularReturnType = returnType
    return noise
  }

  /// Fractal value in 0...1 of the base layer.
  func fbm(_ x: Float, _ y: Float) -> Float {
    NativeTextureMath.clamp01(base.noise(x: x, y: y) * 0.5 + 0.5)
  }

  /// Fractal value in 0...1 of the detail layer.
  func fine(_ x: Float, _ y: Float) -> Float {
    NativeTextureMath.clamp01(detail.noise(x: x, y: y) * 0.5 + 0.5)
  }

  /// Moves a point by two warp fields, each scaled by `amount`. Zero amount leaves it alone.
  func warp(_ x: inout Float, _ y: inout Float, scale: Float, amount: Float) {
    if amount == 0 { return }
    let sx = x * scale
    let sy = y * scale
    let dx = warpX.noise(x: sx + 19.17, y: sy - 7.31)
    let dy = warpY.noise(x: sx - 13.43, y: sy + 23.67)
    x += dx * amount
    y += dy * amount
  }

  /// The distance between the nearest and second nearest feature points, in 0...1.
  func cellEdge(_ x: Float, _ y: Float, scale: Float, jitter: Float) -> Float {
    cells.cellularJitter = NativeTextureMath.clamp(jitter, 0, 2)
    return NativeTextureMath.clamp01(cells.noise(x: x * scale, y: y * scale) + 1)
  }

  /// The same as `cellEdge` on a second, independent set of feature points.
  func secondaryCellEdge(_ x: Float, _ y: Float, scale: Float, jitter: Float) -> Float {
    cells2.cellularJitter = NativeTextureMath.clamp(jitter, 0, 2)
    return NativeTextureMath.clamp01(cells2.noise(x: x * scale, y: y * scale) + 1)
  }

  /// A per-cell value in 0...1 with the jitter of the feature points.
  func cellVariation(_ x: Float, _ y: Float, scale: Float, jitter: Float) -> Float {
    cellValue.cellularJitter = NativeTextureMath.clamp(jitter, 0, 2)
    return NativeTextureMath.clamp01(cellValue.noise(x: x * scale, y: y * scale) * 0.5 + 0.5)
  }
}

/// The per-texture functions of the native code. Each one returns an ARGB pixel for a point, in
/// the file that groups its textures. The extensions live next to the textures they draw.
enum NativeTextureFunctions {}
