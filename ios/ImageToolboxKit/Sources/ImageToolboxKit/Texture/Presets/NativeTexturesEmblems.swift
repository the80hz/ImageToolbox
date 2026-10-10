import Foundation

/// Native textures 48...50 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// peacock feather, nautilus shell and ringed planet, plus the three-stop palette helper.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  static func peacockFeather(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.012), 0.00001)
    let eyeSize = M.clamp(parameter(p, 1, 0.24), 0.08, 0.4)
    let density = M.maxOf(parameter(p, 2, 54), 8)
    let curvature = M.clamp01(parameter(p, 3, 0.58))
    let iridescence = M.clamp01(parameter(p, 4, 0.8))
    let softness = M.clamp01(parameter(p, 5, 0.42))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.43) / unit
    let curvedX = dx + dy * dy * curvature * 0.48
    let featherRadius = ((curvedX / 0.34) * (curvedX / 0.34) + (dy / 0.46) * (dy / 0.46))
      .squareRoot()
    let featherMask = M.smoothstep(1.05, 0.86 - softness * 0.08, featherRadius)
    let eyeX = curvedX / eyeSize
    let eyeY = dy / (eyeSize * 1.22)
    let eyeRadius = (eyeX * eyeX + eyeY * eyeY).squareRoot()
    let grain = noise.fbm(x * s, y * s)
    let barbPhase = abs(curvedX) * density + dy * density * 0.16 + grain * 3
    let barbs = pow(M.clamp01(0.5 + 0.5 * sin(barbPhase)), 5) * featherMask
    var result = M.mixColor(
      colour(c, 0, 0xFF06_150F), colour(c, 1, 0xFF16_7D55), featherMask * (0.58 + barbs * 0.42))
    let goldRing = (1 - M.smoothstep(0.08, 0.18, abs(eyeRadius - 0.83))) * featherMask
    let blueEye = M.smoothstep(0.72, 0.56, eyeRadius) * featherMask
    let darkEye = M.smoothstep(0.38, 0.18, eyeRadius) * featherMask
    result = M.mixColor(result, colour(c, 3, 0xFFE4_BC45), goldRing * iridescence)
    result = M.mixColor(result, colour(c, 2, 0xFF12_48BC), blueEye * iridescence)
    result = M.mixColor(result, colour(c, 0, 0xFF06_150F), darkEye * 0.88)
    let shaft = (1 - M.smoothstep(0.003, 0.012, abs(curvedX))) * M.smoothstep(0.18, 0.55, dy + 0.36)
    return M.mixColor(result, colour(c, 3, 0xFFE4_BC45), shaft * 0.62)
  }

  static func nautilusShell(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.011), 0.00001)
    let turns = M.maxOf(parameter(p, 1, 3.4), 0.5)
    let chambers = M.maxOf(parameter(p, 2, 19), 3)
    let opening = M.clamp(parameter(p, 3, 0.13), 0.03, 0.3)
    let ridges = M.clamp01(parameter(p, 4, 0.68))
    let pearl = M.clamp01(parameter(p, 5, 0.46))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let shellRadius = ((dx / 0.43) * (dx / 0.43) + (dy / 0.36) * (dy / 0.36)).squareRoot()
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let mask = M.smoothstep(1.02, 0.96, shellRadius)
    let grain = noise.fbm(x * s, y * s)
    let spiralPhase = angle - log(radius + 0.018) * turns * 2
    let spiral = pow(M.clamp01(1 - abs(sin(spiralPhase))), 8)
    let chamberLine = pow(
      M.clamp01(1 - abs(sin(angle * chambers * 0.5 + log(radius + 0.025) * 3))), 12)
    let relief = M.clamp01(spiral * 0.8 + chamberLine * ridges * 0.65)
    var shell = M.mixColor(
      colour(c, 1, 0xFF4A_2D22), colour(c, 2, 0xFFD9_AD79),
      M.clamp01(0.35 + grain * 0.42 + (0.5 - dy) * 0.28))
    shell = M.mixColor(shell, colour(c, 3, 0xFFFF_F0D1), relief * pearl)
    var result = M.mixColor(colour(c, 0, 0xFF15_2228), shell, mask)
    let mouthX = dx - 0.25
    let mouthY = dy + 0.02
    let mouth =
      1
      - M.smoothstep(
        opening * 0.45, opening, (mouthX * mouthX + mouthY * mouthY).squareRoot())
    result = M.mixColor(result, colour(c, 1, 0xFF4A_2D22), mouth * mask * 0.72)
    let rim = (1 - M.smoothstep(0, 0.025, abs(shellRadius - 0.98))) * mask
    return M.mixColor(result, colour(c, 3, 0xFFFF_F0D1), rim * 0.54)
  }

  static func ringedPlanet(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ seed: Int32, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let planetSize = M.clamp(parameter(p, 1, 0.24), 0.08, 0.38)
    let tilt = M.clamp01(parameter(p, 2, 0.72))
    let ringWidth = M.clamp(parameter(p, 3, 0.16), 0.03, 0.3)
    let atmosphere = M.clamp01(parameter(p, 4, 0.62))
    let stars = M.clamp01(parameter(p, 5, 0.25))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let flatten = 0.5 - tilt * 0.38
    let ringRadius = (dx * dx + (dy / M.maxOf(flatten, 0.06)) * (dy / M.maxOf(flatten, 0.06)))
      .squareRoot()
    let ringInner = planetSize * 1.15
    let ringOuter = ringInner + ringWidth
    let ring =
      M.smoothstep(ringInner, ringInner + 0.012, ringRadius)
      * (1 - M.smoothstep(ringOuter - 0.012, ringOuter, ringRadius))
    let ringBands = 0.5 + 0.5 * sin(ringRadius * 260 + noise.fine(x * s, y * s) * 2)
    let star = M.smoothstep(1 - stars * 0.008, 1, M.hash(x, y, seed))
    var result = M.mixColor(colour(c, 0, 0xFF02_040D), 0xFFFF_FFFF, star)
    let rings = M.mixColor(
      colour(c, 1, 0xFF15_234D), colour(c, 3, 0xFFFF_E1A6), 0.46 + ringBands * 0.45)
    result = M.mixColor(result, rings, ring * 0.68)
    let planetMask = M.smoothstep(planetSize + 0.006, planetSize - 0.006, radius)
    let light = M.clamp01(0.52 - dx * 1.55 - dy * 0.75)
    let bands = 0.5 + 0.5 * sin(dy / planetSize * 23 + noise.fbm(x * s, y * s) * 2.8)
    let globe = M.mixColor(
      colour(c, 1, 0xFF15_234D), colour(c, 2, 0xFFE5_8C62), light * (0.72 + bands * 0.28))
    result = M.mixColor(result, globe, planetMask)
    result = M.mixColor(result, rings, ring * M.smoothstep(-0.01, 0.02, dy))
    let atmosphereRim =
      (1 - M.smoothstep(0, planetSize * 0.06, abs(radius - planetSize))) * atmosphere
    return M.mixColor(result, colour(c, 3, 0xFFFF_E1A6), atmosphereRim * 0.48)
  }

  /// A colour from a palette of four stops, for a value in 0...1.
  static func palette4(_ colors: [UInt32], _ value: Float) -> UInt32 {
    let t = M.clamp01(value) * 3
    if t < 1 {
      return M.mixColor(colour(colors, 0, 0xFF05_0611), colour(colors, 1, 0xFF29_4A8A), t)
    }
    if t < 2 {
      return M.mixColor(colour(colors, 1, 0xFF29_4A8A), colour(colors, 2, 0xFFD9_4B91), t - 1)
    }
    return M.mixColor(colour(colors, 2, 0xFFD9_4B91), colour(colors, 3, 0xFFFF_E8A3), t - 2)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
