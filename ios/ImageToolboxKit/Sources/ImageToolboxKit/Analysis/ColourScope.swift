import CoreGraphics
import Foundation

/// The two colour scopes of the curves editor, drawn as the Android app draws them.
public enum ColourScopeKind: CaseIterable, Sendable {
  /// Each column shows how often each red, green and blue level occurs. A level is coloured by the
  /// channels that come near the brightest one, so overlapping channels mix.
  case waveform
  /// Each pixel is placed by its chroma (Cb, Cr) and coloured by its hue. Grey pixels sit in the
  /// centre, and the circle and reference marks show where the primary colours fall.
  case vectorscope
}

/// Renders a colour scope into a bitmap. The data comes from the picture's own pixels. The Android
/// app reads the same kind of grid from its histogram module, which is not in this repository.
public enum ColourScopeRenderer {

  /// Cells across and levels up for the waveform, one per byte value.
  static let waveformColumns = 256
  static let waveformLevels = 256
  /// Cells per side of the vectorscope grid.
  static let vectorscopeCells = 384

  /// A density of 1...255 gets an opacity from this range, in six steps, as the Android app does.
  static let minimumAlpha: UInt8 = 46
  static let maximumAlpha: UInt8 = 224
  static let densityBuckets = 6
  static let neutralHueGroup = 18
  static let neutralThreshold = 16

  /// - Parameters:
  ///   - width: output width in pixels. The waveform keeps 256 columns across it.
  ///   - height: output height in pixels.
  public static func render(
    _ image: CGImage, scope: ColourScopeKind, width: Int, height: Int
  ) -> CGImage? {
    guard width > 0, height > 0, let raster = RasterImage(image) else { return nil }
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.setFillColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    switch scope {
    case .waveform:
      drawWaveform(raster, into: context, width: width, height: height)
    case .vectorscope:
      drawVectorscope(raster, into: context, width: width, height: height)
    }
    return context.makeImage()
  }

  // MARK: - Waveform

  private static func drawWaveform(
    _ raster: RasterImage, into context: CGContext, width: Int, height: Int
  ) {
    let straight = raster.straightRGBA()
    var counts = [Int](repeating: 0, count: waveformColumns * waveformLevels * 3)
    for y in 0..<raster.height {
      for x in 0..<raster.width {
        let index = (y * raster.width + x) * 4
        guard raster.pixels[index + 3] > 0 else { continue }
        let column = x * waveformColumns / raster.width
        for channel in 0..<3 {
          let level = Int(straight[index + channel])
          counts[((column * waveformLevels) + level) * 3 + channel] += 1
        }
      }
    }

    let peak = counts.max() ?? 0
    let cellWidth = Double(width) / Double(waveformColumns)
    let cellHeight = Double(height) / Double(waveformLevels)
    for column in 0..<waveformColumns {
      for level in 0..<waveformLevels {
        let base = (column * waveformLevels + level) * 3
        let red = counts[base]
        let green = counts[base + 1]
        let blue = counts[base + 2]
        let density = max(red, green, blue)
        guard let bucket = densityBucket(density, peak: peak) else { continue }

        let threshold = Double(density) * 0.55
        let colour = waveformColour(
          red: Double(red) >= threshold,
          green: Double(green) >= threshold,
          blue: Double(blue) >= threshold)
        // Level 255 is the top row of the image. The context origin is at the bottom.
        let rect = CGRect(
          x: Double(column) * cellWidth,
          y: Double(height) - Double(waveformLevels - level) * cellHeight,
          width: cellWidth, height: cellHeight)
        fill(rect, colour: colour, bucket: bucket, into: context)
      }
    }
  }

  /// The colour of the channels in the mask: each channel's colour, combined by the brightest value.
  private static func waveformColour(red: Bool, green: Bool, blue: Bool) -> (Int, Int, Int) {
    var colour = (0, 0, 0)
    if red { colour = (max(colour.0, 255), max(colour.1, 80), max(colour.2, 80)) }
    if green { colour = (max(colour.0, 80), max(colour.1, 255), max(colour.2, 80)) }
    if blue { colour = (max(colour.0, 90), max(colour.1, 140), max(colour.2, 255)) }
    if !red && !green && !blue { colour = (255, 255, 255) }
    return colour
  }

  // MARK: - Vectorscope

