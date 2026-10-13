// Seed colour of an image for a Material scheme. The Score path ports Material Color Utilities
// (Copyright 2021 Google LLC, Apache License 2.0, https://www.apache.org/licenses/LICENSE-2.0).

import Foundation

/// How the seed colour of a Material scheme is picked from an image.
public enum MaterialSeedMethod: String, CaseIterable, Sendable {
  /// What the Android app does: `androidx.palette` dominant colour blended halfway toward its
  /// vibrant colour.
  case androidPalette
  /// Material Color Utilities: Celebi quantizer, then `Score`. Picks the most attractive
  /// colour rather than the most common one.
  case score
}

/// Finds the colour that best represents an image as the source of a theme.
public enum MaterialSeedColour {

  /// The colour for an image, sampled down first so large images stay fast.
  public static func extract(
    from raster: RasterImage, method: MaterialSeedMethod = .androidPalette
  ) -> RGBA {
    switch method {
    case .androidPalette:
      return AndroidPalette.generate(from: raster).seedColour()
    case .score:
      return ranked(from: raster, count: 1).first ?? fallback
    }
  }

  /// The colour for a list of pixels, used as given.
  public static func extract(
    from pixels: [RGBA], method: MaterialSeedMethod = .androidPalette
  ) -> RGBA {
    switch method {
    case .androidPalette:
      return AndroidPalette.generate(from: pixels).seedColour()
    case .score:
      return ranked(from: pixels, count: 1).first ?? fallback
    }
  }

  /// Up to `count` candidate seed colours, best first, as different in hue as possible.
  /// An image with no colourful pixels gives the Google blue, `#4285F4`.
  public static func ranked(from raster: RasterImage, count: Int = 4) -> [RGBA] {
    rank(sampledPixels(raster, area: AndroidPalette.resizeArea, onlyOpaque: true), count: count)
  }

  /// Same as `ranked(from:count:)` for a list of pixels. Only fully opaque pixels count.
  public static func ranked(from pixels: [RGBA], count: Int = 4) -> [RGBA] {
    rank(pixels.filter { $0.alpha == 255 }.map(MaterialColour.argb), count: count)
  }

  static let fallback = MaterialColour.rgba(Score.fallback)

  private static func rank(_ pixels: [UInt32], count: Int) -> [RGBA] {
    guard count > 0 else { return [] }
    guard !pixels.isEmpty else { return [fallback] }
    let quantized = QuantizerCelebi.quantize(pixels, maxColors: 128)
    return Score.score(quantized, desired: count).map(MaterialColour.rgba)
  }

  /// A nearest-neighbour sample of the image of at most `area` pixels, as opaque ARGB.
  ///
  /// With `onlyOpaque`, pixels that are not fully opaque are skipped; if that leaves nothing,
  /// every visible pixel is used with its colour restored from premultiplied alpha.
  static func sampledPixels(_ raster: RasterImage, area: Int, onlyOpaque: Bool = false) -> [UInt32]
  {
    let width = raster.width
    let height = raster.height
    guard width > 0, height > 0 else { return [] }
    var targetWidth = width
    var targetHeight = height
    if width * height > area {
      let ratio = (Double(area) / Double(width * height)).squareRoot()
      targetWidth = max(1, Int((Double(width) * ratio).rounded(.up)))
      targetHeight = max(1, Int((Double(height) * ratio).rounded(.up)))
    }
    func collect(minimumAlpha: UInt8) -> [UInt32] {
      var result: [UInt32] = []
      result.reserveCapacity(targetWidth * targetHeight)
      for y in 0..<targetHeight {
        let sourceY = min(
          height - 1, Int((Double(y) + 0.5) * Double(height) / Double(targetHeight)))
        for x in 0..<targetWidth {
          let sourceX = min(
            width - 1, Int((Double(x) + 0.5) * Double(width) / Double(targetWidth)))
          let pixel = raster.pixel(x: sourceX, y: sourceY)
          if pixel.alpha < minimumAlpha { continue }
          result.append(MaterialColour.argb(pixel))
        }
      }
      return result
    }
    guard onlyOpaque else { return collect(minimumAlpha: 0) }
    let opaque = collect(minimumAlpha: 255)
    return opaque.isEmpty ? collect(minimumAlpha: 1) : opaque
  }
}
