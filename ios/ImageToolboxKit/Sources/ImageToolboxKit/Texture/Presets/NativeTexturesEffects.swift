import Foundation

/// Native textures 26...30 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// fire, aurora, oil slick, watercolour and the flow texture.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  static func fire(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let frequency = parameter(p, 1, 8)
    let turbulence = parameter(p, 2, 36)
    let intensity = M.clamp01(parameter(p, 3, 0.78))
    let smoke = M.clamp01(parameter(p, 4, 0.18))
    let detail = M.clamp01(parameter(p, 5, 0.62))
    noise.warp(&x, &y, scale: s, amount: turbulence)
    let base = noise.fbm(x * s, y * s * 1.7)
    let tongues = 0.5 + 0.5 * sin(x * s * frequency + base * 9 - y * s * 3)
    var flame = M.clamp01(base * (1 - detail * 0.35) + tongues * detail * 0.35)
    flame = M.smoothstep(0.28 + smoke * 0.25, 0.9, flame) * intensity
    var result = M.mixColor(colour(c, 0, 0xFF10_0807), colour(c, 1, 0xFFB5_1B08), flame)
    result = M.mixColor(result, colour(c, 2, 0xFFFF_7A0A), M.smoothstep(0.38, 0.75, flame))
    return M.mixColor(result, colour(c, 3, 0xFFFF_E98A), M.smoothstep(0.72, 0.98, flame))
  }

  static func aurora(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.004), 0.00001)
    let ribbons = parameter(p, 1, 7)
    noise.warp(&x, &y, scale: s * 0.7, amount: parameter(p, 2, 34))
    let glow = M.clamp01(parameter(p, 3, 0.72))
    let stars = M.clamp01(parameter(p, 4, 0.2))
    let amount = parameter(p, 5, 1.32)
    let flow = noise.fbm(x * s, y * s)
    var band = pow(M.clamp01(0.5 + 0.5 * sin(y * s * ribbons + flow * 9)), 3)
    band = M.contrast(band, amount)
    var light = M.mixColor(colour(c, 1, 0xFF42_D9A0), colour(c, 2, 0xFF65_E4E8), flow)
    light = M.mixColor(light, colour(c, 3, 0xFFA5_6DE2), M.smoothstep(0.62, 0.95, flow))
    let result = M.mixColor(colour(c, 0, 0xFF06_1227), light, band * glow)
    let star = M.smoothstep(1 - stars * 0.009, 1, M.hash(x, y, seed))
    return M.mixColor(result, 0xFFFF_FFFF, star)
  }

  static func oilSlick(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    let bands = parameter(p, 1, 13)
    noise.warp(&x, &y, scale: s, amount: parameter(p, 2, 32))
    let iridescence = M.clamp01(parameter(p, 3, 0.82))
    let darkness = M.clamp01(parameter(p, 4, 0.3))
    let amount = parameter(p, 5, 1.2)
    let field = noise.fbm(x * s, y * s)
    var phase = M.fract((field + x * s * 0.13 - y * s * 0.08) * bands)
    phase = M.contrast(phase, amount)
    var spectrum = M.mixColor(
      colour(c, 1, 0xFFD5_329B), colour(c, 2, 0xFF25_D4D0), M.smoothstep(0, 0.5, phase))
    spectrum = M.mixColor(spectrum, colour(c, 3, 0xFFF0_C33C), M.smoothstep(0.5, 1, phase))
    return M.mixColor(
      colour(c, 0, 0xFF10_101A), spectrum, iridescence * (1 - darkness * 0.65))
  }

  static func watercolor(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let blooms = M.clamp01(parameter(p, 1, 0.72))
    let pigment = M.clamp01(parameter(p, 2, 0.65))
    let edges = M.clamp01(parameter(p, 3, 0.38))
    let paper = M.clamp01(parameter(p, 4, 0.22))
    let diffusion = M.clamp01(parameter(p, 5, 0.62))
    noise.warp(&x, &y, scale: s, amount: diffusion * 28)
    let a = noise.fbm(x * s, y * s)
    let b = noise.fbm(x * s * 0.82 + 9, y * s * 0.82 - 13)
    let granulation = noise.fine(x * s * 5.5, y * s * 5.5)
    var firstWash = M.smoothstep(0.38 - blooms * 0.16, 0.68, a)
    var secondWash = M.smoothstep(0.48 - blooms * 0.12, 0.77, b)
    firstWash *= 0.58 + granulation * 0.42
    secondWash *= 0.62 + (1 - granulation) * 0.38
    let firstBoundary = 1 - M.smoothstep(0.018, 0.09, abs(a - 0.5))
    let secondBoundary = 1 - M.smoothstep(0.018, 0.085, abs(b - 0.56))
    let pooling = M.maxOf(firstBoundary, secondBoundary) * edges
    var result = colour(c, 0, 0xFFF4_EBD8)
    result = M.mixColor(result, colour(c, 1, 0xFF33_7FB3), firstWash * pigment * 0.72)
    result = M.mixColor(result, colour(c, 2, 0xFFD8_5D79), secondWash * pigment * 0.68)
    result = M.mixColor(result, colour(c, 3, 0xFF49_3F76), pooling * pigment * 0.7)
    let horizontalFiber = pow(abs(sin((y + a * 3) * s * 85)), 24)
    let paperGrain = abs(M.hash(x, y, seed) - 0.5) * 2
    let fiber = M.clamp01(horizontalFiber * 0.55 + paperGrain * 0.45) * paper
    let paperShade: UInt32 = M.hash(x, y, seed &+ 31) > 0.5 ? 0xFFFF_FFFF : 0xFFC8_BBA4
    return M.mixColor(result, paperShade, fiber * 0.16)
  }

  static func flowTexture(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let frequency = parameter(p, 1, 12)
    noise.warp(&x, &y, scale: s, amount: parameter(p, 2, 46))
    let symmetry = M.clamp01(parameter(p, 3, 0.3))
    let sharpness = M.maxOf(parameter(p, 4, 1.25), 0.05)
    let glow = M.clamp01(parameter(p, 5, 0.62))
    let q = noise.fbm(x * s, y * s)
    let phase = sin((x + y * symmetry) * s * frequency + q * 11)
    let band = pow(M.clamp01(0.5 + 0.5 * phase), sharpness)
    var result = M.mixColor(colour(c, 0, 0xFF11_1128), colour(c, 1, 0xFF51_55D9), band)
    result = M.mixColor(result, colour(c, 2, 0xFFDE_4BB3), M.smoothstep(0.42, 0.82, q))
    let line = pow(M.clamp01(1 - abs(phase)), 8) * glow
    return M.mixColor(result, colour(c, 3, 0xFF7E_F2E7), line)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
