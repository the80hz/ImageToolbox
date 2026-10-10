// Port of androidx.palette (Palette, Target), which the Android app uses to pick the seed
// colour of a Material You scheme and for its "colours of the image" list.
// Copyright 2014 The Android Open Source Project. Licensed under the Apache License,
// Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// The dominant and the six profile colours of an image, as `androidx.palette.graphics.Palette`
/// finds them: a median-cut quantizer over a downscaled copy, then a weighted pick per target.
public struct AndroidPalette: Sendable {

  /// A colour of the image and how many of the sampled pixels it represents.
  public struct Swatch: Sendable, Equatable {
    public let colour: RGBA
    public let population: Int
  }

  /// Every quantized colour, in the order the quantizer produced them.
  public let swatches: [Swatch]
  /// The swatch with the most pixels.
  public let dominant: Swatch?
  public let vibrant: Swatch?
  public let lightVibrant: Swatch?
  public let darkVibrant: Swatch?
  public let muted: Swatch?
  public let lightMuted: Swatch?
  public let darkMuted: Swatch?

  /// The sampling area `Palette.Builder` resizes to by default (112 x 112).
  public static let resizeArea = 112 * 112
  /// The number of colours `Palette.Builder` quantizes to by default.
  public static let defaultColourCount = 16

  /// Palette of an image. Large images are sampled down to `resizeArea` pixels first.
  public static func generate(
    from raster: RasterImage, maximumColours: Int = defaultColourCount
  ) -> AndroidPalette {
    generate(
      pixels: MaterialSeedColour.sampledPixels(raster, area: resizeArea),
      maximumColours: maximumColours)
  }

  /// Palette of a list of pixels, used as given. Alpha is ignored, as in `Palette`.
  public static func generate(
    from pixels: [RGBA], maximumColours: Int = defaultColourCount
  ) -> AndroidPalette {
    generate(pixels: pixels.map(MaterialColour.argb), maximumColours: maximumColours)
  }

  /// The seed colour the Android app derives from an image (`Bitmap.extractPrimaryColor`): the
  /// dominant colour, blended halfway toward the vibrant one.
  ///
  /// Without a vibrant swatch Android blends toward 0 (transparent black), so the result is the
  /// dominant colour at half brightness; this is kept so both apps agree. With no swatch at all
  /// the result is black. Alpha is always 255.
  public func seedColour(blendWithVibrant: Bool = true) -> RGBA {
    guard let dominant else { return RGBA(red: 0, green: 0, blue: 0) }
    guard blendWithVibrant else { return dominant.colour }
    let other: UInt32 = vibrant.map { MaterialColour.argb($0.colour) } ?? 0
    let blended = AndroidColour.blend(MaterialColour.argb(dominant.colour), other, 0.5)
    return MaterialColour.rgba(blended)
  }

  // MARK: Generation

  private static func generate(pixels: [UInt32], maximumColours: Int) -> AndroidPalette {
    let quantizer = AndroidPaletteQuantizer(pixels: pixels, maxColours: max(1, maximumColours))
    let data = quantizer.quantized
    let dominantData = data.reduce(nil as PaletteSwatchData?) { best, next in
      guard let best else { return next }
      return next.population > best.population ? next : best
    }
    let maxPopulation = dominantData?.population ?? 1

    var used = Set<UInt32>()
    var selected: [Int: PaletteSwatchData] = [:]
    for (index, target) in Target.defaults.enumerated() {
      if let pick = bestSwatch(data, target: target, used: used, maxPopulation: maxPopulation) {
        used.insert(pick.rgb)
        selected[index] = pick
      }
    }
    func swatch(_ data: PaletteSwatchData?) -> Swatch? {
      data.map { Swatch(colour: MaterialColour.rgba($0.rgb), population: $0.population) }
    }
    return AndroidPalette(
      swatches: data.compactMap(swatch), dominant: swatch(dominantData),
      vibrant: swatch(selected[1]), lightVibrant: swatch(selected[0]),
      darkVibrant: swatch(selected[2]), muted: swatch(selected[4]),
      lightMuted: swatch(selected[3]), darkMuted: swatch(selected[5]))
  }

  private static func bestSwatch(
    _ swatches: [PaletteSwatchData], target: Target, used: Set<UInt32>, maxPopulation: Int
  ) -> PaletteSwatchData? {
    var bestScore: Float = 0
    var best: PaletteSwatchData?
    for swatch in swatches {
      let (_, s, l) = swatch.hsl
      guard s >= target.minSaturation, s <= target.maxSaturation, l >= target.minLightness,
        l <= target.maxLightness, !used.contains(swatch.rgb)
      else { continue }
      var score: Float = 0
      if target.saturationWeight > 0 {
        score += target.saturationWeight * (1 - abs(s - target.targetSaturation))
      }
      if target.lightnessWeight > 0 {
        score += target.lightnessWeight * (1 - abs(l - target.targetLightness))
      }
      if target.populationWeight > 0 {
        score += target.populationWeight * (Float(swatch.population) / Float(maxPopulation))
      }
      if best == nil || score > bestScore {
        best = swatch
        bestScore = score
      }
    }
    return best
  }

  /// A kind of colour to look for: saturation and lightness ranges and how much each counts.
  private struct Target {
    var minSaturation: Float = 0
    var targetSaturation: Float = 0.5
    var maxSaturation: Float = 1
    var minLightness: Float = 0
    var targetLightness: Float = 0.5
    var maxLightness: Float = 1

    // Weights are normalised to sum to 1 when the target is built.
    var saturationWeight: Float = 0.24
    var lightnessWeight: Float = 0.52
    var populationWeight: Float = 0.24

    static let targetDarkLuma: Float = 0.26
    static let maxDarkLuma: Float = 0.45
    static let minLightLuma: Float = 0.55
    static let targetLightLuma: Float = 0.74
    static let minNormalLuma: Float = 0.3
    static let targetNormalLuma: Float = 0.5
    static let maxNormalLuma: Float = 0.7
    static let targetMutedSaturation: Float = 0.3
    static let maxMutedSaturation: Float = 0.4
    static let targetVibrantSaturation: Float = 1
    static let minVibrantSaturation: Float = 0.35

    enum Lightness { case light, normal, dark }
    enum Saturation { case vibrant, muted }

    init(_ lightness: Lightness, _ saturation: Saturation) {
      switch lightness {
      case .light:
        minLightness = Self.minLightLuma
        targetLightness = Self.targetLightLuma
      case .normal:
        minLightness = Self.minNormalLuma
        targetLightness = Self.targetNormalLuma
        maxLightness = Self.maxNormalLuma
      case .dark:
        targetLightness = Self.targetDarkLuma
        maxLightness = Self.maxDarkLuma
      }
      switch saturation {
      case .vibrant:
        minSaturation = Self.minVibrantSaturation
        targetSaturation = Self.targetVibrantSaturation
      case .muted:
        targetSaturation = Self.targetMutedSaturation
        maxSaturation = Self.maxMutedSaturation
      }
      let sum = saturationWeight + lightnessWeight + populationWeight
      saturationWeight /= sum
      lightnessWeight /= sum
      populationWeight /= sum
    }

    /// Light vibrant, vibrant, dark vibrant, light muted, muted, dark muted: the order the
    /// builder scores them in, which matters because each pick is removed for the next.
    static let defaults: [Target] = [
      Target(.light, .vibrant), Target(.normal, .vibrant), Target(.dark, .vibrant),
      Target(.light, .muted), Target(.normal, .muted), Target(.dark, .muted),
    ]
  }
}
