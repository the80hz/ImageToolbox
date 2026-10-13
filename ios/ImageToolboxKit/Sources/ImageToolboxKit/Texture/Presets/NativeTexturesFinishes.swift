import Foundation

/// Native textures 31...39 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// opal, damascus, lightning, velvet, ink marbling, holographic, bioluminescence, cosmic vortex
/// and lava lamp.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func opal(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.007), 0.00001)
    let play = M.clamp01(parameter(p, 1, 0.82))
    let milk = M.clamp01(parameter(p, 2, 0.48))
    let bands = parameter(p, 3, 8)
    noise.warp(&x, &y, scale: s, amount: parameter(p, 4, 28))
    let glow = M.clamp01(parameter(p, 5, 0.62))
    let a = noise.fbm(x * s, y * s)
    let b = noise.fine(x * s * 2, y * s * 2)
    let phase = M.fract((a * 0.7 + b * 0.3) * bands)
    var spectrum = M.mixColor(
      colour(c, 1, 0xFF4F_D5D1), colour(c, 2, 0xFFF0_72B6), M.smoothstep(0.15, 0.58, phase))
    spectrum = M.mixColor(spectrum, colour(c, 3, 0xFFFF_C857), M.smoothstep(0.58, 0.95, phase))
    return M.mixColor(
      colour(c, 0, 0xFFDD_E8DF), spectrum,
      play * (1 - milk * 0.55) * M.smoothstep(0.22, 0.8, a + glow * 0.12))
  }

  static func damascus(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let layers = parameter(p, 1, 22)
    let folding = M.clamp01(parameter(p, 2, 0.72))
    noise.warp(&x, &y, scale: s, amount: parameter(p, 3, 34))
    let polish = M.clamp01(parameter(p, 4, 0.58))
    let amount = parameter(p, 5, 1.4)
    let q = noise.fbm(x * s, y * s)
    let band = M.contrast(
      0.5 + 0.5 * sin((x + y * 0.22) * s * layers + q * folding * 13), amount)
    var metal = M.mixColor(colour(c, 0, 0xFF17_1C20), colour(c, 1, 0xFF66_727A), band)
    metal = M.mixColor(metal, colour(c, 2, 0xFFC8_D0D2), M.smoothstep(0.76, 0.98, band) * polish)
    return M.mixColor(
      metal, colour(c, 3, 0xFF30_4C57), M.smoothstep(0.42, 0.58, q) * (1 - band) * 0.35)
  }

  static func lightning(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let branches = parameter(p, 1, 7)
    noise.warp(&x, &y, scale: s, amount: parameter(p, 2, 42))
    let width = M.maxOf(parameter(p, 3, 0.055), 0.002)
    let glow = M.clamp01(parameter(p, 4, 0.82))
    let intensity = M.clamp01(parameter(p, 5, 0.9))
    let q = noise.fbm(x * s, y * s)
    let pathA = abs(sin((x * 0.35 + y) * s * branches + q * 11))
    let pathB = abs(sin((x - y * 0.48) * s * branches * 1.7 - q * 9))
    let distance = M.minOf(pathA, pathB + 0.08)
    let halo = 1 - M.smoothstep(width, width * 5, distance)
    let bolt = 1 - M.smoothstep(width * 0.25, width, distance)
    var result = M.mixColor(colour(c, 0, 0xFF03_0612), colour(c, 1, 0xFF25_46A8), halo * glow)
    result = M.mixColor(result, colour(c, 2, 0xFF68_C9FF), bolt * intensity)
    return M.mixColor(result, colour(c, 3, 0xFFF2_FCFF), bolt * bolt)
  }

  static func velvet(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.014), 0.00001)
    let fibers = M.clamp01(parameter(p, 1, 0.78))
    let angle = parameter(p, 2, 0.18) * 2 * pi
    let softness = M.clamp01(parameter(p, 3, 0.7))
    let sheen = M.clamp01(parameter(p, 4, 0.62))
    let folds = M.clamp01(parameter(p, 5, 0.34))
    let axis = x * cos(angle) + y * sin(angle)
    let q = noise.fbm(x * s * 0.5, y * s * 0.5)
    let nap = pow(M.clamp01(0.5 + 0.5 * sin(axis * s * 70 + q * 4)), 5)
    let fold = 0.5 + 0.5 * sin((x - y * 0.3) * s * 4 + q * 8)
    var result = M.mixColor(
      colour(c, 0, 0xFF17_051E), colour(c, 1, 0xFF5E_176A), softness + fold * folds * 0.3)
    result = M.mixColor(result, colour(c, 2, 0xFFC1_48B8), nap * fibers * sheen)
    return M.mixColor(result, colour(c, 3, 0xFFF0_A6D8), pow(nap, 4) * sheen)
  }

  static func inkMarbling(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    let ribbons = parameter(p, 1, 14)
    noise.warp(&x, &y, scale: s, amount: parameter(p, 2, 48))
    let feather = M.clamp01(parameter(p, 3, 0.52))
    let balance = M.clamp01(parameter(p, 4, 0.5))
    let amount = parameter(p, 5, 1.25)
    let q = noise.fbm(x * s, y * s)
    let wave = M.contrast(0.5 + 0.5 * sin((x + y * 0.45) * s * ribbons + q * 12), amount)
    let ink = M.smoothstep(0.22 - feather * 0.1, 0.78 + feather * 0.1, wave)
    var result = M.mixColor(
      colour(c, 0, 0xFFF3_E9D3), colour(c, 1, 0xFF16_4B78), ink * (1 - balance * 0.35))
    result = M.mixColor(result, colour(c, 2, 0xFF9D_2949), M.smoothstep(0.58, 0.92, q) * balance)
    return M.mixColor(
      result, colour(c, 3, 0xFF1C_1831), pow(M.clamp01(1 - abs(wave * 2 - 1)), 8) * 0.55)
  }

  static func holographic(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    let spectrum = parameter(p, 1, 12)
    let crinkles = M.clamp01(parameter(p, 2, 0.7))
    let diffraction = M.clamp01(parameter(p, 3, 0.82))
    let angle = parameter(p, 4, 0.3) * 2 * pi
    let shine = M.clamp01(parameter(p, 5, 0.72))
    let q = noise.fbm(x * s, y * s)
    let axis = x * cos(angle) + y * sin(angle)
    let phase = M.fract(axis * s * spectrum + q * crinkles * 3)
    var result = M.mixColor(
      colour(c, 1, 0xFF4D_E5E2), colour(c, 2, 0xFFE9_5AC8), M.smoothstep(0.1, 0.55, phase))
    result = M.mixColor(result, colour(c, 3, 0xFFF7_EA72), M.smoothstep(0.55, 0.95, phase))
    result = M.mixColor(colour(c, 0, 0xFFCD_D4DE), result, diffraction)
    return M.mixColor(
      result, 0xFFFF_FFFF, pow(M.clamp01(1 - abs(phase - 0.5) * 2), 12) * shine)
  }

  static func bioluminescence(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let veins = M.clamp01(parameter(p, 1, 0.72))
    let branching = M.clamp01(parameter(p, 2, 0.58))
    noise.warp(&x, &y, scale: s, amount: parameter(p, 3, 30))
    let glow = M.clamp01(parameter(p, 4, 0.86))
    let depth = M.clamp01(parameter(p, 5, 0.62))
    let a = noise.fbm(x * s, y * s)
    let b = noise.fine(x * s * 2.2, y * s * 2.2)
    let ridgeA = 1 - abs(a * 2 - 1)
    let ridgeB = 1 - abs(b * 2 - 1)
    let network = M.maxOf(pow(ridgeA, 9), pow(ridgeB, 12) * branching) * veins
    var result = M.mixColor(colour(c, 0, 0xFF03_1A1A), colour(c, 1, 0xFF0B_514D), a * depth)
    result = M.mixColor(
      result, colour(c, 2, 0xFF20_E6C2), M.smoothstep(0.05, 0.55, network) * glow)
    return M.mixColor(result, colour(c, 3, 0xFFC4_FFF1), M.smoothstep(0.62, 0.98, network))
  }

  static func cosmicVortex(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ seed: Int32, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    let arms = parameter(p, 1, 5)
    let twist = parameter(p, 2, 12)
    let turbulence = M.clamp01(parameter(p, 3, 0.52))
    let stars = M.clamp01(parameter(p, 4, 0.28))
    let coreGlow = M.clamp01(parameter(p, 5, 0.82))
    let dx = (x - Float(width) * 0.5) / Float(max(width, 1))
    let dy = (y - Float(height) * 0.5) / Float(max(height, 1))
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let q = noise.fbm(x * s, y * s)
    let spiral = 0.5 + 0.5 * sin(angle * arms + radius * twist * 20 + q * turbulence * 8)
    let mask = M.smoothstep(0.52, 0.08, radius) * M.smoothstep(0.35, 0.92, spiral)
    let gas = M.mixColor(colour(c, 1, 0xFF27_4AA8), colour(c, 2, 0xFF8D_3EC2), q)
    var result = M.mixColor(colour(c, 0, 0xFF02_030B), gas, mask)
    result = M.mixColor(
      result, colour(c, 3, 0xFFFF_DDA0), M.smoothstep(0.18, 0.0, radius) * coreGlow)
    return M.mixColor(
      result, 0xFFFF_FFFF, M.smoothstep(1 - stars * 0.009, 1, M.hash(x, y, seed)))
  }

  static func lavaLamp(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let s = M.maxOf(parameter(p, 0, 0.007), 0.00001)
    let blobs = parameter(p, 1, 6)
    let softness = M.clamp01(parameter(p, 2, 0.24))
    noise.warp(&x, &y, scale: s, amount: parameter(p, 3, 32))
    let glow = M.clamp01(parameter(p, 4, 0.58))
    let amount = parameter(p, 5, 1.3)
    let a = sin(x * s * blobs + noise.fbm(x * s, y * s) * 7)
    let b = sin(y * s * blobs * 0.83 - noise.fine(x * s, y * s) * 6)
    let field = M.contrast(M.clamp01(0.5 + (a + b) * 0.24), amount)
    let mask = M.smoothstep(0.52 - softness * 0.3, 0.52 + softness * 0.3, field)
    var blob = M.mixColor(colour(c, 1, 0xFFFF_3D81), colour(c, 2, 0xFFFF_8A24), field)
    blob = M.mixColor(blob, colour(c, 3, 0xFFFF_D45C), M.smoothstep(0.74, 0.98, field) * glow)
    return M.mixColor(colour(c, 0, 0xFF1C_0929), blob, mask)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
