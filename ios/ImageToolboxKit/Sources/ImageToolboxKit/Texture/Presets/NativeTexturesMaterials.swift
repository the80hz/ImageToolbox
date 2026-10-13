import Foundation

/// Native textures 7...15 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// rust, fabric, topography, cells, cracks, water ripples, foliage, bricks and terrain.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func rust(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let corrosion = M.clamp01(parameter(p, 1, 0.55))
    let pitting = M.clamp01(parameter(p, 2, 0.34))
    let flakes = M.clamp01(parameter(p, 3, 0.42))
    noise.warp(&x, &y, scale: scale, amount: parameter(p, 4, 16))
    let amount = M.maxOf(parameter(p, 5, 1.25), 0)
    let field = M.contrast(noise.fbm(x * scale, y * scale), amount)
    let rustMask = M.smoothstep(0.72 - corrosion * 0.55, 0.82 - corrosion * 0.25, field)
    let oxidation = noise.fine(x * scale * 4.2, y * scale * 4.2)
    var rustColour = M.mixColor(colour(c, 1, 0xFF3A_170B), colour(c, 2, 0xFF9B_3E13), oxidation)
    rustColour = M.mixColor(
      rustColour, colour(c, 3, 0xFFE0_7822), M.smoothstep(0.68, 0.95, oxidation) * flakes)
    let pits =
      (1 - M.smoothstep(0, 0.16, noise.cellEdge(x, y, scale: scale * 2.4, jitter: 1))) * pitting
    return M.mixColor(
      M.mixColor(colour(c, 0, 0xFF59_6065), rustColour, rustMask),
      colour(c, 1, 0xFF3A_170B), pits)
  }

  static func fabric(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.018), 0.00001)
    let horizontal = M.maxOf(parameter(p, 1, 28), 1)
    let vertical = M.maxOf(parameter(p, 2, 28), 1)
    let irregularity = M.clamp01(parameter(p, 3, 0.14))
    let depth = M.clamp01(parameter(p, 4, 0.48))
    let fuzz = M.clamp01(parameter(p, 5, 0.1))
    let wobble = (noise.fine(x * scale * 2, y * scale * 2) - 0.5) * irregularity * 2
    let warp = 0.5 + 0.5 * cos((x * scale * vertical + wobble) * 2 * pi)
    let weft = 0.5 + 0.5 * cos((y * scale * horizontal - wobble) * 2 * pi)
    let over = fmod(floor(x * scale * vertical) + floor(y * scale * horizontal), 2)
    let thread = over < 1 ? warp : weft
    var result = M.mixColor(colour(c, 0, 0xFF49_6B82), colour(c, 1, 0xFF78_95A7), over)
    result = M.mixColor(result, colour(c, 2, 0xFF26_3C4B), (1 - thread) * depth)
    result = M.mixColor(
      result, colour(c, 3, 0xFFB6_CAD4), M.smoothstep(0.72, 1, thread) * depth)
    return M.mixColor(
      result, colour(c, 3, 0xFFB6_CAD4),
      M.smoothstep(1 - fuzz * 0.12, 1, M.hash(x, y, seed)) * fuzz)
  }

  static func topography(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.0055), 0.00001)
    let lineCount = M.maxOf(parameter(p, 1, 16), 1)
    let thickness = M.clamp(parameter(p, 2, 0.11), 0.001, 0.49)
    let shading = M.clamp01(parameter(p, 3, 0.42))
    noise.warp(&x, &y, scale: scale * 0.75, amount: parameter(p, 4, 12))
    let height = M.contrast(noise.fbm(x * scale, y * scale), parameter(p, 5, 1.1))
    let contourPosition = M.fract(height * lineCount)
    let distance = M.minOf(contourPosition, 1 - contourPosition)
    let line = 1 - M.smoothstep(thickness * 0.45, thickness, distance)
    let fill = 0.5 + (height - 0.5) * shading * 2
    return M.mixColor(
      M.mixColor(colour(c, 0, 0xFF17_3C3B), colour(c, 1, 0xFFB5_C98A), fill),
      colour(c, 2, 0xFFF2_E6B6), line)
  }

  static func cells(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.018), 0.00001)
    let jitter = parameter(p, 1, 0.92)
    let borderWidth = M.clamp(parameter(p, 2, 0.12), 0.001, 0.9)
    let glow = M.clamp01(parameter(p, 3, 0.28))
    noise.warp(&x, &y, scale: scale, amount: parameter(p, 4, 6))
    let variation = M.clamp01(parameter(p, 5, 0.42))
    let edgeDistance = noise.cellEdge(x, y, scale: scale, jitter: jitter)
    let edge = 1 - M.smoothstep(borderWidth * 0.35, borderWidth, edgeDistance)
    let halo = (1 - M.smoothstep(borderWidth, borderWidth * 3.5, edgeDistance)) * glow
    let cellTone = noise.cellVariation(x, y, scale: scale, jitter: jitter) * variation
    var result = M.mixColor(
      colour(c, 0, 0xFF10_1A24), colour(c, 1, 0xFF21_6E78), 0.55 + cellTone)
    result = M.mixColor(result, colour(c, 2, 0xFF5A_D1C8), M.maxOf(edge, halo))
    return M.mixColor(result, colour(c, 3, 0xFFC9_FFF4), edge * glow)
  }

  static func cracks(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.019), 0.00001)
    let width = M.clamp(parameter(p, 1, 0.065), 0.001, 0.5)
    let density = M.clamp01(parameter(p, 2, 0.72))
    noise.warp(&x, &y, scale: scale, amount: parameter(p, 3, 9))
    let depth = M.clamp01(parameter(p, 4, 0.72))
    let branching = M.clamp01(parameter(p, 5, 0.45))
    let primaryDistance = noise.cellEdge(x, y, scale: scale, jitter: 1)
    let secondaryDistance = noise.secondaryCellEdge(
      x + 37, y - 19, scale: scale * 1.9, jitter: 0.82)
    let primary = 1 - M.smoothstep(width * 0.45, width, primaryDistance)
    let secondary =
      (1 - M.smoothstep(width * 0.28, width * 0.72, secondaryDistance)) * branching
    let crack = M.maxOf(primary, secondary) * density
    let edge = (1 - M.smoothstep(width, width * 2.8, primaryDistance)) * (1 - crack) * depth
    let surface = noise.fbm(x * scale * 0.65, y * scale * 0.65)
    var result = M.mixColor(colour(c, 0, 0xFF8D_8374), colour(c, 1, 0xFFC0_B6A5), surface)
    result = M.mixColor(result, colour(c, 3, 0xFF55_4E45), edge)
    return M.mixColor(result, colour(c, 2, 0xFF16_1412), crack * depth)
  }

  static func waterRipples(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.0075), 0.00001)
    let frequency = M.maxOf(parameter(p, 1, 22), 0.1)
    let distortion = parameter(p, 2, 22)
    let caustics = M.clamp01(parameter(p, 3, 0.58))
    let depth = M.clamp01(parameter(p, 4, 0.55))
    let highlights = M.clamp01(parameter(p, 5, 0.62))
    noise.warp(&x, &y, scale: scale * 0.8, amount: distortion)
    let flow = noise.fbm(x * scale, y * scale)
    let waveA = sin((x * 0.78 + y * 0.22) * scale * frequency + flow * 5)
    let waveB = sin((x * -0.31 + y * 0.95) * scale * frequency * 0.73 - flow * 4)
    let waves = M.clamp01(0.5 + (waveA + waveB) * 0.22)
    let lightLines = pow(M.clamp01(1 - abs(waveA + waveB) * 0.5), 7) * caustics
    let tone = M.clamp01(waves * depth + flow * (1 - depth))
    return M.mixColor(
      M.mixColor(colour(c, 0, 0xFF07_3456), colour(c, 1, 0xFF16_8EAE), tone),
      colour(c, 2, 0xFFB9_F7F2), lightLines * highlights)
  }

  static func foliage(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.022), 0.00001)
    let density = M.clamp01(parameter(p, 1, 0.72))
    let softness = M.clamp(parameter(p, 2, 0.16), 0.01, 0.6)
    let veins = M.clamp01(parameter(p, 3, 0.38))
    let lighting = M.clamp01(parameter(p, 4, 0.62))
    let variation = M.clamp01(parameter(p, 5, 0.58))
    noise.warp(&x, &y, scale: scale, amount: 4 + variation * 10)
    let edgeDistance = noise.cellEdge(x, y, scale: scale, jitter: 0.92)
    let cellTone = noise.cellVariation(x, y, scale: scale, jitter: 0.92)
    var leafMask = M.smoothstep(softness * 0.35, softness, edgeDistance)
    let overlap = noise.fbm(x * scale * 0.7, y * scale * 0.7)
    leafMask *= M.smoothstep(1 - density, 1, overlap + density * 0.55)
    let vein = (1 - M.smoothstep(softness, softness * 2.1, edgeDistance)) * veins
    let detail = noise.fine(x * scale * 2.5, y * scale * 2.5)
    let light = M.clamp01(cellTone * variation + detail * lighting)
    var leaf = M.mixColor(colour(c, 1, 0xFF24_5C25), colour(c, 2, 0xFF4E_9A3D), light)
    leaf = M.mixColor(leaf, colour(c, 3, 0xFFA4_CE65), M.smoothstep(0.68, 0.96, light) * lighting)
    leaf = M.mixColor(leaf, colour(c, 1, 0xFF24_5C25), vein)
    return M.mixColor(colour(c, 0, 0xFF10_2A13), leaf, leafMask)
  }

  static func bricks(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let scale = M.maxOf(parameter(p, 0, 0.012), 0.00001)
    let aspect = M.maxOf(parameter(p, 1, 2.15), 0.25)
    let mortarWidth = M.clamp(parameter(p, 2, 0.09), 0.005, 0.45)
    let irregularity = M.clamp01(parameter(p, 3, 0.18))
    let roughness = M.clamp01(parameter(p, 4, 0.42))
    let bevel = M.clamp01(parameter(p, 5, 0.55))
    let row = floor(y * scale)
    let stagger = fmod(abs(row), 2) * 0.5
    let wobble = (noise.fine(x * scale * 0.7, y * scale * 0.7) - 0.5) * irregularity
    let ux = M.fract(x * scale / aspect + stagger + wobble * 0.12)
    let uy = M.fract(y * scale + wobble * 0.1)
    let dx = M.minOf(ux, 1 - ux) * aspect
    let edgeDistance = M.minOf(dx, M.minOf(uy, 1 - uy))
    let brickMask = M.smoothstep(mortarWidth * 0.65, mortarWidth, edgeDistance)
    let edgeLight = M.smoothstep(mortarWidth, mortarWidth * 3.5, edgeDistance) * bevel
    let surface = noise.fine(x * scale * 5, y * scale * 5)
    let brickId = M.hash(floor(x * scale / aspect + stagger), row, 1777)
    let tone = M.clamp01(0.35 + brickId * 0.38 + (surface - 0.5) * roughness * 0.7)
    var brick = M.mixColor(colour(c, 1, 0xFF6F_2418), colour(c, 2, 0xFFB6_4C32), tone)
    brick = M.mixColor(brick, colour(c, 3, 0xFFD7_7A55), edgeLight * 0.32)
    return M.mixColor(colour(c, 0, 0xFFB8_AD99), brick, brickMask)
  }

  static func terrain(
    _ noise: NativeNoiseBank, _ x0: Float, _ y0: Float, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    var x = x0
    var y = y0
    let scale = M.maxOf(parameter(p, 0, 0.0045), 0.00001)
    let waterLevel = M.clamp01(parameter(p, 1, 0.34))
    let mountainLevel = M.clamp01(parameter(p, 2, 0.7))
    let erosion = M.clamp01(parameter(p, 3, 0.46))
    let detail = M.clamp01(parameter(p, 4, 0.58))
    let snowLevel = M.clamp01(parameter(p, 5, 0.86))
    noise.warp(&x, &y, scale: scale * 0.7, amount: erosion * 38)
    let broad = noise.fbm(x * scale, y * scale)
    let fineValue = noise.fine(x * scale * 2.3, y * scale * 2.3)
    let ridges = 1 - abs(fineValue * 2 - 1)
    let height = M.clamp01(broad * (1 - detail * 0.3) + ridges * detail * 0.3)
    let left = noise.fbm((x - 2) * scale, y * scale)
    let right = noise.fbm((x + 2) * scale, y * scale)
    let slope = abs(right - left) * 9
    let shore = M.smoothstep(waterLevel - 0.025, waterLevel + 0.035, height)
    let rock = M.smoothstep(mountainLevel - 0.12, mountainLevel + 0.1, height + slope)
    var land = M.mixColor(colour(c, 1, 0xFF5F_873F), colour(c, 2, 0xFF74_6C5D), rock)
    land = M.mixColor(
      land, colour(c, 3, 0xFFE9_EEE8), M.smoothstep(snowLevel - 0.07, snowLevel, height))
    let water = M.mixColor(
      colour(c, 0, 0xFF19_4D73), colour(c, 1, 0xFF5F_873F),
      M.smoothstep(waterLevel - 0.12, waterLevel, height) * 0.2)
    return M.mixColor(water, land, shore)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
