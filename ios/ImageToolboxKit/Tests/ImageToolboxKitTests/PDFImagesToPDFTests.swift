import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("PDF pictures to PDF width rule")
struct PDFImagesToPDFTests {

  private static let red = RGBA(red: 230, green: 20, blue: 20)
  private static let blue = RGBA(red: 20, green: 40, blue: 230)

  /// Two pictures: 100 x 50 and 200 x 100 pixels.
  private static func pictures() -> [CGImage] {
    [
      TestImages.solid(red, width: 100, height: 50),
      TestImages.solid(blue, width: 200, height: 100),
    ]
  }

  @Test("without a width rule each page is as large as its picture")
  func noWidthRule() throws {
    let pdf = try ImagesToPDF.make(from: Self.pictures())
    #expect(try PDFFixtures.pageSize(of: pdf, page: 0) == CGSize(width: 100, height: 50))
    #expect(try PDFFixtures.pageSize(of: pdf, page: 1) == CGSize(width: 200, height: 100))
  }

  @Test("the widest rule makes every picture as wide as the widest, keeping its proportions")
  func widestRule() throws {
    let options = ImagesToPDF.Options(widthRule: .widest)
    let pdf = try ImagesToPDF.make(from: Self.pictures(), options: options)
    #expect(try PDFFixtures.pageSize(of: pdf, page: 0) == CGSize(width: 200, height: 100))
    #expect(try PDFFixtures.pageSize(of: pdf, page: 1) == CGSize(width: 200, height: 100))
  }

  @Test("the narrowest rule makes every picture as wide as the narrowest")
  func narrowestRule() throws {
    let options = ImagesToPDF.Options(widthRule: .narrowest)
    let pdf = try ImagesToPDF.make(from: Self.pictures(), options: options)
    #expect(try PDFFixtures.pageSize(of: pdf, page: 0) == CGSize(width: 100, height: 50))
    #expect(try PDFFixtures.pageSize(of: pdf, page: 1) == CGSize(width: 100, height: 50))
  }

  @Test("the width rule applies after the scale, so the scaled widths decide")
  func widthRuleAfterScale() throws {
    let options = ImagesToPDF.Options(scale: 0.5, widthRule: .widest)
    let pdf = try ImagesToPDF.make(from: Self.pictures(), options: options)
    #expect(try PDFFixtures.pageSize(of: pdf, page: 0) == CGSize(width: 100, height: 50))
    #expect(try PDFFixtures.pageSize(of: pdf, page: 1) == CGSize(width: 100, height: 50))
  }

  @Test("a quality or a scale outside its range is refused")
  func rangesAreChecked() {
    let pictures = Self.pictures()
    #expect(throws: PDFEditFailure.invalidParameter) {
      try ImagesToPDF.make(from: pictures, options: ImagesToPDF.Options(quality: 0))
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try ImagesToPDF.make(from: pictures, options: ImagesToPDF.Options(scale: 1.5))
    }
    #expect(throws: PDFEditFailure.noPages) {
      try ImagesToPDF.make(from: [])
    }
  }
}
