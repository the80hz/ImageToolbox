import Foundation

/// The Sierpinski carpet and triangle, as the Android engine tests them. Neither is found by iterating
/// a map: a point is tested for the removed parts level by level. A point outside the figure, or in a
/// removed part at any level, is black. A point that is solid at every level takes the engine's one
/// colour, so the figure is a single colour with black holes.
extension EscapeTimeFractal {

  /// The value of every solid point: the engine's colour position 0.2 + 0.72 * 1, as a hue, times 32.
  static let solidGeometryValue = (0.2 + 0.72) * 32

  /// The carpet fills [-1, 1]^2. At each level every cell is split into 3 x 3 parts, and the middle part
  /// is removed. The engine tests from 1 to 14 levels, taken from the iteration count.
  static func carpetValue(_ point: FractalComplex, maxLevels: Int) -> Double? {
    var u = (point.re + 1) / 2
    var v = (point.im + 1) / 2
    guard (0...1).contains(u), (0...1).contains(v) else { return nil }
    u = min(u, 1 - Double.ulpOfOne)
    v = min(v, 1 - Double.ulpOfOne)
    for _ in 0..<min(max(maxLevels, 1), 14) {
      u *= 3
      v *= 3
      let column = floor(u)
      let row = floor(v)
      if column == 1 && row == 1 {
        return nil
      }
      u -= column
      v -= row
    }
    return solidGeometryValue
  }

  /// The triangle has its vertices at (0, 0.96), (-1, -0.78) and (1, -0.78). Its barycentric weights are
  /// a for the top vertex, b for the left one and c for the right one. Each level keeps the corner whose
  /// weight is at least a half, scaled by two about that corner, and a point in the middle is removed.
  /// The engine tests from 1 to 18 levels.
  static func triangleValue(_ point: FractalComplex, maxLevels: Int) -> Double? {
    let top = (0.0, 0.96)
    let left = (-1.0, -0.78)
    let right = (1.0, -0.78)
    let denominator =
      (left.1 - right.1) * (top.0 - right.0) + (right.0 - left.0) * (top.1 - right.1)
    var a =
      ((left.1 - right.1) * (point.re - right.0) + (right.0 - left.0) * (point.im - right.1))
      / denominator
    var b =
      ((right.1 - top.1) * (point.re - right.0) + (top.0 - right.0) * (point.im - right.1))
      / denominator
    var c = 1 - a - b
    guard a >= 0, b >= 0, c >= 0 else { return nil }
    for _ in 0..<min(max(maxLevels, 1), 18) {
      if a >= 0.5 {
        a = a * 2 - 1
        b *= 2
        c *= 2
      } else if b >= 0.5 {
        b = b * 2 - 1
        a *= 2
        c *= 2
      } else if c >= 0.5 {
        c = c * 2 - 1
        a *= 2
        b *= 2
      } else {
        return nil
      }
    }
    return solidGeometryValue
  }
}
