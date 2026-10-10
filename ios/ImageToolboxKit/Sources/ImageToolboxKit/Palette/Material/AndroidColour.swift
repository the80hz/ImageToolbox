// Colour helpers that mirror the Android functions the app's theme code calls, so the same
// inputs give the same bytes: androidx.core ColorUtils, Compose Color compositing and
// Material Color Utilities Blend.cam16Ucs (Copyright 2021 Google LLC, Apache License 2.0).

import Foundation

/// Opaque ARGB helpers with the exact rounding of their Android counterparts.
enum AndroidColour {

  /// `Blend.cam16Ucs`: interpolation in CAM16-UCS, which keeps the hue steady better than RGB.
  static func cam16Blend(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
    let a = Cam16(argb: from)
    let b = Cam16(argb: to)
    return Cam16(
      jstar: a.jstar + (b.jstar - a.jstar) * amount,
      astar: a.astar + (b.astar - a.astar) * amount,
      bstar: a.bstar + (b.bstar - a.bstar) * amount
    ).argb
  }

  /// `ColorUtils.blendARGB`: per-channel linear blend in float, truncated (not rounded).
  static func blend(_ first: UInt32, _ second: UInt32, _ ratio: Float) -> UInt32 {
    let inverse = 1 - ratio
    func channel(_ a: Int, _ b: Int) -> Int {
      Int(Float(a) * inverse + Float(b) * ratio)
    }
    return MaterialColour.argb(
      red: channel(MaterialColour.red(first), MaterialColour.red(second)),
      green: channel(MaterialColour.green(first), MaterialColour.green(second)),
      blue: channel(MaterialColour.blue(first), MaterialColour.blue(second)))
  }

  /// `ColorUtils.calculateLuminance`, 0...1.
  static func luminance(_ argb: UInt32) -> Double {
    func linear(_ component: Int) -> Double {
      let s = Double(component) / 255.0
      return s < 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    let r = linear(MaterialColour.red(argb))
    let g = linear(MaterialColour.green(argb))
    let b = linear(MaterialColour.blue(argb))
    return r * 0.2126 + g * 0.7152 + b * 0.0722
  }

  /// `ColorUtils.calculateContrast` for an opaque foreground.
  static func contrast(foreground: UInt32, background: UInt32) -> Double {
    let first = luminance(foreground) + 0.05
    let second = luminance(background) + 0.05
    return max(first, second) / min(first, second)
  }

  /// `Color.copy(alpha:).compositeOver(background)` in Compose, for an opaque background: the
  /// alpha is stored in 8 bits and the result rounded to 8 bits per channel.
  static func composite(_ foreground: UInt32, alpha: Float, over background: UInt32) -> UInt32 {
    let alphaByte = Int(alpha * 255.0 + 0.5)
    let foregroundAlpha = Float(alphaByte) / 255.0
    let resultAlpha = foregroundAlpha + 1 * (1 - foregroundAlpha)
    func channel(_ fg: Int, _ bg: Int) -> Int {
      let f = Float(fg) / 255.0
      let b = Float(bg) / 255.0
      let value = ((f * foregroundAlpha) + ((b * 1) * (1 - foregroundAlpha))) / resultAlpha
      return min(255, max(0, Int(value * 255.0 + 0.5)))
    }
    return MaterialColour.argb(
      red: channel(MaterialColour.red(foreground), MaterialColour.red(background)),
      green: channel(MaterialColour.green(foreground), MaterialColour.green(background)),
      blue: channel(MaterialColour.blue(foreground), MaterialColour.blue(background)))
  }

  /// `ColorScheme.surfaceColorAtElevation(6.dp)`: the surface tint over the surface at
  /// alpha (4.5 * ln(7) + 2) / 100.
  static func surfaceColorAtElevation6(tint: UInt32, surface: UInt32) -> UInt32 {
    let alpha = ((Float(4.5) * logf(Float(6 + 1))) + 2) / 100
    return composite(tint, alpha: alpha, over: surface)
  }
}
