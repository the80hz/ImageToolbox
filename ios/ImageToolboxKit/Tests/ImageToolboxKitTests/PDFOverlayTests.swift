import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF page numbers, watermark and stamp")
struct PDFOverlayTests {

  private static func plain(pages: Int = 3) throws -> Data {
    try PDFFixtures.make(
      (0..<pages).map { _ in PDFFixtures.Page(size: CGSize(width: 300, height: 200)) },
      title: "Report", author: "Ada")
  }

  /// The region of the picture, as fractions from the top left, for a label at each position.
  private static let top = CGRect(x: 0, y: 0, width: 1, height: 0.25)
  private static let middle = CGRect(x: 0, y: 0.35, width: 1, height: 0.3)
  private static let bottom = CGRect(x: 0, y: 0.75, width: 1, height: 0.25)

  private static func ink(_ data: Data, in region: CGRect, page: Int = 0) throws -> Bool {
    try PDFFixtures.hasInk(in: PDFTools.render(data, page: page, width: 600), region: region)
  }

  // MARK: - Page numbers

  @Test("each page gets its number and the total in the label")
  func numbersText() throws {
    let result = try PDFPageNumbers().apply(to: try Self.plain())
    #expect(try PDFFixtures.texts(of: result) == ["Page 1 of 3", "Page 2 of 3", "Page 3 of 3"])
  }

  @Test("the first number can be changed")
  func firstNumber() throws {
    let numbers = PDFPageNumbers(format: "{n}", firstNumber: 7)
    #expect(try PDFFixtures.texts(of: try numbers.apply(to: try Self.plain())) == ["7", "8", "9"])
  }

  @Test("the label sits at the chosen edge of the page")
  func position() throws {
    let source = try Self.plain(pages: 1)
    let bottom = try PDFPageNumbers(position: .bottomCenter).apply(to: source)
    #expect(try Self.ink(bottom, in: Self.bottom))
    #expect(try !Self.ink(bottom, in: Self.top))
    let top = try PDFPageNumbers(position: .topRight).apply(to: source)
    #expect(try Self.ink(top, in: Self.top))
    #expect(try !Self.ink(top, in: Self.bottom))
    let centre = try PDFPageNumbers(position: .center).apply(to: source)
    #expect(try Self.ink(centre, in: Self.middle))
    #expect(try !Self.ink(centre, in: Self.top))
  }

  @Test("the label goes to the left, the middle or the right of the page")
  func horizontalPosition() throws {
    let source = try Self.plain(pages: 1)
    let left = CGRect(x: 0, y: 0.75, width: 0.2, height: 0.25)
    let right = CGRect(x: 0.8, y: 0.75, width: 0.2, height: 0.25)
    let atLeft = try PDFPageNumbers(position: .bottomLeft).apply(to: source)
    #expect(try Self.ink(atLeft, in: left))
    #expect(try !Self.ink(atLeft, in: right))
    let atRight = try PDFPageNumbers(position: .bottomRight).apply(to: source)
    #expect(try Self.ink(atRight, in: right))
    #expect(try !Self.ink(atRight, in: left))
  }

  @Test("the page keeps its content, size, title and author")
  func numbersKeepThePage() throws {
    let source = try PDFFixtures.make(
      [PDFFixtures.Page(colour: PDFFixtures.red)], title: "Report", author: "Ada")
    let result = try PDFPageNumbers().apply(to: source)
    #expect(try PDFFixtures.isNear(PDFFixtures.colour(of: result), PDFFixtures.red))
    #expect(try PDFFixtures.pageSize(of: result) == CGSize(width: 200, height: 100))
    let metadata = try PDFMetadata.read(from: result)
    #expect(metadata.title == "Report")
    #expect(metadata.author == "Ada")
  }

  @Test("a turned page is numbered upright at the size it is shown at")
  func numbersOnTurnedPage() throws {
    let turned = try PDFPageEditing.rotate(try Self.plain(pages: 1), by: 90)
    let result = try PDFPageNumbers(position: .bottomCenter).apply(to: turned)
    #expect(try PDFFixtures.pageSize(of: result) == CGSize(width: 200, height: 300))
    #expect(try Self.ink(result, in: Self.bottom))
    #expect(try !Self.ink(result, in: Self.top))
  }

  @Test("text outside Latin letters is written too")
  func cyrillicLabel() throws {
    let result = try PDFPageNumbers(format: "Страница {n}").apply(to: try Self.plain(pages: 1))
    #expect(try PDFFixtures.texts(of: result) == ["Страница 1"])
  }

