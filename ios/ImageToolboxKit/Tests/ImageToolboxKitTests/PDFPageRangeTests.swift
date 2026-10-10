import Testing

@testable import ImageToolboxKit

@Suite("PDF page ranges")
struct PDFPageRangeTests {

  @Test("numbers and runs count from 1 and keep the order typed")
  func runsAndOrder() {
    #expect(PDFPageRange.indices(from: "1,3-5,8", pageCount: 9) == [0, 2, 3, 4, 7])
    #expect(PDFPageRange.indices(from: "3,1,2", pageCount: 3) == [2, 0, 1])
    #expect(PDFPageRange.indices(from: "2,2", pageCount: 3) == [1, 1])
  }

  @Test("a run with a larger first number counts down")
  func descendingRun() {
    #expect(PDFPageRange.indices(from: "5-3", pageCount: 5) == [4, 3, 2])
  }

  @Test("an open run goes to the first or the last page")
  func openRuns() {
    #expect(PDFPageRange.indices(from: "4-", pageCount: 6) == [3, 4, 5])
    #expect(PDFPageRange.indices(from: "-2", pageCount: 6) == [0, 1])
  }

  @Test("blank text gives every page")
  func blankText() {
    #expect(PDFPageRange.indices(from: "", pageCount: 3) == [0, 1, 2])
    #expect(PDFPageRange.indices(from: "  ", pageCount: 3) == [0, 1, 2])
  }

  @Test("commas, semicolons and spaces all separate entries")
  func separators() {
    #expect(PDFPageRange.indices(from: "1; 2 ,3", pageCount: 3) == [0, 1, 2])
  }

  @Test(
    "text that is not pages is refused",
    arguments: ["0", "4", "a", "1-x", "--1", "1-9", "2-0", "1.5", "-"])
  func invalid(text: String) {
    #expect(PDFPageRange.indices(from: text, pageCount: 3) == nil)
  }

  @Test("a document with no pages has no valid text")
  func emptyDocument() {
    #expect(PDFPageRange.indices(from: "", pageCount: 0) == nil)
  }

  @Test("the set form drops the order and repeats")
  func setForm() {
    #expect(PDFPageRange.set(from: "3,1,3", pageCount: 3) == [0, 2])
  }
}
