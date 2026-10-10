import CoreGraphics
import Foundation

/// Builds a PDF with one page per picture. Each picture is stored as a JPEG.
public enum ImagesToPDF {

  /// Makes every picture as wide as the widest or the narrowest one, keeping its proportions.
  public enum WidthRule: String, CaseIterable, Sendable {
    case none, widest, narrowest

    /// The width all pictures take, or nil when each keeps its own.
    func targetWidth(among widths: [Int]) -> Int? {
      switch self {
      case .none: nil
      case .widest: widths.max()
      case .narrowest: widths.min()
      }
    }
  }

  public struct Options: Equatable, Sendable {
    /// JPEG quality in 0...1.
    public var quality: Double
    /// The share of the picture's pixels that is kept, from just above 0 to 1.
    public var scale: Double
    /// The paper size of every page. Nil makes each page as large as its picture, one pixel to a
    /// point. With a paper size, the page is turned on its side for a wide picture.
    public var pageSize: PDFPageSize?
    /// The empty border around a picture, in points. Only used with a paper size.
    public var margin: Double
    /// Which width the pictures are made, after `scale` is applied.
    public var widthRule: WidthRule

    public init(
      quality: Double = 0.85, scale: Double = 1, pageSize: PDFPageSize? = nil, margin: Double = 0,
      widthRule: WidthRule = .none
    ) {
      self.quality = quality
      self.scale = scale
      self.pageSize = pageSize
      self.margin = margin
      self.widthRule = widthRule
    }
  }

  /// The document. An empty array throws `noPages`, and a quality, scale or margin outside its
  /// range throws `invalidParameter`.
  public static func make(from pictures: [CGImage], options: Options = Options()) throws -> Data {
    guard !pictures.isEmpty else { throw PDFEditFailure.noPages }
    guard options.quality > 0, options.quality <= 1, options.scale > 0, options.scale <= 1,
      options.margin >= 0
    else { throw PDFEditFailure.invalidParameter }

    let scaledWidths = pictures.map { scaled($0.width, by: options.scale) }
    let targetWidth = options.widthRule.targetWidth(among: scaledWidths)
    let output = try PDFPageWriter.write(pageCount: pictures.count) { index in
      let picture = try prepared(pictures[index], options: options, targetWidth: targetWidth)
      let pixels = CGSize(width: picture.image.width, height: picture.image.height)
      let page = pageSize(for: pixels, options: options)
      let area = CGRect(origin: .zero, size: page).insetBy(
        dx: options.pageSize == nil ? 0 : options.margin,
        dy: options.pageSize == nil ? 0 : options.margin)
      guard area.width > 0, area.height > 0 else { throw PDFEditFailure.invalidParameter }
      let scale = min(area.width / pixels.width, area.height / pixels.height)
      let drawn = CGSize(width: pixels.width * scale, height: pixels.height * scale)
      let target = CGRect(
        x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width,
        height: drawn.height)
      return PDFPageWriter.Page(size: page) { context in context.draw(picture.image, in: target) }
    }
    guard let data = output else { throw PDFEditFailure.writeFailed }
    return data
  }

  /// The page for a picture of `pixels`: the picture's size, or the paper turned to suit it.
  private static func pageSize(for pixels: CGSize, options: Options) -> CGSize {
    guard let paper = options.pageSize else { return pixels }
    return pixels.width > pixels.height ? paper.landscape.size : paper.size
  }

  /// A length of pixels after the share `scale` is kept, at least one pixel.
  private static func scaled(_ length: Int, by scale: Double) -> Int {
    max(1, Int((Double(length) * scale).rounded()))
  }

  /// The picture on white, made smaller by `scale` or made as wide as `targetWidth` with its
  /// proportions kept, and stored as a JPEG that the file can keep.
  private static func prepared(
    _ picture: CGImage, options: Options, targetWidth: Int?
  ) throws -> (image: CGImage, bytes: Data) {
    let scaledWidth = scaled(picture.width, by: options.scale)
    let scaledHeight = scaled(picture.height, by: options.scale)
    let width = targetWidth ?? scaledWidth
    let height =
      targetWidth == nil
      ? scaledHeight
      : max(1, Int((Double(scaledHeight) * Double(width) / Double(scaledWidth)).rounded()))
    guard let context = ImageGeometry.makeContext(width: width, height: height) else {
      throw PDFEditFailure.encodeFailed
    }
    context.interpolationQuality = .high
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let flat = context.makeImage(),
      let jpeg = ImageCodec.encode(flat, as: .jpeg, quality: options.quality)
    else { throw PDFEditFailure.encodeFailed }
    return (PDFPageWriter.jpegBacked(jpeg) ?? flat, jpeg)
  }
}