  @Test("a blank label or a size of zero is refused")
  func numbersInvalid() throws {
    let source = try Self.plain()
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageNumbers(format: "  ").apply(to: source)
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageNumbers(fontSize: 0).apply(to: source)
    }
  }

  // MARK: - Text watermark

  @Test("the watermark is written on the chosen pages only")
  func watermarkPages() throws {
    let watermark = PDFTextWatermark(text: "DRAFT", pages: [1])
    let result = try watermark.apply(to: try Self.plain())
    #expect(try PDFFixtures.texts(of: result) == ["", "DRAFT", ""])
  }

  @Test("the watermark covers the middle of the page and not its corners")
  func watermarkPlace() throws {
    let watermark = PDFTextWatermark(text: "DRAFT", widthFraction: 0.6, angle: 0, opacity: 1)
    let result = try watermark.apply(to: try Self.plain(pages: 1))
    #expect(try Self.ink(result, in: Self.middle))
    #expect(try !Self.ink(result, in: Self.top))
    #expect(try !Self.ink(result, in: Self.bottom))
  }

  @Test("a turned watermark runs from the lower left to the upper right")
  func watermarkAngle() throws {
    let watermark = PDFTextWatermark(text: "WWWWWW", widthFraction: 0.9, angle: 45, opacity: 1)
    let result = try watermark.apply(to: try Self.plain(pages: 1))
    let picture = try PDFTools.render(result, page: 0, width: 600)
    let lowerLeft = CGRect(x: 0.2, y: 0.55, width: 0.15, height: 0.3)
    let upperRight = CGRect(x: 0.65, y: 0.15, width: 0.15, height: 0.3)
    let upperLeft = CGRect(x: 0.2, y: 0.15, width: 0.15, height: 0.3)
    #expect(try PDFFixtures.hasInk(in: picture, region: lowerLeft))
    #expect(try PDFFixtures.hasInk(in: picture, region: upperRight))
    #expect(try !PDFFixtures.hasInk(in: picture, region: upperLeft))
  }

  @Test("a translucent watermark lets the page show through")
  func watermarkOpacity() throws {
    let page = try PDFFixtures.make([PDFFixtures.Page(colour: PDFFixtures.white)])
    let watermark = PDFTextWatermark(
      text: "MMMMMMMM", widthFraction: 1, angle: 0, opacity: 0.4,
      colour: RGBA(red: 0, green: 0, blue: 0))
    let picture = try PDFTools.render(try watermark.apply(to: page), page: 0, width: 800)
    let raster = try #require(RasterImage(picture))
    var darkest = 255
    for y in 0..<raster.height {
      for x in 0..<raster.width { darkest = min(darkest, Int(raster.pixel(x: x, y: y).red)) }
    }
    // 40 percent black over white is about 153.
    #expect(darkest > 120 && darkest < 190, "darkest red value \(darkest)")
  }

  @Test("a blank text, a width outside 0...1 or a page outside the document is refused")
  func watermarkInvalid() throws {
    let source = try Self.plain()
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFTextWatermark(text: " ").apply(to: source)
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFTextWatermark(widthFraction: 1.5).apply(to: source)
    }
    #expect(throws: PDFEditFailure.pageOutOfRange) {
      try PDFTextWatermark(pages: [9]).apply(to: source)
    }
  }

  // MARK: - Image stamp

  private static let stamp = TestImages.solid(PDFFixtures.green, width: 40, height: 20)

  @Test("a stamp is drawn at the chosen place and size")
  func stampPlace() throws {
    let result = try PDFImageStamp(
      image: Self.stamp, centre: CGPoint(x: 0.25, y: 0.25), widthFraction: 0.4
    ).apply(to: try Self.plain(pages: 1))
    #expect(
      try PDFFixtures.isNear(
        PDFFixtures.colour(of: result, at: CGPoint(x: 0.25, y: 0.25)), PDFFixtures.green))
    #expect(
      try PDFFixtures.isNear(
        PDFFixtures.colour(of: result, at: CGPoint(x: 0.75, y: 0.75)), PDFFixtures.white))
    // 0.4 of a 300 point page is 120 points wide, so 0.25 +- 0.2 is covered and 0.5 is not.
    #expect(
      try PDFFixtures.isNear(
        PDFFixtures.colour(of: result, at: CGPoint(x: 0.1, y: 0.25)), PDFFixtures.green))
    #expect(
      try PDFFixtures.isNear(
        PDFFixtures.colour(of: result, at: CGPoint(x: 0.55, y: 0.25)), PDFFixtures.white))
  }

  @Test("a half transparent stamp blends with the page")
  func stampOpacity() throws {
    let result = try PDFImageStamp(image: Self.stamp, widthFraction: 0.5, opacity: 0.5)
      .apply(to: try Self.plain(pages: 1))
    let colour = try PDFFixtures.colour(of: result)
    // Half of green (20, 200, 40) over white.
    #expect(PDFFixtures.isNear(colour, RGBA(red: 137, green: 227, blue: 147), tolerance: 14))
  }

  @Test("a stamp wider than the page is made to fit")
  func stampFits() throws {
    let tall = TestImages.solid(PDFFixtures.blue, width: 10, height: 100)
    let result = try PDFImageStamp(image: tall, widthFraction: 1).apply(
      to: try Self.plain(pages: 1))
    // The page is 200 points high, so the picture is 20 points wide, in the middle.
    #expect(try PDFFixtures.isNear(PDFFixtures.colour(of: result), PDFFixtures.blue))
    #expect(
      try PDFFixtures.isNear(
        PDFFixtures.colour(of: result, at: CGPoint(x: 0.2, y: 0.5)), PDFFixtures.white))
  }

  @Test("only the chosen pages are stamped")
  func stampPages() throws {
    let result = try PDFImageStamp(image: Self.stamp, widthFraction: 0.5, pages: [2])
      .apply(to: try Self.plain())
    #expect(try PDFFixtures.isNear(PDFFixtures.colour(of: result, page: 0), PDFFixtures.white))
    #expect(try PDFFixtures.isNear(PDFFixtures.colour(of: result, page: 2), PDFFixtures.green))
  }

  @Test("a width outside 0...1 is refused for a stamp")
  func stampInvalid() throws {
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFImageStamp(image: Self.stamp, widthFraction: 0).apply(to: try Self.plain())
    }
  }
}
