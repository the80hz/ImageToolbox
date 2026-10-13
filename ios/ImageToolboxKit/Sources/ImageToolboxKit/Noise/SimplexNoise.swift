import Foundation

/// 2D simplex noise (Perlin's simplex construction on a triangular grid). The permutation comes
/// from a seed, so the same seed always draws the same field. Output is about -1...1.
public struct SimplexNoise2D: Sendable {
  private let permutation: [Int]

  private static let gradients: [(Double, Double)] = [
    (1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1),
  ]
  private static let skew = 0.5 * (3.0.squareRoot() - 1)
  private static let unskew = (3 - 3.0.squareRoot()) / 6

  public init(seed: UInt64) {
    var generator = SeededGenerator(seed: seed ^ 0x5149_4D50)
    var table = Array(0..<256)
    table.shuffle(using: &generator)
    permutation = table + table
  }

  /// Noise value at a point, roughly in -1...1.
  public func value(x: Double, y: Double) -> Double {
    let skewed = (x + y) * Self.skew
    let cellX = (x + skewed).rounded(.down)
    let cellY = (y + skewed).rounded(.down)
    let unskewed = (cellX + cellY) * Self.unskew
    let x0 = x - (cellX - unskewed)
    let y0 = y - (cellY - unskewed)
    let step = x0 > y0 ? (1.0, 0.0) : (0.0, 1.0)
    let x1 = x0 - step.0 + Self.unskew
    let y1 = y0 - step.1 + Self.unskew
    let x2 = x0 - 1 + 2 * Self.unskew
    let y2 = y0 - 1 + 2 * Self.unskew

    let column = Int(cellX) & 255
    let row = Int(cellY) & 255
    let gradientA = permutation[column + permutation[row]] % 8
    let gradientB = permutation[column + Int(step.0) + permutation[row + Int(step.1)]] % 8
    let gradientC = permutation[column + 1 + permutation[row + 1]] % 8

    return 70
      * (corner(gradientA, x0, y0) + corner(gradientB, x1, y1)
        + corner(gradientC, x2, y2))
  }

  private func corner(_ gradient: Int, _ x: Double, _ y: Double) -> Double {
    let falloff = 0.5 - x * x - y * y
    guard falloff > 0 else { return 0 }
    let (gx, gy) = Self.gradients[gradient]
    let squared = falloff * falloff
    return squared * squared * (gx * x + gy * y)
  }
}
