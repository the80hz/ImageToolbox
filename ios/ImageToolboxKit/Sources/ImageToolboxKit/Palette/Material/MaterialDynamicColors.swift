// Port of Material Color Utilities (dynamiccolor/material_dynamic_colors, 2021 spec).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// The role definitions of the Material 3 colour scheme: surfaces, primary and error.
/// Secondary, tertiary and the fixed roles are in `MaterialDynamicColors+Accents.swift`.
enum MaterialDynamicColors {

  // MARK: Helpers

  static func isFidelity(_ scheme: DynamicScheme) -> Bool {
    scheme.variant == .fidelity || scheme.variant == .content
  }

  static func isMonochrome(_ scheme: DynamicScheme) -> Bool {
    scheme.variant == .monochrome
  }

  /// The surface the others are compared with: the dimmest in light, the brightest in dark.
  static func highestSurface(_ scheme: DynamicScheme) -> DynamicColor {
    scheme.isDark ? surfaceBright : surfaceDim
  }

  /// Walks to the chroma the palette can show nearest to `chroma`, moving the tone away from
  /// the start in one direction.
  static func findDesiredChromaByTone(
    hue: Double, chroma: Double, tone: Double, byDecreasingTone: Bool
  ) -> Double {
    var answer = tone
    var closest = Hct(hue: hue, chroma: chroma, tone: tone)
    if closest.chroma < chroma {
      var chromaPeak = closest.chroma
      while closest.chroma < chroma {
        answer += byDecreasingTone ? -1.0 : 1.0
        let candidate = Hct(hue: hue, chroma: chroma, tone: answer)
        if chromaPeak > candidate.chroma { break }
        if abs(candidate.chroma - chroma) < 0.4 { break }
        if abs(candidate.chroma - chroma) < abs(closest.chroma - chroma) {
          closest = candidate
        }
        chromaPeak = max(chromaPeak, candidate.chroma)
      }
    }
    return answer
  }

  // MARK: Surfaces

  static let background = DynamicColor(
    name: "background", palette: \.neutralPalette,
    tone: { $0.isDark ? 6 : 98 }, isBackground: true)

  static let onBackground = DynamicColor(
    name: "on_background", palette: \.neutralPalette,
    tone: { $0.isDark ? 90 : 10 }, background: { _ in background },
    contrastCurve: ContrastCurve(3, 3, 4.5, 7))

  static let surface = DynamicColor(
    name: "surface", palette: \.neutralPalette,
    tone: { $0.isDark ? 6 : 98 }, isBackground: true)

  static let surfaceDim = DynamicColor(
    name: "surface_dim", palette: \.neutralPalette,
    tone: { $0.isDark ? 6 : ContrastCurve(87, 87, 80, 75).value(at: $0.contrastLevel) },
    isBackground: true)

  static let surfaceBright = DynamicColor(
    name: "surface_bright", palette: \.neutralPalette,
    tone: { $0.isDark ? ContrastCurve(24, 24, 29, 34).value(at: $0.contrastLevel) : 98 },
    isBackground: true)

  static let surfaceContainerLowest = DynamicColor(
    name: "surface_container_lowest", palette: \.neutralPalette,
    tone: { $0.isDark ? ContrastCurve(4, 4, 2, 0).value(at: $0.contrastLevel) : 100 },
    isBackground: true)

  static let surfaceContainerLow = DynamicColor(
    name: "surface_container_low", palette: \.neutralPalette,
    tone: {
      $0.isDark
        ? ContrastCurve(10, 10, 11, 12).value(at: $0.contrastLevel)
        : ContrastCurve(96, 96, 96, 95).value(at: $0.contrastLevel)
    }, isBackground: true)

  static let surfaceContainer = DynamicColor(
    name: "surface_container", palette: \.neutralPalette,
    tone: {
      $0.isDark
        ? ContrastCurve(12, 12, 16, 20).value(at: $0.contrastLevel)
        : ContrastCurve(94, 94, 92, 90).value(at: $0.contrastLevel)
    }, isBackground: true)

  static let surfaceContainerHigh = DynamicColor(
    name: "surface_container_high", palette: \.neutralPalette,
    tone: {
      $0.isDark
        ? ContrastCurve(17, 17, 21, 25).value(at: $0.contrastLevel)
        : ContrastCurve(92, 92, 88, 85).value(at: $0.contrastLevel)
    }, isBackground: true)

