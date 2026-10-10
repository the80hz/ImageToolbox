import CoreGraphics
import Foundation

/// Compares two PDFs page by page and draws what differs.
public enum PDFComparison {

  /// A document of difference pictures and how much each page differs.
  public struct Result: Sendable {
    /// One page for each page of the longer document. A page of the first document is drawn
    /// pale, and the pixels that differ from the second are painted in the highlight colour.
    public let data: Data
    /// For each page, the number of pixels that differ.
    public let differingPixels: [Int]

    /// The number of pages that differ at all.
    public var differingPages: Int { differingPixels.filter { $0 > 0 }.count }
  }

  /// The longer side of a difference picture is at most this many pixels.
  private static let maximumSide = 1_600
  /// Pages are drawn at this many pixels to a point before they are compared, which is 144 dpi.
  private static let scale = 2.0

  /// - Parameters:
  ///   - highlight: the colour of pixels that differ.
  ///   - tolerance: how far a pixel may differ, from 0 to 1, before it counts as different. The
  ///     default hides the noise of anti-aliasing. The metric reads it as its own threshold.
  ///   - metric: how the pixels of two pages are compared. Absolute error is the default.
  public static func compare(
    _ first: Data, with second: Data, highlight: RGBA = RGBA(red: 255, green: 48, blue: 48),
    tolerance: Double = 0.06, metric: PDFComparisonMetric = .absoluteError
  ) throws -> Result {
    guard tolerance >= 0, tolerance < 1 else { throw PDFEditFailure.invalidParameter }
    let left = try PDFSourcePages(first)
    let right = try PDFSourcePages(second)
    let count = max(left.pageCount, right.pageCount)
    let counts = Counter()

    let output = try PDFPageWriter.write(pageCount: count) { index in
      let a = index < left.pageCount ? left.render(index, scale: scale, maximumSide: 8_192) : nil
      let b = index < right.pageCount ? right.render(index, scale: scale, maximumSide: 8_192) : nil
      let canvas = canvasSize(a, b)
      guard let a = place(a, on: canvas), let b = place(b, on: canvas),
        let (picture, differing) = difference(
          a, b, highlight: highlight, metric: metric, tolerance: tolerance),
        let jpeg = ImageCodec.encode(picture, as: .jpeg, quality: 0.9)
      else { throw PDFEditFailure.encodeFailed }
      counts.pixels.append(differing)
      let image = PDFPageWriter.jpegBacked(jpeg) ?? picture
      return PDFPageWriter.Page(size: CGSize(width: canvas.width, height: canvas.height)) {
        $0.draw(image, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
      }
    }
    guard let data = output else { throw PDFEditFailure.writeFailed }
    return Result(data: data, differingPixels: counts.pixels)
  }

  private final class Counter {
    var pixels: [Int] = []
  }

  /// The size both pictures are compared at: the larger of each side, made smaller to fit.
  private static func canvasSize(_ a: CGImage?, _ b: CGImage?) -> (width: Int, height: Int) {
    let width = max(a?.width ?? 1, b?.width ?? 1)
    let height = max(a?.height ?? 1, b?.height ?? 1)
    let fit = min(1, Double(maximumSide) / Double(max(width, height)))
    return (max(1, Int(Double(width) * fit)), max(1, Int(Double(height) * fit)))
  }

  /// The picture stretched over the canvas, or a white canvas for a page the document lacks.
  private static func place(_ image: CGImage?, on canvas: (width: Int, height: Int)) -> RasterImage?
  {
    guard let context = ImageGeometry.makeContext(width: canvas.width, height: canvas.height) else {
      return nil
    }
    let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(bounds)
    context.interpolationQuality = .high
    if let image { context.draw(image, in: bounds) }
    return context.makeImage().flatMap(RasterImage.init)
  }

  private static func difference(
    _ a: RasterImage, _ b: RasterImage, highlight: RGBA, metric: PDFComparisonMetric,
    tolerance: Double
  ) -> (CGImage, Int)? {
    let marked = PDFPixelMetric.differences(a, b, metric: metric, tolerance: tolerance)
    var pixels = [UInt8](repeating: 255, count: a.width * a.height * 4)
    var differing = 0
    for pixel in 0..<(a.width * a.height) {
      let offset = pixel * 4
      if marked[pixel] {
        differing += 1
        pixels[offset] = highlight.red
        pixels[offset + 1] = highlight.green
        pixels[offset + 2] = highlight.blue
      } else {
        // The page is shown pale, so the highlight stands out.
        for channel in 0..<3 {
          pixels[offset + channel] = UInt8((Int(a.pixels[offset + channel]) + 255 * 2) / 3)
        }
      }
    }
    let image = RasterImage(width: a.width, height: a.height, pixels: pixels).toCGImage()
    return image.map { ($0, differing) }
  }
}
