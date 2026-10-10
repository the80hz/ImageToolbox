// Port of Material Color Utilities (dynamiccolor/dynamic_scheme and scheme/scheme_*).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// The nine palette styles of the Android app, each a Material Color Utilities scheme variant.
public enum MaterialSchemeStyle: String, CaseIterable, Sendable {
  case tonalSpot
  case neutral
  case vibrant
  case expressive
  case rainbow
  case fruitSalad
  case monochrome
  case fidelity
  case content
}

/// The six tonal palettes of one scheme, plus what the role tones need to know.
struct DynamicScheme: Sendable {
  let sourceColor: Hct
  let variant: MaterialSchemeStyle
  let isDark: Bool
  /// -1 (lowest) to 1 (highest); 0 is the standard contrast.
  let contrastLevel: Double
  let primaryPalette: TonalPalette
  let secondaryPalette: TonalPalette
  let tertiaryPalette: TonalPalette
  let neutralPalette: TonalPalette
  let neutralVariantPalette: TonalPalette
  let errorPalette: TonalPalette

  init(
    sourceColor: Hct, variant: MaterialSchemeStyle, isDark: Bool, contrastLevel: Double,
    primary: TonalPalette, secondary: TonalPalette, tertiary: TonalPalette,
    neutral: TonalPalette, neutralVariant: TonalPalette,
    error: TonalPalette = TonalPalette(hue: 25.0, chroma: 84.0)
  ) {
    self.sourceColor = sourceColor
    self.variant = variant
    self.isDark = isDark
    self.contrastLevel = contrastLevel
    self.primaryPalette = primary
    self.secondaryPalette = secondary
    self.tertiaryPalette = tertiary
    self.neutralPalette = neutral
    self.neutralVariantPalette = neutralVariant
    self.errorPalette = error
  }

  /// The standard scheme of a style for a source colour.
  init(style: MaterialSchemeStyle, source: Hct, isDark: Bool, contrastLevel: Double) {
    let hue = source.hue
    let chroma = source.chroma
    func palette(_ hue: Double, _ chroma: Double) -> TonalPalette {
      TonalPalette(hue: hue, chroma: chroma)
    }
    let primary: TonalPalette
    let secondary: TonalPalette
    let tertiary: TonalPalette
    let neutral: TonalPalette
    let neutralVariant: TonalPalette
    switch style {
    case .tonalSpot:
      primary = palette(hue, 36.0)
      secondary = palette(hue, 16.0)
      tertiary = palette(MaterialColour.sanitizeDegrees(hue + 60.0), 24.0)
      neutral = palette(hue, 6.0)
      neutralVariant = palette(hue, 8.0)
    case .neutral:
      primary = palette(hue, 12.0)
      secondary = palette(hue, 8.0)
      tertiary = palette(hue, 16.0)
      neutral = palette(hue, 2.0)
      neutralVariant = palette(hue, 2.0)
    case .vibrant:
      primary = palette(hue, 200.0)
      secondary = palette(
        Self.rotatedHue(
          source, hues: [0, 41, 61, 101, 131, 181, 251, 301, 360],
          rotations: [18, 15, 10, 12, 15, 18, 15, 12, 12]), 24.0)
      tertiary = palette(
        Self.rotatedHue(
          source, hues: [0, 41, 61, 101, 131, 181, 251, 301, 360],
          rotations: [35, 30, 20, 25, 30, 35, 30, 25, 25]), 32.0)
      neutral = palette(hue, 10.0)
      neutralVariant = palette(hue, 12.0)
    case .expressive:
      primary = palette(MaterialColour.sanitizeDegrees(hue + 240.0), 40.0)
      secondary = palette(
        Self.rotatedHue(
          source, hues: [0, 21, 51, 121, 151, 191, 271, 321, 360],
          rotations: [45, 95, 45, 20, 45, 90, 45, 45, 45]), 24.0)
      tertiary = palette(
        Self.rotatedHue(
          source, hues: [0, 21, 51, 121, 151, 191, 271, 321, 360],
          rotations: [120, 120, 20, 45, 20, 15, 20, 120, 120]), 32.0)
      neutral = palette(hue + 15.0, 8.0)
      neutralVariant = palette(hue + 15.0, 12.0)
    case .rainbow:
      primary = palette(hue, 48.0)
      secondary = palette(hue, 16.0)
      tertiary = palette(MaterialColour.sanitizeDegrees(hue + 60.0), 24.0)
      neutral = palette(hue, 0.0)
      neutralVariant = palette(hue, 0.0)
    case .fruitSalad:
      primary = palette(MaterialColour.sanitizeDegrees(hue - 50.0), 48.0)
      secondary = palette(MaterialColour.sanitizeDegrees(hue - 50.0), 36.0)
      tertiary = palette(hue, 36.0)
      neutral = palette(hue, 10.0)
      neutralVariant = palette(hue, 16.0)
    case .monochrome:
      primary = palette(hue, 0.0)
      secondary = palette(hue, 0.0)
      tertiary = palette(hue, 0.0)
      neutral = palette(hue, 0.0)
      neutralVariant = palette(hue, 0.0)
    case .fidelity:
      primary = palette(hue, chroma)
      secondary = palette(hue, max(chroma - 32.0, chroma * 0.5))
      tertiary = TonalPalette(
        DislikeAnalyzer.fixIfDisliked(TemperatureCache(source).complement))
      neutral = palette(hue, chroma / 8.0)
      neutralVariant = palette(hue, chroma / 8.0 + 4.0)
    case .content:
      primary = palette(hue, chroma)
      secondary = palette(hue, max(chroma - 32.0, chroma * 0.5))
      tertiary = TonalPalette(
        DislikeAnalyzer.fixIfDisliked(
          TemperatureCache(source).analogous(count: 3, divisions: 6)[2]))
      neutral = palette(hue, chroma / 8.0)
      neutralVariant = palette(hue, chroma / 8.0 + 4.0)
    }
    self.init(
      sourceColor: source, variant: style, isDark: isDark, contrastLevel: contrastLevel,
      primary: primary, secondary: secondary, tertiary: tertiary, neutral: neutral,
      neutralVariant: neutralVariant)
  }

  /// Rotates the source hue by the entry of `rotations` for the band of `hues` it falls in.
  static func rotatedHue(_ source: Hct, hues: [Double], rotations: [Double]) -> Double {
    let sourceHue = source.hue
    if rotations.count == 1 {
      return MaterialColour.sanitizeDegrees(sourceHue + rotations[0])
    }
    for index in 0..<(hues.count - 1) where hues[index] < sourceHue && sourceHue < hues[index + 1] {
      return MaterialColour.sanitizeDegrees(sourceHue + rotations[index])
    }
    // Not in any band, which only happens exactly on a band edge.
    return sourceHue
  }

  /// The ARGB colour of a role in this scheme.
  func argb(_ role: DynamicColor) -> UInt32 {
    role.argb(self)
  }
}
