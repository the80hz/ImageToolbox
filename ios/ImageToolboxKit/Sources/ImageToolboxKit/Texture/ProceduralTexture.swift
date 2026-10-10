import Foundation

/// The pattern families that `ProceduralTexture` can draw. Each one maps a pixel to a value
/// in 0...1, and that value blends between the two colours of `TextureSettings`.
public enum TextureKind: CaseIterable, Sendable {
  /// Fractal Perlin noise: several octaves of smooth random variation.
  case noise
  /// Sum of absolute noise octaves, which gives a sharper, cloudier look than `noise`.
  case turbulence
  /// Sine veins warped by noise.
  case marble
  /// Concentric rings, stretched along the grain and perturbed by noise.
  case wood
  /// Distance to the nearest random feature point, with a random colour per cell.
  case voronoi
  /// Sine bands across the pattern.
  case stripes
  /// Alternating square cells.
  case checkerboard
  /// A grid of round dots on the background colour.
  case dots
}

/// Parameters for one procedural texture. `normalized()` clamps every value into its range.
public struct TextureSettings: Equatable, Sendable {
  public var kind: TextureKind
  /// Drives every random choice: noise permutation, voronoi feature points and per-cell colours.
  public var seed: UInt64
  /// Characteristic size in pixels: the period of noise, stripes and marble, the cell size of a
  /// checkerboard or voronoi, the spacing of dots. From 1 to 4096.
  public var scale: Double
  /// Noise octaves, from 1 to 8. Kinds without octaves ignore it.
  public var octaves: Int
  /// Colour for the value 0, as red, green and blue in 0...1.
  public var colourA: SIMD3<Double>
  /// Colour for the value 1, as red, green and blue in 0...1.
  public var colourB: SIMD3<Double>
  /// Rotation of the whole pattern around the image centre, in radians.
  public var angle: Double

  public init(
    kind: TextureKind = .noise,
    seed: UInt64 = 0,
    scale: Double = 64,
    octaves: Int = 4,
    colourA: SIMD3<Double> = SIMD3(0, 0, 0),
    colourB: SIMD3<Double> = SIMD3(1, 1, 1),
    angle: Double = 0
  ) {
    self.kind = kind
    self.seed = seed
    self.scale = scale
    self.octaves = octaves
    self.colourA = colourA
    self.colourB = colourB
    self.angle = angle
  }

  /// The same settings with every value inside its range. Non-finite numbers fall back to defaults.
  public func normalized() -> TextureSettings {
    var result = self
    result.scale = min(max(Self.finite(scale, fallback: 64), 1), 4096)
    result.octaves = min(max(octaves, 1), 8)
    result.angle = Self.finite(angle, fallback: 0)
    result.colourA = Self.clampedColour(colourA)
    result.colourB = Self.clampedColour(colourB)
    return result
  }

  private static func finite(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? value : fallback
  }

  private static func clampedColour(_ colour: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
      finite(colour.x, fallback: 0),
      finite(colour.y, fallback: 0),
      finite(colour.z, fallback: 0)
    ).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
  }
}

/// Draws procedural textures on the CPU. The same settings always give the same picture.
public enum ProceduralTexture {

