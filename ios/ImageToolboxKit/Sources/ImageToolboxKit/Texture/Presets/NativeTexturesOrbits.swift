import Foundation

/// Native textures 44...47 of the Android fast-noise module, ported from `ProceduralTextures.cpp`:
/// strange attractor, ferrofluid crown, supernova and iris.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func strangeAttractor(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.01), 0.00001)
    let lobes = M.maxOf(parameter(p, 1, 3), 1)
    let density = M.clamp(parameter(p, 2, 18), 4, 40)
    let curvature = parameter(p, 3, 6)
    let thickness = M.maxOf(parameter(p, 4, 0.035), 0.002)
    let glow = M.clamp01(parameter(p, 5, 0.8))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    var minimumDistance: Float = 10
    let samples = Int(64 + density * 3)
    let phase = (noise.fbm(x * s * 0.2, y * s * 0.2) - 0.5) * 0.12
    for i in 0..<samples {
      let t = Float(i) / Float(samples - 1) * 2 * pi
      var orbitX = sin(t * lobes + sin(t * curvature) * 0.72) * 0.31
      var orbitY = sin(t * (lobes + 1) + cos(t * curvature * 0.73) * 0.58) * 0.31
      orbitX += sin(t * 2) * phase
      orbitY += cos(t * 3) * phase
      let distance = ((dx - orbitX) * (dx - orbitX) + (dy - orbitY) * (dy - orbitY)).squareRoot()
      minimumDistance = M.minOf(minimumDistance, distance)
    }
    let line = 1 - M.smoothstep(thickness * 0.22, thickness, minimumDistance)
    let halo = 1 - M.smoothstep(thickness, thickness * 4.5, minimumDistance)
    let tone = M.clamp01(0.5 + dx * 1.8 + dy * 0.6)
    let orbit = M.mixColor(colour(c, 1, 0xFF14_D9C5), colour(c, 2, 0xFFFF_3A79), tone)
    var result = M.mixColor(colour(c, 0, 0xFF03_0511), orbit, halo * glow * 0.62)
    result = M.mixColor(result, orbit, line)
    return M.mixColor(result, colour(c, 3, 0xFFFF_F1B5), line * line * glow)
  }

  static func ferrofluidCrown(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.012), 0.00001)
    let spikes = M.maxOf(parameter(p, 1, 19), 3)
    let spikeLength = M.clamp(parameter(p, 2, 0.14), 0, 0.3)
    let bodySize = M.clamp(parameter(p, 3, 0.22), 0.05, 0.4)
    let metallic = M.clamp01(parameter(p, 4, 0.86))
    let distortion = M.clamp01(parameter(p, 5, 0.42))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.52) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let grain = noise.fbm(x * s, y * s) - 0.5
    let spikeWave = M.maxOf(cos(angle * spikes + grain * distortion * 5), 0)
    let boundary = bodySize + pow(spikeWave, 9) * spikeLength * (0.72 + grain * 0.35)
    let body = M.smoothstep(boundary + 0.008, boundary - 0.008, radius)
    let shadowRadius =
      ((dx + 0.025) * (dx + 0.025) + (dy - 0.035) * (dy - 0.035)).squareRoot()
    let shadow = M.smoothstep(boundary + 0.09, boundary, shadowRadius) * (1 - body) * 0.34
    let normalLight = M.clamp01(0.45 - dx * 1.15 - dy * 0.92 + grain * 0.18)
    let specular = pow(normalLight, 9) * metallic
    var result = M.mixColor(colour(c, 0, 0xFFE8_E1D4), colour(c, 1, 0xFF07_090C), shadow)
    var metal = M.mixColor(colour(c, 1, 0xFF07_090C), colour(c, 2, 0xFF35_3D43), normalLight)
    metal = M.mixColor(metal, colour(c, 3, 0xFFD9_F7FF), specular)
    result = M.mixColor(result, metal, body)
    let rim = (1 - M.smoothstep(0, 0.012, abs(radius - boundary))) * body
    return M.mixColor(result, colour(c, 3, 0xFFD9_F7FF), rim * metallic * 0.55)
  }

  static func supernova(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ seed: Int32, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.01), 0.00001)
    let shockRadius = M.clamp(parameter(p, 1, 0.27), 0.08, 0.45)
    let shellWidth = M.maxOf(parameter(p, 2, 0.075), 0.008)
    let ejecta = M.clamp01(parameter(p, 3, 0.72))
    let turbulence = M.clamp01(parameter(p, 4, 0.68))
    let stars = M.clamp01(parameter(p, 5, 0.24))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let grain = noise.fbm(x * s, y * s)
    let fineValue = noise.fine(x * s * 2.7, y * s * 2.7)
    let distortedRadius = radius + (grain - 0.5) * shellWidth * turbulence * 1.8
    let shell =
      1 - M.smoothstep(shellWidth * 0.2, shellWidth, abs(distortedRadius - shockRadius))
    let rays = pow(M.clamp01(0.5 + 0.5 * sin(angle * 37 + fineValue * 8)), 5)
    let radialEjecta =
      rays * M.smoothstep(shockRadius + shellWidth * 2.8, shockRadius * 0.35, radius) * ejecta
    let cloud =
      M.smoothstep(shockRadius + shellWidth * 2.1, shockRadius * 0.18, distortedRadius)
      * (0.28 + grain * 0.55)
    var result = M.mixColor(colour(c, 0, 0xFF02_030B), colour(c, 1, 0xFF69_23B7), cloud)
    result = M.mixColor(
      result, colour(c, 2, 0xFFFF_4D22),
      shell * (0.62 + fineValue * 0.38) + radialEjecta * 0.54)
    let core = M.smoothstep(shockRadius * 0.22, 0, radius)
    result = M.mixColor(result, colour(c, 3, 0xFFFF_F2C5), core + shell * shell * 0.72)
    var star = M.smoothstep(1 - stars * 0.008, 1, M.hash(x, y, seed))
    star *= M.smoothstep(shockRadius * 1.7, shockRadius * 2.2, radius)
    return M.mixColor(result, 0xFFFF_FFFF, star)
  }

  static func iris(
    _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.014), 0.00001)
    let pupil = M.clamp(parameter(p, 1, 0.12), 0.03, 0.28)
    let irisSize = M.clamp(parameter(p, 2, 0.38), pupil + 0.04, 0.48)
    let fibers = M.maxOf(parameter(p, 3, 46), 6)
    let variation = M.clamp01(parameter(p, 4, 0.72))
    let catchlight = M.clamp01(parameter(p, 5, 0.82))
    let unit = Float(max(min(width, height), 1))
    let dx = (x - Float(width) * 0.5) / unit
    let dy = (y - Float(height) * 0.5) / unit
    let radius = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)
    let grain = noise.fbm(x * s, y * s)
    let angular = 0.5 + 0.5 * sin(angle * fibers + grain * 8 + radius * 65)
    let radialFibers = pow(M.clamp01(angular), 3) * M.smoothstep(pupil, irisSize, radius)
    let innerGold =
      M.smoothstep(pupil + 0.11, pupil, radius) * M.smoothstep(pupil * 0.92, pupil * 1.08, radius)
    let irisMask = M.smoothstep(irisSize + 0.008, irisSize - 0.008, radius)
    var irisColour = M.mixColor(
      colour(c, 1, 0xFF12_3646), colour(c, 2, 0xFF37_B6A5), radialFibers * variation + grain * 0.18)
    irisColour = M.mixColor(irisColour, colour(c, 3, 0xFFE6_B650), innerGold)
    var result = M.mixColor(colour(c, 0, 0xFF08_0A0D), irisColour, irisMask)
    let limbalRing = (1 - M.smoothstep(0, 0.026, abs(radius - irisSize))) * irisMask
    result = M.mixColor(result, colour(c, 0, 0xFF08_0A0D), limbalRing * 0.86)
    if radius < pupil {
      result = 0xFF01_0103
    }
    let lightDx = dx + irisSize * 0.34
    let lightDy = dy + irisSize * 0.38
    let reflection =
      (1
        - M.smoothstep(
          irisSize * 0.035, irisSize * 0.13, (lightDx * lightDx + lightDy * lightDy).squareRoot()))
      * catchlight
    return M.mixColor(result, 0xFFFF_FFFF, reflection)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
