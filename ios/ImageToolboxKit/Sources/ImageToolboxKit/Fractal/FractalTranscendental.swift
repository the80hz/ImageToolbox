import Foundation

/// The transcendental maps: the sine map c*sin z, the cosine and sinh of z plus c, and the power tower
/// c^z. The Mandelbrot-style kinds start with c the pixel (the sine map at z = 1, the others at 0),
/// and the Julia-style kinds start at the pixel with c fixed. Each follows the engine's Rust renderer.
extension EscapeTimeFractal {

  static func advanceTranscendental(_ orbit: inout Orbit, _ kind: Kind) {
    let z = orbit.z
    let c = orbit.c
    orbit.previous = z
    switch kind {
    case .sine, .juliaSine:
      // The sine map multiplies the sine by the constant: z' = c*sin z.
      orbit.z = c * z.sine
    case .cosine, .juliaCosine:
      orbit.z = z.cosine + c
    case .sinh, .juliaSinh:
      orbit.z = z.hyperbolicSine + c
    case .tetration:
      // c^z = exp(z * log c). A base of zero, or one that is not finite, has no logarithm, so the
      // orbit leaves at once with infinite values, as the engine gives them.
      let base = c.squaredMagnitude
      if base > 0 && base.isFinite {
        orbit.z = (z * c.logarithm).exponential
      } else {
        orbit.z = FractalComplex(.infinity, .infinity)
      }
    default:
      preconditionFailure("\(kind) is not a transcendental map")
    }
  }
}
