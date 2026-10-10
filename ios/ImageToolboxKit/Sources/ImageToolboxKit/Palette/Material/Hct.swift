// Port of Material Color Utilities (hct/hct, palettes/tonal_palette).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// A colour in the HCT space of Material 3: CAM16 hue and chroma with CIE L* as the tone.
///
/// Tone is perceptual lightness, so two colours with a tone difference of 50 or more always
/// have a contrast ratio of at least 4.5. Build one from an sRGB colour, or from the three
/// numbers: out-of-gamut chroma is reduced to the most the display can show at that hue and tone.
public struct Hct: Sendable, Hashable {
  /// Hue in degrees, 0..<360.
  public let hue: Double
  /// Colourfulness. About 0...120 for sRGB; the maximum depends on hue and tone.
  public let chroma: Double
  /// Lightness, 0 (black) to 100 (white).
  public let tone: Double
  let argb: UInt32

  /// Solves for the closest sRGB colour. The stored values are those of the solved colour.
  public init(hue: Double, chroma: Double, tone: Double) {
    self.init(argb: HctSolver.solve(hue: hue, chroma: chroma, lstar: tone))
  }

  /// HCT of an sRGB colour. Alpha is ignored.
  public init(_ colour: RGBA) {
    self.init(argb: MaterialColour.argb(colour))
  }

  init(argb: UInt32) {
    let cam = Cam16(argb: argb)
    self.hue = cam.hue
    self.chroma = cam.chroma
    self.tone = MaterialColour.lstar(fromARGB: argb)
    self.argb = argb
  }

  /// The sRGB colour, opaque.
  public var rgba: RGBA { MaterialColour.rgba(argb) }

  /// The same colour with another tone, keeping hue and chroma as far as the gamut allows.
  public func with(tone newTone: Double) -> Hct {
    Hct(hue: hue, chroma: chroma, tone: newTone)
  }
}

/// The 13 standard tones of one hue and chroma, and any tone in between.
///
/// A Material 3 scheme is built from six of these: primary, secondary, tertiary, neutral,
/// neutral variant and error.
public struct TonalPalette: Sendable, Equatable {
  public let hue: Double
  public let chroma: Double
  private let source: Hct?

  /// Palette of the given hue (degrees) and chroma.
  public init(hue: Double, chroma: Double) {
    self.hue = hue
    self.chroma = chroma
    self.source = nil
  }

  /// Palette that has the hue and chroma of a colour. Its key colour is that colour.
  public init(_ hct: Hct) {
    self.hue = hct.hue
    self.chroma = hct.chroma
    self.source = hct
  }

  public init(_ colour: RGBA) {
    self.init(Hct(colour))
  }

  init(argb: UInt32) {
    self.init(Hct(argb: argb))
  }

  /// The colour at a tone, 0...100.
  public func hct(tone: Double) -> Hct {
    Hct(hue: hue, chroma: chroma, tone: tone)
  }

  public func colour(tone: Double) -> RGBA {
    hct(tone: tone).rgba
  }

  func argb(tone: Double) -> UInt32 {
    HctSolver.solve(hue: hue, chroma: chroma, lstar: tone)
  }

  /// The tone that can show this chroma most closely, searched outwards from tone 50.
  public var keyColor: Hct {
    if let source { return source }
    var best = Hct(hue: hue, chroma: chroma, tone: 50.0)
    var smallestDelta = abs(best.chroma - chroma)
    for delta in 1..<50 {
      // Stop on a match after rounding, so 16.51 requested and 16.49 found counts as exact.
      if chroma.rounded() == best.chroma.rounded() { return best }
      let plus = Hct(hue: hue, chroma: chroma, tone: 50.0 + Double(delta))
      let plusDelta = abs(plus.chroma - chroma)
      if plusDelta < smallestDelta {
        smallestDelta = plusDelta
        best = plus
      }
      let minus = Hct(hue: hue, chroma: chroma, tone: 50.0 - Double(delta))
      let minusDelta = abs(minus.chroma - chroma)
      if minusDelta < smallestDelta {
        smallestDelta = minusDelta
        best = minus
      }
    }
    return best
  }
}
