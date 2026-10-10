import Foundation

/// Simulated fields 108...112 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  static func lunarEjecta(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let distortion = f.distortion
    let spacing = 0.18 + (1 - f.complexity) * 0.14
    let baseX = Int(floor(u / spacing))
    let baseY = Int(floor(v / spacing))
    var craterField: Float = 0
    var rays: Float = 0
    var depressions: Float = 0
    for oy in -1...1 {
      for ox in -1...1 {
        let craterX = baseX + ox
        let craterY = baseY + oy
        let craterSeed = M.hash(Float(craterX), Float(craterY), seed)
        if craterSeed < 0.22 { continue }
        let cx =
          (Float(craterX) + 0.5) * spacing
          + (M.hash(Float(craterX), Float(craterY), seed &+ 19) - 0.5) * spacing * 0.52
        let cy =
          (Float(craterY) + 0.5) * spacing
          + (M.hash(Float(craterY), Float(craterX), seed &+ 37) - 0.5) * spacing * 0.52
        let craterRadius = spacing * (0.12 + craterSeed * 0.2)
        let dx = u - cx
        let dy = v - cy
        let distance = (dx * dx + dy * dy).squareRoot()
        let rimWidth = craterRadius * (0.12 + distortion * 0.12)
        let rim = 1 - M.smoothstep(rimWidth * 0.35, rimWidth, abs(distance - craterRadius))
        let depression =
          (1 - M.smoothstep(0, craterRadius, distance)) * (0.4 + craterSeed * 0.28)
        let rayPattern =
          1
          - M.smoothstep(
            0, 0.13, abs(sin(atan2(dy, dx) * (4 + floor(craterSeed * 7)))))
        let rayFade = M.smoothstep(
          craterRadius * (5 + distortion * 4), craterRadius * 1.2, distance)
        craterField = M.maxOf(craterField, rim)
        depressions = M.maxOf(depressions, depression)
        rays = M.maxOf(rays, rayPattern * rayFade * 0.5)
      }
    }
    return M.clamp01(
      0.24 + (f.a - 0.5) * 0.22 - depressions * 0.24 + craterField * 0.68 + rays * 0.42)
  }

  static func oceanCurrents(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let distortion = f.distortion
    let spacing = 0.34 + (1 - f.complexity) * 0.18
    let baseX = Int(floor(u / spacing))
    let baseY = Int(floor(v / spacing))
    var velocityPhase: Float = 0
    var totalWeight: Float = 0
    for oy in -1...1 {
      for ox in -1...1 {
        let vortexX = baseX + ox
        let vortexY = baseY + oy
        let vortexSeed = M.hash(Float(vortexX), Float(vortexY), seed)
        let cx = (Float(vortexX) + 0.5) * spacing + (vortexSeed - 0.5) * spacing * 0.48
        let cy =
          (Float(vortexY) + 0.5) * spacing
          + (M.hash(Float(vortexY), Float(vortexX), seed &+ 53) - 0.5) * spacing * 0.48
        let dx = u - cx
        let dy = v - cy
        let localRadius = (dx * dx + dy * dy).squareRoot()
        let weight = exp(-localRadius * localRadius / (spacing * spacing * 0.34))
        let spin: Float = vortexSeed < 0.5 ? -1 : 1
        velocityPhase +=
          sin(
            atan2(dy, dx) * spin * (1 + floor(vortexSeed * 3))
              + localRadius / spacing * (13 + distortion * 18)) * weight
        totalWeight += weight
      }
    }
    let jet = sin(
      (v + sin(u * 3.2 + f.a * 2) * distortion * 0.12) * (18 + f.complexity * 34))
    let current = velocityPhase / M.maxOf(totalWeight, 0.001) * 0.72 + jet * 0.28
    return M.clamp01(1 - abs(current) * 2.35)
  }

  static func inkWashMountains(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    var mountains: Float = 0
    for layer in 0..<6 {
      let depth = Float(layer) / 5
      let ridge =
        -0.34 + depth * 0.13
        + sin(u * (7 + Float(layer) * 2.3) + Float(layer) * 1.7) * (0.06 + depth * 0.025)
        + f.noise.fbm(
          (u + Float(layer) * 0.37) * (3 + complexity * 4), Float(layer) * 2.1) * 0.13
      let silhouette = M.smoothstep(
        ridge - 0.018, ridge + 0.018 + distortion * 0.025, v)
      mountains = M.maxOf(mountains, silhouette * (1 - depth * 0.13))
    }
    return M.clamp01(mountains)
  }

  static func neonCity(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let horizon = 0.08 + sin(u * 13) * 0.025
    let perspective = M.clamp01((v - horizon) / 0.45)
    let columns = M.fract(
      (u + 0.5) * (12 + f.complexity * 24) / M.maxOf(0.28, 1 - perspective * 0.72))
    let buildingSeed = M.hash(floor(columns * 17), floor(u * 31), f.seed)
    let buildings = M.smoothstep(horizon - 0.32 * buildingSeed, horizon, v)
    let windows = pow(M.clamp01(0.5 + 0.5 * sin(u * 180) * sin(v * 145)), 7)
    let road = M.smoothstep(horizon, 0.48, v) * (1 - M.smoothstep(0.02, 0.11, abs(u)))
    return M.clamp01(
      buildings * 0.25 + windows * buildings + road * (0.55 + distortion * 0.4))
  }

  static func phyllotaxisBloom(_ f: NativeFieldInput) -> Float {
    let seedCount = 150 + Int(f.complexity * 330)
    let normalizedRadius = M.clamp01(f.radius / 0.48)
    let estimated = Int(normalizedRadius * normalizedRadius * Float(seedCount))
    var nearest: Float = 1
    let goldenAngle: Float = 2.3999632 + (f.distortion - 0.5) * 0.24
    for offset in -7...7 {
      let seedIndex = min(max(estimated + offset, 0), seedCount - 1)
      let seedRadius = (Float(seedIndex) / Float(seedCount)).squareRoot() * 0.47
      let seedAngle = Float(seedIndex) * goldenAngle
      let px = cos(seedAngle) * seedRadius
      let py = sin(seedAngle) * seedRadius
      let distance = ((f.u - px) * (f.u - px) + (f.v - py) * (f.v - py)).squareRoot()
      nearest = M.minOf(nearest, distance)
    }
    return M.clamp01(1 - M.smoothstep(0.004, 0.012, nearest))
  }
}
