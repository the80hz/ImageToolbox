import CoreGraphics
import Foundation
import PDFKit

/// Makes a PDF smaller by drawing each page as a JPEG picture. Text and vector graphics become pixels,
/// so the result cannot be searched or selected. Scanned and image-heavy documents shrink the most.
public enum PDFCompression {

  public enum Failure: Error, Equatable {
    /// The data is not a PDF that PDFKit can open.
    case unreadable
    /// The document has no pages.
    case noPages
    /// `maxSide` is not a positive number of pixels.
    case invalidSize
    case encodeFailed
    case writeFailed
  }

  /// Re-encodes every page as a JPEG in a new document. Each page keeps the size it is shown at, and
  /// its picture has its longer side at `maxSide` pixels. A page turned with /Rotate is written upright.
  ///
  /// The result is never larger than `data`: when the re-encoded document is not smaller, `data` is
  /// returned unchanged.
  /// - Parameters:
  ///   - quality: JPEG quality in 0...1.
  ///   - maxSide: the longer side of each page picture, in pixels.
  public static func compress(_ data: Data, quality: Double, maxSide: Int) throws -> Data {
    guard maxSide > 0 else { throw Failure.invalidSize }
    guard let document = PDFDocument(data: data) else { throw Failure.unreadable }
    guard document.pageCount > 0 else { throw Failure.noPages }
    let coreGraphicsDocument = CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) }

    let rendered = try PDFPageWriter.write(pageCount: document.pageCount) { index in
      guard let page = document.page(at: index) else { throw Failure.unreadable }
      let size = displayedSize(of: page)
      guard size.width > 0, size.height > 0 else { throw Failure.unreadable }
      let pixels = pixelSize(of: size, maxSide: maxSide)

      let picture: CGImage
      if page.rotation % 360 == 0 {
        picture = try PDFTools.render(data, page: index, width: pixels.width)
      } else {
        guard let turned = coreGraphicsDocument?.page(at: index + 1) else {
          throw Failure.unreadable
        }
        picture = try uprightPicture(turned, pixels: pixels)
      }

      guard let jpeg = ImageCodec.encode(picture, as: .jpeg, quality: quality) else {
        throw Failure.encodeFailed
      }
      let image = PDFPageWriter.jpegBacked(jpeg) ?? picture
      return PDFPageWriter.Page(size: size) { context in
        context.draw(image, in: CGRect(origin: .zero, size: size))
      }
    }

    guard let output = rendered else { throw Failure.writeFailed }
    return output.count < data.count ? output : data
  }

  /// The size the page is shown at, in points: its media box, turned a quarter turn when /Rotate is
  /// 90 or 270.
  private static func displayedSize(of page: PDFPage) -> CGSize {
    let box = page.bounds(for: .mediaBox).size
    return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
  }

  /// The picture size in pixels: the longer side is `maxSide`, the other keeps the page's proportions.
  private static func pixelSize(of size: CGSize, maxSide: Int) -> (width: Int, height: Int) {
    if size.width >= size.height {
      let height = Int((Double(maxSide) * size.height / size.width).rounded())
      return (maxSide, max(1, height))
    }
    let width = Int((Double(maxSide) * size.width / size.height).rounded())
    return (max(1, width), maxSide)
  }

  /// Draws a turned page upright at `pixels`. PDFTools.render draws a turned page at its unturned size
  /// and clips it, so the page is drawn here with its drawing transform instead.
  private static func uprightPicture(
    _ page: CGPDFPage, pixels: (width: Int, height: Int)
  ) throws -> CGImage {
    guard let context = ImageGeometry.makeContext(width: pixels.width, height: pixels.height)
    else { throw Failure.unreadable }
    let target = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(target)
    context.concatenate(
      page.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw Failure.unreadable }
    return image
  }
}
