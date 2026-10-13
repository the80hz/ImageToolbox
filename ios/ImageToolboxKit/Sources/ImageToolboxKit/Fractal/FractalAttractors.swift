import Foundation

/// The two-dimensional attractors. Each map is iterated from a fixed start, the first steps are
/// dropped so the orbit settles, and every later point is a hit. The orbit stops when it leaves the
/// square of side 2*10^7 or becomes non-finite. The starts and the maps follow the Android engine.
enum FractalAttractors {

  private static let transient = 100
  private static let limit = 1e7

  /// The start point of each attractor's orbit.
  static func start(_ kind: EscapeTimeFractal.Kind) -> (Double, Double) {
    switch kind {
    case .gingerbreadman, .gumowskiMira: (-0.1, 0)
    case .tinkerbell: (-0.72, -0.64)
    default: (0.1, 0)
    }
  }

  static func plot(
    _ kind: EscapeTimeFractal.Kind,
    _ constants: EscapeTimeFractal.Coefficients,
    into canvas: inout DensityCanvas,
    steps: Int
  ) {
    var (x, y) = start(kind)
    for index in 0..<(transient + steps) {
      (x, y) = step(kind, x, y, constants)
      // NaN fails the comparison, so an orbit that overflows ends the drawing.
      guard abs(x) <= limit && abs(y) <= limit else { break }
      if index >= transient {
        // The engine stamps each orbit point with a disc of radius 2, not the radius 1 of the lines.
        canvas.add(real: x, imaginary: y, radius: 2)
      }
    }
  }

  /// One step of the map. The constants a to d are the kind's own, as the defaults describe.
  static func step(
    _ kind: EscapeTimeFractal.Kind,
    _ x: Double,
    _ y: Double,
    _ constants: EscapeTimeFractal.Coefficients
  ) -> (Double, Double) {
    let a = constants.a
    let b = constants.b
    let c = constants.c
    let d = constants.d
    switch kind {
    case .hopalong:
      let root = sqrt(abs(b * x - c))
      return (y - (x < 0 ? -root : root), a - x)
    case .martin:
      return (y - sin(x), a - x)
    case .gingerbreadman:
      return (1 - y + abs(x), x)
    case .clifford:
      return (sin(a * y) + c * cos(a * x), sin(b * x) + d * cos(b * y))
    case .deJong:
      return (sin(a * y) - cos(b * x), sin(c * x) - cos(d * y))
    case .ikeda:
      // The rotation angle falls with the squared radius, as in the classic Ikeda map.
      let angle = c - d / (1 + x * x + y * y)
      return (
        a + b * (x * cos(angle) - y * sin(angle)),
        b * (x * sin(angle) + y * cos(angle))
      )
    case .tinkerbell:
      return (x * x - y * y + a * x + b * y, 2 * x * y + c * x + d * y)
    case .gumowskiMira:
      // The engine's form: x' = y + a(1 - b*y^2)*y + f(x), with f(v) = bv + 2(1 - b)v^2/(1 + v^2).
      let nextX = y + a * (1 - b * y * y) * y + gumowskiCurve(x, b)
      return (nextX, -x + gumowskiCurve(nextX, b))
    case .chip:
      let sign: Double = x < 0 ? -1 : 1
      let first = log(max(abs(b * x - c), 0.001))
      let second = log(max(abs(c * x - b), 0.001))
      return (y - sign * cos(first * first) * atan(second * second), a - x)
    case .quadruptwo:
      let sign: Double = x < 0 ? -1 : 1
      let first = log(max(abs(b * x - c), 0.001))
      let second = abs(c * x - b)
      return (y - sign * sin(first) * atan(second * second), a - x)
    case .threeply:
      let sign: Double = x < 0 ? -1 : 1
      let term = sin(x) * cos(b) + c - x * sin(a + b + c)
      return (y - sign * abs(term), a - x)
    default:
      preconditionFailure("\(kind) is not an attractor")
    }
  }

  /// f(v) = muv + 2(1 - mu)v^2 / (1 + v^2), the non-linear term of the Gumowski-Mira map.
  private static func gumowskiCurve(_ value: Double, _ mu: Double) -> Double {
    mu * value + 2 * (1 - mu) * value * value / (1 + value * value)
  }
}
