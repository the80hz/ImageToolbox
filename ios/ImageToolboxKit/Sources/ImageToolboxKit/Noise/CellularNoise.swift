import Foundation

/// Cellular (Worley) noise: every unit cell holds one feature point, and the field is the
/// distance to the nearest points. Deterministic for a seed.
public struct CellularNoise2D: Sendable {
  private let seed: UInt64

  public init(seed: UInt64) {
    self.seed = seed
  }

  /// The distances to the nearest and second nearest feature points, in cell units.
  /// `jitter` in 0...1 moves the points away from the cell centres: 0 puts every point at its
  /// centre (a regular grid), 1 lets it roam over the whole cell.
  public func distances(x: Double, y: Double, jitter: Double = 1) -> (
    nearest: Double, second: Double
  ) {
    let cellX = Int(x.rounded(.down))
    let cellY = Int(y.rounded(.down))
    let spread = min(max(jitter, 0), 1)
    var nearest = Double.infinity
    var second = Double.infinity
    for row in -1...1 {
      for column in -1...1 {
        let featureX =
          Double(cellX + column)
          + 0.5 + (NoiseHash.unit(seed: seed, x: cellX + column, y: cellY + row) - 0.5) * spread
        let featureY =
          Double(cellY + row)
          + 0.5 + (NoiseHash.unit(seed: seed ^ 0xA5, x: cellX + column, y: cellY + row) - 0.5)
          * spread
        let distance = ((x - featureX) * (x - featureX) + (y - featureY) * (y - featureY))
          .squareRoot()
        if distance < nearest {
          second = nearest
          nearest = distance
        } else if distance < second {
          second = distance
        }
      }
    }
    return (nearest, second)
  }

  /// A value in 0...1 for the cell that contains a point, one per feature point.
  public func cellValue(x: Double, y: Double) -> Double {
    let cellX = Int(x.rounded(.down))
    let cellY = Int(y.rounded(.down))
    return NoiseHash.unit(seed: seed ^ 0x3C, x: cellX, y: cellY)
  }
}
