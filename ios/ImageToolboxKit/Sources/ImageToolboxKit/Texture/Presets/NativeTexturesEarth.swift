import Foundation

/// Native textures 0...6 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// lava, clouds, smoke, stone, wood, camouflage and paper. Expressions keep the C++ operand order
/// so that the `Float` results agree with the native code.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func lava(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.008), 0.00001)
    noise.warp(&x, &y, scale: scale * 0.7, amount: parameter(p, 1, 32))
    let flow = M.maxOf(parameter(p, 2, 1.35), 0.05)
    let detail = M.clamp01(parameter(p, 3, 0.55))
    let crust = M.clamp01(parameter(p, 4, 0.52))
    let glow = M.clamp01(parameter(p, 5, 0.72))
    var field = noise.fbm(x * scale, y * scale)
    field =
      field * (1 - detail * 0.35)
      + noise.fine(x * scale * 3.7, y * scale * 3.7) * detail * 0.35
    let channels = pow(M.clamp01(1 - abs(field * 2 - 1)), flow)
    let molten = M.smoothstep(crust - 0.18, crust + 0.18, channels)
    let core = M.smoothstep(0.66, 0.98, channels) * glow
    let result = M.mixColor(colour(c, 0, 0xFF12_0B0A), colour(c, 1, 0xFFD5_2B0A), molten)
    return M.mixColor(result, colour(c, 2, 0xFFFF_D45A), core)
  }

  static func clouds(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.0045), 0.00001)
    let coverage = M.clamp01(parameter(p, 1, 0.48))
    let softness = M.maxOf(parameter(p, 2, 0.22), 0.005)
    let detail = M.clamp01(parameter(p, 3, 0.62))
    noise.warp(&x, &y, scale: scale * 0.65, amount: parameter(p, 4, 24))
    let density = M.maxOf(parameter(p, 5, 0.92), 0)
    let field =
      noise.fbm(x * scale, y * scale) * (1 - detail * 0.3)
      + noise.fine(x * scale * 3.2, y * scale * 3.2) * detail * 0.3
    let mask = M.smoothstep(coverage - softness, coverage + softness, field) * density
    let light = M.clamp01(
      field + (noise.fbm((x - 7) * scale, (y - 11) * scale) - field) * 1.8)
    let cloud = M.mixColor(colour(c, 1, 0xFF9E_ADBC), colour(c, 2, 0xFFF8_FBFF), light)
    return M.mixColor(colour(c, 0, 0xFF6F_A9DC), cloud, mask)
  }

  static func smoke(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.006), 0.00001)
    noise.warp(&x, &y, scale: scale * 0.7, amount: parameter(p, 1, 34))
    let density = M.clamp01(parameter(p, 2, 0.56))
    let wisps = M.maxOf(parameter(p, 3, 2.2), 0)
    let amount = M.maxOf(parameter(p, 4, 1.35), 0)
    let detail = M.clamp01(parameter(p, 5, 0.5))
    let base = noise.fbm(x * scale, y * scale)
    let curls = 0.5 + 0.5 * sin((x + y * 0.35) * scale * wisps * 4 + base * 8)
    var field =
      base * (0.8 - detail * 0.25)
      + noise.fine(x * scale * 4, y * scale * 4) * detail * 0.25 + curls * 0.2
    field = M.contrast(field, amount)
    let mask = M.smoothstep(1 - density, 0.92, field)
    let plume = M.mixColor(
      colour(c, 1, 0xFF44_4A52), colour(c, 2, 0xFFD5_D9DD), M.smoothstep(0.42, 0.9, field))
    return M.mixColor(colour(c, 0, 0xFF11_1318), plume, mask)
  }

  static func stone(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.011), 0.00001)
    let grain = M.clamp01(parameter(p, 1, 0.3))
    let veins = M.clamp01(parameter(p, 2, 0.58))
    let veinScale = M.maxOf(parameter(p, 3, 0.024), 0.00001)
    noise.warp(&x, &y, scale: scale, amount: parameter(p, 4, 18))
    let amount = M.maxOf(parameter(p, 5, 1.12), 0)
    var body = noise.fbm(x * scale, y * scale)
    body = M.contrast(
      body + (noise.fine(x * scale * 7, y * scale * 7) - 0.5) * grain * 0.35, amount)
    let veinField = abs(
      sin((x + y * 0.42) * veinScale + noise.fbm(x * scale * 0.7, y * scale * 0.7) * 9))
    let vein = (1 - M.smoothstep(0, 0.16, veinField)) * veins
    return M.mixColor(
      M.mixColor(colour(c, 0, 0xFF34_3536), colour(c, 1, 0xFFAA_A79F), body),
      colour(c, 2, 0xFFE2_DED3), vein)
  }

  static func wood(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.0039), 0.00001)
    let rings = M.maxOf(parameter(p, 1, 11.4), 0.1)
    let grain = M.clamp01(parameter(p, 2, 0.75))
    let distortion = parameter(p, 3, 15)
    let stretch = M.maxOf(parameter(p, 4, 7.42), 0.1)
    let amount = M.maxOf(parameter(p, 5, 0.17), 0)
    let low = noise.fbm(x * scale / stretch, y * scale)
    let phase = (x * scale / stretch + low * distortion * scale) * rings * 2 * pi
    let ring = M.contrast(0.5 + 0.5 * sin(phase), amount)
    let fibers = noise.fine(x * scale * 7 / stretch, y * scale * 7)
    let tone = M.clamp01(ring * (1 - grain * 0.35) + fibers * grain * 0.35)
    let poreNoise = noise.fine(x * scale * 19 / stretch, y * scale * 12)
    let elongatedPores = pow(M.clamp01(1 - abs(poreNoise * 2 - 1)), 7)
    let pores = M.smoothstep(0.62, 0.94, elongatedPores) * grain * 0.85
    return M.mixColor(
      M.mixColor(colour(c, 0, 0xFF3A_190B), colour(c, 1, 0xFFB9_6E32), tone),
      colour(c, 2, 0xFF1D_0D07), pores)
  }

  static func camouflage(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.007), 0.00001)
    noise.warp(&x, &y, scale: scale * 0.75, amount: parameter(p, 4, 28))
    let field = noise.fbm(x * scale, y * scale)
    let softness = M.maxOf(parameter(p, 5, 0.035), 0.0001)
    let firstMask = M.smoothstep(
      parameter(p, 1, 0.36) - softness, parameter(p, 1, 0.36) + softness, field)
    let secondMask = M.smoothstep(
      parameter(p, 2, 0.58) - softness, parameter(p, 2, 0.58) + softness, field)
    let thirdMask = M.smoothstep(
      parameter(p, 3, 0.76) - softness, parameter(p, 3, 0.76) + softness, field)
    var result = M.mixColor(colour(c, 0, 0xFF20_2719), colour(c, 1, 0xFF4F_6134), firstMask)
    result = M.mixColor(result, colour(c, 2, 0xFF78_6344), secondMask)
    return M.mixColor(result, colour(c, 3, 0xFFB4_A477), thirdMask)
  }

  static func paper(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.012), 0.00001)
    let density = M.maxOf(parameter(p, 1, 72), 1)
    let fiberStrength = M.clamp01(parameter(p, 2, 0.24))
    let grain = M.clamp01(parameter(p, 3, 0.16))
    let stains = M.clamp01(parameter(p, 4, 0.14))
    let roughness = M.clamp01(parameter(p, 5, 0.35))
    let body = noise.fbm(x * scale, y * scale)
    var fibers = pow(
      abs(sin((x + noise.fine(x * scale, y * scale) * 8) * scale * density)), 18)
    fibers = M.maxOf(
      fibers, pow(abs(sin((y + body * 7) * scale * density * 0.83)), 22))
    let speckle = M.hash(x, y, seed)
    let tone = M.clamp01(0.58 + (body - 0.5) * roughness + (speckle - 0.5) * grain)
    var result = M.mixColor(colour(c, 0, 0xFFE4_D4AE), colour(c, 1, 0xFFF5_E9C9), tone)
    result = M.mixColor(result, colour(c, 2, 0xFFB5_9C70), fibers * fiberStrength)
    let stain =
      M.smoothstep(0.72, 0.94, noise.fbm(x * scale * 0.35, y * scale * 0.35)) * stains
    return M.mixColor(result, colour(c, 3, 0xFF8A_6841), stain)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
