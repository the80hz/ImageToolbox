// Port of Material Color Utilities (contrast, dynamiccolor/dynamic_color,
// dynamiccolor/contrast_curve, dynamiccolor/tone_delta_pair).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// WCAG-style contrast between tones (L*).
enum Contrast {
  static func ratio(ofTones a: Double, _ b: Double) -> Double {
    ratio(
      ofYs: MaterialColour.yFromLstar(MaterialColour.clamp(a, 0, 100)),
      MaterialColour.yFromLstar(MaterialColour.clamp(b, 0, 100)))
  }

  static func ratio(ofYs a: Double, _ b: Double) -> Double {
    (max(a, b) + 5.0) / (min(a, b) + 5.0)
  }

  /// The lightest-needed tone that is at least `ratio` lighter than `tone`, or -1.
  static func lighter(tone: Double, ratio: Double) -> Double {
    if tone < 0.0 || tone > 100.0 { return -1.0 }
    let darkY = MaterialColour.yFromLstar(tone)
    let lightY = ratio * (darkY + 5.0) - 5.0
    let real = Contrast.ratio(ofYs: lightY, darkY)
    if real < ratio && abs(real - ratio) > 0.04 { return -1.0 }
    // Round up by 0.4 so a rounded result still reaches the ratio.
    let value = MaterialColour.lstarFromY(lightY) + 0.4
    return value < 0 || value > 100 ? -1.0 : value
  }

  /// The darkest-needed tone that is at least `ratio` darker than `tone`, or -1.
  static func darker(tone: Double, ratio: Double) -> Double {
    if tone < 0.0 || tone > 100.0 { return -1.0 }
    let lightY = MaterialColour.yFromLstar(tone)
    let darkY = (lightY + 5.0) / ratio - 5.0
    let real = Contrast.ratio(ofYs: lightY, darkY)
    if real < ratio && abs(real - ratio) > 0.04 { return -1.0 }
    let value = MaterialColour.lstarFromY(darkY) - 0.4
    return value < 0 || value > 100 ? -1.0 : value
  }

  static func lighterUnsafe(tone: Double, ratio: Double) -> Double {
    let value = lighter(tone: tone, ratio: ratio)
    return value < 0 ? 100.0 : value
  }

  static func darkerUnsafe(tone: Double, ratio: Double) -> Double {
    let value = darker(tone: tone, ratio: ratio)
    return value < 0 ? 0.0 : value
  }
}

/// A contrast ratio that depends on the scheme's contrast level (-1 low, 0 standard, 0.5 medium,
/// 1 high).
struct ContrastCurve: Sendable {
  let low: Double
  let normal: Double
  let medium: Double
  let high: Double

  init(_ low: Double, _ normal: Double, _ medium: Double, _ high: Double) {
    self.low = low
    self.normal = normal
    self.medium = medium
    self.high = high
  }

  func value(at contrastLevel: Double) -> Double {
    if contrastLevel <= -1.0 { return low }
    if contrastLevel < 0.0 { return MaterialColour.lerp(low, normal, contrastLevel + 1.0) }
    if contrastLevel < 0.5 { return MaterialColour.lerp(normal, medium, contrastLevel / 0.5) }
    if contrastLevel < 1.0 {
      return MaterialColour.lerp(medium, high, (contrastLevel - 0.5) / 0.5)
    }
    return high
  }
}

/// How two paired roles must differ in tone.
enum TonePolarity: Sendable {
  case darker, lighter, nearer, farther
}

/// Two roles, such as primary and primary container, that must stay at least `delta` apart.
struct ToneDeltaPair: Sendable {
  let roleA: DynamicColor
  let roleB: DynamicColor
  let delta: Double
  let polarity: TonePolarity
  let stayTogether: Bool
}

/// A scheme role: a palette, a tone that depends on the scheme, and the contrast it must keep
/// against its background.
final class DynamicColor: Sendable {
  let name: String
  let palette: @Sendable (DynamicScheme) -> TonalPalette
  let tone: @Sendable (DynamicScheme) -> Double
  let isBackground: Bool
  let background: (@Sendable (DynamicScheme) -> DynamicColor)?
  let secondBackground: (@Sendable (DynamicScheme) -> DynamicColor)?
  let contrastCurve: ContrastCurve?
  let toneDeltaPair: (@Sendable (DynamicScheme) -> ToneDeltaPair)?

  init(
    name: String,
    palette: @escaping @Sendable (DynamicScheme) -> TonalPalette,
    tone: @escaping @Sendable (DynamicScheme) -> Double,
    isBackground: Bool = false,
    background: (@Sendable (DynamicScheme) -> DynamicColor)? = nil,
    secondBackground: (@Sendable (DynamicScheme) -> DynamicColor)? = nil,
    contrastCurve: ContrastCurve? = nil,
    toneDeltaPair: (@Sendable (DynamicScheme) -> ToneDeltaPair)? = nil
  ) {
    self.name = name
    self.palette = palette
    self.tone = tone
    self.isBackground = isBackground
    self.background = background
    self.secondBackground = secondBackground
    self.contrastCurve = contrastCurve
    self.toneDeltaPair = toneDeltaPair
  }

  func argb(_ scheme: DynamicScheme) -> UInt32 {
    palette(scheme).argb(tone: resolvedTone(scheme))
  }

  // MARK: Tone helpers

  static func tonePrefersLightForeground(_ tone: Double) -> Bool { tone.rounded() < 60.0 }

