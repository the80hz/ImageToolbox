import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF comic options")
struct PDFComicOptionsTests {

  private static let red = RGBA(red: 230, green: 20, blue: 20)
  private static let green = RGBA(red: 20, green: 200, blue: 40)
  private static let blue = RGBA(red: 20, green: 40, blue: 230)

  private static func pngData(_ color: RGBA, width: Int, height: Int) throws -> Data {
    let picture = TestImages.solid(color, width: width, height: height)
    return try #require(ImageCodec.encode(picture, as: .png))
  }

  /// Pseudo-random colours, which PNG cannot shrink.
  private static func noisePNG(width: Int, height: Int) throws -> Data {
    let picture = TestImages.image(width: width, height: height) { x, y in
      var value = UInt32(truncatingIfNeeded: x) &* 2_654_435_761 ^ UInt32(truncatingIfNeeded: y)
      value = value &* 2_246_822_519 ^ (value >> 13)
      return RGBA(
        red: UInt8(truncatingIfNeeded: value), green: UInt8(truncatingIfNeeded: value >> 8),
        blue: UInt8(truncatingIfNeeded: value >> 16))
    }
    return try #require(ImageCodec.encode(picture, as: .png))
  }

  /// A picture of `width` x `height` with its left half `left` and its right half `right`.
  private static func halves(left: RGBA, right: RGBA, width: Int, height: Int) throws -> Data {
    let picture = TestImages.image(width: width, height: height) { x, _ in
      x < width / 2 ? left : right
    }
    return try #require(ImageCodec.encode(picture, as: .png))
  }

  /// The colour at the centre of page `index`, rendered at a small width.
  private static func centreColour(of pdf: Data, page index: Int) throws -> RGBA {
    try PDFFixtures.colour(of: pdf, page: index)
  }

  private static func archive(_ entries: [(String, Data)]) throws -> Data {
    try ZipWriter.archive(entries.map { ZipWriter.Entry(name: $0.0, data: $0.1) })
  }

  @Test("reversing the order reads the last picture first")
  func reversedOrder() throws {
    let data = try Self.archive([
      ("a.png", try Self.pngData(Self.red, width: 90, height: 120)),
      ("b.png", try Self.pngData(Self.green, width: 90, height: 120)),
      ("c.png", try Self.pngData(Self.blue, width: 90, height: 120)),
    ])
    let pdf = try ComicConverter.pdf(
      fromArchive: data, options: ComicConverter.Options(reversesOrder: true))
    #expect(try PDFTools.pageCount(pdf) == 3)
    #expect(try Self.centreColour(of: pdf, page: 0).blue > 180)
    #expect(try Self.centreColour(of: pdf, page: 2).red > 180)
  }

  @Test("skipping the cover leaves out the first picture in name order")
  func skippedCover() throws {
    let data = try Self.archive([
      ("02.png", try Self.pngData(Self.green, width: 90, height: 120)),
      ("01.png", try Self.pngData(Self.red, width: 90, height: 120)),
      ("03.png", try Self.pngData(Self.blue, width: 90, height: 120)),
    ])
    let pdf = try ComicConverter.pdf(
      fromArchive: data, options: ComicConverter.Options(skipsCover: true))
    #expect(try PDFTools.pageCount(pdf) == 2)
    #expect(try Self.centreColour(of: pdf, page: 0).green > 150)
    #expect(try Self.centreColour(of: pdf, page: 1).blue > 180)
  }

