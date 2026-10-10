// Port of Material Color Utilities (hct/cam16, hct/viewing_conditions).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// The environment a colour is viewed in, for CAM16.
///
/// Only the standard conditions of Material Color Utilities are used: D65 white point,
/// 50 L* background, average surround, no illuminant discounting.
struct ViewingConditions: Sendable {
  let whitePoint: SIMD3<Double>
  let adaptingLuminance: Double
  let backgroundLstar: Double
  let surround: Double
  let n: Double
  let aw: Double
  let nbb: Double
  let ncb: Double
  let c: Double
  let nc: Double
  let rgbD: SIMD3<Double>
  let fl: Double
  let flRoot: Double
  let z: Double

  /// Standard conditions, `ViewingConditions.DEFAULT` upstream.
  static let standard = ViewingConditions(
    whitePoint: MaterialColour.whitePointD65,
    adaptingLuminance: 200.0 / Double.pi * MaterialColour.yFromLstar(50.0) / 100.0,
    backgroundLstar: 50.0, surround: 2.0, discountingIlluminant: false)

  init(
    whitePoint: SIMD3<Double>, adaptingLuminance: Double, backgroundLstar: Double,
    surround: Double, discountingIlluminant: Bool
  ) {
    let luminance = adaptingLuminance
    let background = max(0.1, backgroundLstar)
    let white = Cam16.cone.apply(whitePoint)
    let f = 0.8 + surround / 10.0
    let c =
      f >= 0.9
      ? MaterialColour.lerp(0.59, 0.69, (f - 0.9) * 10.0)
      : MaterialColour.lerp(0.525, 0.59, (f - 0.8) * 10.0)
    var d =
      discountingIlluminant
      ? 1.0 : f * (1.0 - (1.0 / 3.6) * exp((-luminance - 42.0) / 92.0))
    d = MaterialColour.clamp(d, 0.0, 1.0)
    let rgbD = SIMD3(
      d * (100.0 / white.x) + 1.0 - d,
      d * (100.0 / white.y) + 1.0 - d,
      d * (100.0 / white.z) + 1.0 - d)
    let k = 1.0 / (5.0 * luminance + 1.0)
    let k4 = k * k * k * k
    let k4F = 1.0 - k4
    let fl = k4 * luminance + 0.1 * k4F * k4F * cbrt(5.0 * luminance)
    let n = MaterialColour.yFromLstar(background) / whitePoint.y
    let nbb = 0.725 / pow(n, 0.2)
    let adapted = SIMD3(
      pow(fl * rgbD.x * white.x / 100.0, 0.42),
      pow(fl * rgbD.y * white.y / 100.0, 0.42),
      pow(fl * rgbD.z * white.z / 100.0, 0.42))
    let response = SIMD3(
      400.0 * adapted.x / (adapted.x + 27.13),
      400.0 * adapted.y / (adapted.y + 27.13),
      400.0 * adapted.z / (adapted.z + 27.13))

    self.whitePoint = whitePoint
    self.adaptingLuminance = luminance
    self.backgroundLstar = background
    self.surround = surround
    self.n = n
    self.aw = (40.0 * response.x + 20.0 * response.y + response.z) / 20.0 * nbb
    self.nbb = nbb
    self.ncb = nbb
    self.c = c
    self.nc = f
    self.rgbD = rgbD
    self.fl = fl
    self.flRoot = pow(fl, 0.25)
    self.z = 1.48 + sqrt(n)
  }
}

/// CAM16 colour appearance: hue, chroma, lightness J, and the CAM16-UCS coordinates.
struct Cam16: Sendable {
  /// Hue in degrees, 0..<360.
  let hue: Double
  let chroma: Double
  let j: Double
  let q: Double
  let m: Double
  let s: Double
  let jstar: Double
  let astar: Double
  let bstar: Double

  static let cone = Matrix3(
    SIMD3(0.401288, 0.650173, -0.051461),
    SIMD3(-0.250268, 1.204414, 0.045854),
    SIMD3(-0.002079, 0.048952, 0.953127))

  static let coneInverse = Matrix3(
    SIMD3(1.8620678550872327, -1.0112546305316843, 0.14918677544445175),
    SIMD3(0.38752654323613717, 0.6214474419314753, -0.008973985167612518),
    SIMD3(-0.015841498849333856, -0.03412293802851557, 1.0499644368778496))

  /// Appearance of an sRGB colour under the standard viewing conditions.
  init(argb: UInt32) {
    self.init(xyz: MaterialColour.xyz(fromARGB: argb), conditions: .standard)
  }

