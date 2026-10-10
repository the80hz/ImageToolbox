import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("PDF edit session")
@MainActor
struct PDFEditSessionTests {

  @Test("a run keeps the file of its tool, and a change of tool drops it")
  func runKeepsFile() async throws {
    let session = PDFEditSession()
    session.setDocument(try PDFFixtures.texts(["A", "B", "C"]))
    session.options.partSize = 2
    await session.run()
    #expect(session.output?.kind == .archive)
    #expect(session.failure == nil)
    session.tool = .grayscale
    #expect(session.output == nil)
  }

  @Test("a run without a document does nothing")
  func runWithoutDocument() async {
    let session = PDFEditSession()
    await session.run()
    #expect(session.output == nil)
    #expect(session.failure == nil)
  }

  @Test("a failed run keeps its reason until an option changes")
  func failureUntilChange() async throws {
    let session = PDFEditSession()
    session.setDocument(try PDFFixtures.texts(["A", "B"]))
    session.tool = .removePages
    await session.run()
    #expect(session.failure == .invalidParameter)
    session.options.pagesText = "2"
    #expect(session.failure == nil)
    await session.run()
    let output = try #require(session.output)
    #expect(try PDFTools.pageCount(output.data) == 1)
  }

  @Test("choosing a document reads its metadata for the metadata tool")
  func metadataFromDocument() throws {
    let session = PDFEditSession()
    let data = try PDFFixtures.make([PDFFixtures.Page()], title: "Report", author: "Ada")
    session.setDocument(data)
    #expect(session.options.metadata.title == "Report")
    #expect(session.options.metadata.author == "Ada")
  }

  @Test("a locked document is kept, so the unlock tool can open it")
  func lockedDocument() async throws {
    let locked = try PDFSecurity.protect(try PDFFixtures.texts(["A"]), password: "pw")
    let session = PDFEditSession()
    session.setDocument(locked)
    session.tool = .unlock
    session.options.password = "pw"
    await session.run()
    #expect(session.output?.kind == .document)
    #expect(session.failure == nil)
  }

  @Test("clearing the document drops the document and the file")
  func clearDocument() async throws {
    let session = PDFEditSession()
    session.setDocument(try PDFFixtures.texts(["A"]))
    session.tool = .grayscale
    await session.run()
    session.setDocument(nil)
    #expect(session.document == nil)
    #expect(session.output == nil)
  }
}

@Suite("Per-page turns text")
struct PDFPageTurnsTests {

  @Test("each entry sets the turn of its page, and the other pages stay upright")
  func parses() throws {
    #expect(try PDFPageTurns.degrees(from: "1:90, 3:-90", pageCount: 3) == [90, 0, -90])
    #expect(try PDFPageTurns.degrees(from: "2:180;3:0 1:270", pageCount: 3) == [270, 180, 0])
  }

  @Test("blank text, a turn that is not a quarter turn and a page named twice are refused")
  func refusesMalformed() {
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageTurns.degrees(from: " ", pageCount: 3)
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageTurns.degrees(from: "1:45", pageCount: 3)
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageTurns.degrees(from: "1", pageCount: 3)
    }
    #expect(throws: PDFEditFailure.invalidParameter) {
      try PDFPageTurns.degrees(from: "1:90,1:180", pageCount: 3)
    }
  }

  @Test("a page number outside the document is refused")
  func refusesOutOfRange() {
    #expect(throws: PDFEditFailure.pageOutOfRange) {
      try PDFPageTurns.degrees(from: "0:90", pageCount: 3)
    }
    #expect(throws: PDFEditFailure.pageOutOfRange) {
      try PDFPageTurns.degrees(from: "4:90", pageCount: 3)
    }
  }
}
