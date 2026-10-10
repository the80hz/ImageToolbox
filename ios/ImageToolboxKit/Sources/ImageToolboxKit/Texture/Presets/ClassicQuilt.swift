import Foundation

/// `QuiltFilter` of the native code: an orbit of a map of the unit square is followed for the
/// given number of steps, and each cell it lands in is counted. The counts run through the linear
/// colour map from black to white, against the highest count.
enum ClassicQuilt {
  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let iterations = max(ClassicMath.toInt(preset.value("iterations", fallback: 25000)), 0)
    let orbit = QuiltOrbit(
      a: Float(preset.value("a", fallback: -0.59)),
      b: Float(preset.value("b", fallback: 0.2)),
      c: Float(preset.value("c", fallback: 0.1)),
      d: Float(preset.value("d", fallback: 0)),
      k: Float(ClassicMath.toInt(preset.value("k", fallback: 0))))
    var x: Float = 0.1
    var y: Float = 0.3
    for _ in 0..<20 {
      (x, y) = orbit.step(x, y)
    }
    var counts = [Int](repeating: 0, count: width * height)
    var highest = 0
    for _ in 0..<iterations {
      (x, y) = orbit.step(x, y)
      let column = ClassicMath.toInt(Float(width) * x)
      let row = ClassicMath.toInt(Float(height) * y)
      guard column >= 0, column < width, row >= 0, row < height else { continue }
      let index = row * width + column
      let previous = counts[index]
      counts[index] = previous + 1
      // The native code compares the count before the visit, as this does.
      highest = max(highest, previous)
    }
    let colours = ClassicLinearColormap(low: 0xff00_0000, high: 0xffff_ffff)
    return counts.map { colours.colour(Float($0) / Float(highest)) }
  }
}

/// The map of `QuiltFilter.advance`, in float, with the constants of the filter.
private struct QuiltOrbit {
  let a: Float
  let b: Float
  let c: Float
  let d: Float
  let k: Float

  func step(_ x: Float, _ y: Float) -> (Float, Float) {
    let mx = ClassicNative.pi * x
    let my = ClassicNative.pi * y
    let sinX2 = sinf(2 * mx)
    let sinY2 = sinf(2 * my)
    let nextX =
      a * sinX2 + b * sinX2 * cosf(2 * my) + c * sinf(4 * mx) + d * sinf(6 * mx) * cosf(4 * my)
      + k * x
    let nextY =
      a * sinY2 + b * sinY2 * cosf(2 * mx) + c * sinf(4 * my) + d * sinf(6 * my) * cosf(4 * mx)
      + k * y
    return (Self.wrap(nextX), Self.wrap(nextY))
  }

  /// The fractional part of the value, kept in 0..<1 for negative values as well.
  private static func wrap(_ value: Float) -> Float {
    let whole = value.rounded(.towardZero)
    return value >= 0 ? value - whole : value - whole + 1
  }
}
