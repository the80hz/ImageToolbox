import Foundation

/// Smooth value noise: each integer lattice point holds a random value, and the field is
/// interpolated between them. Output is in -1...1 and is deterministic for a seed.
public struct ValueNoise2D: Sendable {
  private let seed: UInt64

  public init(seed: UInt64) {
    self.seed = seed
  }

  /// Noise value at a point, in -1...1.
  public func value(x: Double, y: Double) -> Double {
    let floorX = x.rounded(.down)
    let floorY = y.rounded(.down)
    let cellX = Int(floorX)
    let cellY = Int(floorY)
    let u = NoiseHash.fade(x - floorX)
    let v = NoiseHash.fade(y - floorY)
    let v00 = lattice(cellX, cellY)
    let v10 = lattice(cellX + 1, cellY)
    let v01 = lattice(cellX, cellY + 1)
    let v11 = lattice(cellX + 1, cellY + 1)
    let bottom = v00 + (v10 - v00) * u
    let top = v01 + (v11 - v01) * u
    return bottom + (top - bottom) * v
  }

  private func lattice(_ x: Int, _ y: Int) -> Double {
    NoiseHash.unit(seed: seed, x: x, y: y) * 2 - 1
  }
}
