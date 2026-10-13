import Foundation

/// Simulated fields 83...88 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func bacterialCulture(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let complexity = f.complexity
    let spacing = 0.15 + (1 - complexity) * 0.12
    let baseX = Int(floor(u / spacing))
    let baseY = Int(floor(v / spacing))
    var rods: Float = 0
    for oy in -1...1 {
      for ox in -1...1 {
        let bacteriaX = baseX + ox
        let bacteriaY = baseY + oy
        let bacteriaSeed = M.hash(Float(bacteriaX), Float(bacteriaY), seed)
        if bacteriaSeed < 0.18 + (1 - complexity) * 0.28 { continue }
        let cx =
          (Float(bacteriaX) + 0.5) * spacing
          + (M.hash(Float(bacteriaX), Float(bacteriaY), seed &+ 13) - 0.5) * spacing * 0.58
        let cy =
          (Float(bacteriaY) + 0.5) * spacing
          + (M.hash(Float(bacteriaY), Float(bacteriaX), seed &+ 31) - 0.5) * spacing * 0.58
        let orientation = bacteriaSeed * pi
        let dx = u - cx
        let dy = v - cy
        let along = dx * cos(orientation) + dy * sin(orientation)
        let across = -dx * sin(orientation) + dy * cos(orientation)
        let halfLength = spacing * (0.22 + bacteriaSeed * 0.16)
        let bodyX = M.maxOf(abs(along) - halfLength, 0)
        let bodyDistance = (bodyX * bodyX + across * across).squareRoot()
        let body = 1 - M.smoothstep(spacing * 0.055, spacing * 0.11, bodyDistance)
        let nucleus =
          1
          - M.smoothstep(
            spacing * 0.02, spacing * 0.055, (along * along + across * across).squareRoot())
        rods = M.maxOf(rods, body * 0.7 + nucleus * 0.42)
      }
    }
    return M.clamp01(f.a * 0.12 + rods)
  }

  static func fluidVorticity(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let complexity = f.complexity
    let distortion = f.distortion
    var vortices: Float = 0
    for i in 0..<4 {
      let cx = (M.hash(Float(i), 3.7, seed) - 0.5) * 0.72
      let cy = (M.hash(8.4, Float(i), seed &+ 13) - 0.5) * 0.72
      let dx = u - cx
      let dy = v - cy
      let localRadius = (dx * dx + dy * dy).squareRoot()
      let spiral = sin(atan2(dy, dx) * (2 + Float(i)) + localRadius * (42 + complexity * 58))
      vortices += spiral * exp(-localRadius * (7 - distortion * 3))
    }
    return M.clamp01(0.5 + vortices * 0.34)
  }

  static func crystalGrowth(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let shardCount = 7 + Int(f.complexity * 13)
    var shards: Float = 0
    for i in 0..<shardCount {
      let direction = 2 * pi * Float(i) / Float(shardCount)
      let projection = u * cos(direction) + v * sin(direction)
      let lateral = abs(-u * sin(direction) + v * cos(direction))
      let shard =
        M.smoothstep(-0.03, 0.05, projection)
        * (1 - M.smoothstep(0.018, 0.055 + projection * 0.16, lateral))
      shards = M.maxOf(shards, shard)
    }
    return M.clamp01(shards * (0.75 + f.b * 0.25))
  }

  static func galacticWeb(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let seed = f.seed
    let distortion = f.distortion
    let spacing = 0.27 + (1 - f.complexity) * 0.13
    let baseX = Int(floor(u / spacing))
    let baseY = Int(floor(v / spacing))
    var web: Float = 0
    func nodePoint(_ px: Int, _ py: Int) -> (Float, Float) {
      let jitterX = (M.hash(Float(px), Float(py), seed) - 0.5) * spacing * 0.62
      let jitterY = (M.hash(Float(py), Float(px), seed &+ 37) - 0.5) * spacing * 0.62
      return ((Float(px) + 0.5) * spacing + jitterX, (Float(py) + 0.5) * spacing + jitterY)
    }
    func segmentDistance(_ from: (Float, Float), _ to: (Float, Float)) -> Float {
      let vx = to.0 - from.0
      let vy = to.1 - from.1
      let lengthSquared = M.maxOf(vx * vx + vy * vy, 0.000001)
      let t = M.clamp01(((u - from.0) * vx + (v - from.1) * vy) / lengthSquared)
      let dx = u - from.0 - vx * t
      let dy = v - from.1 - vy * t
      return (dx * dx + dy * dy).squareRoot()
    }
    for oy in -1...1 {
      for ox in -1...1 {
        let nodeX = baseX + ox
        let nodeY = baseY + oy
        let node = nodePoint(nodeX, nodeY)
        let nodeDistance =
          ((u - node.0) * (u - node.0) + (v - node.1) * (v - node.1)).squareRoot()
        let halo = exp(-nodeDistance * nodeDistance / (spacing * spacing * 0.025))
        web = M.maxOf(web, halo)
        let right = nodePoint(nodeX + 1, nodeY)
        let up = nodePoint(nodeX, nodeY + 1)
        var linkDistance = M.minOf(segmentDistance(node, right), segmentDistance(node, up))
        if M.hash(Float(nodeX), Float(nodeY), seed &+ 71) > 0.48 {
          let diagonal = nodePoint(nodeX + 1, nodeY + 1)
          linkDistance = M.minOf(linkDistance, segmentDistance(node, diagonal))
        }
        let filament =
          1
          - M.smoothstep(
            spacing * 0.008, spacing * (0.025 + distortion * 0.025), linkDistance)
        web = M.maxOf(web, filament * 0.78)
      }
    }
    return M.clamp01(web)
  }

  static func veinedLeaf(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let mainVein = 1 - M.smoothstep(0, 0.035, abs(u))
    let side =
      1
      - abs(
        sin((v + f.a * 0.09) * (22 + f.complexity * 38) + abs(u) * 46))
    return M.clamp01(mainVein + side * 0.6 + f.a * 0.22)
  }

  static func porousSponge(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let complexity = f.complexity
    let pores =
      sin(u * (42 + complexity * 72))
      + sin((u * 0.5 + v * 0.866) * (45 + complexity * 68))
      + sin((-u * 0.5 + v * 0.866) * (39 + complexity * 76))
    let holes = M.smoothstep(1.25 - f.distortion * 0.55, 2.55, pores)
    return M.clamp01((1 - holes) * 0.72 + f.b * 0.28)
  }
}
