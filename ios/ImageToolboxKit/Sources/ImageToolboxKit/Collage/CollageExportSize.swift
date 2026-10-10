import Foundation

/// The size a collage is exported at, as the Android collage sizes its output. The aspect ratio is one of the numeric
/// presets of the Android app. The longer side of the output is the longer side of the largest picture times the
/// output scale from 0.1 to 1, at most 8192 pixels, and the pixel count stays within an iOS memory budget.
public enum CollageExportSize {

  /// An aspect ratio as the Android presets write it, such as 9 by 16.
  public struct Aspect: Hashable, Sendable {
    /// The width part of the ratio.
    public let width: Double
    /// The height part of the ratio.
    public let height: Double

    /// Makes a ratio. A part that is not a positive number becomes 1.
    public init(width: Double, height: Double) {
      self.width = width.isFinite && width > 0 ? width : 1
      self.height = height.isFinite && height > 0 ? height : 1
    }

    /// The width divided by the height.
    public var ratio: Double { width / height }

    /// The ratio as text, such as "9:16". Numbers are not translated.
    public var title: String {
      "\(Self.text(width)):\(Self.text(height))"
    }

    private static func text(_ value: Double) -> String {
      value.rounded() == value ? String(Int(value)) : String(value)
    }
  }

  /// The numeric aspect ratios of the Android app, in its order, without the free, original and custom entries.
  public static let aspects: [Aspect] = [
    Aspect(width: 1, height: 1),
    Aspect(width: 10, height: 16),
    Aspect(width: 9, height: 16),
    Aspect(width: 9, height: 18.5),
    Aspect(width: 9, height: 20),
    Aspect(width: 9, height: 21),
    Aspect(width: 1, height: 1.91),
    Aspect(width: 2, height: 3),
    Aspect(width: 1, height: 2),
    Aspect(width: 5, height: 3),
    Aspect(width: 5, height: 4),
    Aspect(width: 4, height: 3),
    Aspect(width: 21, height: 9),
    Aspect(width: 20, height: 9),
    Aspect(width: 18.5, height: 9),
    Aspect(width: 16, height: 9),
    Aspect(width: 16, height: 10),
    Aspect(width: 1.91, height: 1),
    Aspect(width: 3, height: 2),
    Aspect(width: 3, height: 4),
    Aspect(width: 4, height: 5),
    Aspect(width: 3, height: 5),
    Aspect(width: 2, height: 1),
  ]

  /// The square, the first preset and the Android default.
  public static let defaultAspect = Aspect(width: 1, height: 1)

  /// The output scales on offer, as the Android slider.
  public static let scales: ClosedRange<Double> = 0.1...1

  /// The output scale the Android app starts with.
  public static let defaultScale = 0.5

  /// The longer side of the design canvas that the layout is worked out on, in pixels. The spacing and margin are
  /// in these pixels, and an export scales them with the canvas.
  public static let designLongSide = 1080

  /// The longest side an export may have, as on Android.
  public static let maximumLongSide = 8192

  /// The most pixels an export may have. It keeps the memory of the picture within the limits of an iPhone.
  public static let maximumPixels = 32_000_000

  /// The width and height of a picture with `aspect` whose longer side is `longSide` pixels. The shorter side is
  /// rounded to the nearest pixel and is at least one pixel.
  public static func dimensions(aspect: Aspect, longSide: Int) -> (width: Int, height: Int) {
    let long = max(longSide, 1)
    let short = max(Int((Double(long) / max(aspect.ratio, 1 / aspect.ratio)).rounded()), 1)
    return aspect.ratio >= 1 ? (long, short) : (short, long)
  }

  /// The export size for pictures whose largest side is `sourceLongSide` pixels, at `scale` of that side. The scale
  /// is kept within `scales` and the size within `maximumLongSide` and `maximumPixels`.
  public static func exportDimensions(
    aspect: Aspect, sourceLongSide: Int, scale: Double
  ) -> (width: Int, height: Int) {
    let clampedScale =
      scale.isFinite ? min(max(scale, scales.lowerBound), scales.upperBound) : defaultScale
    let source = min(max(sourceLongSide, 1), maximumLongSide)
    let longSide = Double(source) * clampedScale
    var size = dimensions(aspect: aspect, longSide: Int(longSide.rounded()))
    let pixels = size.width * size.height
    if pixels > maximumPixels {
      // The pixel budget is spent evenly on both sides, so the longer side shrinks by the square root of the excess.
      let factor = (Double(maximumPixels) / Double(pixels)).squareRoot()
      size = dimensions(aspect: aspect, longSide: Int((longSide * factor).rounded(.down)))
    }
    return size
  }
}