  static let surfaceContainerHighest = DynamicColor(
    name: "surface_container_highest", palette: \.neutralPalette,
    tone: {
      $0.isDark
        ? ContrastCurve(22, 22, 26, 30).value(at: $0.contrastLevel)
        : ContrastCurve(90, 90, 84, 80).value(at: $0.contrastLevel)
    }, isBackground: true)

  static let onSurface = DynamicColor(
    name: "on_surface", palette: \.neutralPalette,
    tone: { $0.isDark ? 90 : 10 }, background: highestSurface,
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let surfaceVariant = DynamicColor(
    name: "surface_variant", palette: \.neutralVariantPalette,
    tone: { $0.isDark ? 30 : 90 }, isBackground: true)

  static let onSurfaceVariant = DynamicColor(
    name: "on_surface_variant", palette: \.neutralVariantPalette,
    tone: { $0.isDark ? 80 : 30 }, background: highestSurface,
    contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  static let inverseSurface = DynamicColor(
    name: "inverse_surface", palette: \.neutralPalette,
    tone: { $0.isDark ? 90 : 20 })

  static let inverseOnSurface = DynamicColor(
    name: "inverse_on_surface", palette: \.neutralPalette,
    tone: { $0.isDark ? 20 : 95 }, background: { _ in inverseSurface },
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let outline = DynamicColor(
    name: "outline", palette: \.neutralVariantPalette,
    tone: { $0.isDark ? 60 : 50 }, background: highestSurface,
    contrastCurve: ContrastCurve(1.5, 3, 4.5, 7))

  static let outlineVariant = DynamicColor(
    name: "outline_variant", palette: \.neutralVariantPalette,
    tone: { $0.isDark ? 30 : 80 }, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5))

  static let scrim = DynamicColor(
    name: "scrim", palette: \.neutralPalette, tone: { _ in 0 })

  static let surfaceTint = DynamicColor(
    name: "surface_tint", palette: \.primaryPalette,
    tone: { $0.isDark ? 80 : 40 }, isBackground: true)

  // MARK: Primary

  static let primary: DynamicColor = DynamicColor(
    name: "primary", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 100 : 0) : ($0.isDark ? 80 : 40) },
    isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(3, 4.5, 7, 7),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: primaryContainer, roleB: primary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onPrimary = DynamicColor(
    name: "on_primary", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 10 : 90) : ($0.isDark ? 20 : 100) },
    background: { _ in primary }, contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let primaryContainer: DynamicColor = DynamicColor(
    name: "primary_container", palette: \.primaryPalette,
    tone: {
      if isFidelity($0) { return $0.sourceColor.tone }
      if isMonochrome($0) { return $0.isDark ? 85 : 25 }
      return $0.isDark ? 30 : 90
    },
    isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: primaryContainer, roleB: primary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onPrimaryContainer = DynamicColor(
    name: "on_primary_container", palette: \.primaryPalette,
    tone: {
      if isFidelity($0) {
        return DynamicColor.foregroundTone(bgTone: primaryContainer.tone($0), ratio: 4.5)
      }
      if isMonochrome($0) { return $0.isDark ? 0 : 100 }
      return $0.isDark ? 90 : 30
    },
    background: { _ in primaryContainer }, contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  static let inversePrimary = DynamicColor(
    name: "inverse_primary", palette: \.primaryPalette,
    tone: { $0.isDark ? 40 : 80 }, background: { _ in inverseSurface },
    contrastCurve: ContrastCurve(3, 4.5, 7, 7))

  // MARK: Error

  static let error: DynamicColor = DynamicColor(
    name: "error", palette: \.errorPalette,
    tone: { $0.isDark ? 80 : 40 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(3, 4.5, 7, 7),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: errorContainer, roleB: error, delta: 10, polarity: .nearer, stayTogether: false)
    })

  static let onError = DynamicColor(
    name: "on_error", palette: \.errorPalette,
    tone: { $0.isDark ? 20 : 100 }, background: { _ in error },
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let errorContainer: DynamicColor = DynamicColor(
    name: "error_container", palette: \.errorPalette,
    tone: { $0.isDark ? 30 : 90 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: errorContainer, roleB: error, delta: 10, polarity: .nearer, stayTogether: false)
    })

  static let onErrorContainer = DynamicColor(
    name: "on_error_container", palette: \.errorPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 90 : 10) : ($0.isDark ? 90 : 30) },
    background: { _ in errorContainer }, contrastCurve: ContrastCurve(3, 4.5, 7, 11))
}
