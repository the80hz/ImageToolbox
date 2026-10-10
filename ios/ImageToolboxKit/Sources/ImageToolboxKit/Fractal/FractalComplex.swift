import Foundation

/// A complex number for the fractal maps. Division by zero gives infinities or NaN, and the
/// escape test treats both as escaped, so the maps need no special cases for poles.
struct FractalComplex: Equatable, Sendable {
  var re: Double
  var im: Double

  init(_ re: Double, _ im: Double) {
    self.re = re
    self.im = im
  }

  static let zero = FractalComplex(0, 0)

  var squaredMagnitude: Double {
    re * re + im * im
  }

  var conjugate: FractalComplex {
    FractalComplex(re, -im)
  }

  /// z^exponent in polar form, with the principal argument.
  static func power(_ value: FractalComplex, _ exponent: Double) -> FractalComplex {
    let radius = pow(value.squaredMagnitude.squareRoot(), exponent)
    let angle = atan2(value.im, value.re) * exponent
    return FractalComplex(radius * cos(angle), radius * sin(angle))
  }

  /// The principal logarithm: ln|z| + i*arg z.
  var logarithm: FractalComplex {
    FractalComplex(log(squaredMagnitude) / 2, atan2(im, re))
  }

  var exponential: FractalComplex {
    let scale = exp(re)
    return FractalComplex(scale * cos(im), scale * sin(im))
  }

  /// sin(a + bi) = sin a * cosh b + i * cos a * sinh b.
  var sine: FractalComplex {
    FractalComplex(sin(re) * cosh(im), cos(re) * sinh(im))
  }

  /// cos(a + bi) = cos a * cosh b - i * sin a * sinh b.
  var cosine: FractalComplex {
    FractalComplex(cos(re) * cosh(im), -sin(re) * sinh(im))
  }

  /// sinh(a + bi) = sinh a * cos b + i * cosh a * sin b.
  var hyperbolicSine: FractalComplex {
    FractalComplex(sinh(re) * cos(im), cosh(re) * sin(im))
  }

  static func + (lhs: FractalComplex, rhs: FractalComplex) -> FractalComplex {
    FractalComplex(lhs.re + rhs.re, lhs.im + rhs.im)
  }

  static func - (lhs: FractalComplex, rhs: FractalComplex) -> FractalComplex {
    FractalComplex(lhs.re - rhs.re, lhs.im - rhs.im)
  }

  static func + (lhs: FractalComplex, rhs: Double) -> FractalComplex {
    FractalComplex(lhs.re + rhs, lhs.im)
  }

  static func - (lhs: FractalComplex, rhs: Double) -> FractalComplex {
    FractalComplex(lhs.re - rhs, lhs.im)
  }

  static func * (lhs: FractalComplex, rhs: FractalComplex) -> FractalComplex {
    FractalComplex(lhs.re * rhs.re - lhs.im * rhs.im, lhs.re * rhs.im + lhs.im * rhs.re)
  }

  static func * (scalar: Double, value: FractalComplex) -> FractalComplex {
    FractalComplex(scalar * value.re, scalar * value.im)
  }

  static func / (lhs: FractalComplex, rhs: FractalComplex) -> FractalComplex {
    let denominator = rhs.squaredMagnitude
    let product = lhs * rhs.conjugate
    return FractalComplex(product.re / denominator, product.im / denominator)
  }
}
