import Foundation

/// Native textures 40...43 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// event horizon, fractal bloom, chromatic tunnel and eclipse corona. The shapes are centred on
/// the image and scaled by its shorter side, so they need the picture size.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  static func eventHorizon(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ seed: Int32, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    let tilt = M.clamp01(parameter(p, 1, 0.72))
    let horizon = M.clamp(parameter(p, 2, 0.15), 0.04, 0.35)
    let diskWidth = M.maxOf(parameter(p, 3, 0.065), 0.005)
    let lensing = M.clamp01(parameter(p, 4, 0.82))
    let stars = M.clamp01(parameter(p, 5, 0.22))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let flatten = 0.42 - tilt * 0.34
    let diskRadius = (dx * dx + (dy / M.maxOf(flatten, 0.04)) * (dy / M.maxOf(flatten, 0.04)))
      .squareRoot()
    let grain = noise.fbm(x * s, y * s)
    let inner = horizon * 1.18
    let outer = horizon * 2.75
    var disk =
      M.smoothstep(inner, inner + diskWidth, diskRadius)
      * (1 - M.smoothstep(outer - diskWidth, outer, diskRadius))
    disk *= 0.62 + grain * 0.38
    let hot = disk * M.smoothstep(outer, inner, diskRadius)
    let photonRing =
      (1 - M.smoothstep(horizon * 0.045, horizon * 0.18, abs(radius - horizon * 1.08)))
      * lensing
    let upperLens = photonRing * M.smoothstep(-horizon * 0.25, -horizon, dy)
    var result = M.mixColor(colour(c, 0, 0xFF01_0107), colour(c, 3, 0xFF7C_48FF), upperLens * 0.7)
    result = M.mixColor(result, colour(c, 1, 0xFFFF_5A18), disk)
    result = M.mixColor(
      result, colour(c, 2, 0xFFFF_E0A3), hot * (0.45 + 0.55 * M.smoothstep(0, outer, dx)))
    result = M.mixColor(result, colour(c, 2, 0xFFFF_E0A3), photonRing)
    if radius < horizon {
      result = M.mixColor(colour(c, 0, 0xFF01_0107), 0xFF00_0000, 0.94)
    }
    var star = M.smoothstep(1 - stars * 0.008, 1, M.hash(x, y, seed))
    star *= M.smoothstep(horizon * 3.2, horizon * 4.0, radius)
    return M.mixColor(result, 0xFFFF_FFFF, star)
  }

  static func fractalBloom(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.01), 0.00001)
    let petals = M.maxOf(parameter(p, 1, 7), 2)
    let layers = M.maxOf(parameter(p, 2, 5), 1)
    let curl = parameter(p, 3, 4.2)
    let filigree = M.clamp01(parameter(p, 4, 0.7))
    let glow = M.clamp01(parameter(p, 5, 0.72))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let organic = noise.fbm(x * s, y * s) - 0.5
    let petalWave = 0.5 + 0.5 * cos(angle * petals + radius * curl * 10 + organic * 1.2)
    let boundary = 0.18 + 0.19 * pow(petalWave, 0.62)
    let body = M.smoothstep(boundary + 0.018, boundary - 0.018, radius)
    let layerWave = 0.5 + 0.5 * cos(radius * layers * 42 - angle * 1.7 + petalWave * 2.5)
    let veins = pow(M.clamp01(1 - abs(layerWave * 2 - 1)), 9) * filigree * body
    let edge = (1 - M.smoothstep(0, 0.026, abs(radius - boundary))) * body
    let bloom = M.mixColor(
      colour(c, 1, 0xFF59_40D6), colour(c, 2, 0xFFFF_3E93), M.smoothstep(boundary, 0.04, radius))
    var result = M.mixColor(colour(c, 0, 0xFF09_061B), bloom, body)
    result = M.mixColor(result, colour(c, 3, 0xFFFF_E88A), veins * glow)
    result = M.mixColor(result, colour(c, 3, 0xFFFF_E88A), edge * 0.55)
    return M.mixColor(
      result, colour(c, 3, 0xFFFF_E88A), M.smoothstep(0.075, 0, radius) * glow)
  }

  static func chromaticTunnel(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let depth = M.maxOf(parameter(p, 1, 18), 1)
    let twist = parameter(p, 2, 5.5)
    let facets = M.maxOf(parameter(p, 3, 7), 2)
    let curvature = M.clamp01(parameter(p, 4, 0.48))
    let glow = M.clamp01(parameter(p, 5, 0.78))
    let unit = Float(max(min(width, height), 1))
    let bend = (noise.fbm(x * s * 0.35, y * s * 0.35) - 0.5) * curvature * 0.08
    let dx = (x - Float(width) * 0.5) / unit + bend
    let dy = (y - Float(height) * 0.5) / unit - bend * 0.55
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let perspective = 1 / (radius + 0.045)
    let spiral = angle * twist + perspective * depth
    let pulse = 0.5 + 0.5 * sin(spiral)
    let facet = 0.5 + 0.5 * cos(angle * facets - log(radius + 0.025) * twist)
    let ribbon = pow(M.clamp01(1 - abs(pulse * 2 - 1)), 5)
    let spectrum = M.mixColor(colour(c, 1, 0xFF00_D5FF), colour(c, 2, 0xFFFF_2C9C), facet)
    var result = M.mixColor(
      colour(c, 0, 0xFF03_0516), spectrum,
      M.smoothstep(0.02, 0.48, radius) * (0.32 + ribbon * 0.68))
    result = M.mixColor(
      result, colour(c, 3, 0xFFFF_F1B8), ribbon * glow * M.smoothstep(0.5, 0.06, radius))
    return M.mixColor(result, colour(c, 0, 0xFF03_0516), M.smoothstep(0.05, 0, radius))
  }

  static func eclipseCorona(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    let moon = M.clamp(parameter(p, 1, 0.23), 0.06, 0.4)
    let coronaSize = M.maxOf(parameter(p, 2, 0.2), 0.02)
    let rays = M.maxOf(parameter(p, 3, 34), 2)
    let turbulence = M.clamp01(parameter(p, 4, 0.62))
    let diamondRing = M.clamp01(parameter(p, 5, 0.8))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let grain = noise.fbm(x * s, y * s)
    let rayShape =
      0.38 + 0.62 * pow(M.clamp01(0.5 + 0.5 * sin(angle * rays + grain * turbulence * 7)), 3)
    let outer = moon + coronaSize * rayShape
    let corona =
      M.smoothstep(outer, moon * 1.01, radius)
      * M.smoothstep(
        moon * 0.94, moon * 1.04, radius)
    let halo = M.smoothstep(moon + coronaSize * 1.8, moon, radius) * 0.32
    let rim = 1 - M.smoothstep(moon * 0.015, moon * 0.06, abs(radius - moon))
    let pointAngle: Float = -0.72
    let px = cos(pointAngle) * moon
    let py = sin(pointAngle) * moon
    let pointDistance = ((dx - px) * (dx - px) + (dy - py) * (dy - py)).squareRoot()
    let diamond = (1 - M.smoothstep(0.004, 0.035, pointDistance)) * diamondRing
    var result = M.mixColor(colour(c, 0, 0xFF02_030A), colour(c, 1, 0xFF76_5BFF), halo)
    result = M.mixColor(result, colour(c, 2, 0xFFFF_9B45), corona)
    result = M.mixColor(result, colour(c, 3, 0xFFFF_FFFF), rim * 0.82 + diamond)
    if radius < moon * 0.985 {
      result = M.mixColor(colour(c, 0, 0xFF02_030A), 0xFF00_0000, 0.88)
    }
    return result
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