  /// The tone for a foreground that reaches `ratio` against `bgTone`, on the preferred side.
  static func foregroundTone(bgTone: Double, ratio: Double) -> Double {
    let lighterTone = Contrast.lighterUnsafe(tone: bgTone, ratio: ratio)
    let darkerTone = Contrast.darkerUnsafe(tone: bgTone, ratio: ratio)
    let lighterRatio = Contrast.ratio(ofTones: lighterTone, bgTone)
    let darkerRatio = Contrast.ratio(ofTones: darkerTone, bgTone)
    if tonePrefersLightForeground(bgTone) {
      // Both sides can fall just short when the ratio asked for is already very high.
      let negligible =
        abs(lighterRatio - darkerRatio) < 0.1 && lighterRatio < ratio && darkerRatio < ratio
      return lighterRatio >= ratio || lighterRatio >= darkerRatio || negligible
        ? lighterTone : darkerTone
    }
    return darkerRatio >= ratio || darkerRatio >= lighterRatio ? darkerTone : lighterTone
  }

  // MARK: Tone solving

  /// The tone after contrast adjustment for the scheme's contrast level.
  func resolvedTone(_ scheme: DynamicScheme) -> Double {
    if let pairProvider = toneDeltaPair {
      return pairTone(scheme, pair: pairProvider(scheme))
    }
    var answer = tone(scheme)
    guard let background, let curve = contrastCurve else { return answer }
    let backgroundColour = background(scheme)
    let bgTone = backgroundColour.resolvedTone(scheme)
    let desired = curve.value(at: scheme.contrastLevel)
    if Contrast.ratio(ofTones: bgTone, answer) < desired {
      answer = Self.foregroundTone(bgTone: bgTone, ratio: desired)
    }
    if scheme.contrastLevel < 0 {
      answer = Self.foregroundTone(bgTone: bgTone, ratio: desired)
    }
    if isBackground && answer >= 50 && answer < 60 {
      // Backgrounds in 50...59 look indecisive: jump to whichever side keeps the contrast.
      answer = Contrast.ratio(ofTones: 49, bgTone) >= desired ? 49 : 60
    }
    if let second = secondBackground {
      return adjustForTwoBackgrounds(
        answer: answer, desired: desired, bgTone1: bgTone,
        bgTone2: second(scheme).resolvedTone(scheme))
    }
    return answer
  }

  private func adjustForTwoBackgrounds(
    answer: Double, desired: Double, bgTone1: Double, bgTone2: Double
  ) -> Double {
    let upper = max(bgTone1, bgTone2)
    let lower = min(bgTone1, bgTone2)
    if Contrast.ratio(ofTones: upper, answer) >= desired
      && Contrast.ratio(ofTones: lower, answer) >= desired
    {
      return answer
    }
    let lightOption = Contrast.lighter(tone: upper, ratio: desired)
    let darkOption = Contrast.darker(tone: lower, ratio: desired)
    let prefersLight =
      Self.tonePrefersLightForeground(bgTone1) || Self.tonePrefersLightForeground(bgTone2)
    if prefersLight { return lightOption < 0 ? 100 : lightOption }
    if lightOption >= 0 && darkOption < 0 { return lightOption }
    if darkOption >= 0 && lightOption < 0 { return darkOption }
    return darkOption < 0 ? 0 : darkOption
  }

  private func pairTone(_ scheme: DynamicScheme, pair: ToneDeltaPair) -> Double {
    let roleA = pair.roleA
    let roleB = pair.roleB
    let delta = pair.delta
    let decreasing = scheme.contrastLevel < 0
    let bgTone = background?(scheme).resolvedTone(scheme) ?? 50
    let aIsNearer =
      pair.polarity == .nearer || (pair.polarity == .lighter && !scheme.isDark)
      || (pair.polarity == .darker && scheme.isDark)
    let nearer = aIsNearer ? roleA : roleB
    let farther = aIsNearer ? roleB : roleA
    let amNearer = name == nearer.name
    let expansion: Double = scheme.isDark ? 1 : -1

    let nContrast = nearer.contrastCurve?.value(at: scheme.contrastLevel) ?? 1
    let fContrast = farther.contrastCurve?.value(at: scheme.contrastLevel) ?? 1

    let nInitial = nearer.tone(scheme)
    var nTone =
      Contrast.ratio(ofTones: bgTone, nInitial) >= nContrast
      ? nInitial : Self.foregroundTone(bgTone: bgTone, ratio: nContrast)
    let fInitial = farther.tone(scheme)
    var fTone =
      Contrast.ratio(ofTones: bgTone, fInitial) >= fContrast
      ? fInitial : Self.foregroundTone(bgTone: bgTone, ratio: fContrast)

    if decreasing {
      // Lower contrast settles at the bare minimum that still passes.
      nTone = Self.foregroundTone(bgTone: bgTone, ratio: nContrast)
      fTone = Self.foregroundTone(bgTone: bgTone, ratio: fContrast)
    }

    if (fTone - nTone) * expansion < delta {
      // Expand the farther role first, then pull the nearer one back.
      fTone = MaterialColour.clamp(nTone + delta * expansion, 0, 100)
      if (fTone - nTone) * expansion < delta {
        nTone = MaterialColour.clamp(fTone - delta * expansion, 0, 100)
      }
    }

    // Keep both roles out of the 50...59 zone, where text contrast is ambiguous.
    if nTone >= 50 && nTone < 60 {
      if expansion > 0 {
        nTone = 60
        fTone = max(fTone, nTone + delta * expansion)
      } else {
        nTone = 49
        fTone = min(fTone, nTone + delta * expansion)
      }
    } else if fTone >= 50 && fTone < 60 {
      if pair.stayTogether {
        if expansion > 0 {
          nTone = 60
          fTone = max(fTone, nTone + delta * expansion)
        } else {
          nTone = 49
          fTone = min(fTone, nTone + delta * expansion)
        }
      } else {
        fTone = expansion > 0 ? 60 : 49
      }
    }
    return amNearer ? nTone : fTone
  }
}
