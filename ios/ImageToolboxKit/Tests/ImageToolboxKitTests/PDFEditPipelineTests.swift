import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF tools through the edit pipeline")
struct PDFEditPipelineTests {

  /// Runs `tool` on `data`, with the options that `edit` sets.
  private static func run(
    _ tool: PDFEditTool, _ data: Data, _ edit: (inout PDFEditOptions) -> Void = { _ in }
  ) throws -> PDFEditOutput {
    var options = PDFEditOptions()
    edit(&options)
    return try PDFEditPipeline.run(tool, on: data, options: options)
  }

  /// A document with one page per number, each page holding "Page n".
  private static func pages(_ count: Int) throws -> Data {
    try PDFFixtures.texts((1...count).map { "Page \($0)" })
  }

  @Test("remove pages keeps the others, and an empty choice is refused")
  func removePages() throws {
    let output = try Self.run(.removePages, try Self.pages(3)) { $0.pagesText = "2" }
    #expect(try PDFFixtures.texts(of: output.data) == ["Page 1", "Page 3"])
    #expect(throws: PDFEditFailure.invalidParameter) {
      try Self.run(.removePages, try Self.pages(3))
    }
  }

  @Test("split makes a zip with the parts of the chosen size")
  func split() throws {
    let output = try Self.run(.splitIntoParts, try Self.pages(5)) { $0.partSize = 2 }
    #expect(output.kind == .archive)
    #expect(output.fileName(baseName: "report") == "report_parts.zip")
    let entries = try PDFFixtures.archiveEntries(output.data)
    #expect(entries.map(\.name) == ["page_1.pdf", "page_2.pdf", "page_3.pdf"])
    #expect(try PDFTools.pageCount(entries[2].data) == 1)
  }

  @Test("turn pages turns each named page and leaves the others")
  func turnPages() throws {
    let output = try Self.run(.turnPages, try Self.pages(3)) { $0.pageTurnsText = "2:90, 3:-90" }
    let document = try #require(PDFDocument(data: output.data))
    #expect(document.page(at: 0)?.rotation == 0)
    #expect(document.page(at: 1)?.rotation == 90)
    #expect(document.page(at: 2)?.rotation == 270)
  }

  @Test("turn pages refuses a turn that is not a quarter turn and a page outside the document")
  func turnPagesInvalid() throws {
    let data = try Self.pages(3)
    #expect(throws: PDFEditFailure.invalidParameter) {
      try Self.run(.turnPages, data) { $0.pageTurnsText = "1:45" }
    }
    #expect(throws: PDFEditFailure.pageOutOfRange) {
      try Self.run(.turnPages, data) { $0.pageTurnsText = "4:90" }
    }
  }

  @Test("watermark marks only the chosen pages")
  func watermarkPages() throws {
    let data = try PDFFixtures.solid([PDFFixtures.white, PDFFixtures.white])
    let output = try Self.run(.watermark, data) { options in
      options.pagesText = "2"
      options.watermark = PDFTextWatermark(text: "DRAFT", widthFraction: 1, angle: 0, opacity: 1)
    }
    let middle = CGRect(x: 0, y: 0.35, width: 1, height: 0.3)
    let first = try PDFTools.render(output.data, page: 0, width: 600)
    let second = try PDFTools.render(output.data, page: 1, width: 600)
    #expect(try !PDFFixtures.hasInk(in: first, region: middle))
    #expect(try PDFFixtures.hasInk(in: second, region: middle))
  }

  @Test("page numbers keep every page")
  func pageNumbers() throws {
    let output = try Self.run(.pageNumbers, try Self.pages(2))
    #expect(output.kind == .document)
    #expect(try PDFTools.pageCount(output.data) == 2)
  }

  @Test("extract images finds the picture that a stamp put in the document")
  func extractImages() throws {
    let picture = TestImages.solid(PDFFixtures.green, width: 40, height: 20)
    let stamped = try PDFImageStamp(image: picture).apply(to: try Self.pages(1))
    let output = try Self.run(.extractImages, stamped)
    #expect(output.kind == .archive)
    #expect(try PDFFixtures.archiveEntries(output.data).count == 1)
  }

  @Test("extract images on a document without pictures finds nothing")
  func extractImagesNothing() throws {
    #expect(throws: PDFEditFailure.nothingFound) {
      try Self.run(.extractImages, try Self.pages(1))
    }
  }

  @Test("PDF to images makes a zip with one picture per page")
  func pagesToImages() throws {
    let output = try Self.run(.pagesToImages, try Self.pages(2)) { $0.imageFormat = .png }
    #expect(output.kind == .archive)
    #expect(try PDFFixtures.archiveEntries(output.data).count == 2)
  }

  @Test("crop cuts the chosen share from each side")
  func crop() throws {
    let data = try PDFFixtures.solid([PDFFixtures.white], size: CGSize(width: 200, height: 100))
    let cut = PDFPageLayout.Crop(left: 0.25, right: 0.25)
    let output = try Self.run(.crop, data) { $0.crop = cut }
    #expect(try PDFFixtures.pageSize(of: output.data) == CGSize(width: 100, height: 100))
  }

  @Test("metadata writes the fields that are given")
  func metadata() throws {
    let output = try Self.run(.metadata, try Self.pages(1)) {
      $0.metadata = PDFMetadata(title: "Report", author: "Ada")
    }
    let read = try PDFMetadata.read(from: output.data)
    #expect(read.title == "Report")
    #expect(read.author == "Ada")
  }

  @Test("protect locks the file, and unlock needs the password")
  func protectAndUnlock() throws {
    let locked = try Self.run(.protect, try Self.pages(2)) { $0.password = "secret" }.data
    #expect(PDFSecurity.state(of: locked) == .locked)
    #expect(throws: PDFEditFailure.wrongPassword) {
      try Self.run(.unlock, locked) { $0.password = "nope" }
    }
    let open = try Self.run(.unlock, locked) { $0.password = "secret" }.data
    #expect(PDFSecurity.state(of: open) == .open)
    #expect(try PDFFixtures.texts(of: open) == ["Page 1", "Page 2"])
  }

  @Test("grayscale leaves the channels of each pixel equal")
  func grayscale() throws {
    let output = try Self.run(.grayscale, try PDFFixtures.solid([PDFFixtures.red]))
    let pixel = try PDFFixtures.colour(of: output.data)
    #expect(abs(Int(pixel.red) - Int(pixel.green)) <= 2)
    #expect(abs(Int(pixel.green) - Int(pixel.blue)) <= 2)
  }

  @Test("repair, flatten, align rotation and dark mode keep the pages")
  func pageKeepingTools() throws {
    let data = try Self.pages(2)
    for tool in [PDFEditTool.repair, .flatten, .alignRotation, .darkMode] {
      let output = try Self.run(tool, data)
      #expect(try PDFTools.pageCount(output.data) == 2, "\(tool)")
    }
  }

  @Test("extract text gives the words of the pages as a text file")
  func extractText() throws {
    let output = try Self.run(.extractText, try Self.pages(2))
    #expect(output.kind == .text)
    #expect(output.fileExtension == "txt")
    #expect(String(decoding: output.data, as: UTF8.self).contains("Page 2"))
  }
}
