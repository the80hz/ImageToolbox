import Foundation

/// Simulated fields 89...95 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func rainOnGlass(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let distortion = f.distortion
    func dropletLayer(_ grid: Float, _ layerSeed: Int32, _ stretch: Float) -> Float {
      let gx = u * grid
      let gy = v * grid
      let ix = Int(floor(gx))
      let iy = Int(floor(gy))
      var localX = M.fract(gx) - 0.5
      var localY = M.fract(gy) - 0.5
      localX += (M.hash(Float(ix), Float(iy), seed &+ layerSeed) - 0.5) * 0.56
      localY += (M.hash(Float(iy), Float(ix), seed &+ layerSeed &+ 19) - 0.5) * 0.5
      let dropSeed = M.hash(Float(ix * 7), Float(iy * 11), seed &+ layerSeed &+ 41)
      let radiusX = 0.16 + dropSeed * 0.11
      let radiusY = radiusX * stretch
      let teardropX = localX / radiusX
      let teardropY = (localY + M.maxOf(localY, 0) * 0.28) / radiusY
      let distance = (teardropX * teardropX + teardropY * teardropY).squareRoot()
      let dome = M.clamp01(1 - distance)
      let rim = 1 - M.smoothstep(0.72, 1, distance)
      let streak =
        (1 - M.smoothstep(0, 0.18, abs(teardropX))) * M.smoothstep(0.15, 0.48, localY)
        * distortion
      return M.clamp01(dome * dome * 0.82 + rim * 0.16 + streak * 0.45)
    }
    let largeDrops = dropletLayer(5 + f.complexity * 7, 0, 1.35)
    let smallDrops = dropletLayer(9 + f.complexity * 12, 97, 1.05)
    return M.clamp01(M.maxOf(largeDrops, smallDrops * 0.72))
  }

  static func emberField(_ f: NativeFieldInput) -> Float {
    let embers = M.smoothstep(
      0.985 - f.complexity * 0.025, 1,
      M.hash(floor(f.x * 0.45), floor(f.y * 0.45), f.seed))
    return M.clamp01(f.a * 0.25 + embers * (0.65 + f.b * 0.35))
  }

  static func quantumFoam(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    var foam: Float = 0
    let waveCount = 4 + Int(f.complexity * 8)
    for i in 0..<waveCount {
      let cx = M.hash(Float(i), 2.6, f.seed) - 0.5
      let cy = M.hash(7.1, Float(i), f.seed &+ 37) - 0.5
      let distance = ((u - cx) * (u - cx) + (v - cy) * (v - cy)).squareRoot()
      foam += sin(distance * (48 + f.distortion * 82) + Float(i) * 1.9)
    }
    return M.clamp01(0.5 + foam / Float(waveCount) * 0.5)
  }

  static func chladniPlate(_ f: NativeFieldInput) -> Float {
    let modeA = 2 + floor(f.complexity * 6)
    let modeB = modeA + 1 + floor(f.distortion * 4)
    let plateX = f.u + 0.5
    let plateY = f.v + 0.5
    let vibration =
      sin(modeA * pi * plateX) * sin(modeB * pi * plateY)
      - sin(modeB * pi * plateX) * sin(modeA * pi * plateY)
    return M.clamp01(1 - abs(vibration) * 4.5)
  }

  static func cymaticRosette(_ f: NativeFieldInput) -> Float {
    let petals = 5 + floor(f.complexity * 15)
    let radialWave = sin(
      f.radius * (72 + f.complexity * 120) + sin(f.angle * petals) * (2 + f.distortion * 8))
    let angularWave = cos(f.angle * petals + f.radius * 18)
    return M.clamp01(1 - abs(radialWave * 0.72 + angularWave * 0.28) * 2.8)
  }

  static func lichtenbergFigure(_ f: NativeFieldInput) -> Float {
    let branches = 7 + floor(f.complexity * 22)
    let fork = sin(
      f.angle * branches + sin(f.angle * 3 + f.radius * 31) * (1 + f.distortion * 5))
    let secondary = sin(f.angle * branches * 2.07 - f.radius * 44 + f.a * 4)
    return M.clamp01(
      1 - M.minOf(abs(fork), abs(secondary) * 1.2) * (5 + f.radius * 3))
  }

  static func quasicrystal(_ f: NativeFieldInput) -> Float {
    let symmetry = 5 + Int(f.complexity * 8)
    var sum: Float = 0
    for i in 0..<symmetry {
      let direction = 2 * pi * Float(i) / Float(symmetry)
      sum += cos(
        (f.u * cos(direction) + f.v * sin(direction)) * (48 + f.distortion * 70))
    }
    sum /= Float(symmetry)
    return M.clamp01(1 - abs(sum) * 3.2)
  }
}
