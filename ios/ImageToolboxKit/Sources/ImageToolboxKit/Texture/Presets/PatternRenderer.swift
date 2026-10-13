import Foundation

/// Draws the 28 pattern presets. Each one is a port of its Android GLSL shader, evaluated per pixel
/// on the CPU. The coordinates follow the shader: the image is centred, its aspect ratio is kept,
/// and the point is scaled by the preset frequency.
enum PatternRenderer {
  static func render(
    _ preset: TexturePreset,
    kind: PatternKind,
    seed: UInt64,
    width: Int,
    height: Int
  ) -> RasterImage {
    let environment = PatternEnvironment(preset: preset, seed: seed)
    let aspect = Double(width) / Double(height)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let uv = SIMD2((Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height))
        let point = ((uv - 0.5) * SIMD2(aspect, 1)) * preset.scale
        let colour = PatternShapes.shade(kind, point, environment)
        let index = (y * width + x) * 4
        // The shader writes premultiplied colour over black, so the output is opaque.
        pixels[index] = byte(colour.x * colour.w)
        pixels[index + 1] = byte(colour.y * colour.w)
        pixels[index + 2] = byte(colour.z * colour.w)
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func byte(_ channel: Double) -> UInt8 {
    UInt8((min(max(channel, 0), 1) * 255).rounded())
  }
}

/// The inputs of a pattern shader: four colours, the preset values and the seed. Also holds the
/// shader helpers (hashes, palette, distances), which the Android shader defines the same way.
struct PatternEnvironment: Sendable {
  /// colour1...colour4 as RGBA in 0...1.
  let colours: [SIMD4<Double>]
  let values: [String: Double]
  /// The shader's `seed` uniform: the user's seed when the pattern has one, else 0.
  let seed: Double

  init(preset: TexturePreset, seed: UInt64) {
    colours = (0..<4).map { index in
      let argb = preset.colours.indices.contains(index) ? preset.colours[index] : 0xFF00_0000
      return SIMD4(
        Double((argb >> 16) & 0xFF) / 255,
        Double((argb >> 8) & 0xFF) / 255,
        Double(argb & 0xFF) / 255,
        Double(argb >> 24) / 255)
    }
    values = Dictionary(uniqueKeysWithValues: preset.parameters.map { ($0.name, $0.value) })
    let hasSeed = values["seed"] != nil
    self.seed = hasSeed ? Double(seed % 10_001) : 0
  }

  func value(_ name: String) -> Double {
    values[name] ?? 0
  }

  /// A parameter rounded to a whole number, for the loops over counts and layers.
  func count(_ name: String) -> Int {
    Int(value(name).rounded())
  }

  /// `fract(sin(dot(p + seed, (127.1, 311.7))) * 43758.5453)`, the shader's hash.
  func hash(_ point: SIMD2<Double>) -> Double {
    let shifted = point + seed
    let dot = shifted.x * 127.1 + shifted.y * 311.7
    return fract(sin(dot) * 43758.5453)
  }

  func hash2(_ point: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2(hash(point), hash(point + 19.3))
  }

  /// The angle of a point, or 0 at the origin.
  func safeAngle(_ point: SIMD2<Double>) -> Double {
    (point * point).sum() < 0.0000001 ? 0 : atan2(point.y, point.x)
  }

  /// Distance from a point to the segment from `a` to `b`.
  func segment(_ point: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    let ab = b - a
    let t = min(max(((point - a) * ab).sum() / max((ab * ab).sum(), 0.00001), 0), 1)
    return ((point - a - ab * t) * (point - a - ab * t)).sum().squareRoot()
  }

  /// Walks the four colours as a loop: colour1 to 2, 2 to 3, 3 to 4, then 4 back to 1.
  func palette(_ value: Double) -> SIMD4<Double> {
    let t = fract(value) * 4
    if t < 1 { return mix(colours[0], colours[1], t) }
    if t < 2 { return mix(colours[1], colours[2], t - 1) }
    if t < 3 { return mix(colours[2], colours[3], t - 2) }
    return mix(colours[3], colours[0], t - 3)
  }

  /// The colour of the shader's `hsv` helper, with hue, saturation and value in 0...1.
  func hsv(_ hue: Double, _ saturation: Double, _ value: Double) -> SIMD3<Double> {
    let offsets: [Double] = [0, 0.666_667, 0.333_333]
    let channels = offsets.map { offset -> Double in
      let folded = abs(fract(hue + offset) * 6 - 3) - 1
      let clamped = min(max(folded, 0), 1)
      return value * ((1 - saturation) + saturation * clamped)
    }
    return SIMD3(channels[0], channels[1], channels[2])
  }

  func step(_ edge: Double, _ value: Double) -> Double {
    value < edge ? 0 : 1
  }

  func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
    guard high != low else { return value < low ? 0 : 1 }
    let t = min(max((value - low) / (high - low), 0), 1)
    return t * t * (3 - 2 * t)
  }
}

/// `fract` as the shader defines it: x - floor(x).
func fract(_ value: Double) -> Double {
  value - value.rounded(.down)
}

func fract(_ point: SIMD2<Double>) -> SIMD2<Double> {
  point - point.rounded(.down)
}

/// GLSL `mod`: the result has the sign of the divisor.
func glMod(_ value: Double, _ divisor: Double) -> Double {
  value - divisor * (value / divisor).rounded(.down)
}

func mix(_ a: SIMD4<Double>, _ b: SIMD4<Double>, _ t: Double) -> SIMD4<Double> {
  a + (b - a) * t
}

/// Two pi, the shaders' TAU.
let tau = 6.28318530718

/// The absolute value of each component, as the shader's `abs(vec2)`.
func absVec(_ vector: SIMD2<Double>) -> SIMD2<Double> {
  SIMD2(abs(vector.x), abs(vector.y))
}

/// The length of a 2D vector.
func length(_ vector: SIMD2<Double>) -> Double {
  (vector * vector).sum().squareRoot()
}
