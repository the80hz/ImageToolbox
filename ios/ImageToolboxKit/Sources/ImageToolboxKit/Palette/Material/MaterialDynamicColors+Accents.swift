// Port of Material Color Utilities (dynamiccolor/material_dynamic_colors, 2021 spec).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Secondary, tertiary and the fixed roles.
extension MaterialDynamicColors {

  // MARK: Secondary

  static let secondary: DynamicColor = DynamicColor(
    name: "secondary", palette: \.secondaryPalette,
    tone: { $0.isDark ? 80 : 40 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(3, 4.5, 7, 7),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: secondaryContainer, roleB: secondary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onSecondary = DynamicColor(
    name: "on_secondary", palette: \.secondaryPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 10 : 100) : ($0.isDark ? 20 : 100) },
    background: { _ in secondary }, contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let secondaryContainer: DynamicColor = DynamicColor(
    name: "secondary_container", palette: \.secondaryPalette,
    tone: {
      let initialTone: Double = $0.isDark ? 30 : 90
      if isMonochrome($0) { return $0.isDark ? 30 : 85 }
      if !isFidelity($0) { return initialTone }
      return findDesiredChromaByTone(
        hue: $0.secondaryPalette.hue, chroma: $0.secondaryPalette.chroma, tone: initialTone,
        byDecreasingTone: !$0.isDark)
    },
    isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: secondaryContainer, roleB: secondary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onSecondaryContainer = DynamicColor(
    name: "on_secondary_container", palette: \.secondaryPalette,
    tone: {
      if isMonochrome($0) { return $0.isDark ? 90 : 10 }
      if !isFidelity($0) { return $0.isDark ? 90 : 30 }
      return DynamicColor.foregroundTone(bgTone: secondaryContainer.tone($0), ratio: 4.5)
    },
    background: { _ in secondaryContainer }, contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  // MARK: Tertiary

  static let tertiary: DynamicColor = DynamicColor(
    name: "tertiary", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 90 : 25) : ($0.isDark ? 80 : 40) },
    isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(3, 4.5, 7, 7),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: tertiaryContainer, roleB: tertiary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onTertiary = DynamicColor(
    name: "on_tertiary", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? ($0.isDark ? 10 : 90) : ($0.isDark ? 20 : 100) },
    background: { _ in tertiary }, contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let tertiaryContainer: DynamicColor = DynamicColor(
    name: "tertiary_container", palette: \.tertiaryPalette,
    tone: {
      if isMonochrome($0) { return $0.isDark ? 60 : 49 }
      if !isFidelity($0) { return $0.isDark ? 30 : 90 }
      let proposed = $0.tertiaryPalette.hct(tone: $0.sourceColor.tone)
      return DislikeAnalyzer.fixIfDisliked(proposed).tone
    },
    isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: tertiaryContainer, roleB: tertiary, delta: 10, polarity: .nearer,
        stayTogether: false)
    })

  static let onTertiaryContainer = DynamicColor(
    name: "on_tertiary_container", palette: \.tertiaryPalette,
    tone: {
      if isMonochrome($0) { return $0.isDark ? 0 : 100 }
      if !isFidelity($0) { return $0.isDark ? 90 : 30 }
      return DynamicColor.foregroundTone(bgTone: tertiaryContainer.tone($0), ratio: 4.5)
    },
    background: { _ in tertiaryContainer }, contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  // MARK: Fixed

  static let primaryFixed: DynamicColor = DynamicColor(
    name: "primary_fixed", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? 40 : 90 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: primaryFixed, roleB: primaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let primaryFixedDim: DynamicColor = DynamicColor(
    name: "primary_fixed_dim", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? 30 : 80 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: primaryFixed, roleB: primaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let onPrimaryFixed = DynamicColor(
    name: "on_primary_fixed", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? 100 : 10 },
    background: { _ in primaryFixedDim }, secondBackground: { _ in primaryFixed },
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let onPrimaryFixedVariant = DynamicColor(
    name: "on_primary_fixed_variant", palette: \.primaryPalette,
    tone: { isMonochrome($0) ? 90 : 30 },
    background: { _ in primaryFixedDim }, secondBackground: { _ in primaryFixed },
    contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  static let secondaryFixed: DynamicColor = DynamicColor(
    name: "secondary_fixed", palette: \.secondaryPalette,
    tone: { isMonochrome($0) ? 40 : 90 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: secondaryFixed, roleB: secondaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let secondaryFixedDim: DynamicColor = DynamicColor(
    name: "secondary_fixed_dim", palette: \.secondaryPalette,
    tone: { isMonochrome($0) ? 30 : 80 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: secondaryFixed, roleB: secondaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let onSecondaryFixed = DynamicColor(
    name: "on_secondary_fixed", palette: \.secondaryPalette,
    tone: { isMonochrome($0) ? 100 : 10 },
    background: { _ in secondaryFixedDim }, secondBackground: { _ in secondaryFixed },
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let onSecondaryFixedVariant = DynamicColor(
    name: "on_secondary_fixed_variant", palette: \.secondaryPalette,
    tone: { isMonochrome($0) ? 90 : 30 },
    background: { _ in secondaryFixedDim }, secondBackground: { _ in secondaryFixed },
    contrastCurve: ContrastCurve(3, 4.5, 7, 11))

  static let tertiaryFixed: DynamicColor = DynamicColor(
    name: "tertiary_fixed", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? 40 : 90 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: tertiaryFixed, roleB: tertiaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let tertiaryFixedDim: DynamicColor = DynamicColor(
    name: "tertiary_fixed_dim", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? 30 : 80 }, isBackground: true, background: highestSurface,
    contrastCurve: ContrastCurve(1, 1, 3, 4.5),
    toneDeltaPair: { _ in
      ToneDeltaPair(
        roleA: tertiaryFixed, roleB: tertiaryFixedDim, delta: 10, polarity: .lighter,
        stayTogether: true)
    })

  static let onTertiaryFixed = DynamicColor(
    name: "on_tertiary_fixed", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? 100 : 10 },
    background: { _ in tertiaryFixedDim }, secondBackground: { _ in tertiaryFixed },
    contrastCurve: ContrastCurve(4.5, 7, 11, 21))

  static let onTertiaryFixedVariant = DynamicColor(
    name: "on_tertiary_fixed_variant", palette: \.tertiaryPalette,
    tone: { isMonochrome($0) ? 90 : 30 },
    background: { _ in tertiaryFixedDim }, secondBackground: { _ in tertiaryFixed },
    contrastCurve: ContrastCurve(3, 4.5, 7, 11))
}
