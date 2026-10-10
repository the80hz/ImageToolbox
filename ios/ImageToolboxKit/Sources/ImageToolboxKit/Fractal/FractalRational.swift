import Foundation

/// The rational and Newton-type iterations: Newton's method for z^3 - 1, Nova, the two Magnet sets, the
/// complex Collatz map and the Lyapunov exponent of the logistic map. Each follows the Android
/// engine's loop, with its start, its escape or convergence test and the value it colours.
extension EscapeTimeFractal {

  /// Newton's method for z^3 - 1, from the pixel. The orbit converges when a step moves it by less than
  /// 10^-10, and its value is the step count at that point, plus a third of the hue wheel for each root
  /// (32 / 3 counts), so the three roots get three colours. Nil when it does not converge within
  /// `maxIterations`, or when the derivative vanishes at z = 0.
  static func newtonValue(real: Double, imaginary: Double, maxIterations: Int) -> Double? {
    let roots = [
      FractalComplex(1, 0), FractalComplex(-0.5, sqrt(3) / 2), FractalComplex(-0.5, -sqrt(3) / 2),
    ]
    var z = FractalComplex(real, imaginary)
    var iterations = 0
    while iterations < maxIterations {
      let old = z
      let square = old * old
      let derivative = 3 * square
      guard derivative.squaredMagnitude > 0 else { return nil }
      z = old - (square * old - 1) / derivative
      iterations += 1
      if (z - old).squaredMagnitude < 1e-20 {
        let index =
          roots.indices.min { (z - roots[$0]).squaredMagnitude < (z - roots[$1]).squaredMagnitude }
          ?? 0
        return Double(iterations) + Double(index) * 32 / 3
      }
    }
    return nil
  }

  /// Nova: z' = z - a*(z^3 - 1)/(3z^2) + c, from z = 1 with c the pixel. It stops when a step moves less
  /// than 10^-10, or when the orbit leaves the bailout radius, and its value is the plain step count.
  static func novaValue(
    _ point: FractalComplex, relaxation: Double, bailout: Double, maxIterations: Int
  ) -> Double? {
    var z = FractalComplex(1, 0)
    let limit = bailout * bailout
    var iterations = 0
    while iterations < maxIterations {
      let old = z
      let square = old * old
      let derivative = 3 * square
      guard derivative.squaredMagnitude > 0 else { return nil }
      z = old - relaxation * ((square * old - 1) / derivative) + point
      iterations += 1
      let converged = (z - old).squaredMagnitude < 1e-20
      if converged || !(z.squaredMagnitude <= limit) {
        return Double(iterations)
      }
    }
    return nil
  }

  /// The Magnet I map z' = ((z^2 + c - 1)/(2z + c - 2))^2 and the Magnet II map z' = q^2, where
  /// q = (z^3 + 3(c - 1)z + (c - 1)(c - 2)) / (3z^2 + 3(c - 2)z + (c - 1)(c - 2) + 1), both from z = 0
  /// with c the pixel. The radius is the bailout or 100, whichever is larger. The value is the step
  /// count, unsmoothed, and an orbit that settles on 1 is black.
  static func magnetValue(
    _ point: FractalComplex, doubled: Bool, bailout: Double, maxIterations: Int
  ) -> Double? {
    let radius = max(bailout, 100)
    let limit = radius * radius
    var z = FractalComplex.zero
    var iterations = 0
    while iterations < maxIterations {
      guard let quotient = magnetQuotient(z, point, doubled: doubled) else {
        return Double(iterations + 1)
      }
      z = quotient * quotient
      iterations += 1
      let finite = z.re.isFinite && z.im.isFinite
      if !finite || !(z.squaredMagnitude <= limit) {
        return Double(iterations)
      }
      if (z - 1).squaredMagnitude < 1e-20 {
        return nil
      }
    }
    return nil
  }

  /// The quotient q of one magnet step at z, or nil when its denominator vanishes.
  static func magnetQuotient(
    _ z: FractalComplex, _ c: FractalComplex, doubled: Bool
  ) -> FractalComplex? {
    let square = z * z
    let numerator: FractalComplex
    let denominator: FractalComplex
    if doubled {
      let minusOne = c - 1
      let minusTwo = c - 2
      let common = minusOne * minusTwo
      numerator = z * square + 3 * (minusOne * z) + common
      denominator = 3 * square + 3 * (minusTwo * z) + common + 1
    } else {
      numerator = square + c - 1
      denominator = 2 * z + c - 2
    }
    guard denominator.squaredMagnitude > 0 else { return nil }
    return numerator / denominator
  }

  /// The complex Collatz map (2 + 7z - (2 + 5z)*cos piz)/4, from the pixel. An orbit that leaves
  /// |z|^2 > B^2 is coloured by its smoothed step, and every other orbit by twice its nearest distance to
  /// zero, so nothing is black. The position is a hue turn, and the value is 32 times it.
  static func collatzValue(_ point: FractalComplex, bailout: Double, maxIterations: Int) -> Double {
    let limit = bailout * bailout
    var z = point
    var nearest = Double.infinity
    for iteration in 0..<max(maxIterations, 0) {
      let squared = z.squaredMagnitude
      if !squared.isFinite || squared > limit {
        // The engine takes the larger of |z|^2 and 1, so a NaN counts as 1.
        let clamped = squared.isNaN ? 1 : max(squared, 1)
        let logarithm = 0.5 * log(clamped)
        let smooth =
          Double(iteration) + 1 - log(max(logarithm / log(2), 1e-4)) / log(2)
        return 32 * wrappedUnit(smooth / 50)
      }
      nearest = min(nearest, squared.squareRoot())
      z = collatzStep(z)
    }
    let position = nearest.isFinite ? wrappedUnit(nearest * 2) : 0
    return 32 * position
  }

  private static func collatzStep(_ z: FractalComplex) -> FractalComplex {
    let cosine = FractalComplex(Double.pi * z.re, Double.pi * z.im).cosine
    let linear = FractalComplex(2, 0) + 7 * z
    let factor = FractalComplex(2, 0) + 5 * z
    return 0.25 * (linear - factor * cosine)
  }

  /// The Lyapunov exponent of x -> r*x(1 - x), where r alternates between a and b. The orbit settles for
  /// 32 steps, then the derivative ln|r(1 - 2x)| of each step is averaged, taken before the step. A
  /// stable order has a negative exponent and is coloured by its size, and a chaotic one by its positive
  /// size. The value is 32 times that hue position.
  static func lyapunovValue(a: Double, b: Double, maxIterations: Int) -> Double {
    var state = 0.5
    for index in 0..<32 {
      let rate = index % 2 == 0 ? a : b
      state = rate * state * (1 - state)
    }
    var sum = 0.0
    for index in 0..<max(maxIterations, 0) {
      let rate = index % 2 == 0 ? a : b
      let magnitude = abs(rate * (1 - 2 * state))
      // A NaN derivative takes the floor, as the engine's max does.
      let derivative = magnitude.isNaN ? 1e-15 : max(magnitude, 1e-15)
      sum += log(derivative)
      state = rate * state * (1 - state)
    }
    let exponent = sum / Double(maxIterations)
    let position: Double
    if exponent < 0 {
      position = 0.42 + clampedUnit(-exponent / 2.5) * 0.58
    } else {
      position = 0.18 * (1 - clampedUnit(exponent / 2.5))
    }
    return 32 * position
  }

  /// x mod 1 in [0, 1), as the engine's rem_euclid gives it.
  static func wrappedUnit(_ value: Double) -> Double {
    value - floor(value)
  }

  private static func clampedUnit(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}
