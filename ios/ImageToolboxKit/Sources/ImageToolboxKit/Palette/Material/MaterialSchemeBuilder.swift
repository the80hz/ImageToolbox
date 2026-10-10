// Builds the colour scheme the way the Android app's `getColorScheme` does, on top of a port of
// Material Color Utilities (Copyright 2021 Google LLC, Apache License 2.0,
// https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Android `DynamicTheme.kt` post-processing, role by role, on opaque ARGB colours.
enum MaterialSchemeBuilder {
  typealias Roles = [MaterialColourRole: UInt32]

  /// All roles for a seed colour and options, after the same adjustments the Android app makes.
  static func build(
    seed: RGBA, isDark: Bool, options: MaterialColourScheme.Options
  ) -> Roles {
    let source = Hct(seed)
    let scheme = dynamicScheme(source: source, isDark: isDark, options: options)
    var roles = Roles()
    for role in MaterialColourRole.allCases { roles[role] = role.definition.argb(scheme) }

    applyDynamicError(&roles, options: options, isDark: isDark)
    applyExpressiveOn(&roles, isDark: isDark)
    if !isDark { applyContrastingSurfaces(&roles, surfaceSeed: options.surface) }
    if options.amoled && isDark { applyAmoled(&roles) }
    if options.invertColours { applyInvert(&roles) }
    applyFinal(&roles)
    return roles
  }

  // MARK: Scheme

  private static func dynamicScheme(
    source: Hct, isDark: Bool, options: MaterialColourScheme.Options
  ) -> DynamicScheme {
    guard options.style == .tonalSpot else {
      return DynamicScheme(
        style: options.style, source: source, isDark: isDark,
        contrastLevel: options.contrastLevel)
    }
    // Tonal spot keeps the seed's own chroma in the primary palette and lets the tuple override
    // the other palettes, unlike the stock scheme with its fixed chroma of 36.
    let hue = source.hue
    let chroma = source.chroma
    func palette(_ override: RGBA?, hue: Double, chroma: Double) -> TonalPalette {
      override.map { TonalPalette($0) } ?? TonalPalette(hue: hue, chroma: chroma)
    }
    let primary = TonalPalette(source)
    let secondary = palette(
      options.secondary, hue: hue, chroma: MaterialColour.clamp(chroma / 3.0, 14.0, 28.0))
    let tertiary = palette(
      options.tertiary, hue: MaterialColour.sanitizeDegrees(hue + 60.0),
      chroma: MaterialColour.clamp(chroma / 2.0, 20.0, 42.0))
    let neutral = palette(options.surface, hue: hue, chroma: min(chroma / 12.0, 4.0))
    // Android derives a tone-90 palette from the neutral one and uses it as the default variant.
    let variantDefault = TonalPalette(argb: neutral.argb(tone: 90))
    let neutralVariant = options.neutralVariant.map { TonalPalette($0) } ?? variantDefault
    let error = options.error.map { TonalPalette($0) } ?? TonalPalette(hue: 25.0, chroma: 84.0)
    return DynamicScheme(
      sourceColor: source, variant: .tonalSpot, isDark: isDark,
      contrastLevel: options.contrastLevel, primary: primary, secondary: secondary,
      tertiary: tertiary, neutral: neutral, neutralVariant: neutralVariant, error: error)
  }

  // MARK: Error colours

  private static func errorChroma(_ style: MaterialSchemeStyle) -> Double {
    switch style {
    case .neutral: return 56.0
    case .tonalSpot: return 72.0
    case .expressive: return 76.0
    case .vibrant: return 80.0
    default: return 72.0
    }
  }

  private static func errorHue(of hue: Double) -> Double {
    let breakpoints: [Double] = [0, 3, 13, 23, 33, 43, 153, 273, 360]
    let hues: [Double] = [12, 22, 32, 12, 22, 32, 22, 12]
    let last = breakpoints.lastIndex { hue >= $0 } ?? 0
    return hues[min(last, hues.count - 1)]
  }

  /// Error colours whose hue follows the seed and are pulled 15% toward the primary roles.
  private static func applyDynamicError(
    _ roles: inout Roles, options: MaterialColourScheme.Options, isDark: Bool
  ) {
    let hue =
      options.error.map { Hct($0).hue }
      ?? errorHue(of: Hct(argb: roles[.primary] ?? 0).hue)
    let palette = TonalPalette(hue: hue, chroma: errorChroma(options.style))
    let blend = Double(Float(0.15))
    roles[.error] = AndroidColour.cam16Blend(
      palette.argb(tone: isDark ? 70 : 30), roles[.primary] ?? 0, blend)
    roles[.onError] = palette.argb(tone: isDark ? 22 : 84)
    roles[.errorContainer] = AndroidColour.cam16Blend(
      palette.argb(tone: isDark ? 30 : 78), roles[.primaryContainer] ?? 0, blend)
    roles[.onErrorContainer] = palette.argb(tone: isDark ? 84 : 22)
  }

