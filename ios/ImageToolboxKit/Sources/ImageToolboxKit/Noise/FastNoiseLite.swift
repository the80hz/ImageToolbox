import Foundation

/// A Swift port of the 2D part of FastNoiseLite (MIT License, Copyright (c) 2023 Jordan Peck and
/// Contributors), the library the Android texture presets use. The arithmetic follows the C++
/// header with `Float`, so the output agrees with it bit for bit for the same settings.
///
/// Only the 2D paths are ported. The 3D functions are not needed by the presets, and the
/// settings names keep the header's meaning: `frequency` scales the input, `octaves`, `gain` and
/// `lacunarity` shape the fractals, and `cellularJitter` moves the cellular feature points.
public struct FastNoiseLite: Sendable {
  /// The base noise of every sample.
  public enum NoiseType: Sendable {
    case openSimplex2
    case openSimplex2S
    case cellular
    case perlin
    case valueCubic
    case value
  }

  /// How the octaves of the base noise are combined.
  public enum FractalType: Sendable {
    case none
    /// Octaves summed with falling amplitude.
    case fbm
    /// Octaves of `1 - |noise|`, which gives sharp creases.
    case ridged
    /// Octaves of a ping-pong fold of the noise.
    case pingPong
    /// Domain warp applied octave after octave, each on the result of the last.
    case domainWarpProgressive
    /// Domain warp octaves that all start from the same input point.
    case domainWarpIndependent
  }

  /// How the distance to a feature point is measured.
  public enum CellularDistanceFunction: Sendable {
    case euclidean
    case euclideanSq
    case manhattan
    case hybrid
  }

  /// What a cellular sample returns. The raw values follow the header's order, which the
  /// square root test relies on.
  public enum CellularReturnType: Int, Sendable {
    case cellValue
    case distance
    case distance2
    case distance2Add
    case distance2Sub
    case distance2Mul
    case distance2Div
  }

  /// The kind of domain warp applied by `domainWarp`.
  public enum DomainWarpType: Sendable {
    case openSimplex2
    case openSimplex2Reduced
    case basicGrid
  }

  public var seed: Int32
  public var frequency: Float = 0.01
  public var noiseType: NoiseType = .openSimplex2
  public var fractalType: FractalType = .none
  public var octaves: Int = 3
  public var lacunarity: Float = 2
  public var gain: Float = 0.5
  public var weightedStrength: Float = 0
  public var pingPongStrength: Float = 2
  public var cellularDistanceFunction: CellularDistanceFunction = .euclideanSq
  public var cellularReturnType: CellularReturnType = .distance
  public var cellularJitter: Float = 1
  public var domainWarpType: DomainWarpType = .openSimplex2
  public var domainWarpAmp: Float = 1

  public init(seed: Int32 = 1337) {
    self.seed = seed
  }

  /// The factor that keeps the fractal in range: one over the sum of the octave amplitudes.
  /// The header recomputes it whenever the octaves or the gain change, so it is derived here.
  var fractalBounding: Float {
    let amplitude0 = Self.fastAbs(gain)
    var amplitude = amplitude0
    var sum: Float = 1
    for _ in stride(from: 1, to: octaves, by: 1) {
      sum += amplitude
      amplitude *= amplitude0
    }
    return 1 / sum
  }

  /// The noise at a point. Equal to `GetNoise` of the header for 2D input.
  public func noise(x: Float, y: Float) -> Float {
    var x = x
    var y = y
    transformCoordinate(&x, &y)
    switch fractalType {
    case .fbm: return fractalFBm(x, y)
    case .ridged: return fractalRidged(x, y)
    case .pingPong: return fractalPingPong(x, y)
    default: return singleNoise(seed, x, y)
    }
  }

  /// Moves a point by the domain warp that the settings describe. Equal to `DomainWarp` of the
  /// header for 2D input.
  public func domainWarp(x: inout Float, y: inout Float) {
    switch fractalType {
    case .domainWarpProgressive: warpProgressive(&x, &y)
    case .domainWarpIndependent: warpIndependent(&x, &y)
    default: warpSingle(&x, &y)
    }
  }

  /// Scales the input by the frequency and, for the simplex types, skews it onto the triangle
  /// grid.
  func transformCoordinate(_ x: inout Float, _ y: inout Float) {
    x *= frequency
    y *= frequency
    switch noiseType {
    case .openSimplex2, .openSimplex2S:
      let sqrt3: Float = 1.7320508075688772935274463415059
      let f2: Float = 0.5 * (sqrt3 - 1)
      let t = (x + y) * f2
      x += t
      y += t
    default:
      break
    }
  }

  /// One octave of the base noise for the chosen type.
  func singleNoise(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    switch noiseType {
    case .openSimplex2: return Self.singleSimplex(seed, x, y)
    case .openSimplex2S: return Self.singleOpenSimplex2S(seed, x, y)
    case .cellular:
      return Self.singleCellular(
        seed, x, y,
        distanceFunction: cellularDistanceFunction,
        returnType: cellularReturnType,
        jitter: cellularJitter)
    case .perlin: return Self.singlePerlin(seed, x, y)
    case .valueCubic: return Self.singleValueCubic(seed, x, y)
    case .value: return Self.singleValue(seed, x, y)
    }
  }

  /// Fractional Brownian motion: the octaves are summed with falling amplitude.
  func fractalFBm(_ x: Float, _ y: Float) -> Float {
    var x = x
    var y = y
    var seed = self.seed
    var sum: Float = 0
    var amplitude = fractalBounding
    for _ in 0..<max(0, octaves) {
      let value = singleNoise(seed, x, y)
      seed = seed &+ 1
      sum += value * amplitude
      amplitude *= Self.lerp(1, Self.fastMin(value + 1, 2) * 0.5, weightedStrength)
      x *= lacunarity
      y *= lacunarity
      amplitude *= gain
    }
    return sum
  }

  /// Ridged multifractal: each octave is folded to sharp creases.
  func fractalRidged(_ x: Float, _ y: Float) -> Float {
    var x = x
    var y = y
    var seed = self.seed
    var sum: Float = 0
    var amplitude = fractalBounding
    for _ in 0..<max(0, octaves) {
      let value = Self.fastAbs(singleNoise(seed, x, y))
      seed = seed &+ 1
      sum += (value * -2 + 1) * amplitude
      amplitude *= Self.lerp(1, 1 - value, weightedStrength)
      x *= lacunarity
      y *= lacunarity
      amplitude *= gain
    }
    return sum
  }

  /// Ping-pong fractal: each octave is folded back and forth between 0 and 1.
  func fractalPingPong(_ x: Float, _ y: Float) -> Float {
    var x = x
    var y = y
    var seed = self.seed
    var sum: Float = 0
    var amplitude = fractalBounding
    for _ in 0..<max(0, octaves) {
      let value = Self.pingPong((singleNoise(seed, x, y) + 1) * pingPongStrength)
      seed = seed &+ 1
      sum += (value - 0.5) * 2 * amplitude
      amplitude *= Self.lerp(1, value, weightedStrength)
      x *= lacunarity
      y *= lacunarity
      amplitude *= gain
    }
    return sum
  }

  /// Folds a value back and forth on the interval 0...2, then to 0...1.
  static func pingPong(_ value: Float) -> Float {
    var t = value
    t -= Float(truncate(t * 0.5) &* 2)
    return t < 1 ? t : 2 - t
  }
}
