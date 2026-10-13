import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF compression, comic conversion and searchable PDF")
struct PDFExtrasTests {

  private static let red = RGBA(red: 230, green: 20, blue: 20)
  private static let green = RGBA(red: 20, green: 200, blue: 40)
  private static let blue = RGBA(red: 20, green: 40, blue: 230)

  /// A one-page PDF of `size` points with `picture` stretched over the page.
  private static func pdf(of picture: CGImage, size: CGSize) throws -> Data {
    let output = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: output))
    var box = CGRect(origin: .zero, size: size)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.draw(picture, in: box)
    context.endPDFPage()
    context.closePDF()
    return output as Data
  }

  /// Pseudo-random colours, which Flate cannot shrink, so the source PDF stays large.
  private static func noise(_ x: Int, _ y: Int) -> RGBA {
    var value = UInt32(truncatingIfNeeded: x) &* 2_654_435_761 ^ UInt32(truncatingIfNeeded: y)
    value = value &* 2_246_822_519 ^ (value >> 13)
    return RGBA(
      red: UInt8(truncatingIfNeeded: value), green: UInt8(truncatingIfNeeded: value >> 8),
      blue: UInt8(truncatingIfNeeded: value >> 16))
  }

  /// A PNG of a solid colour, as a comic page would be stored.
  private static func pngData(_ color: RGBA, width: Int, height: Int) throws -> Data {
    let picture = TestImages.solid(color, width: width, height: height)
    return try #require(ImageCodec.encode(picture, as: .png))
  }

  /// The colour at the centre of page `index`, rendered at a small width.
  private static func centreColour(of pdf: Data, page index: Int) throws -> RGBA {
    let picture = try PDFTools.render(pdf, page: index, width: 40)
    let raster = try #require(RasterImage(picture))
    return raster.pixel(x: raster.width / 2, y: raster.height / 2)
  }

  /// Draws `text` in large black letters on white, so the recogniser has clean input.
  private static func textPicture(_ text: String) throws -> CGImage {
    let width = 900
    let height = 220
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 96, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
        red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: 40, y: 60)
    CTLineDraw(line, context)
    return try #require(context.makeImage())
  }

  // MARK: - Compression

  @Test("compression makes a PDF of large pictures smaller")
  func compressionShrinksLargePictures() throws {
    let size = CGSize(width: 1600, height: 1200)
    let source = try Self.pdf(
      of: TestImages.image(width: 1600, height: 1200, pixel: Self.noise), size: size)
    let compressed = try PDFCompression.compress(source, quality: 0.5, maxSide: 800)
    #expect(compressed.count < source.count / 2)
    #expect(try PDFTools.pageCount(compressed) == 1)
  }

  @Test("compression keeps the number of pages and the page sizes")
  func compressionKeepsPages() throws {
    let size = CGSize(width: 300, height: 200)
    let page = try Self.pdf(of: TestImages.solid(Self.green, width: 300, height: 200), size: size)
    let source = try PDFTools.merge([page, page, page])
    let compressed = try PDFCompression.compress(source, quality: 0.8, maxSide: 600)
    #expect(try PDFTools.pageCount(compressed) == 3)

    let document = try #require(PDFDocument(data: compressed))
    let box = try #require(document.page(at: 2)).bounds(for: .mediaBox).size
    #expect(box == size)
  }

  @Test("compression never returns more bytes than it was given")
  func compressionNeverGrows() throws {
    let page = try Self.pdf(
      of: TestImages.solid(Self.blue, width: 64, height: 64), size: CGSize(width: 64, height: 64))
    let compressed = try PDFCompression.compress(page, quality: 1, maxSide: 4000)
    #expect(compressed.count <= page.count)
  }

  @Test("damaged data is refused by compression")
  func compressionRefusesDamagedData() {
    #expect(throws: PDFCompression.Failure.unreadable) {
      try PDFCompression.compress(Data("not a pdf".utf8), quality: 0.5, maxSide: 500)
    }
  }

  @Test("a turned page is compressed upright, at the size it is shown at")
  func compressionKeepsTurnedPagesUpright() throws {
    // Red on the left, blue on the right. Turned clockwise, red ends up on top.
    let halves = TestImages.halves(
      left: Self.red, right: Self.blue, width: 800, height: 400)
    let flat = try Self.pdf(of: halves, size: CGSize(width: 800, height: 400))
    let turned = try PDFTools.rotate(flat, quarterTurns: 1)

    let compressed = try PDFCompression.compress(turned, quality: 0.9, maxSide: 400)
    let document = try #require(PDFDocument(data: compressed))
    let size = try #require(document.page(at: 0)).bounds(for: .mediaBox).size
    #expect(size == CGSize(width: 400, height: 800))

    let picture = try PDFTools.render(compressed, page: 0, width: 40)
    let raster = try #require(RasterImage(picture))
    let top = raster.pixel(x: raster.width / 2, y: raster.height / 4)
    let bottom = raster.pixel(x: raster.width / 2, y: raster.height * 3 / 4)
    #expect(top.red > 180 && top.blue < 80)
    #expect(bottom.blue > 180 && bottom.red < 80)
  }

  // MARK: - Comic archives

  @Test("a comic gives one page per picture, sized as the picture, in name order")
  func comicPagesFollowNames() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "ComicInfo.xml", data: Data("<ComicInfo/>".utf8)),
      ZipWriter.Entry(
        name: "page 10.png", data: try Self.pngData(Self.blue, width: 90, height: 120)),
      ZipWriter.Entry(name: "__MACOSX/._page 1.png", data: Data("resource fork".utf8)),
      ZipWriter.Entry(
        name: "page 2.png", data: try Self.pngData(Self.green, width: 90, height: 120)),
      ZipWriter.Entry(name: "page 1.PNG", data: try Self.pngData(Self.red, width: 90, height: 120)),
    ])

    let pdf = try ComicConverter.pdf(fromArchive: archive)
    #expect(try PDFTools.pageCount(pdf) == 3)

    let document = try #require(PDFDocument(data: pdf))
    let size = try #require(document.page(at: 0)).bounds(for: .mediaBox).size
    #expect(size == CGSize(width: 90, height: 120))

    let first = try Self.centreColour(of: pdf, page: 0)
    let second = try Self.centreColour(of: pdf, page: 1)
    let third = try Self.centreColour(of: pdf, page: 2)
    #expect(first.red > 180 && first.green < 80)
    #expect(second.green > 150 && second.red < 80)
    #expect(third.blue > 180 && third.red < 80)
  }

  @Test("a CBR archive, a RAR of pictures, makes the same PDF as a CBZ")
  func comicFromRAR() throws {
    // A RAR 4 archive with one picture. The RAR reader checks the CRC of the picture before the
    // converter reads it.
    let png = try Self.pngData(Self.green, width: 90, height: 120)
    let rar = RARArchiveBuilder.rar4(name: "page 1.png", data: png)
    let pdf = try ComicConverter.pdf(fromArchive: rar)
    #expect(try PDFTools.pageCount(pdf) == 1)

    let document = try #require(PDFDocument(data: pdf))
    let size = try #require(document.page(at: 0)).bounds(for: .mediaBox).size
    #expect(size == CGSize(width: 90, height: 120))
  }

  @Test("an archive without pictures is refused")
  func comicWithoutPictures() throws {
    let empty = try ZipWriter.archive([])
    #expect(throws: ComicConverter.Failure.noPictures) {
      try ComicConverter.pdf(fromArchive: empty)
    }
    let text = try ZipWriter.archive([
      ZipWriter.Entry(name: "ComicInfo.xml", data: Data("<ComicInfo/>".utf8))
    ])
    #expect(throws: ComicConverter.Failure.noPictures) {
      try ComicConverter.pdf(fromArchive: text)
    }
  }

  @Test("data that is not a zip archive is refused as malformed")
  func comicNotAnArchive() {
    #expect(throws: ComicConverter.Failure.malformedArchive) {
      try ComicConverter.pdf(fromArchive: Data("not a zip".utf8))
    }
  }

  @Test("a corrupt picture is named in the error")
  func comicCorruptPicture() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "001.png", data: Data("broken".utf8))
    ])
    #expect(throws: ComicConverter.Failure.undecodablePicture(name: "001.png")) {
      try ComicConverter.pdf(fromArchive: archive)
    }
  }

  // MARK: - Searchable PDF

  @Test("the searchable PDF carries the recognised word as text on a page of the picture's size")
  func searchablePDFHasText() throws {
    let picture = try Self.textPicture("HELLO 2026")
    let data = try SearchablePDF.make(from: [picture], languages: ["en-US"])

    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 1)
    let page = try #require(document.page(at: 0))
    #expect(page.bounds(for: .mediaBox).size == CGSize(width: 900, height: 220))
    let text = try #require(page.string)
    #expect(text.uppercased().contains("HELLO"))
  }

  @Test("a searchable PDF needs at least one picture")
  func searchablePDFWithoutPictures() {
    #expect(throws: SearchablePDF.Failure.noPictures) {
      try SearchablePDF.make(from: [], languages: ["en-US"])
    }
  }
}
