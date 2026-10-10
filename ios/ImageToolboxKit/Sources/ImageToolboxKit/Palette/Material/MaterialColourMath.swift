// Port of Material Color Utilities (utils/color_utils, utils/math_utils).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// A 3x3 matrix applied to a column vector, in the row order used by Material Color Utilities.
struct Matrix3: Sendable {
  let row0: SIMD3<Double>
  let row1: SIMD3<Double>
  let row2: SIMD3<Double>

  init(_ row0: SIMD3<Double>, _ row1: SIMD3<Double>, _ row2: SIMD3<Double>) {
    self.row0 = row0
    self.row1 = row1
    self.row2 = row2
  }

  func apply(_ v: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
      v.x * row0.x + v.y * row0.y + v.z * row0.z,
      v.x * row1.x + v.y * row1.y + v.z * row1.z,
      v.x * row2.x + v.y * row2.y + v.z * row2.z)
  }
}

/// sRGB, XYZ and CIE L*a*b* helpers on opaque 32-bit ARGB integers (`0xAARRGGBB`).
enum MaterialColour {
  static let whitePointD65 = SIMD3<Double>(95.047, 100.0, 108.883)

  static let srgbToXYZ = Matrix3(
    SIMD3(0.41233895, 0.35762064, 0.18051042),
    SIMD3(0.2126, 0.7152, 0.0722),
    SIMD3(0.01932141, 0.11916382, 0.95034478))

  static let xyzToSRGB = Matrix3(
    SIMD3(3.2413774792388685, -1.5376652402851851, -0.49885366846268053),
    SIMD3(-0.9691452513005321, 1.8758853451067872, 0.04156585616912061),
    SIMD3(0.05562093689691305, -0.20395524564742123, 1.0571799111220335))

  // MARK: ARGB packing

  static func argb(red: Int, green: Int, blue: Int) -> UInt32 {
    let r = UInt32(truncatingIfNeeded: red & 255)
    let g = UInt32(truncatingIfNeeded: green & 255)
    let b = UInt32(truncatingIfNeeded: blue & 255)
    return 0xFF00_0000 | (r << 16) | (g << 8) | b
  }

  static func red(_ argb: UInt32) -> Int { Int((argb >> 16) & 255) }
  static func green(_ argb: UInt32) -> Int { Int((argb >> 8) & 255) }
  static func blue(_ argb: UInt32) -> Int { Int(argb & 255) }

  static func argb(_ colour: RGBA) -> UInt32 {
    argb(red: Int(colour.red), green: Int(colour.green), blue: Int(colour.blue))
  }

  static func rgba(_ argb: UInt32) -> RGBA {
    RGBA(
      red: UInt8(red(argb)), green: UInt8(green(argb)), blue: UInt8(blue(argb)), alpha: 255)
  }

  // MARK: Transfer function

  /// sRGB 0...255 to linear light 0...100.
  static func linearized(_ component: Int) -> Double {
    let normalized = Double(component) / 255.0
    if normalized <= 0.040449936 {
      return normalized / 12.92 * 100.0
    }
    return pow((normalized + 0.055) / 1.055, 2.4) * 100.0
  }

  /// Linear light 0...100 to sRGB 0...255, rounded and clamped.
  static func delinearized(_ component: Double) -> Int {
    let normalized = component / 100.0
    let value: Double
    if normalized <= 0.0031308 {
      value = normalized * 12.92
    } else {
      value = 1.055 * pow(normalized, 1.0 / 2.4) - 0.055
    }
    return min(255, max(0, Int((value * 255.0).rounded())))
  }

  static func argbFromLinear(_ linear: SIMD3<Double>) -> UInt32 {
    argb(
      red: delinearized(linear.x), green: delinearized(linear.y),
      blue: delinearized(linear.z))
  }

  // MARK: XYZ and L*

  static func xyz(fromARGB argb: UInt32) -> SIMD3<Double> {
    let linear = SIMD3(
      linearized(red(argb)), linearized(green(argb)), linearized(blue(argb)))
    return srgbToXYZ.apply(linear)
  }

  static func argb(fromXYZ xyz: SIMD3<Double>) -> UInt32 {
    argbFromLinear(xyzToSRGB.apply(xyz))
  }

  private static let labEpsilon = 216.0 / 24389.0
  private static let labKappa = 24389.0 / 27.0

  private static func labF(_ t: Double) -> Double {
    t > labEpsilon ? pow(t, 1.0 / 3.0) : (labKappa * t + 16) / 116
  }

  private static func labInvF(_ ft: Double) -> Double {
    let ft3 = ft * ft * ft
    return ft3 > labEpsilon ? ft3 : (116 * ft - 16) / labKappa
  }

  /// Luminance Y in 0...100 for a CIE L* (tone) in 0...100.
  static func yFromLstar(_ lstar: Double) -> Double {
    100.0 * labInvF((lstar + 16.0) / 116.0)
  }

  static func lstarFromY(_ y: Double) -> Double {
    labF(y / 100.0) * 116.0 - 16.0
  }

  static func lstar(fromARGB argb: UInt32) -> Double {
    lstarFromY(xyz(fromARGB: argb).y)
  }

  /// The grey with the given tone.
  static func argb(fromLstar lstar: Double) -> UInt32 {
    let component = delinearized(yFromLstar(lstar))
    return argb(red: component, green: component, blue: component)
  }

  static func lab(fromARGB argb: UInt32) -> SIMD3<Double> {
    let xyz = xyz(fromARGB: argb)
    let fx = labF(xyz.x / whitePointD65.x)
    let fy = labF(xyz.y / whitePointD65.y)
    let fz = labF(xyz.z / whitePointD65.z)
    return SIMD3(116.0 * fy - 16, 500.0 * (fx - fy), 200.0 * (fy - fz))
  }

  static func argb(fromLab lab: SIMD3<Double>) -> UInt32 {
    let fy = (lab.x + 16.0) / 116.0
    let fx = lab.y / 500.0 + fy
    let fz = fy - lab.z / 200.0
    let xyz = SIMD3(labInvF(fx), labInvF(fy), labInvF(fz)) * whitePointD65
    return argb(fromXYZ: xyz)
  }

  // MARK: Angles and clamping

  static func sanitizeDegrees(_ degrees: Double) -> Double {
    let reduced = degrees.truncatingRemainder(dividingBy: 360.0)
    return reduced < 0 ? reduced + 360.0 : reduced
  }

  /// Integer variant: wraps into 0..<360 (Java remainder semantics).
  static func sanitizeDegrees(_ degrees: Int) -> Int {
    if degrees < 0 { return degrees % 360 + 360 }
    if degrees >= 360 { return degrees % 360 }
    return degrees
  }

  /// Shortest angular distance between two hues, 0...180.
  static func differenceDegrees(_ a: Double, _ b: Double) -> Double {
    180.0 - abs(abs(a - b) - 180.0)
  }

  /// 1 when the shorter way from `from` to `to` increases the angle, otherwise -1.
  static func rotationDirection(from: Double, to: Double) -> Double {
    sanitizeDegrees(to - from) <= 180.0 ? 1.0 : -1.0
  }

  static func lerp(_ start: Double, _ stop: Double, _ amount: Double) -> Double {
    (1.0 - amount) * start + amount * stop
  }

  static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(max(value, low), high)
  }

  static func signum(_ value: Double) -> Double {
    value < 0 ? -1.0 : (value > 0 ? 1.0 : 0.0)
  }
}
