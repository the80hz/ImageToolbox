// Port of Material Color Utilities (hct/hct_solver).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Finds the in-gamut sRGB colour for a hue, chroma and tone (L*).
///
/// When the requested chroma is out of gamut the chroma is reduced, never the hue or tone.
enum HctSolver {
  private static let scaledDiscountFromLinear = Matrix3(
    SIMD3(0.001200833568784504, 0.002389694492170889, 0.0002795742885861124),
    SIMD3(0.0005891086651375999, 0.0029785502573438758, 0.0003270666104008398),
    SIMD3(0.00010146692491640572, 0.0005364214359186694, 0.0032979401770712076))

  private static let linearFromScaledDiscount = Matrix3(
    SIMD3(1373.2198709594231, -1100.4251190754821, -7.278681089101213),
    SIMD3(-271.815969077903, 559.6580465940733, -32.46047482791194),
    SIMD3(1.9622899599665666, -57.173814538844006, 308.7233197812385))

  private static let yFromLinear = SIMD3(0.2126, 0.7152, 0.0722)

  /// Linear light at the boundary of each of the 255 pairs of neighbouring 8-bit values.
  private static let criticalPlanes: [Double] = (0..<255).map { index in
    linearPlane(Double(index) + 0.5)
  }

  private static func linearPlane(_ coordinate: Double) -> Double {
    let normalized = coordinate / 255.0
    if normalized <= 0.040449936 { return normalized / 12.92 * 100.0 }
    return pow((normalized + 0.055) / 1.055, 2.4) * 100.0
  }

  /// The ARGB colour for the given hue (degrees), chroma and tone (L*).
  static func solve(hue: Double, chroma: Double, lstar: Double) -> UInt32 {
    if chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999 {
      return MaterialColour.argb(fromLstar: lstar)
    }
    let hueRadians = MaterialColour.sanitizeDegrees(hue) * Double.pi / 180.0
    let y = MaterialColour.yFromLstar(lstar)
    if let exact = findResult(hueRadians: hueRadians, chroma: chroma, y: y) {
      return exact
    }
    return MaterialColour.argbFromLinear(bisectToLimit(y: y, targetHue: hueRadians))
  }

  // MARK: Exact solution

  private static func sanitizeRadians(_ angle: Double) -> Double {
    (angle + Double.pi * 8).truncatingRemainder(dividingBy: Double.pi * 2)
  }

  private static func trueDelinearized(_ component: Double) -> Double {
    let normalized = component / 100.0
    let value =
      normalized <= 0.0031308 ? normalized * 12.92 : 1.055 * pow(normalized, 1.0 / 2.4) - 0.055
    return value * 255.0
  }

  private static func chromaticAdaptation(_ component: Double) -> Double {
    let factor = pow(abs(component), 0.42)
    return MaterialColour.signum(component) * 400.0 * factor / (factor + 27.13)
  }

  private static func inverseChromaticAdaptation(_ adapted: Double) -> Double {
    let magnitude = abs(adapted)
    let base = max(0, 27.13 * magnitude / (400.0 - magnitude))
    return MaterialColour.signum(adapted) * pow(base, 1.0 / 0.42)
  }

  /// Hue in radians (-pi...pi) of a linear RGB colour under the standard viewing conditions.
  private static func hueOf(_ linear: SIMD3<Double>) -> Double {
    let scaled = scaledDiscountFromLinear.apply(linear)
    let rA = chromaticAdaptation(scaled.x)
    let gA = chromaticAdaptation(scaled.y)
    let bA = chromaticAdaptation(scaled.z)
    let a = (11.0 * rA + -12.0 * gA + bA) / 11.0
    let b = (rA + gA - 2.0 * bA) / 9.0
    return atan2(b, a)
  }

