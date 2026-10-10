import Foundation

/// Simulated fields 102...107 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func xRayBotanical(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let complexity = f.complexity
    let distortion = f.distortion
    let gridX = u / 0.62
    let gridY = v / 0.94
    let plantX = Int(floor(gridX + 0.5))
    let plantY = Int(floor(gridY + 0.5))
    let localX = M.fract(gridX + 0.5) - 0.5
    let localY = M.fract(gridY + 0.5) - 0.5
    let plantSeed = M.hash(Float(plantX), Float(plantY), seed)
    let stemPath = sin(localY * (5 + plantSeed * 4) + plantSeed * 6) * distortion * 0.045
    let stem =
      (1 - M.smoothstep(0.007, 0.022, abs(localX - stemPath)))
      * M.smoothstep(0.49, 0.42, abs(localY))
    var leaves: Float = 0
    let leafCount = 5 + Int(complexity * 6)
    for i in 0..<leafCount {
      let leafY = -0.36 + Float(i) * 0.72 / Float(max(leafCount - 1, 1))
      let side: Float = ((i + plantX + plantY) & 1) == 0 ? -1 : 1
      let leafSeed = M.hash(Float(plantX * 17 + i), Float(plantY), seed &+ 43)
      let leafX = stemPath + side * (0.13 + leafSeed * 0.08)
      let rotation = side * (0.28 + leafSeed * 0.34)
      let dx = localX - leafX
      let dy = localY - leafY
      let rx = dx * cos(rotation) + dy * sin(rotation)
      let ry = -dx * sin(rotation) + dy * cos(rotation)
      let leafDistance = (rx * rx / 0.038 + ry * ry / 0.0042).squareRoot()
      let leaf = 1 - M.smoothstep(0.72, 1, leafDistance)
      let mainVein = 1 - M.smoothstep(0.004, 0.018, abs(ry))
      let sideVeins =
        1
        - M.smoothstep(
          0, 0.16, abs(sin(rx * (48 + complexity * 35)) - ry * 18))
      let leafStructure = leaf * (0.22 + mainVein * 0.52 + sideVeins * 0.32)
      leaves = M.maxOf(leaves, leafStructure)
    }
    return M.clamp01(stem + leaves)
  }

  static func chromatophore(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let spots =
      sin(u * (52 + f.complexity * 68) + sin(v * 17) * 3)
      + sin(v * (46 + f.complexity * 74) + cos(u * 19) * 3)
    let pulse = 0.5 + 0.5 * sin(spots * 2.4 + f.distortion * 2 * pi + f.a * 3)
    return M.clamp01(pulse)
  }

  static func biomechanicalTissue(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let ribs = abs(
      sin((u + sin(v * 9) * f.distortion * 0.08) * (48 + f.complexity * 90)))
    let tendons = abs(sin((v - u * 0.28) * (22 + f.complexity * 36) + f.a * 5))
    return M.clamp01(1 - M.minOf(ribs, tendons * 1.4) * 2.7)
  }

  static func gildedFiligree(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let curls = sin(f.angle * (4 + f.complexity * 11) + f.radius * (34 + f.distortion * 55))
    let scrolls = sin((u * u - v * v) * 95 + f.angle * 6)
    return M.clamp01(1 - M.minOf(abs(curls), abs(scrolls)) * 4.2)
  }

  static func ancientRunes(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let grid = 5 + f.complexity * 9
    let gx = M.fract((u + 0.5) * grid) - 0.5
    let gy = M.fract((v + 0.5) * grid) - 0.5
    let cellX = Int(floor((u + 0.5) * grid))
    let cellY = Int(floor((v + 0.5) * grid))
    let glyph = M.hash(Float(cellX), Float(cellY), f.seed)
    let diagonal = glyph < 0.5 ? abs(gx - gy) : abs(gx + gy)
    let vertical = abs(gx + (glyph - 0.5) * 0.32)
    let crossbar = abs(gy - (glyph - 0.5) * 0.26)
    let stroke = M.minOf(diagonal, M.minOf(vertical, crossbar))
    let cellMask = M.smoothstep(0.48, 0.36, M.maxOf(abs(gx), abs(gy)))
    return M.clamp01((1 - M.smoothstep(0.018, 0.065, stroke)) * cellMask)
  }

  static func solarGranulation(_ f: NativeFieldInput) -> Float {
    let convection = sin((f.a - 0.5) * (18 + f.complexity * 34) + f.b * 7)
    let granules = 1 - abs(convection)
    return M.clamp01(granules * 0.78 + f.a * 0.3)
  }
}
