import Foundation

/// The polynomial maps: z -> f(z) + c, where f is a square, a power or a fold of z, and the extra
/// terms of Phoenix, Spider and Man o' War. Lambda is the one map that has no "+ c": its constant
/// is the multiplier. The Buddhabrot uses the Mandelbrot map.
extension EscapeTimeFractal {

  static func advancePolynomial(_ orbit: inout Orbit, _ settings: Settings) {
    let z = orbit.z
    let c = orbit.c
    let previous = orbit.previous

    if settings.kind == .spider {
      // Spider: z' = z^2 + c, then the constant moves to c/2 + z'.
      let next = z * z + c
      orbit.previous = z
      orbit.z = next
      orbit.c = 0.5 * c + next
      return
    }

    var next: FractalComplex
    switch settings.kind {
    case .mandelbrot, .julia, .buddhabrot:
      next = z * z
    case .burningShip, .burningShipJulia:
      let folded = FractalComplex(abs(z.re), abs(z.im))
      next = folded * folded
    case .perpendicularBurningShip:
      // Only the imaginary part is folded, as the engine's (re z, -|im z|) does.
      let folded = FractalComplex(z.re, -abs(z.im))
      next = folded * folded
    case .tricorn:
      let conjugate = z.conjugate
      next = conjugate * conjugate
    case .multibrot:
      next = FractalComplex.power(z, Double(settings.power))
    case .multicorn:
      next = FractalComplex.power(z.conjugate, Double(settings.power))
    case .celtic, .celticJulia:
      let square = z * z
      next = FractalComplex(abs(square.re), square.im)
    case .phoenix:
      next = z * z + settings.phoenixParameter * previous
    case .manOWar:
      next = z * z + previous
    case .lambda:
      // lambda*z*(1 - z), with lambda in `c`. This map has no additive constant.
      orbit.previous = z
      orbit.z = c * z * (FractalComplex(1, 0) - z)
      return
    default:
      preconditionFailure("\(settings.kind) is not a polynomial map")
    }
    orbit.previous = z
    orbit.z = next + c
  }
}
