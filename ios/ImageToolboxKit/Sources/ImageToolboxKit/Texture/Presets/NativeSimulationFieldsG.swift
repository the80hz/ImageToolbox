import Foundation

/// Simulated fields 113...121 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func sierpinskiTriangle(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let depth = 4 + Int(f.complexity * 7)
    let size = 1 << depth
    let rotation = (f.distortion - 0.5) * pi * 0.5
    let rx = u * cos(rotation) - v * sin(rotation)
    let ry = u * sin(rotation) + v * cos(rotation)
    let ix = min(max(Int((rx + 0.5) * Float(size)), 0), size - 1)
    let iy = min(max(Int((ry + 0.5) * Float(size)), 0), size - 1)
    var triangle: Float = (ix & iy) == 0 ? 1 : 0
    triangle *= M.smoothstep(0.52, 0.45, M.maxOf(abs(rx), abs(ry)))
    return triangle
  }

  static func apollonianGasket(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    var rings: Float = 0
    let levels = 3 + Int(f.complexity * 6)
    for level in 0..<levels {
      let frequency = exp2(Float(level))
      let qx = M.fract((u + 0.5) * frequency) - 0.5
      let qy = M.fract((v + 0.5) * frequency) - 0.5
      let localRadius = (qx * qx + qy * qy).squareRoot()
      let target = 0.28 + sin(Float(level) * 1.7) * f.distortion * 0.035
      let ring = 1 - M.smoothstep(0.008, 0.032, abs(localRadius - target))
      rings = M.maxOf(rings, ring * (1 - Float(level) * 0.06))
    }
    return M.clamp01(rings)
  }

  static func hyperbolicTiling(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    let sqrt3: Float = 1.7320508
    let cellSize: Float = 0.42
    let rowStep = cellSize * sqrt3 * 0.5
    let baseRow = Int(floor(v / rowStep))
    var bestDistanceSquared: Float = 1000
    var localX: Float = 0
    var localY: Float = 0
    var selectedColumn = 0
    var selectedRow = 0
    for row in (baseRow - 1)...(baseRow + 1) {
      let rowOffset: Float = row % 2 != 0 ? cellSize * 0.5 : 0
      let baseColumn = Int(floor((u - rowOffset) / cellSize))
      for column in (baseColumn - 1)...(baseColumn + 1) {
        let centerX = (Float(column) + 0.5) * cellSize + rowOffset
        let centerY = (Float(row) + 0.5) * rowStep
        let dx = u - centerX
        let dy = v - centerY
        let distanceSquared = dx * dx + dy * dy
        if distanceSquared < bestDistanceSquared {
          bestDistanceSquared = distanceSquared
          localX = dx / cellSize
          localY = dy / cellSize
          selectedColumn = column
          selectedRow = row
        }
      }
    }
    var hexRadius = M.maxOf(abs(localX) * 2, abs(localX) + abs(localY) * sqrt3)
    hexRadius = M.minOf(hexRadius, 0.992)
    let hyperbolicRadius = log((1 + hexRadius) / M.maxOf(1 - hexRadius, 0.008))
    let localAngle = atan2(localY, localX)
    let sides = 4 + floor(complexity * 9)
    let parity: Float = abs((selectedColumn + selectedRow) % 2) > 0 ? 1 : 0
    let orientation = parity * pi / sides + Float(f.seed) * 0.0017
    let curvedAngle = localAngle + orientation + sin(hyperbolicRadius * 0.72) * distortion * 0.16
    let radialFamily = abs(
      sin(
        hyperbolicRadius * (2.15 + complexity * 1.35)
          + cos(curvedAngle * sides) * (0.85 + distortion * 1.25)))
    let diagonalFamily = abs(
      sin(curvedAngle * sides + hyperbolicRadius * (0.62 + distortion * 1.45)))
    let counterFamily = abs(
      sin(curvedAngle * (sides - 2) - hyperbolicRadius * (1.18 + distortion * 0.82)))
    let geodesicDistance = M.minOf(radialFamily, M.minOf(diagonalFamily, counterFamily))
    let geodesics = 1 - M.smoothstep(0.025, 0.13, geodesicDistance)
    let boundary = 1 - M.smoothstep(0.018, 0.075, 1 - hexRadius)
    let chambers =
      0.5 + 0.5
      * cos(
        hyperbolicRadius * 1.32 - curvedAngle * (sides * 0.5) + parity * pi)
    return M.clamp01(geodesics * 0.78 + boundary * 0.58 + chambers * 0.14)
  }

  static func moebiusWeave(_ f: NativeFieldInput) -> Float {
    let bands = 3 + floor(f.complexity * 9)
    let twist = f.angle * (1 + f.distortion * 4) + f.radius * 24
    let ribbon = sin(twist) * cos(f.angle * bands - f.radius * 8)
    let frontBack = 0.5 + 0.5 * sin(f.angle + f.radius * pi * 2)
    return M.clamp01((1 - abs(ribbon) * 2.9) * (0.55 + frontBack * 0.45))
  }

  static func rorschachInkblot(_ f: NativeFieldInput) -> Float {
    let v = f.v
    let distortion = f.distortion
    let complexity = f.complexity
    let mirroredX = abs(f.u)
    let ink = f.noise.fbm(
      (mirroredX + sin(v * 7) * distortion * 0.08) * (3 + complexity * 5),
      v * (3 + complexity * 5))
    let lobes = 0.5 + 0.5 * sin(v * (8 + complexity * 18) + mirroredX * 11)
    let silhouette = M.smoothstep(
      0.58 - distortion * 0.22, 0.76, ink * 0.72 + lobes * 0.28)
    return M.clamp01(silhouette * M.smoothstep(0.48, 0.03, mirroredX))
  }

  static func seismicInterference(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    var waves: Float = 0
    let sources = 2 + Int(f.complexity * 5)
    for i in 0..<sources {
      let sourceX = (Float(i) / Float(max(sources - 1, 1)) - 0.5) * 0.72
      let sourceY = (M.hash(Float(i), 6.4, f.seed) - 0.5) * 0.42
      let distance =
        ((u - sourceX) * (u - sourceX) + (v - sourceY) * (v - sourceY)).squareRoot()
      waves += sin(distance * (58 + f.distortion * 72) + Float(i) * 1.3)
    }
    return M.clamp01(0.5 + waves / Float(sources) * 0.5)
  }

  static func rayleighBenard(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let frequency = 24 + f.complexity * 52
    let convection =
      sin(u * frequency + sin(v * 9) * f.distortion * 5)
      + sin((u * 0.5 + v * 0.866) * frequency)
      + sin((-u * 0.5 + v * 0.866) * frequency)
    let plumes = 0.5 + 0.5 * sin(v * 18 + f.a * 5)
    return M.clamp01(convection / 6 + 0.5 + plumes * 0.2)
  }

  static func origamiFacets(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let foldA = abs(M.fract((u + v * 0.62) * (5 + f.complexity * 13)) - 0.5)
    let foldB = abs(
      M.fract((v - u * 0.38) * (6 + f.complexity * 11) + f.distortion * 0.3) - 0.5)
    let crease = M.minOf(foldA, foldB)
    let face = M.fract(foldA * 2 + foldB * 3)
    return M.clamp01(face * 0.58 + (1 - M.smoothstep(0, 0.055, crease)) * 0.62)
  }

  static func fiberOpticBundle(_ f: NativeFieldInput) -> Float {
    let u = f.u
    let v = f.v
    let grid = 8 + f.complexity * 19
    let gx = M.fract((u + 0.5 + sin(v * 8) * f.distortion * 0.04) * grid) - 0.5
    let gy = M.fract((v + 0.5 + cos(u * 7) * f.distortion * 0.04) * grid) - 0.5
    let core = (gx * gx + gy * gy).squareRoot()
    let ring = 1 - M.smoothstep(0.07, 0.18, core)
    let cladding = 1 - M.smoothstep(0.16, 0.28, core)
    return M.clamp01(ring + cladding * 0.28)
  }
}
