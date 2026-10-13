import Foundation

/// The distance estimators of the Mandelbulb family and of the quaternion sets, as the Android engine's
/// Rust renderer computes them. Each returns a signed distance, which is zero or negative inside the
/// set. The iteration counts come from the caller's work plan, so the loops take them as they are.
enum Fractal3DBulb {

  /// Mandelbulb: z -> z^power + c in spherical coordinates, with c the point. The loop stops once the
  /// radius passes 2.5, and the estimate is 0.5*ln r*r / |dr|. A point at the origin is reported as 0.
  static func mandelbulb(_ point: FractalVector, power: Double, iterations: Int) -> Double {
    var z = point
    var derivative = 1.0
    var radius = 0.0
    for _ in 0..<max(iterations, 0) {
      radius = z.length
      if radius > 2.5 { break }
      if radius < 1e-12 { return 0 }
      let theta = acos(min(max(z.z / radius, -1), 1))
      let phi = atan2(z.y, z.x)
      derivative = pow(radius, power - 1) * power * derivative + 1
      let raised = pow(radius, power)
      z =
        FractalVector(
          raised * sin(theta * power) * cos(phi * power),
          raised * sin(theta * power) * sin(phi * power),
          raised * cos(theta * power)) + point
    }
    return 0.5 * log(radius) * radius / max(abs(derivative), 1e-12)
  }

  /// Hybrid Mandelbulb-Julia: the Mandelbulb step with c the point on even steps and the Julia constant
  /// on odd steps. The loop stops once the radius passes 2, and runs from 6 to 24 steps.
  static func hybrid(
    _ point: FractalVector, power: Double, julia: FractalVector, iterations: Int
  ) -> Double {
    let exponent = min(max(power, 2), 16)
    var value = point
    var derivative = 1.0
    var radius = value.length
    for step in 0..<min(max(iterations, 6), 24) {
      if radius > 2 { break }
      if radius < 1e-12 { return 0 }
      let theta = acos(min(max(value.z / radius, -1), 1))
      let phi = atan2(value.y, value.x)
      derivative = pow(radius, exponent - 1) * exponent * derivative + 1
      let raised = pow(radius, exponent)
      let constant = step.isMultiple(of: 2) ? point : julia
      value =
        FractalVector(
          raised * sin(theta * exponent) * cos(phi * exponent),
          raised * sin(theta * exponent) * sin(phi * exponent),
          raised * cos(theta * exponent)) + constant
      radius = value.length
    }
    return 0.5 * log(max(radius, 1e-12)) * radius / max(abs(derivative), 1e-12)
  }

  /// Quaternion cubic: z -> z^3 + c, with c the constant and z starting at the point embedded in the
  /// quaternion. The constant and the point are reordered as the engine reorders them, so that the
  /// scalar part is the x component of each. The loop runs from 6 to 24 steps.
  static func quaternionCubic(
    _ point: FractalVector, constant: FractalQuaternion, iterations: Int
  ) -> Double {
    let c = FractalQuaternion(constant.y, constant.z, constant.w, constant.x)
    var q = FractalQuaternion(point.y, point.z, 0, point.x)
    var derivative = FractalQuaternion(0, 0, 0, 1)
    var radiusSquared = q.normSquared
    for _ in 0..<min(max(iterations, 6), 24) {
      if radiusSquared.squareRoot() > 2 { break }
      let square = q * q
      derivative = square * derivative * 3
      q = q * square + c
      radiusSquared = q.normSquared
    }
    let radius = max(radiusSquared.squareRoot(), 1e-12)
    return 0.5 * log(radius) * radius / max(derivative.normSquared.squareRoot(), 1e-12)
  }

  /// Quaternion Julia set: z -> z^2 + c, with c the constant and z starting at the point. The point is
  /// embedded as the engine embeds it: its x is the scalar part, its y and z are the i and j parts, and
  /// k is zero. The constant is reordered from its catalogue order, with its x as the scalar part. The
  /// derivative takes dr -> 2*max(|z|, 10^-8)*dr, and the loop stops once |z|^2 passes 16. The estimate is
  /// 0.5*ln|z|*|z| / dr.
  static func quaternionJulia(
    _ point: FractalVector, constant: FractalQuaternion, iterations: Int
  ) -> Double {
    let c = FractalQuaternion(constant.y, constant.z, constant.w, constant.x)
    var z = FractalQuaternion(point.y, point.z, 0, point.x)
    var derivative = 1.0
    var radiusSquared = z.normSquared
    for _ in 0..<max(iterations, 0) {
      derivative *= 2 * max(radiusSquared.squareRoot(), 1e-8)
      z = z * z + c
      radiusSquared = z.normSquared
      if radiusSquared > 16 { break }
    }
    let radius = max(radiusSquared.squareRoot(), 1e-12)
    return 0.5 * log(radius) * radius / max(derivative, 1e-12)
  }
}
