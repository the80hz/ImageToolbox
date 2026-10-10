import CoreGraphics
import Foundation

/// A line of text written across pages at an angle, in a translucent colour. The pages are drawn
/// again into a new document, so text and vector graphics stay, but links, form fields and
/// outlines are not kept.
public struct PDFTextWatermark: Equatable, Sendable {
  public var text: String
  /// The width of the text before it is turned, as a share of the page width.
  public var widthFraction: Double
  /// Degrees counterclockwise: 45 reads from the lower left to the upper right.
  public var angle: Double
  public var opacity: Double
  public var colour: RGBA
  /// Zero-based pages to mark. Nil marks every page.
  public var pages: Set<Int>?

  public init(
    text: String = "Watermark", widthFraction: Double = 0.5, angle: Double = 45,
    opacity: Double = 0.3, colour: RGBA = RGBA(red: 0, green: 0, blue: 0), pages: Set<Int>? = nil
  ) {
    self.text = text
    self.widthFraction = widthFraction
    self.angle = angle
    self.opacity = opacity
    self.colour = colour
    self.pages = pages
  }

  /// The document with the text on the chosen pages. Blank text or a width outside 0...1 throws
  /// `invalidParameter`, and a page outside the document throws `pageOutOfRange`.
  public func apply(to data: Data) throws -> Data {
    guard widthFraction > 0, widthFraction <= 1,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw PDFEditFailure.invalidParameter }
    let source = try PDFSourcePages(data)
    if let pages, !pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) {
      throw PDFEditFailure.pageOutOfRange
    }
    return try source.overlay(pages: pages) { _, size, context in
      guard let line = PDFTextLine(text, fittingWidth: size.width * widthFraction) else { return }
      context.saveGState()
      // The opacity is set on the context: a colour's own alpha is ignored for text in a PDF.
      context.setFillColor(colour.cgColor())
      context.setAlpha(CGFloat(min(max(opacity, 0), 1)))
      context.translateBy(x: size.width / 2, y: size.height / 2)
      context.rotate(by: angle * .pi / 180)
      line.draw(at: CGPoint(x: -line.width / 2, y: -(line.ascent - line.descent) / 2), in: context)
      context.restoreGState()
    }
  }
}

/// A picture placed on pages, such as a signature or a logo. The pages are drawn again into a new
/// document, so text and vector graphics stay, but links, form fields and outlines are not kept.
public struct PDFImageStamp: @unchecked Sendable {
  public var image: CGImage
  /// The centre of the picture, as fractions of the page from its top left corner.
  public var centre: CGPoint
  /// The width of the picture as a share of the page width. The picture is made smaller when it
  /// would be taller than the page.
  public var widthFraction: Double
  public var opacity: Double
  /// Zero-based pages to mark. Nil marks every page.
  public var pages: Set<Int>?

  public init(
    image: CGImage, centre: CGPoint = CGPoint(x: 0.5, y: 0.5), widthFraction: Double = 0.25,
    opacity: Double = 1, pages: Set<Int>? = nil
  ) {
    self.image = image
    self.centre = centre
    self.widthFraction = widthFraction
    self.opacity = opacity
    self.pages = pages
  }

  /// Pictures larger than this are scaled down before they go into the file.
  private static let maximumSide = 1_600

  /// The document with the picture on the chosen pages. A width outside 0...1 throws
  /// `invalidParameter`, and a page outside the document throws `pageOutOfRange`.
  public func apply(to data: Data) throws -> Data {
    guard widthFraction > 0, widthFraction <= 1, image.width > 0, image.height > 0 else {
      throw PDFEditFailure.invalidParameter
    }
    let source = try PDFSourcePages(data)
    if let pages, !pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) {
      throw PDFEditFailure.pageOutOfRange
    }
    let picture = Self.reduced(image)
    let aspect = CGFloat(image.width) / CGFloat(image.height)
    return try source.overlay(pages: pages) { _, size, context in
      let width = min(size.width * widthFraction, size.height * aspect)
      let height = width / aspect
      let x = min(max(size.width * centre.x - width / 2, 0), max(size.width - width, 0))
      let top = min(max(size.height * centre.y - height / 2, 0), max(size.height - height, 0))
      context.saveGState()
      context.setAlpha(CGFloat(min(max(opacity, 0), 1)))
      context.draw(
        picture, in: CGRect(x: x, y: size.height - top - height, width: width, height: height))
      context.restoreGState()
    }
  }

  private static func reduced(_ image: CGImage) -> CGImage {
    let longest = max(image.width, image.height)
    guard longest > maximumSide else { return image }
    let scale = Double(maximumSide) / Double(longest)
    return ImageGeometry.resize(
      image, width: max(1, Int(Double(image.width) * scale)),
      height: max(1, Int(Double(image.height) * scale))) ?? image
  }
}