  private static func drawVectorscope(
    _ raster: RasterImage, into context: CGContext, width: Int, height: Int
  ) {
    let cells = vectorscopeCells
    let straight = raster.straightRGBA()
    var counts = [Int](repeating: 0, count: cells * cells)
    var sums = [Int](repeating: 0, count: cells * cells * 3)
    for y in 0..<raster.height {
      for x in 0..<raster.width {
        let index = (y * raster.width + x) * 4
        guard raster.pixels[index + 3] > 0 else { continue }
        let red = Double(straight[index]) / 255
        let green = Double(straight[index + 1]) / 255
        let blue = Double(straight[index + 2]) / 255
        let cb = -0.168736 * red - 0.331264 * green + 0.5 * blue
        let cr = 0.5 * red - 0.418688 * green - 0.081312 * blue
        let column = min(max(Int(((cb + 0.5) * Double(cells - 1)).rounded()), 0), cells - 1)
        let row = min(max(Int(((0.5 - cr) * Double(cells - 1)).rounded()), 0), cells - 1)
        let cell = row * cells + column
        counts[cell] += 1
        sums[cell * 3] += Int(straight[index])
        sums[cell * 3 + 1] += Int(straight[index + 1])
        sums[cell * 3 + 2] += Int(straight[index + 2])
      }
    }

    let peak = counts.max() ?? 0
    let cellWidth = Double(width) / Double(cells)
    let cellHeight = Double(height) / Double(cells)
    for cell in 0..<(cells * cells) where counts[cell] > 0 {
      let count = counts[cell]
      guard let bucket = densityBucket(count, peak: peak) else { continue }
      let average = (
        sums[cell * 3] / count, sums[cell * 3 + 1] / count, sums[cell * 3 + 2] / count
      )
      let group = hueGroup(red: average.0, green: average.1, blue: average.2)
      let colour = group == neutralHueGroup ? (200, 200, 200) : hueColour(group: group)
      let rect = CGRect(
        x: Double(cell % cells) * cellWidth,
        y: Double(height) - Double(cell / cells + 1) * cellHeight,
        width: cellWidth, height: cellHeight)
      fill(rect, colour: colour, bucket: bucket, into: context)
    }

    drawVectorscopeGuides(into: context, width: width, height: height)
  }

  /// The hue group of an average colour: 18 hue groups, or the neutral group for greys.
  static func hueGroup(red: Int, green: Int, blue: Int) -> Int {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let range = maximum - minimum
    if range < neutralThreshold { return neutralHueGroup }

    var hue: Double
    if maximum == red {
      hue = Double(green - blue) / Double(range)
    } else if maximum == green {
      hue = 2 + Double(blue - red) / Double(range)
    } else {
      hue = 4 + Double(red - green) / Double(range)
    }
    hue /= 6
    if hue < 0 { hue += 1 }
    return min(max(Int(hue * Double(neutralHueGroup)), 0), neutralHueGroup - 1)
  }

  /// The saturated colour of a hue group, at 80% saturation.
  private static func hueColour(group: Int) -> (Int, Int, Int) {
    let hue = Double(group) / Double(neutralHueGroup)
    let scaled = hue * 6
    let sector = Int(scaled.rounded(.down)) % 6
    let fraction = scaled - scaled.rounded(.down)
    let saturation = 0.8
    let low = 1 - saturation
    let rising = 1 - saturation * (1 - fraction)
    let falling = 1 - saturation * fraction
    let rgb: (Double, Double, Double)
    switch sector {
    case 0: rgb = (1, rising, low)
    case 1: rgb = (falling, 1, low)
    case 2: rgb = (low, 1, rising)
    case 3: rgb = (low, falling, 1)
    case 4: rgb = (rising, low, 1)
    default: rgb = (1, low, falling)
    }
    return (Int(rgb.0 * 255), Int(rgb.1 * 255), Int(rgb.2 * 255))
  }

  private static func drawVectorscopeGuides(into context: CGContext, width: Int, height: Int) {
    let centre = CGPoint(x: Double(width) / 2, y: Double(height) / 2)
    let radius = Double(min(width, height)) * 0.46
    context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.35)
    context.setLineWidth(1)
    context.strokeEllipse(
      in: CGRect(
        x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    context.move(to: CGPoint(x: centre.x - radius, y: centre.y))
    context.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
    context.move(to: CGPoint(x: centre.x, y: centre.y - radius))
    context.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
    context.strokePath()

    for step in 0..<6 {
      let angle = Double.pi * 2 * Double(step) / 6
      let point = CGPoint(
        x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
      context.strokeEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
    }
  }

  // MARK: - Shared

  /// The density bucket of a count, on a logarithmic scale from the largest count in the scope.
  /// Nil for an empty cell.
  static func densityBucket(_ count: Int, peak: Int) -> Int? {
    guard count > 0, peak > 0 else { return nil }
    let value = min(255, Int((255 * log1p(Double(count)) / log1p(Double(peak))).rounded()))
    guard value > 0 else { return nil }
    return min(max((value - 1) * densityBuckets / 255, 0), densityBuckets - 1)
  }

  private static func fill(
    _ rect: CGRect, colour: (Int, Int, Int), bucket: Int, into context: CGContext
  ) {
    let step = Double(maximumAlpha - minimumAlpha) / Double(densityBuckets - 1)
    let alpha = Double(minimumAlpha) + Double(bucket) * step
    context.setFillColor(
      red: Double(colour.0) / 255, green: Double(colour.1) / 255, blue: Double(colour.2) / 255,
      alpha: alpha / 255)
    context.fill(rect)
  }
}