  // MARK: On colours

  /// On colours taken from the colour's own palette, at the first tone that reads well on it.
  private static func applyExpressiveOn(_ roles: inout Roles, isDark: Bool) {
    let tones: [Double] =
      isDark ? [22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10] : [96, 97, 98]
    let pairs: [(MaterialColourRole, MaterialColourRole)] = [
      (.primary, .onPrimary), (.secondary, .onSecondary), (.tertiary, .onTertiary),
    ]
    for (background, foreground) in pairs {
      guard let base = roles[background] else { continue }
      let palette = TonalPalette(argb: base)
      for tone in tones {
        let candidate = palette.argb(tone: tone)
        if AndroidColour.contrast(foreground: candidate, background: base) >= 4.5 {
          roles[foreground] = candidate
          break
        }
      }
    }
  }

  // MARK: Surfaces

  /// Light themes: tinted surfaces that follow the neutral hue with a bit more chroma.
  private static func applyContrastingSurfaces(_ roles: inout Roles, surfaceSeed: RGBA?) {
    let seed = surfaceSeed.map { Hct($0) } ?? Hct(argb: roles[.surface] ?? 0)
    func surface(_ tone: Double, _ multiplier: Double = 1.0) -> UInt32 {
      let chroma = min(seed.chroma * multiplier, 12.0)
      return TonalPalette(hue: seed.hue, chroma: chroma).argb(tone: tone)
    }
    roles[.surface] = surface(97)
    roles[.surfaceBright] = surface(99)
    roles[.surfaceDim] = surface(82, 1.8)
    roles[.surfaceContainerLowest] = surface(100)
    roles[.surfaceContainerLow] = surface(94, 1.2)
    roles[.surfaceContainer] = surface(91, 1.4)
    roles[.surfaceContainerHigh] = surface(88, 1.6)
    roles[.surfaceContainerHighest] = surface(85, 1.8)
    roles[.surfaceVariant] = surface(85, 1.8)
  }

  // MARK: AMOLED and invert

  private static let amoledFractions: [(MaterialColourRole, Float)] = {
    var list: [(MaterialColourRole, Float)] = []
    let on: Set<MaterialColourRole> = [
      .onPrimary, .onPrimaryContainer, .onSecondary, .onSecondaryContainer, .onTertiary,
      .onTertiaryContainer, .onBackground, .onSurface, .onSurfaceVariant, .inverseOnSurface,
      .onError, .onErrorContainer, .onPrimaryFixed, .onPrimaryFixedVariant, .onSecondaryFixed,
      .onSecondaryFixedVariant, .onTertiaryFixed, .onTertiaryFixedVariant,
    ]
    let accent: Set<MaterialColourRole> = [
      .primary, .primaryContainer, .inversePrimary, .secondary, .secondaryContainer, .tertiary,
      .tertiaryContainer, .error, .errorContainer, .primaryFixed, .primaryFixedDim,
      .secondaryFixed, .secondaryFixedDim, .tertiaryFixed, .tertiaryFixedDim,
    ]
    let half: Set<MaterialColourRole> = [
      .inverseSurface, .scrim, .surfaceBright, .surfaceDim, .surfaceContainer,
      .surfaceContainerHigh, .surfaceContainerHighest, .surfaceContainerLow,
      .surfaceContainerLowest,
    ]
    for role in MaterialColourRole.allCases {
      if on.contains(role) {
        list.append((role, 0.1))
      } else if accent.contains(role) {
        list.append((role, 0.3))
      } else if half.contains(role) {
        list.append((role, 0.5))
      } else if role == .outline || role == .outlineVariant {
        list.append((role, 0.2))
      } else if role == .surfaceVariant {
        list.append((role, 0.1))
      }
    }
    return list
  }()

  /// Dark themes on OLED screens: black background and surface, other roles blended toward black.
  private static func applyAmoled(_ roles: inout Roles) {
    for (role, fraction) in amoledFractions {
      guard let colour = roles[role] else { continue }
      roles[role] = AndroidColour.blend(colour, 0xFF00_0000, fraction)
    }
    roles[.background] = 0xFF00_0000
    roles[.surface] = 0xFF00_0000
  }

  private static func applyInvert(_ roles: inout Roles) {
    for (role, colour) in roles where role != .scrim {
      roles[role] = colour ^ 0x00FF_FFFF
    }
  }

  /// The outline variant is a veil of the secondary container over the 6 dp elevated surface.
  private static func applyFinal(_ roles: inout Roles) {
    let surface = roles[.surface] ?? 0
    let elevated = AndroidColour.surfaceColorAtElevation6(
      tint: roles[.surfaceTint] ?? 0, surface: surface)
    roles[.outlineVariant] = AndroidColour.composite(
      roles[.onSecondaryContainer] ?? 0, alpha: 0.2, over: elevated)
    roles[.background] = surface
  }
}
