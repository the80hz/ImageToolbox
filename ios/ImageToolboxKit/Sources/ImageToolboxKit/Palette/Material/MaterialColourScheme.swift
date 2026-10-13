// Material 3 colour scheme for a seed colour, built on a Swift port of Material Color Utilities
// (Copyright 2021 Google LLC, Apache License 2.0, https://www.apache.org/licenses/LICENSE-2.0).

import Foundation

/// A Material 3 ("Material You") colour scheme: every role as a plain sRGB colour.
///
/// The roles match the Android app's Material You palette screen: the same nine styles, the
/// same contrast level, invert and AMOLED options, and the same adjustments to the error, on
/// and surface colours that the app's theme code applies on top of the standard scheme.
public struct MaterialColourScheme: Sendable, Equatable {

  /// What to build, besides the seed colour and light or dark.
  public struct Options: Sendable, Equatable {
    public var style: MaterialSchemeStyle
    /// -1 (lowest) to 1 (highest); 0 is the standard contrast.
    public var contrastLevel: Double
    /// Flips every role except the scrim (the "invert colours" switch).
    public var invertColours: Bool
    /// Dark scheme only: black background and surface, other roles darkened.
    public var amoled: Bool
    /// How `from(_ raster:)` and `from(pixels:)` pick the seed.
    public var seedMethod: MaterialSeedMethod
    /// Optional anchors for the tonal-spot style, like the extra colours of the Android
    /// `ColorTuple`. Other styles only use `surface` and `error`.
    public var secondary: RGBA?
    public var tertiary: RGBA?
    public var surface: RGBA?
    public var neutralVariant: RGBA?
    public var error: RGBA?

    public init(
      style: MaterialSchemeStyle = .tonalSpot, contrastLevel: Double = 0,
      invertColours: Bool = false, amoled: Bool = false,
      seedMethod: MaterialSeedMethod = .androidPalette,
      secondary: RGBA? = nil, tertiary: RGBA? = nil, surface: RGBA? = nil,
      neutralVariant: RGBA? = nil, error: RGBA? = nil
    ) {
      self.style = style
      self.contrastLevel = min(max(contrastLevel, -1), 1)
      self.invertColours = invertColours
      self.amoled = amoled
      self.seedMethod = seedMethod
      self.secondary = secondary
      self.tertiary = tertiary
      self.surface = surface
      self.neutralVariant = neutralVariant
      self.error = error
    }
  }

  /// The colour the scheme was built from. Opaque.
  public let seed: RGBA
  public let isDark: Bool
  public let options: Options
  private let colours: [MaterialColourRole: RGBA]

  /// The colour of a role. Always opaque.
  public subscript(_ role: MaterialColourRole) -> RGBA {
    colours[role] ?? RGBA(red: 0, green: 0, blue: 0)
  }

  /// Every role with its colour.
  public var allColours: [MaterialColourRole: RGBA] { colours }

  /// A scheme for a seed colour. Alpha of the seed is ignored.
  public static func from(
    seedRGB: RGBA, dark: Bool = false, options: Options = Options()
  ) -> MaterialColourScheme {
    let seed = RGBA(red: seedRGB.red, green: seedRGB.green, blue: seedRGB.blue)
    let roles = MaterialSchemeBuilder.build(seed: seed, isDark: dark, options: options)
    return MaterialColourScheme(
      seed: seed, isDark: dark, options: options,
      colours: roles.mapValues { MaterialColour.rgba($0) })
  }

  /// A scheme for the seed colour found in an image, by `options.seedMethod`.
  public static func from(
    _ raster: RasterImage, dark: Bool = false, options: Options = Options()
  ) -> MaterialColourScheme {
    let seed = MaterialSeedColour.extract(from: raster, method: options.seedMethod)
    return from(seedRGB: seed, dark: dark, options: options)
  }

  /// A scheme for the seed colour found in a list of pixels. The list is used as given, so
  /// downscale large images first; `from(_ raster:)` does that itself.
  public static func from(
    pixels: [RGBA], dark: Bool = false, options: Options = Options()
  ) -> MaterialColourScheme {
    let seed = MaterialSeedColour.extract(from: pixels, method: options.seedMethod)
    return from(seedRGB: seed, dark: dark, options: options)
  }

  /// Kotlin source for a Compose `ColorScheme` of this scheme, as the Android "Copy as Compose
  /// code" button writes it. `name` defaults to `lightColorScheme` or `darkColorScheme`.
  public func composeCode(name: String? = nil) -> String {
    let name = name ?? (isDark ? "darkColorScheme" : "lightColorScheme")
    var lines = ["val \(name) = ColorScheme("]
    for role in MaterialColourRole.composeCodeOrder {
      let colour = self[role]
      let hex = String(format: "%02x%02x%02x", colour.red, colour.green, colour.blue)
      lines.append("    \(role.rawValue) = Color(0xff\(hex)),")
    }
    lines.append(")")
    return lines.joined(separator: "\n")
  }

  /// The light and the dark Compose code for the same seed and options, separated by a blank
  /// line, like the Android button.
  public static func composeCode(
    seedRGB: RGBA, options: Options = Options()
  ) -> String {
    let light = from(seedRGB: seedRGB, dark: false, options: options).composeCode()
    let dark = from(seedRGB: seedRGB, dark: true, options: options).composeCode()
    return light + "\n\n" + dark
  }
}
