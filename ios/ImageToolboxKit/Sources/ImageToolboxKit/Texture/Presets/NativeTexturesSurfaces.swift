import Foundation

/// Native textures 16...19 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// ice, sand, nebula and honeycomb.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func ice(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.014), 0.00001)
    let crackWidth = M.clamp(parameter(p, 1, 0.075), 0.002, 0.4)
    let frost = M.clamp01(parameter(p, 2, 0.48))
    let depth = M.clamp01(parameter(p, 3, 0.64))
    noise.warp(&x, &y, scale: scale, amount: parameter(p, 4, 8))
    let sparkle = M.clamp01(parameter(p, 5, 0.32))
    let body = noise.fbm(x * scale * 0.65, y * scale * 0.65)
    let edgeDistance = noise.cellEdge(x, y, scale: scale, jitter: 0.95)
    let crack = 1 - M.smoothstep(crackWidth * 0.45, crackWidth, edgeDistance)
    let fineValue = noise.fine(x * scale * 3.2, y * scale * 3.2)
    let frostMask = M.smoothstep(0.58, 0.9, fineValue) * frost
    let speck = M.smoothstep(1 - sparkle * 0.025, 1, M.hash(x, y, seed)) * sparkle
    var result = M.mixColor(
      colour(c, 0, 0xFF15_5A79), colour(c, 1, 0xFF79_C8DC), M.clamp01(body + depth * 0.2))
    result = M.mixColor(result, colour(c, 2, 0xFFD8_F4F5), M.maxOf(frostMask, speck))
    return M.mixColor(result, colour(c, 3, 0xFFF5_FFFF), crack * depth)
  }

  static func sand(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.005), 0.00001)
    let frequency = M.maxOf(parameter(p, 1, 12), 0.1)
    let angle = parameter(p, 2, 0.32) * 2 * pi
    let ripples = M.clamp01(parameter(p, 3, 0.62))
    let grain = M.clamp01(parameter(p, 4, 0.22))
    let amount = M.maxOf(parameter(p, 5, 1.18), 0)
    let dune = noise.fbm(x * scale, y * scale)
    let axis = x * cos(angle) + y * sin(angle)
    let wave = 0.5 + 0.5 * sin(axis * scale * frequency + dune * 5)
    let grains = M.hash(x, y, seed)
    var tone = dune * (1 - ripples * 0.42) + wave * ripples * 0.42
    tone = M.contrast(tone + (grains - 0.5) * grain * 0.22, amount)
    let result = M.mixColor(colour(c, 0, 0xFF9A_632E), colour(c, 1, 0xFFD6_A85A), tone)
    let highlight = M.smoothstep(0.7, 0.96, wave) * ripples * 0.45
    return M.mixColor(result, colour(c, 2, 0xFFF2_D58D), highlight)
  }

  static func nebula(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.004), 0.00001)
    noise.warp(&x, &y, scale: scale * 0.65, amount: parameter(p, 1, 44))
    let density = M.clamp01(parameter(p, 2, 0.64))
    let stars = M.clamp01(parameter(p, 3, 0.38))
    let glow = M.clamp01(parameter(p, 4, 0.72))
    let amount = M.maxOf(parameter(p, 5, 1.45), 0)
    let a = noise.fbm(x * scale, y * scale)
    let b = noise.fine(x * scale * 2.1 + 11, y * scale * 2.1 - 7)
    let cloud = M.contrast(a * 0.68 + b * 0.32, amount)
    let mask = M.smoothstep(0.7 - density * 0.42, 0.88, cloud)
    var gas = M.mixColor(colour(c, 1, 0xFF54_2577), colour(c, 2, 0xFF23_67A2), b)
    gas = M.mixColor(gas, colour(c, 3, 0xFFF2_A4DF), M.smoothstep(0.7, 0.96, cloud) * glow)
    let result = M.mixColor(colour(c, 0, 0xFF05_0713), gas, mask)
    let star = M.smoothstep(1 - stars * 0.012, 1, M.hash(x, y, seed))
    return M.mixColor(result, 0xFFFF_FFFF, star)
  }

  static func honeycomb(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.018), 0.00001)
    let borderWidth = M.clamp(parameter(p, 1, 0.095), 0.005, 0.4)
    let bevel = M.clamp01(parameter(p, 2, 0.5))
    let irregularity = M.clamp01(parameter(p, 3, 0.12))
    let fill = M.clamp01(parameter(p, 4, 0.72))
    let glow = M.clamp01(parameter(p, 5, 0.35))
    let wobble = (noise.fine(x * scale, y * scale) - 0.5) * irregularity
    let px = x * scale + wobble
    let py = y * scale + wobble * 0.7
    let ax = M.fract(px / 1.7320508) * 1.7320508 - 0.8660254
    let ay = M.fract(py) - 0.5
    let bx = M.fract((px - 0.8660254) / 1.7320508) * 1.7320508 - 0.8660254
    let by = M.fract(py - 0.5) - 0.5
    let useA = ax * ax + ay * ay < bx * bx + by * by
    let gx = useA ? ax : bx
    let gy = useA ? ay : by
    let hexDistance = M.maxOf(abs(gx) * 0.8660254 + abs(gy) * 0.5, abs(gy))
    let edgeDistance = 0.5 - hexDistance
    let interior = M.smoothstep(borderWidth * 0.55, borderWidth, edgeDistance)
    let bevelLight = M.smoothstep(borderWidth, borderWidth * 3.2, edgeDistance) * bevel
    let center = M.clamp01(1 - hexDistance * 1.7)
    var cell = M.mixColor(colour(c, 1, 0xFF6F_3A08), colour(c, 2, 0xFFE5_9B12), center * fill)
    cell = M.mixColor(cell, colour(c, 3, 0xFFFF_D45C), bevelLight * glow)
    return M.mixColor(colour(c, 0, 0xFF24_1305), cell, interior)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
