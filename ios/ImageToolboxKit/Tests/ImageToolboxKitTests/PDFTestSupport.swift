import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

/// Builds PDFs from code and reads their pixels back, so the PDF tests need no fixture files.
enum PDFFixtures {

  static let red = RGBA(red: 230, green: 20, blue: 20)
  static let green = RGBA(red: 20, green: 200, blue: 40)
  static let blue = RGBA(red: 20, green: 40, blue: 230)
  static let yellow = RGBA(red: 240, green: 220, blue: 20)
  static let white = RGBA(red: 255, green: 255, blue: 255)

  /// One page: a background colour, an optional line of text, and optionally a second colour that
  /// covers the right half.
  struct Page {
    var size = CGSize(width: 200, height: 100)
    var colour = PDFFixtures.white
    var rightColour: RGBA?
    var text: String?
  }

  /// The PDF of `pages`. Title and author go to the information dictionary.
  static func make(_ pages: [Page], title: String? = nil, author: String? = nil) throws -> Data {
    let output = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: output))
    var box = CGRect(origin: .zero, size: pages.first?.size ?? .zero)
    var info: [String: Any] = [:]
    if let title { info[kCGPDFContextTitle as String] = title }
    if let author { info[kCGPDFContextAuthor as String] = author }
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary))
    for page in pages {
      let bounds = CGRect(origin: .zero, size: page.size)
      var pageBox = bounds
      context.beginPage(mediaBox: &pageBox)
      context.setFillColor(page.colour.cgColor())
      context.fill(bounds)
      if let right = page.rightColour {
        context.setFillColor(right.cgColor())
        context.fill(CGRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height))
      }
      if let text = page.text {
        draw(text, in: context, at: CGPoint(x: 12, y: page.size.height / 2))
      }
      context.endPage()
    }
    context.closePDF()
    return output as Data
  }

  /// One page for each colour, all of the same size.
  static func solid(
    _ colours: [RGBA], size: CGSize = CGSize(width: 200, height: 100)
  ) throws -> Data {
    try make(colours.map { Page(size: size, colour: $0) })
  }

  /// One page for each text, so tests can tell the pages apart by their text.
  static func texts(_ texts: [String]) throws -> Data {
    try make(texts.map { Page(text: $0) })
  }

  private static func draw(_ text: String, in context: CGContext, at point: CGPoint) {
    let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font
    ]
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.textPosition = point
    CTLineDraw(
      CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)),
      context)
  }

  /// The entries of a zip, in order.
  static func archiveEntries(_ data: Data) throws -> [ZipReader.Entry] {
    try ZipReader.entries(in: data, maximumEntries: 5_000, maximumEntrySize: 256 << 20) { _ in true
    }
  }

  /// The text of each page, as PDFKit reads it.
  static func texts(of data: Data) throws -> [String] {
    let document = try #require(PDFDocument(data: data))
    return (0..<document.pageCount).map {
      document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
  }

  /// The size a page is shown at, in points.
  static func pageSize(of data: Data, page index: Int = 0) throws -> CGSize {
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: index))
    let box = page.bounds(for: .cropBox).size
    return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
  }

  /// The colour at `point`, given as fractions of the page from its top left corner. The page is
  /// drawn by `PDFTools.render`, which PDFKit's own tests cover.
  static func colour(
    of data: Data, page index: Int = 0, at point: CGPoint = CGPoint(x: 0.5, y: 0.5),
    width: Int = 200
  ) throws -> RGBA {
    try colour(in: PDFTools.render(data, page: index, width: width), at: point)
  }

  /// The colour at `point` of a page drawn upright by the crop box, which `PDFTools.render` does
  /// not use.
  static func shownColour(
    of data: Data, page index: Int = 0, at point: CGPoint = CGPoint(x: 0.5, y: 0.5),
    scale: Double = 1
  ) throws -> RGBA {
    try colour(in: PDFImageExport.render(data, page: index, scale: scale), at: point)
  }

  static func colour(in picture: CGImage, at point: CGPoint) throws -> RGBA {
    let raster = try #require(RasterImage(picture))
    let x = min(raster.width - 1, max(0, Int(point.x * Double(raster.width))))
    let y = min(raster.height - 1, max(0, Int(point.y * Double(raster.height))))
    return raster.pixel(x: x, y: y)
  }

  /// Whether any pixel in `region`, given as fractions of the picture from its top left corner, is
  /// darker than `threshold` in some channel. For text on a white page.
  static func hasInk(in picture: CGImage, region: CGRect, threshold: Int = 200) throws -> Bool {
    let raster = try #require(RasterImage(picture))
    let x0 = Int(region.minX * Double(raster.width))
    let x1 = min(raster.width, Int(region.maxX * Double(raster.width)))
    let y0 = Int(region.minY * Double(raster.height))
    let y1 = min(raster.height, Int(region.maxY * Double(raster.height)))
    for y in y0..<y1 {
      for x in x0..<x1 {
        let pixel = raster.pixel(x: x, y: y)
        if Int(pixel.red) < threshold || Int(pixel.green) < threshold || Int(pixel.blue) < threshold
        {
          return true
        }
      }
    }
    return false
  }

  /// Whether the colours differ by no more than `tolerance` in each channel.
  static func isNear(_ a: RGBA, _ b: RGBA, tolerance: Int = 12) -> Bool {
    abs(Int(a.red) - Int(b.red)) <= tolerance && abs(Int(a.green) - Int(b.green)) <= tolerance
      && abs(Int(a.blue) - Int(b.blue)) <= tolerance
  }
}
