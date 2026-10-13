import Foundation

/// The escape-time maps that do not fit the other families: Buffalo, the two Alpha Mandelbrot sets,
/// Cactus, Zubieta, the four Barnsley sets, Thorn and Feather. Each follows the Android engine's
/// update rule, with the start values that `EscapeTimeFractal.start` gives them.
extension EscapeTimeFractal {

  static func advanceSpecial(_ orbit: inout Orbit, _ settings: Settings) {
    let z = orbit.z
    let c = orbit.c
    orbit.previous = z
    switch settings.kind {
    case .buffalo:
      // The power of (|re z| + i|im z|), with the real and imaginary parts each made positive
      // again and shifted by c.
      let folded = FractalComplex(abs(z.re), abs(z.im))
      let powered = FractalComplex.power(folded, Double(settings.power))
      orbit.z = FractalComplex(abs(powered.re) + c.re, abs(powered.im) + c.im)
    case .alphaMandelbrot, .alphaMandelbrotJulia:
      // With s = z^2: z' = s + (s + c)^2 + c.
      let square = z * z
      let shifted = square + c
      orbit.z = square + shifted * shifted + c
    case .cactus:
      // z' = z*z^2 + (c - 1)*z - c.
      orbit.z = z * (z * z) + (c - 1) * z - c
    case .zubieta:
      // z' = z^2 + c/z. A zero z makes c/z undefined, which the division gives as infinity.
      orbit.z = z * z + c / z
    case .barnsleyMandelbrot, .barnsleyJulia:
      // Barnsley's first map: z' = (z -/+ 1)*c, with -1 when Re z >= 0 and +1 otherwise.
      let offset: Double = z.re >= 0 ? -1 : 1
      orbit.z = (z + offset) * c
    case .barnsleyII:
      // The second map chooses the sign by the imaginary part of z*c.
      let product = z * c
      let offset: Double = product.im >= 0 ? -1 : 1
      orbit.z = (z + offset) * c
    case .barnsleyIII:
      // z' = z^2 - 1, plus c*Re z when Re z is not positive.
      let square = z * z
      orbit.z = z.re > 0 ? square - 1 : square - 1 + z.re * c
    case .thorn:
      // z' = Re z / cos(Im z) + c.re, and Im z / sin(Re z) + c.im. A zero denominator escapes.
      let cosine = cos(z.im)
      let sine = sin(z.re)
      if abs(cosine) < 1e-14 || abs(sine) < 1e-14 {
        orbit.z = FractalComplex(.infinity, .infinity)
      } else {
        orbit.z = FractalComplex(z.re / cosine + c.re, z.im / sine + c.im)
      }
    case .feather:
      // z' = z^3 / ((1 + Re z^2) + i*Im z^2) + c.
      let cube = z * z * z
      let denominator = FractalComplex(1 + z.re * z.re, z.im * z.im)
      orbit.z = cube / denominator + c
    default:
      preconditionFailure("\(settings.kind) is not a special map")
    }
  }
}