  /// Renders an opaque `width` x `height` picture with row 0 at the top.
  /// Returns nil when either size is not positive.
  public static func render(_ settings: TextureSettings, width: Int, height: Int) -> RasterImage? {
    guard width > 0, height > 0 else { return nil }
    let parameters = settings.normalized()
    let field = TextureField(settings: parameters)
    let cosine = cos(parameters.angle)
    let sine = sin(parameters.angle)
    let centreX = Double(width) / 2
    let centreY = Double(height) / 2
    var pixels = [UInt8](repeating: 255, count: width * height * 4)

    for y in 0..<height {
      let dy = Double(y) + 0.5 - centreY
      for x in 0..<width {
        let dx = Double(x) + 0.5 - centreX
        // Rotate the pixel offset into the pattern's own frame.
        let u = dx * cosine + dy * sine
        let v = dy * cosine - dx * sine
        let colour = blend(
          field.value(u: u, v: v), parameters.colourA, parameters.colourB)
        let index = (y * width + x) * 4
        pixels[index] = byte(colour.x)
        pixels[index + 1] = byte(colour.y)
        pixels[index + 2] = byte(colour.z)
        pixels[index + 3] = 255
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Linear interpolation between two colours, with `t` clamped to 0...1.
  private static func blend(_ t: Double, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    a + (b - a) * min(max(t, 0), 1)
  }

  private static func byte(_ channel: Double) -> UInt8 {
    UInt8((min(max(channel, 0), 1) * 255).rounded())
  }
}

/// Maps a point of the pattern frame to a value in 0...1 for one `TextureKind`.
/// Coordinates are pixel offsets from the image centre, already rotated by the angle.
private struct TextureField {
  private let kind: TextureKind
  private let scale: Double
  private let octaves: Int
  private let seed: UInt64
  private let noise: PerlinNoise

  init(settings: TextureSettings) {
    kind = settings.kind
    scale = settings.scale
    octaves = settings.octaves
    seed = settings.seed
    noise = PerlinNoise(seed: settings.seed)
  }

  func value(u: Double, v: Double) -> Double {
    // Work in units of `scale` so every kind reads the same way at any size.
    let x = u / scale
    let y = v / scale
    switch kind {
    case .noise:
      return clamp01(0.5 + noise.fractal(x: x, y: y, octaves: octaves))
    case .turbulence:
      return clamp01(2 * turbulence(x: x, y: y))
    case .marble:
      let warp = noise.fractal(x: x, y: y, octaves: octaves)
      return abs(sin(Double.pi * (x + 1.5 * warp)))
    case .wood:
      // Rings are stretched along x (the grain) and their radii wobble with noise.
      let warp = noise.fractal(x: x, y: y, octaves: octaves)
      let grainX = 0.15 * x
      let ring = (grainX * grainX + y * y).squareRoot() + 2 * warp
      let wave = 0.5 + 0.5 * sin(2 * Double.pi * ring)
      return wave * wave
    case .voronoi:
      return voronoi(x: x, y: y)
    case .stripes:
      return 0.5 + 0.5 * sin(2 * Double.pi * x)
    case .checkerboard:
      let parity = (Int(x.rounded(.down)) + Int(y.rounded(.down))) & 1
      return parity == 0 ? 0 : 1
    case .dots:
      let dotRadius = 0.3
      let offsetX = x - x.rounded(.down) - 0.5
      let offsetY = y - y.rounded(.down) - 0.5
      let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
      // Signed distance to the dot edge in pixels, shifted so that edge pixels blend.
      return clamp01((dotRadius - distance) * scale + 0.5)
    }
  }

  /// Sum of |noise| over the octaves, normalised to about 0...0.75.
  private func turbulence(x: Double, y: Double) -> Double {
    var total = 0.0
    var amplitude = 1.0
    var frequency = 1.0
    var norm = 0.0
    for _ in 0..<octaves {
      total += abs(noise.value(x: x * frequency, y: y * frequency)) * amplitude
      norm += amplitude
      amplitude *= 0.5
      frequency *= 2
    }
    return total / norm
  }

  /// Each lattice cell holds one feature point and one palette value. The value returned is the
  /// palette value of the nearest point, darkened slightly as the distance to it grows.
  private func voronoi(x: Double, y: Double) -> Double {
    let cellX = Int(x.rounded(.down))
    let cellY = Int(y.rounded(.down))
    var nearest = Double.infinity
    var nearestShade = 0.0
    for offsetY in -1...1 {
      for offsetX in -1...1 {
        let column = cellX + offsetX
        let row = cellY + offsetY
        var generator = Self.cellGenerator(seed: seed, column: column, row: row)
        let featureX = Double(column) + Self.unitValue(generator.next())
        let featureY = Double(row) + Self.unitValue(generator.next())
        let shade = Self.unitValue(generator.next())
        let distanceX = x - featureX
        let distanceY = y - featureY
        let distance = (distanceX * distanceX + distanceY * distanceY).squareRoot()
        if distance < nearest {
          nearest = distance
          nearestShade = shade
        }
      }
    }
    return nearestShade * (1 - 0.5 * min(nearest, 1))
  }

  /// A generator that depends only on the seed and the lattice cell, so neighbours are independent.
  private static func cellGenerator(seed: UInt64, column: Int, row: Int) -> SeededGenerator {
    let key =
      seed
      ^ (UInt64(bitPattern: Int64(column)) &* 0xD6E8_FEB8_6659_FD93)
      ^ (UInt64(bitPattern: Int64(row)) &* 0xA076_1D64_78BD_642F)
    var mixer = SeededGenerator(seed: key)
    return SeededGenerator(seed: mixer.next())
  }

  /// Maps 64 random bits to 0..<1 using the top 53 bits.
  private static func unitValue(_ bits: UInt64) -> Double {
    Double(bits >> 11) / 9_007_199_254_740_992
  }

  private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}