  init(xyz: SIMD3<Double>, conditions vc: ViewingConditions) {
    let cone = Self.cone.apply(xyz)
    let discounted = cone * vc.rgbD

    func adapt(_ value: Double) -> Double {
      let factor = pow(vc.fl * abs(value) / 100.0, 0.42)
      return MaterialColour.signum(value) * 400.0 * factor / (factor + 27.13)
    }
    let rA = adapt(discounted.x)
    let gA = adapt(discounted.y)
    let bA = adapt(discounted.z)

    let a = (11.0 * rA + -12.0 * gA + bA) / 11.0
    let b = (rA + gA - 2.0 * bA) / 9.0
    let u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0
    let p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0

    let degrees = atan2(b, a) * 180.0 / Double.pi
    let hue = degrees < 0 ? degrees + 360.0 : (degrees >= 360 ? degrees - 360.0 : degrees)
    let hueRadians = hue * Double.pi / 180.0

    let ac = p2 * vc.nbb
    let j = 100.0 * pow(ac / vc.aw, vc.c * vc.z)
    let q = (4.0 / vc.c) * sqrt(j / 100.0) * (vc.aw + 4.0) * vc.flRoot

    let huePrime = hue < 20.14 ? hue + 360 : hue
    let eHue = 0.25 * (cos(huePrime * Double.pi / 180.0 + 2.0) + 3.8)
    let p1 = 50000.0 / 13.0 * eHue * vc.nc * vc.ncb
    let t = p1 * hypot(a, b) / (u + 0.305)
    let alpha = pow(1.64 - pow(0.29, vc.n), 0.73) * pow(t, 0.9)
    let chroma = alpha * sqrt(j / 100.0)
    let m = chroma * vc.flRoot
    let s = 50.0 * sqrt((alpha * vc.c) / (vc.aw + 4.0))

    let jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
    let mstar = 1.0 / 0.0228 * log(1.0 + 0.0228 * m)

    self.hue = hue
    self.chroma = chroma
    self.j = j
    self.q = q
    self.m = m
    self.s = s
    self.jstar = jstar
    self.astar = mstar * cos(hueRadians)
    self.bstar = mstar * sin(hueRadians)
  }

  private init(
    hue: Double, chroma: Double, j: Double, q: Double, m: Double, s: Double,
    jstar: Double, astar: Double, bstar: Double
  ) {
    self.hue = hue
    self.chroma = chroma
    self.j = j
    self.q = q
    self.m = m
    self.s = s
    self.jstar = jstar
    self.astar = astar
    self.bstar = bstar
  }

  /// Builds the appearance from lightness J, chroma and hue.
  init(j: Double, chroma: Double, hue: Double, conditions vc: ViewingConditions = .standard) {
    let q = (4.0 / vc.c) * sqrt(j / 100.0) * (vc.aw + 4.0) * vc.flRoot
    let m = chroma * vc.flRoot
    let alpha = chroma / sqrt(j / 100.0)
    let s = 50.0 * sqrt((alpha * vc.c) / (vc.aw + 4.0))
    let hueRadians = hue * Double.pi / 180.0
    let jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
    let mstar = 1.0 / 0.0228 * log(1.0 + 0.0228 * m)
    self.init(
      hue: hue, chroma: chroma, j: j, q: q, m: m, s: s, jstar: jstar,
      astar: mstar * cos(hueRadians), bstar: mstar * sin(hueRadians))
  }

  /// Builds the appearance from CAM16-UCS coordinates.
  init(jstar: Double, astar: Double, bstar: Double, conditions vc: ViewingConditions = .standard) {
    let m = hypot(astar, bstar)
    let colourfulness = (exp(m * 0.0228) - 1.0) / 0.0228
    let chroma = colourfulness / vc.flRoot
    var hue = atan2(bstar, astar) * 180.0 / Double.pi
    if hue < 0 { hue += 360.0 }
    let j = jstar / (1.0 - (jstar - 100.0) * 0.007)
    self.init(j: j, chroma: chroma, hue: hue, conditions: vc)
  }

  /// The XYZ colour this appearance corresponds to under the given viewing conditions.
  func xyz(conditions vc: ViewingConditions = .standard) -> SIMD3<Double> {
    let alpha = (chroma == 0.0 || j == 0.0) ? 0.0 : chroma / sqrt(j / 100.0)
    let t = pow(alpha / pow(1.64 - pow(0.29, vc.n), 0.73), 1.0 / 0.9)
    let hueRadians = hue * Double.pi / 180.0
    let eHue = 0.25 * (cos(hueRadians + 2.0) + 3.8)
    let ac = vc.aw * pow(j / 100.0, 1.0 / vc.c / vc.z)
    let p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
    let p2 = ac / vc.nbb
    let hSin = sin(hueRadians)
    let hCos = cos(hueRadians)
    let gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin)
    let a = gamma * hCos
    let b = gamma * hSin
    let rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
    let gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
    let bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0

    func restore(_ adapted: Double, _ discount: Double) -> Double {
      let base = max(0, (27.13 * abs(adapted)) / (400.0 - abs(adapted)))
      let cone = MaterialColour.signum(adapted) * (100.0 / vc.fl) * pow(base, 1.0 / 0.42)
      return cone / discount
    }
    let rgb = SIMD3(restore(rA, vc.rgbD.x), restore(gA, vc.rgbD.y), restore(bA, vc.rgbD.z))
    return Self.coneInverse.apply(rgb)
  }

  /// The sRGB colour this appearance corresponds to under the standard viewing conditions.
  var argb: UInt32 {
    MaterialColour.argb(fromXYZ: xyz())
  }
}
