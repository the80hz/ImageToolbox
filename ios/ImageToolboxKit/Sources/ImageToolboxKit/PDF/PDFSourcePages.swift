import CoreGraphics
import Foundation
import PDFKit

/// Why a PDF edit failed. Every tool in this folder that is not part of `PDFTools` reports its
/// failures with this type, so a screen needs one message table for all of them.
public enum PDFEditFailure: Error, Equatable, Sendable {
  /// The data is not a PDF that Core Graphics and PDFKit can open.
  case unreadable
  /// The document is encrypted and no password was given.
  case locked
  /// The password does not open the document.
  case wrongPassword
  /// The edit would leave a document with no pages.
  case noPages
  /// A page number is outside the document.
  case pageOutOfRange
  /// A parameter is empty, zero or otherwise unusable, such as a blank password or a zero size.
  case invalidParameter
  /// The document holds nothing the tool can work on, such as no images to extract.
  case nothingFound
  /// A picture could not be encoded.
  case encodeFailed
  case writeFailed
}

/// The pages of a document for tools that draw each page into a new document. The result keeps
/// vector content and text, but not what lives outside the page content: links, form fields,
/// outlines and attachments.
struct PDFSourcePages {
  private let document: CGPDFDocument
  /// Title, author and the other keys that a new document takes from the source.
  let info: [String: Any]

  /// Opens `data`. An encrypted document must open with an empty password.
  init(_ data: Data) throws {
    guard let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider)
    else { throw PDFEditFailure.unreadable }
    if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") {
      throw PDFEditFailure.locked
    }
    guard document.numberOfPages > 0 else { throw PDFEditFailure.unreadable }
    self.document = document
    self.info = Self.contextInfo(of: data)
  }

  var pageCount: Int { document.numberOfPages }

  /// The size the page is shown at, in points: its crop box, turned a quarter turn when the page
  /// is turned by 90 or 270 degrees.
  func displayedSize(of index: Int) -> CGSize {
    guard let page = document.page(at: index + 1) else { return .zero }
    let box = page.getBoxRect(.cropBox).size
    return page.rotationAngle % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
  }

  /// Draws the whole page, upright, stretched over `destination`. The page is clipped to the
  /// destination, so a destination larger than `clip` shows only part of the page.
  func draw(_ index: Int, in context: CGContext, to destination: CGRect, clip: CGRect? = nil) {
    guard let page = document.page(at: index + 1) else { return }
    let size = displayedSize(of: index)
    context.saveGState()
    context.clip(to: clip ?? destination)
    // getDrawingTransform does not enlarge a page to a larger rectangle: with a destination bigger
    // than the page it keeps the page at its own size. So the page is turned upright at its
    // displayed size, and that size is then stretched to the destination.
    context.translateBy(x: destination.minX, y: destination.minY)
    context.scaleBy(x: destination.width / size.width, y: destination.height / size.height)
    context.concatenate(
      page.getDrawingTransform(
        .cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: false))
    context.clip(to: page.getBoxRect(.cropBox))
    context.drawPDFPage(page)
    context.restoreGState()
  }

  /// The page drawn upright over a white background, `scale` pixels to a point.
  func render(_ index: Int, scale: Double, maximumSide: Int) -> CGImage? {
    let size = displayedSize(of: index)
    guard size.width > 0, size.height > 0, scale > 0 else { return nil }
    let fit = min(1, Double(maximumSide) / Double(max(size.width, size.height) * scale))
    let width = max(1, Int((Double(size.width) * scale * fit).rounded()))
    let height = max(1, Int((Double(size.height) * scale * fit).rounded()))
    guard let context = ImageGeometry.makeContext(width: width, height: height) else {
      return nil
    }
    let target = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(target)
    draw(index, in: context, to: target)
    return context.makeImage()
  }

  /// A new document with the same pages, one per entry of `sizes`, each painted by `paint`. The
  /// source's title, author, subject, keywords and creator are carried over when `keepInfo` is true.
  func rebuild(
    sizes: [CGSize], keepInfo: Bool = true,
    paint: @escaping (_ index: Int, _ context: CGContext) throws -> Void
  ) throws -> Data {
    let output = try PDFPageWriter.write(pageCount: sizes.count, info: keepInfo ? info : nil) {
      index in
      PDFPageWriter.Page(size: sizes[index]) { context in try paint(index, context) }
    }
    guard let data = output else { throw PDFEditFailure.writeFailed }
    return data
  }

  /// A copy of the document with `paint` called after each selected page is drawn. Pages that are
  /// not selected are copied as they are. `pages` holds zero-based indices, and nil means every
  /// page. A `backdrop` colour is filled over each page before the page is drawn, so that blend
  /// modes in `paint` have an opaque page to work on.
  func overlay(
    pages: Set<Int>?, backdrop: CGColor? = nil,
    paint: @escaping (_ index: Int, _ size: CGSize, _ context: CGContext) -> Void
  ) throws -> Data {
    let sizes = (0..<pageCount).map(displayedSize(of:))
    return try rebuild(sizes: sizes) { index, context in
      let size = sizes[index]
      let rect = CGRect(origin: .zero, size: size)
      if let backdrop {
        context.setFillColor(backdrop)
        context.fill(rect)
      }
      draw(index, in: context, to: rect)
      if pages?.contains(index) ?? true { paint(index, size, context) }
    }
  }

  // MARK: - Information

  /// Auxiliary information for a Core Graphics PDF context, taken from the document's attributes.
  private static func contextInfo(of data: Data) -> [String: Any] {
    guard let attributes = PDFDocument(data: data)?.documentAttributes else { return [:] }
    var info: [String: Any] = [:]
    let keys: [(PDFDocumentAttribute, CFString)] = [
      (.titleAttribute, kCGPDFContextTitle), (.authorAttribute, kCGPDFContextAuthor),
      (.subjectAttribute, kCGPDFContextSubject), (.creatorAttribute, kCGPDFContextCreator),
    ]
    for (attribute, key) in keys {
      if let text = attributes[attribute.rawValue] as? String, !text.isEmpty {
        info[key as String] = text
      }
    }
    let keywords = attributes[PDFDocumentAttribute.keywordsAttribute.rawValue]
    if let words = keywords as? [String], !words.isEmpty {
      info[kCGPDFContextKeywords as String] = words.joined(separator: ", ")
    }
    return info
  }
}

/// PDFKit documents for the tools that edit pages in place or copy pages between documents.
enum PDFKitAccess {

  /// The document, open and with at least one page. A locked document throws `locked`.
  static func open(_ data: Data) throws -> PDFDocument {
    guard let document = PDFDocument(data: data) else { throw PDFEditFailure.unreadable }
    if document.isLocked { throw PDFEditFailure.locked }
    guard document.pageCount > 0 else { throw PDFEditFailure.unreadable }
    return document
  }

  static func write(_ document: PDFDocument) throws -> Data {
    guard let data = document.dataRepresentation() else { throw PDFEditFailure.writeFailed }
    return data
  }

  /// A new document with copies of the source pages at `indices`, in that order.
  static func copy(_ source: PDFDocument, pages indices: [Int]) throws -> PDFDocument {
    let result = PDFDocument()
    for index in indices {
      guard index >= 0, index < source.pageCount, let page = source.page(at: index) else {
        throw PDFEditFailure.pageOutOfRange
      }
      result.insert(page, at: result.pageCount)
    }
    guard result.pageCount > 0 else { throw PDFEditFailure.noPages }
    return result
  }
}
