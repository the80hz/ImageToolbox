import Foundation

/// The base noise that a fractal sums up.
public enum NoiseBasis: Sendable {
  case value
  case perlin
  case simplex
}

/// How the octaves of a fractal are combined.
public enum FractalShape: Sendable {
  /// Plain fractal Brownian motion: the octaves are summed with falling amplitude.
  case fbm
  /// Ridges: each octave is folded with `1 - |noise|`, which gives sharp creases.
  case ridged
  /// Turbulence: the octaves of `|noise|` are summed, which gives a cloudy, billowy look.
  case turbulence
}

/// Fractal combinations of value, Perlin or simplex noise, with domain warping. Every field is
/// deterministic for its seed. Results are normalised to about -1...1 (`fbm`, `ridged` gives 0...1).
public struct FractalNoise: Sendable {
  private let basis: NoiseBasis
  private let perlin: PerlinNoise
  private let simplex: SimplexNoise2D
  private let value: ValueNoise2D

  public init(seed: UInt64, basis: NoiseBasis) {
    self.basis = basis
    perlin = PerlinNoise(seed: seed)
    simplex = SimplexNoise2D(seed: seed)
    value = ValueNoise2D(seed: seed)
  }

  /// One octave of the base noise, roughly -1...1.
  public func sample(x: Double, y: Double) -> Double {
    switch basis {
    case .value: value.value(x: x, y: y)
    case .perlin: perlin.value(x: x, y: y) * 4 / 3
    case .simplex: simplex.value(x: x, y: y)
    }
  }

  /// Sums `octaves` layers. Each layer multiplies the frequency by `lacunarity` and the amplitude
  /// by `gain`. The result is divided by the total amplitude, so it stays in -1...1 for `fbm`
  /// and in 0...1 for `ridged` and `turbulence`.
  public func fractal(
    x: Double,
    y: Double,
    octaves: Int,
    gain: Double = 0.5,
    lacunarity: Double = 2,
    shape: FractalShape = .fbm
  ) -> Double {
    var total = 0.0
    var amplitude = 1.0
    var frequency = 1.0
    var norm = 0.0
    for _ in 0..<max(1, octaves) {
      let sample = sample(x: x * frequency, y: y * frequency)
      switch shape {
      case .fbm:
        total += sample * amplitude
      case .ridged:
        let ridge = 1 - abs(sample)
        total += ridge * ridge * amplitude
      case .turbulence:
        total += abs(sample) * amplitude
      }
      norm += amplitude
      amplitude *= gain
      frequency *= lacunarity
    }
    let average = total / norm
    switch shape {
    case .fbm: return average
    case .ridged: return average
    case .turbulence: return min(max(average * 1.5, 0), 1)
    }
  }

  /// Moves a point by two independent fractal fields, the classic domain warp. `amount` is in
  /// the same units as `x` and `y`.
  public func warp(
    x: Double,
    y: Double,
    amount: Double,
    octaves: Int = 3,
    gain: Double = 0.5
  ) -> (x: Double, y: Double) {
    let offsetX = fractal(x: x + 5.2, y: y + 1.3, octaves: octaves, gain: gain)
    let offsetY = fractal(x: x + 1.7, y: y + 9.2, octaves: octaves, gain: gain)
    return (x + amount * offsetX, y + amount * offsetY)
  }
}
