import Foundation
import PDFKit
import Testing

@testable import ImageToolboxKit

@Suite("PDF page editing")
struct PDFPageEditingTests {

  private static func document() throws -> Data {
    try PDFFixtures.texts(["alpha", "bravo", "charlie", "delta", "echo"])
  }

  @Test("removing pages keeps the others in their order")
  func removePages() throws {
    let result = try PDFPageEditing.remove(try Self.document(), pages: [1, 3])
    #expect(try PDFFixtures.texts(of: result) == ["alpha", "charlie", "echo"])
  }

  @Test("removing every page is refused")
  func removeEverything() throws {
    #expect(throws: PDFEditFailure.noPages) {
      try PDFPageEditing.remove(try Self.document(), pages: [0, 1, 2, 3, 4])
    }
  }

  @Test("a page outside the document is refused")
  func removeOutOfRange() throws {
    #expect(throws: PDFEditFailure.pageOutOfRange) {
      try PDFPageEditing.remove(try Self.document(), pages: [5])
    }
  }

  @Test("rotating chosen pages turns only those pages")
  func rotateSomePages() throws {
    let result = try PDFPageEditing.rotate(try Self.document(), by: 90, pages: [0, 2])
    let document = try #require(PDFDocument(data: result))
    let turns = (0..<document.pageCount).map { document.page(at: $0)?.rotation }
    #expect(turns == [90, 0, 90, 0, 0])
  }

  @Test("a turn adds to the turn a page has, and a negative turn goes the other way")
  func rotateAdds() throws {
    let once = try PDFPageEditing.rotate(try Self.document(), by: 270)
    let twice = try PDFPageEditing.rotate(once, by: 180)
    let back = try PDFPageEditing.rotate(twice, by: -90)
    let rotations = [once, twice, back].map { data in
      PDFDocument(data: data)?.page(at: 0)?.rotation
    }
    #expect(rotations == [270, 90, 0])
  }

  @Test("a turn that is not a multiple of 90 is refused")
  func rotateInvalid() throws {
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageEditing.rotate(try Self.document(), by: 45)
    }
  }

  @Test("each page can be turned by its own amount")
  func rotatePerPage() throws {
    let result = try PDFPageEditing.rotate(try Self.document(), degreesPerPage: [90, 180, 270])
    let document = try #require(PDFDocument(data: result))
    let turns = (0..<document.pageCount).map { document.page(at: $0)?.rotation }
    #expect(turns == [90, 180, 270, 0, 0])
  }

  @Test("pages are aligned to the turn that most pages have")
  func alignRotations() throws {
    let source = try PDFPageEditing.rotate(
      try Self.document(), degreesPerPage: [90, 90, 0, 90, 180])
    #expect(try PDFPageEditing.alignedRotations(source) == [0, 0, 90, 0, 270])
    let aligned = try PDFPageEditing.alignRotations(source)
    let document = try #require(PDFDocument(data: aligned))
    let turns = Set((0..<document.pageCount).compactMap { document.page(at: $0)?.rotation })
    #expect(turns == [90])
  }

  @Test("a document splits into parts of the chosen size, the last one shorter")
  func splitParts() throws {
    let parts = try PDFPageEditing.split(try Self.document(), every: 2)
    #expect(
      try parts.map { try PDFFixtures.texts(of: $0) } == [
        ["alpha", "bravo"], ["charlie", "delta"], ["echo"],
      ])
  }

  @Test("the split archive names its parts in order")
  func splitArchive() throws {
    let archive = try PDFPageEditing.splitArchive(try Self.document(), every: 2, baseName: "book")
    let entries = try PDFFixtures.archiveEntries(archive)
    #expect(entries.map(\.name) == ["book_1.pdf", "book_2.pdf", "book_3.pdf"])
    #expect(try PDFTools.pageCount(entries[2].data) == 1)
  }

  @Test("a part size of zero is refused")
  func splitInvalid() throws {
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageEditing.split(try Self.document(), every: 0)
    }
  }

  @Test("damaged data is refused")
  func unreadable() {
    #expect(throws: PDFEditFailure.unreadable) {
      try PDFPageEditing.remove(Data("not a pdf".utf8), pages: [0])
    }
  }
}
