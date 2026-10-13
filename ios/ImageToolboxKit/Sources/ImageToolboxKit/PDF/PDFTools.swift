import CoreGraphics
import Foundation
import PDFKit

/// PDF operations with PDFKit: merging documents, extracting page ranges, rotating pages, and rendering a
/// page to a picture. Pages are kept as they are, so no page is re-encoded.
public enum PDFTools {

  public enum Failure: Error, Equatable {
    case unreadable
    case noPages
    case pageOutOfRange
    case writeFailed
  }

  /// Joins the pages of several documents, in the order given.
  public static func merge(_ documents: [Data]) throws -> Data {
    let merged = PDFDocument()
    for data in documents {
      guard let document = PDFDocument(data: data) else { throw Failure.unreadable }
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        merged.insert(page, at: merged.pageCount)
      }
    }
    guard merged.pageCount > 0 else { throw Failure.noPages }
    return try write(merged)
  }

  /// A new document with the pages at the given zero-based indices, in the order given.
  public static func extract(_ data: Data, pages indices: [Int]) throws -> Data {
    let source = try document(data)
    let result = PDFDocument()
    for index in indices {
      guard index >= 0, index < source.pageCount, let page = source.page(at: index) else {
        throw Failure.pageOutOfRange
      }
      result.insert(page, at: result.pageCount)
    }
    guard result.pageCount > 0 else { throw Failure.noPages }
    return try write(result)
  }

  /// The document with each page turned by `quarterTurns` clockwise (a multiple of 90 degrees).
  public static func rotate(_ data: Data, quarterTurns: Int) throws -> Data {
    let source = try document(data)
    let turn = ((quarterTurns % 4) + 4) % 4 * 90
    for index in 0..<source.pageCount {
      guard let page = source.page(at: index) else { continue }
      page.rotation = (page.rotation + turn) % 360
    }
    return try write(source)
  }

  /// The number of pages in the document.
  public static func pageCount(_ data: Data) throws -> Int {
    try document(data).pageCount
  }

  /// The page at `index`, drawn at `width` pixels across, with a white background. A page turned
  /// with /Rotate is drawn turned, at the size it is shown at.
  public static func render(_ data: Data, page index: Int, width: Int) throws -> CGImage {
    let source = try document(data)
    guard index >= 0, index < source.pageCount, let page = source.page(at: index) else {
      throw Failure.pageOutOfRange
    }
    let size = displayedSize(of: page)
    guard width > 0, size.width > 0, size.height > 0 else { throw Failure.unreadable }
    let scale = CGFloat(width) / size.width
    let height = Int((size.height * scale).rounded())
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure.unreadable }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    if page.rotation % 360 == 0 {
      page.draw(with: .mediaBox, to: context)
    } else {
      // PDFKit draws a turned page into the unturned media box, which clips half of it. The page is
      // drawn with its drawing transform instead, which turns it to the displayed size.
      guard
        let turned = CGDataProvider(data: data as CFData)
          .flatMap({ CGPDFDocument($0) })?.page(at: index + 1)
      else { throw Failure.unreadable }
      context.concatenate(
        turned.getDrawingTransform(
          .mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0,
          preserveAspectRatio: true))
      context.drawPDFPage(turned)
    }
    guard let image = context.makeImage() else { throw Failure.unreadable }
    return image
  }

  // MARK: - Helpers

  private static func document(_ data: Data) throws -> PDFDocument {
    guard let document = PDFDocument(data: data), document.pageCount > 0 else {
      throw Failure.unreadable
    }
    return document
  }

  /// The size the page is shown at, in points: its media box, turned a quarter turn when /Rotate is
  /// 90 or 270.
  private static func displayedSize(of page: PDFPage) -> CGSize {
    let box = page.bounds(for: .mediaBox).size
    return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
  }

  private static func write(_ document: PDFDocument) throws -> Data {
    guard let data = document.dataRepresentation() else { throw Failure.writeFailed }
    return data
  }
}
