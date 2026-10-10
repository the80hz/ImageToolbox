import Foundation

/// Native textures 20...25 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// grass, dirt, leather, concrete, asphalt and moss.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  static func grass(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.012), 0.00001)
    let density = M.clamp01(parameter(p, 1, 1))
    let length = M.maxOf(parameter(p, 2, 50), 1)
    let wind = parameter(p, 3, 1)
    let patchiness = M.clamp01(parameter(p, 4, 0.35))
    let highlights = M.clamp01(parameter(p, 5, 0.45))
    let patch = noise.fbm(x * s * 0.45, y * s * 0.45)
    let bend = noise.fbm(x * s, y * s) * wind * 12
    let blades = pow(M.clamp01(0.5 + 0.5 * sin((x * s + bend) * length + y * s * 1.7)), 9)
    let cover = M.smoothstep(1 - density, 0.92, patch + density * 0.42)
    let tone = M.clamp01(noise.fine(x * s * 3, y * s * 3) + patchiness * (patch - 0.5))
    var blade = M.mixColor(colour(c, 1, 0xFF1D_491F), colour(c, 2, 0xFF4D_8A32), tone)
    blade = M.mixColor(blade, colour(c, 3, 0xFF9B_C45A), blades * highlights)
    return M.mixColor(colour(c, 0, 0xFF3A_2B18), blade, M.clamp01(cover * 0.75 + blades * 0.5))
  }

  static func dirt(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let clumps = M.clamp01(parameter(p, 1, 0.62))
    let moisture = M.clamp01(parameter(p, 2, 0.35))
    let pebbles = M.clamp01(parameter(p, 3, 0.22))
    let roughness = M.clamp01(parameter(p, 4, 0.68))
    let variation = M.clamp01(parameter(p, 5, 0.52))
    let broad = noise.fbm(x * s, y * s)
    let crumb = noise.fine(x * s * 5, y * s * 5)
    var body = M.clamp01(broad * (1 - clumps * 0.3) + crumb * clumps * 0.3)
    body = M.clamp01(body + (M.hash(x, y, seed) - 0.5) * roughness * 0.22)
    var earth = M.mixColor(
      colour(c, 0, 0xFF2A_190E), colour(c, 1, 0xFF69_4226), body + moisture * 0.1)
    earth = M.mixColor(
      earth, colour(c, 2, 0xFFA1_764D),
      M.smoothstep(0.58, 0.9, broad) * variation * (1 - moisture))
    let pebble = M.smoothstep(
      1 - pebbles * 0.018, 1, M.hash(x * 0.37, y * 0.37, seed &+ 91))
    return M.mixColor(earth, colour(c, 3, 0xFFB1_A28C), pebble)
  }

  static func leather(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.011), 0.00001)
    let wrinkles = M.clamp01(parameter(p, 1, 0.58))
    let pores = M.clamp01(parameter(p, 2, 0.42))
    let grain = M.clamp01(parameter(p, 3, 0.5))
    let softness = M.clamp01(parameter(p, 4, 0.38))
    let shine = M.clamp01(parameter(p, 5, 0.035))
    noise.warp(&x, &y, scale: s, amount: 10 * wrinkles)
    let base = noise.fbm(x * s, y * s)
    let fold = 1 - abs(sin((x * 0.63 + y) * s * 8 + base * 7))
    let fineValue = noise.fine(x * s * 8, y * s * 8)
    let pore = M.smoothstep(0.78, 0.96, fineValue) * pores
    let tone = M.clamp01(0.42 + (base - 0.5) * grain + fold * wrinkles * 0.24)
    var result = M.mixColor(
      colour(c, 0, 0xFF30_160F), colour(c, 1, 0xFF7B_3D25), tone + softness * 0.18)
    result = M.mixColor(result, colour(c, 2, 0xFFB3_6B43), M.smoothstep(0.72, 0.98, fold) * shine)
    return M.mixColor(result, colour(c, 3, 0xFF1C_0C08), pore)
  }

  static func concrete(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.014), 0.00001)
    let aggregate = M.clamp01(parameter(p, 1, 0.45))
    let stains = M.clamp01(parameter(p, 2, 0.28))
    let roughness = M.clamp01(parameter(p, 3, 0.65))
    let cracks = M.clamp01(parameter(p, 4, 0.14))
    let amount = parameter(p, 5, 1.08)
    noise.warp(&x, &y, scale: s * 0.7, amount: 16)
    let body = M.contrast(noise.fbm(x * s, y * s), amount)
    let grit = noise.fine(x * s * 6, y * s * 6)
    let tone = M.clamp01(body * 0.65 + grit * roughness * 0.35)
    var result = M.mixColor(colour(c, 0, 0xFF5A_5955), colour(c, 2, 0xFFC7_C3B9), tone)
    result = M.mixColor(result, colour(c, 1, 0xFF99_968E), 0.35 + aggregate * 0.3)
    result = M.mixColor(
      result, colour(c, 0, 0xFF5A_5955),
      M.smoothstep(0.72, 0.94, noise.fbm(x * s * 0.3, y * s * 0.3)) * stains)
    let line = abs(sin((x + y * 0.41) * s * 3 + body * 12))
    let crack = (1 - M.smoothstep(0, 0.018 + cracks * 0.09, line)) * cracks
    let speck = M.smoothstep(0.995, 1, M.hash(x, y, seed)) * aggregate
    return M.mixColor(
      M.mixColor(result, colour(c, 3, 0xFF35_3532), crack), colour(c, 2, 0xFFC7_C3B9), speck)
  }

  static func asphalt(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.02), 0.00001)
    let aggregate = M.clamp01(parameter(p, 1, 0.72))
    let tar = M.clamp01(parameter(p, 2, 0.44))
    let wear = M.clamp01(parameter(p, 3, 0.28))
    let speckles = M.clamp01(parameter(p, 4, 0.48))
    let amount = parameter(p, 5, 1.3)
    let coarse = M.contrast(noise.fine(x * s * 2.2, y * s * 2.2), amount)
    let fineValue = M.hash(x, y, seed)
    let tone = M.clamp01(coarse * aggregate + fineValue * (1 - aggregate))
    var result = M.mixColor(
      colour(c, 0, 0xFF17_191A), colour(c, 1, 0xFF3E_4242), tone + tar * 0.12)
    let stone = M.smoothstep(0.72, 0.96, coarse) * aggregate
    result = M.mixColor(result, colour(c, 2, 0xFF89_8B85), stone)
    let dust = M.smoothstep(1 - speckles * 0.035, 1, fineValue) * (0.4 + wear * 0.6)
    return M.mixColor(result, colour(c, 3, 0xFFB0_A995), dust)
  }

  static func moss(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.018), 0.00001)
    let density = M.clamp01(parameter(p, 1, 0.74))
    let fibers = M.clamp01(parameter(p, 2, 0.58))
    let moisture = M.clamp01(parameter(p, 3, 0.38))
    let variation = M.clamp01(parameter(p, 4, 0.62))
    let clumps = M.clamp01(parameter(p, 5, 0.46))
    let patch = noise.fbm(x * s * 0.65, y * s * 0.65)
    let fuzz = noise.fine(x * s * 4, y * s * 4)
    let mask = M.smoothstep(1 - density, 0.9, patch + density * 0.45)
    let tone = M.clamp01(fuzz * variation + patch * (1 - variation))
    var result = M.mixColor(colour(c, 1, 0xFF29_451C), colour(c, 2, 0xFF64_8044), tone)
    var tips = M.smoothstep(0.75, 0.96, fuzz) * fibers
    tips += M.smoothstep(0.995, 1, M.hash(x, y, seed)) * fibers
    result = M.mixColor(result, colour(c, 3, 0xFFB1_BD69), M.clamp01(tips))
    result = M.mixColor(result, colour(c, 1, 0xFF29_451C), moisture * (1 - tone) * 0.4)
    return M.mixColor(colour(c, 0, 0xFF29_2516), result, mask * (0.7 + clumps * 0.3))
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
