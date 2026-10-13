import Foundation

/// The values that every simulated field of the native code shares for one pixel: the warped
/// coordinates, the two fractal samples and the polar and scaled coordinates.
struct NativeFieldInput {
  let noise: NativeNoiseBank
  let x: Float
  let y: Float
  let u: Float
  let v: Float
  let nx: Float
  let ny: Float
  /// Fractal sample at the warped point.
  let a: Float
  /// Detail sample at the warped point.
  let b: Float
  let radius: Float
  let angle: Float
  /// The scale of the coordinates relative to a 0.008 base, clamped to 0.125...5.
  let spatialScale: Float
  let s: Float
  let complexity: Float
  let distortion: Float
  let seed: Int32
  let width: Int
  let height: Int
  let p: [Float]
}

/// Simulated fields 71...82 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`. Each returns the field value of one pixel; the shading step maps it
/// to colours.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func reactionDiffusion(_ f: NativeFieldInput) -> Float {
    M.clamp01(0.5 + 0.5 * sin((f.a * 1.7 + f.b * 0.8) * (10 + f.complexity * 18)))
  }

  static func coralGrowth(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let b = f.b
    let spacing: Float = 0.68
    let gridX = u / spacing
    let gridY = v / spacing
    let cellX = Int(floor(gridX))
    let cellY = Int(floor(gridY))
    let localX = M.fract(gridX) - 0.5
    let localY = M.fract(gridY) - 0.5
    let colonySeed = M.hash(Float(cellX), Float(cellY), f.seed)
    let sway = sin(localY * (7 + colonySeed * 5) + colonySeed * pi * 2) * distortion * 0.045
    let trunkWidth = 0.018 + colonySeed * 0.012
    var coral =
      (1 - M.smoothstep(trunkWidth, trunkWidth + 0.018, abs(localX - sway)))
      * M.smoothstep(0.48, 0.31, localY) * M.smoothstep(-0.48, -0.38, localY)
    let limbCount = 4 + Int(f.complexity * 6)
    for i in 0..<limbCount {
      let originY = 0.3 - Float(i) * 0.65 / Float(limbCount)
      let side: Float = ((i + cellX + cellY) & 1) == 0 ? -1 : 1
      let limbSeed = M.hash(Float(cellX * 13 + i), Float(cellY), f.seed &+ 23)
      let reach = 0.13 + limbSeed * 0.18
      let dy = localY - originY
      let progress = M.smoothstep(0.015, -0.22, dy)
      let branchX =
        sway + side * reach * progress + sin(dy * 21 + limbSeed * 5) * distortion * 0.018
      var branch = 1 - M.smoothstep(0.012, 0.032, abs(localX - branchX))
      branch *= M.smoothstep(-0.27, -0.05, dy) * (1 - M.smoothstep(-0.015, 0.035, dy))
      let polypDistance =
        ((localX - branchX) * (localX - branchX) + (dy + 0.24) * (dy + 0.24)).squareRoot()
      let polyp = 1 - M.smoothstep(0.025, 0.065, polypDistance)
      coral = M.maxOf(coral, branch)
      coral = M.maxOf(coral, polyp)
    }
    return M.clamp01(coral * (0.72 + b * 0.28))
  }

  static func slimeMold(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    let flow = sin((u + sin(v * 8 + f.a * 3) * distortion * 0.18) * (28 + complexity * 62))
    let split = sin((v - cos(u * 11) * distortion * 0.14) * (17 + complexity * 39))
    let trails = M.minOf(abs(flow), abs(flow * 0.62 + split * 0.38))
    return M.clamp01(1 - trails * 4)
  }

  static func dendriticCrystal(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    let spacing: Float = 0.72
    let localX = M.fract(u / spacing + 0.5) - 0.5
    let localY = M.fract(v / spacing + 0.5) - 0.5
    let cellX = Int(floor(u / spacing + 0.5))
    let cellY = Int(floor(v / spacing + 0.5))
    let crystalSeed = M.hash(Float(cellX), Float(cellY), f.seed)
    let localRadius = (localX * localX + localY * localY).squareRoot()
    let localAngle = atan2(localY, localX) + crystalSeed * 0.35
    let arms = 5 + floor(complexity * 5)
    let sector = 2 * pi / arms
    let foldedAngle = abs(M.fract((localAngle + pi) / sector) - 0.5) * sector
    let branchDistance = localRadius * sin(foldedAngle)
    let trunk = 1 - M.smoothstep(0.008, 0.023, abs(branchDistance))
    var sideBranches =
      1
      - M.smoothstep(
        0, 0.065, abs(sin(localRadius * (65 + distortion * 55) - foldedAngle * 9)))
    sideBranches *=
      M.smoothstep(0.04, 0.31, localRadius)
      * (1 - M.smoothstep(0.3, 0.42, localRadius))
    let crystal = M.maxOf(trunk, sideBranches * 0.72)
    return M.clamp01(crystal * (1 - M.smoothstep(0.34, 0.46, localRadius)))
  }

  static func electricArcField(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    let tileWidth: Float = 0.58
    let tileHeight: Float = 0.92
    let gridX = u / tileWidth
    let gridY = v / tileHeight
    let cellX = Int(floor(gridX + 0.5))
    let cellY = Int(floor(gridY + 0.5))
    let localX = M.fract(gridX + 0.5) - 0.5
    let localY = M.fract(gridY + 0.5) - 0.5
    let boltSeed = M.hash(Float(cellX), Float(cellY), f.seed)
    let mainPath =
      sin(localY * (12 + boltSeed * 9) + boltSeed * 8) * (0.025 + distortion * 0.07)
      + sin(localY * 37 + boltSeed * 17) * distortion * 0.018
    var arc = 1 - M.smoothstep(0.008, 0.022, abs(localX - mainPath))
    let branches = 2 + Int(complexity * 5)
    for i in 0..<branches {
      let forkY = 0.28 - Float(i) * 0.56 / Float(max(branches - 1, 1))
      let dy = localY - forkY
      let side: Float = ((i + cellX) & 1) == 0 ? -1 : 1
      let progress = M.smoothstep(-0.02, -0.26, dy)
      let branchPath = mainPath + side * progress * (0.09 + 0.045 * Float(i))
      var branch = 1 - M.smoothstep(0.006, 0.018, abs(localX - branchPath))
      branch *= M.smoothstep(-0.3, -0.04, dy) * (1 - M.smoothstep(-0.015, 0.035, dy))
      arc = M.maxOf(arc, branch * 0.82)
    }
    return M.clamp01(arc * M.smoothstep(0.5, 0.42, abs(localY)))
  }

  static func cloudChamber(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    var tracks: Float = 0
    let spacing = 0.09 + (1 - complexity) * 0.08
    let familySlope = -0.72 + distortion * 1.44
    let estimatedTrack = Int(floor((v - familySlope * u) / spacing))
    for offset in -2...2 {
      let trackIndex = estimatedTrack + offset
      let trackSeed = M.hash(Float(trackIndex), 3.7, f.seed)
      let slope = familySlope + (trackSeed - 0.5) * 0.65
      let pathY =
        Float(trackIndex) * spacing + slope * u
        + sin(u * (2.5 + trackSeed * 5) + trackSeed * 9) * distortion * 0.045
      let trackWidth = 0.0025 + M.hash(Float(trackIndex), 8.1, f.seed &+ 17) * 0.0045
      let track = 1 - M.smoothstep(trackWidth, trackWidth * 2.6, abs(v - pathY))
      let droplets = M.smoothstep(
        0.82, 1, sin(u * (48 + trackSeed * 42) + trackSeed * 13) * 0.5 + 0.5)
      tracks = M.maxOf(tracks, track)
      tracks = M.maxOf(tracks, track * droplets)
    }
    return M.clamp01(tracks * (0.78 + f.b * 0.22))
  }

  static func turbulentInk(_ f: NativeFieldInput) -> Float {
    M.clamp01(
      0.5 + 0.5 * sin((f.nx - f.ny * 0.35) * f.s * (9 + f.complexity * 22) + f.a * 12))
  }

  static func cellularEmbryo(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let grid = 4 + f.complexity * 8
    let gx = M.fract((u + 0.5) * grid) - 0.5
    let gy = M.fract((v + 0.5) * grid) - 0.5
    let ix = Int(floor((u + 0.5) * grid))
    let iy = Int(floor((v + 0.5) * grid))
    let tilt = (M.hash(Float(ix), Float(iy), f.seed) - 0.5) * distortion
    let embryo = ((gx + gy * tilt) * (gx + gy * tilt) / 0.09 + gy * gy / 0.16).squareRoot()
    let membrane = 1 - M.smoothstep(0.78, 1, embryo)
    let nucleusDistance = ((gx + 0.1) * (gx + 0.1) + (gy - 0.04) * (gy - 0.04)).squareRoot()
    let nucleus = 1 - M.smoothstep(0.08, 0.18, nucleusDistance)
    return M.clamp01(membrane * 0.45 + nucleus * 0.75)
  }

  static func neuralGarden(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let seed = f.seed
    let spacing = 0.31 - f.complexity * 0.1
    let baseX = Int(floor(u / spacing))
    let baseY = Int(floor(v / spacing))
    var network: Float = 0
    func neuronPoint(_ px: Int, _ py: Int) -> (Float, Float) {
      let jitterX = (M.hash(Float(px), Float(py), seed) - 0.5) * spacing * 0.5
      let jitterY = (M.hash(Float(py), Float(px), seed &+ 29) - 0.5) * spacing * 0.5
      return ((Float(px) + 0.5) * spacing + jitterX, (Float(py) + 0.5) * spacing + jitterY)
    }
    func segmentDistance(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
      let vx = bx - ax
      let vy = by - ay
      let lengthSquared = M.maxOf(vx * vx + vy * vy, 0.000001)
      let t = M.clamp01(((u - ax) * vx + (v - ay) * vy) / lengthSquared)
      let dx = u - ax - vx * t
      let dy = v - ay - vy * t
      return (dx * dx + dy * dy).squareRoot()
    }
    for oy in -1...1 {
      for ox in -1...1 {
        let neuronX = baseX + ox
        let neuronY = baseY + oy
        let point = neuronPoint(neuronX, neuronY)
        let somaDistance =
          ((u - point.0) * (u - point.0) + (v - point.1) * (v - point.1)).squareRoot()
        let soma = 1 - M.smoothstep(spacing * 0.055, spacing * 0.16, somaDistance)
        network = M.maxOf(network, soma)
        let right = neuronPoint(neuronX + 1, neuronY)
        let diagonal = neuronPoint(neuronX + ((neuronY & 1) == 0 ? 1 : -1), neuronY + 1)
        let axonDistance = M.minOf(
          segmentDistance(point.0, point.1, right.0, right.1),
          segmentDistance(point.0, point.1, diagonal.0, diagonal.1))
        let axon =
          1
          - M.smoothstep(
            spacing * 0.012, spacing * (0.035 + distortion * 0.025), axonDistance)
        network = M.maxOf(network, axon * 0.72)
      }
    }
    return M.clamp01(network)
  }

  static func magneticField(_ f: NativeFieldInput) -> Float {
    let left = atan2(f.v, f.u + 0.18)
    let right = atan2(f.v, f.u - 0.18)
    return M.clamp01(
      0.5 + 0.5 * sin((left - right) * (8 + f.complexity * 18) + f.a * f.distortion * 4))
  }

  static func riverDelta(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let frequency = 4 + f.complexity * 12
    let meander = u + sin(v * 3.7 + f.a * 2) * distortion * 0.16
    let trunk = abs(sin(meander * frequency * pi))
    let tributaryA = abs(
      sin((u * 0.62 + v * 0.78 + sin(v * 5) * distortion * 0.08) * frequency * 1.7 * pi))
    let tributaryB = abs(
      sin((u * 0.58 - v * 0.82 + cos(v * 4.2) * distortion * 0.07) * frequency * 2.3 * pi))
    let hierarchy = M.minOf(trunk, M.minOf(tributaryA * 1.25, tributaryB * 1.55))
    let width = 0.045 + (0.5 + 0.5 * sin(v * frequency * 0.7)) * 0.028
    return M.clamp01(1 - M.smoothstep(width * 0.35, width, hierarchy))
  }

  static func lichenColony(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let rosettes =
      sin(u * (18 + f.complexity * 38) + sin(v * 13) * 2)
      * sin(v * (21 + f.complexity * 31) + cos(u * 11) * 2)
    let patches = M.smoothstep(0.38 - f.distortion * 0.3, 0.82, f.a)
    return M.clamp01((0.5 + rosettes * 0.5) * patches + f.b * 0.18)
  }
}