  @Test("a comic whose only picture is the cover has no pages left")
  func coverOnlyComic() throws {
    let data = try Self.archive([
      ("01.png", try Self.pngData(Self.red, width: 90, height: 120))
    ])
    #expect(throws: ComicConverter.Failure.noPictures) {
      try ComicConverter.pdf(fromArchive: data, options: ComicConverter.Options(skipsCover: true))
    }
  }

  @Test("a picture wider than 1.2 times its height is split into two pages, left first")
  func splitWidePicture() throws {
    let data = try Self.archive([
      ("spread.png", try Self.halves(left: Self.red, right: Self.green, width: 200, height: 100))
    ])
    let pdf = try ComicConverter.pdf(
      fromArchive: data, options: ComicConverter.Options(splitsWidePictures: true))
    #expect(try PDFTools.pageCount(pdf) == 2)
    #expect(try PDFFixtures.pageSize(of: pdf, page: 0) == CGSize(width: 100, height: 100))
    #expect(try Self.centreColour(of: pdf, page: 0).red > 180)
    #expect(try Self.centreColour(of: pdf, page: 1).green > 150)
  }

  @Test("right to left reading puts the right half first")
  func splitRightToLeft() throws {
    let data = try Self.archive([
      ("spread.png", try Self.halves(left: Self.red, right: Self.green, width: 200, height: 100))
    ])
    let options = ComicConverter.Options(splitsWidePictures: true, rightToLeft: true)
    let pdf = try ComicConverter.pdf(fromArchive: data, options: options)
    #expect(try PDFTools.pageCount(pdf) == 2)
    #expect(try Self.centreColour(of: pdf, page: 0).green > 150)
    #expect(try Self.centreColour(of: pdf, page: 1).red > 180)
  }

  @Test("a picture that is not wider than 1.2 times its height is kept whole")
  func narrowPictureIsNotSplit() throws {
    let data = try Self.archive([
      ("page.png", try Self.halves(left: Self.red, right: Self.green, width: 110, height: 100))
    ])
    let pdf = try ComicConverter.pdf(
      fromArchive: data, options: ComicConverter.Options(splitsWidePictures: true))
    #expect(try PDFTools.pageCount(pdf) == 1)
  }

  @Test("a paper size gives every page that size, with the picture fitted inside")
  func paperSize() throws {
    let data = try Self.archive([
      ("a.png", try Self.pngData(Self.red, width: 100, height: 50)),
      ("b.png", try Self.pngData(Self.blue, width: 60, height: 120)),
    ])
    let options = ComicConverter.Options(pageSize: PDFPageSize.a4)
    let pdf = try ComicConverter.pdf(fromArchive: data, options: options)
    #expect(try PDFTools.pageCount(pdf) == 2)
    for index in 0..<2 {
      let size = try PDFFixtures.pageSize(of: pdf, page: index)
      #expect(abs(size.width - 595) < 0.5)
      #expect(abs(size.height - 842) < 0.5)
    }
  }

  @Test("an automatic page is at most 14,400 points on its longer side")
  func longPictureIsCapped() throws {
    let data = try Self.archive([
      ("long.png", try Self.pngData(Self.red, width: 15_000, height: 10))
    ])
    let pdf = try ComicConverter.pdf(fromArchive: data)
    let size = try PDFFixtures.pageSize(of: pdf)
    #expect(size.width == 14_400)
    #expect(abs(size.height - 9.6) < 0.01)
  }

  @Test("a quality outside 0 < quality <= 1 is refused")
  func qualityIsValidated() throws {
    let data = try Self.archive([("a.png", try Self.pngData(Self.red, width: 90, height: 120))])
    for quality in [0.0, -0.5, 1.5] {
      #expect(throws: ComicConverter.Failure.invalidParameter) {
        try ComicConverter.pdf(
          fromArchive: data, options: ComicConverter.Options(quality: quality))
      }
    }
  }

  @Test("a lower quality re-encodes the pictures as JPEG and makes a smaller PDF")
  func lowerQualityIsSmaller() throws {
    let data = try Self.archive([("noise.png", try Self.noisePNG(width: 300, height: 300))])
    let full = try ComicConverter.pdf(fromArchive: data)
    let low = try ComicConverter.pdf(
      fromArchive: data, options: ComicConverter.Options(quality: 0.2))
    #expect(try PDFTools.pageCount(low) == 1)
    #expect(low.count < full.count)
  }
}
