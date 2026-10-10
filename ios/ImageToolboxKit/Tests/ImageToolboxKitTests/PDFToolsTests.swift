import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF operations with PDFKit")
struct PDFToolsTests {

  /// A one-page PDF of 200 x 100 points with a filled rectangle, drawn with a PDF context so that it
  /// works on macOS and iOS alike.
  private static func onePagePDF(colour: CGFloat) throws -> Data {
    let output = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: output))
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(red: colour, green: 0.2, blue: 0.2, alpha: 1)
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
    return output as Data
  }

  @Test("merging keeps the pages of every document in order")
  func merge() throws {
    let first = try Self.onePagePDF(colour: 0.9)
    let second = try Self.onePagePDF(colour: 0.1)
    let merged = try PDFTools.merge([first, second])
    #expect(try PDFTools.pageCount(merged) == 2)
  }

  @Test("extracting pages keeps the chosen pages in the given order")
  func extract() throws {
    let first = try Self.onePagePDF(colour: 0.9)
    let merged = try PDFTools.merge([first, first, first])
    let picked = try PDFTools.extract(merged, pages: [2, 0])
    #expect(try PDFTools.pageCount(picked) == 2)
    #expect(throws: PDFTools.Failure.pageOutOfRange) {
      try PDFTools.extract(merged, pages: [5])
    }
  }

  @Test("rotating a page by a quarter turn swaps its width and height")
  func rotate() throws {
    let data = try Self.onePagePDF(colour: 0.5)
    let rotated = try PDFTools.rotate(data, quarterTurns: 1)
    let document = try #require(PDFDocument(data: rotated))
    let page = try #require(document.page(at: 0))
    #expect(page.rotation == 90)
  }

  @Test("rendering a page gives a picture of the requested width")
  func render() throws {
    let data = try Self.onePagePDF(colour: 0.9)
    let picture = try PDFTools.render(data, page: 0, width: 400)
    #expect(picture.width == 400)
    #expect(picture.height == 200)
  }

  @Test(
    "a page turned by a quarter turn is rendered whole, not cut to its unturned box",
    arguments: [1, 3])
  func renderTurnedPage(quarterTurns: Int) throws {
    let data = try PDFTools.rotate(try Self.onePagePDF(colour: 0.1), quarterTurns: quarterTurns)
    let picture = try PDFTools.render(data, page: 0, width: 200)
    // 200 x 100 points turned a quarter turn is 100 x 200 points: a 200 x 400 picture.
    try #require(picture.width == 200)
    try #require(picture.height == 400)
    // The lower half lies outside the unturned box. Before the fix it stayed white.
    let raster = try #require(RasterImage(picture))
    #expect(raster.pixel(x: 150, y: 300).red < 128)
  }

  @Test("damaged data is refused")
  func unreadable() {
    #expect(throws: PDFTools.Failure.unreadable) {
      try PDFTools.pageCount(Data("not a pdf".utf8))
    }
  }
}