  /// Newton-style search over J for the colour with the exact chroma and luminance, if in gamut.
  private static func findResult(hueRadians: Double, chroma: Double, y: Double) -> UInt32? {
    var j = sqrt(y) * 11.0
    let vc = ViewingConditions.standard
    let tInnerCoefficient = 1.0 / pow(1.64 - pow(0.29, vc.n), 0.73)
    let eHue = 0.25 * (cos(hueRadians + 2.0) + 3.8)
    let p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
    let hSin = sin(hueRadians)
    let hCos = cos(hueRadians)

    for round in 0..<5 {
      let jNormalized = j / 100.0
      let alpha = (chroma == 0.0 || j == 0.0) ? 0.0 : chroma / sqrt(jNormalized)
      let t = pow(alpha * tInnerCoefficient, 1.0 / 0.9)
      let ac = vc.aw * pow(jNormalized, 1.0 / vc.c / vc.z)
      let p2 = ac / vc.nbb
      let gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11 * t * hCos + 108.0 * t * hSin)
      let a = gamma * hCos
      let b = gamma * hSin
      let rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
      let gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
      let bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0
      let scaled = SIMD3(
        inverseChromaticAdaptation(rA), inverseChromaticAdaptation(gA),
        inverseChromaticAdaptation(bA))
      let linear = linearFromScaledDiscount.apply(scaled)
      if linear.x < 0 || linear.y < 0 || linear.z < 0 { return nil }
      let fnj = yFromLinear.x * linear.x + yFromLinear.y * linear.y + yFromLinear.z * linear.z
      if fnj <= 0 { return nil }
      if round == 4 || abs(fnj - y) < 0.002 {
        if linear.x > 100.01 || linear.y > 100.01 || linear.z > 100.01 { return nil }
        return MaterialColour.argbFromLinear(linear)
      }
      // Newton step on J with the derivative approximated as 2 * fnj / j.
      j -= (fnj - y) * j / (2 * fnj)
    }
    return nil
  }

  // MARK: Gamut-boundary fallback

  private static func areInCyclicOrder(_ a: Double, _ b: Double, _ c: Double) -> Bool {
    sanitizeRadians(b - a) < sanitizeRadians(c - a)
  }

  private static func intercept(_ source: Double, _ mid: Double, _ target: Double) -> Double {
    (mid - source) / (target - source)
  }

  private static func lerpPoint(
    _ source: SIMD3<Double>, _ t: Double, _ target: SIMD3<Double>
  ) -> SIMD3<Double> {
    SIMD3(
      source.x + (target.x - source.x) * t,
      source.y + (target.y - source.y) * t,
      source.z + (target.z - source.z) * t)
  }

  private static func setCoordinate(
    _ source: SIMD3<Double>, _ coordinate: Double, _ target: SIMD3<Double>, axis: Int
  ) -> SIMD3<Double> {
    let t = intercept(source[axis], coordinate, target[axis])
    return lerpPoint(source, t, target)
  }

  private static func isBounded(_ x: Double) -> Bool { x >= 0.0 && x <= 100.0 }

  /// The n-th of the 12 vertices of the hexagon the plane Y = `y` cuts out of the RGB cube.
  private static func nthVertex(y: Double, n: Int) -> SIMD3<Double>? {
    let kR = yFromLinear.x
    let kG = yFromLinear.y
    let kB = yFromLinear.z
    let coordA = n % 4 <= 1 ? 0.0 : 100.0
    let coordB = n % 2 == 0 ? 0.0 : 100.0
    if n < 4 {
      let g = coordA
      let b = coordB
      let r = (y - g * kG - b * kB) / kR
      return isBounded(r) ? SIMD3(r, g, b) : nil
    } else if n < 8 {
      let b = coordA
      let r = coordB
      let g = (y - r * kR - b * kB) / kG
      return isBounded(g) ? SIMD3(r, g, b) : nil
    } else {
      let r = coordA
      let g = coordB
      let b = (y - r * kR - g * kG) / kB
      return isBounded(b) ? SIMD3(r, g, b) : nil
    }
  }

  /// The edge of the hexagon that contains the target hue.
  private static func bisectToSegment(
    y: Double, targetHue: Double
  ) -> (left: SIMD3<Double>, right: SIMD3<Double>) {
    var left = SIMD3<Double>(-1, -1, -1)
    var right = left
    var leftHue = 0.0
    var rightHue = 0.0
    var initialized = false
    var uncut = true
    for n in 0..<12 {
      guard let mid = nthVertex(y: y, n: n) else { continue }
      let midHue = hueOf(mid)
      if !initialized {
        left = mid
        right = mid
        leftHue = midHue
        rightHue = midHue
        initialized = true
        continue
      }
      if uncut || areInCyclicOrder(leftHue, midHue, rightHue) {
        uncut = false
        if areInCyclicOrder(leftHue, targetHue, midHue) {
          right = mid
          rightHue = midHue
        } else {
          left = mid
          leftHue = midHue
        }
      }
    }
    return (left, right)
  }

  private static func bisectToLimit(y: Double, targetHue: Double) -> SIMD3<Double> {
    var (left, right) = bisectToSegment(y: y, targetHue: targetHue)
    var leftHue = hueOf(left)
    for axis in 0..<3 where left[axis] != right[axis] {
      var lPlane: Int
      var rPlane: Int
      if left[axis] < right[axis] {
        lPlane = Int(floor(trueDelinearized(left[axis]) - 0.5))
        rPlane = Int(ceil(trueDelinearized(right[axis]) - 0.5))
      } else {
        lPlane = Int(ceil(trueDelinearized(left[axis]) - 0.5))
        rPlane = Int(floor(trueDelinearized(right[axis]) - 0.5))
      }
      for _ in 0..<8 {
        if abs(rPlane - lPlane) <= 1 { break }
        let mPlane = Int(floor(Double(lPlane + rPlane) / 2.0))
        let mid = setCoordinate(left, criticalPlanes[mPlane], right, axis: axis)
        let midHue = hueOf(mid)
        if areInCyclicOrder(leftHue, targetHue, midHue) {
          right = mid
          rPlane = mPlane
        } else {
          left = mid
          leftHue = midHue
          lPlane = mPlane
        }
      }
    }
    return (left + right) / 2.0
  }
}
