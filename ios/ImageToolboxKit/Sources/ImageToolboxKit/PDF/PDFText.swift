import CoreGraphics
import Foundation
import PDFKit

/// Reads the text of a PDF: the text stored in the file, and for pages that hold only a picture,
/// the text that Vision recognises in it on the device.
public enum PDFText {

  /// The text of each page.
  public struct Extraction: Equatable, Sendable {
    /// One entry for each page, trimmed. A page with no text is an empty string.
    public let pages: [String]
    /// The number of pages whose text was recognised in a picture of the page.
    public let recognisedPages: Int

    /// The pages joined, with a blank line between them and empty pages left out.
    public var text: String {
      pages.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
  }

  /// Pages are drawn at 200 dpi for recognition, and no larger than this on the longer side.
  private static let recognitionScale = 200.0 / 72.0
  private static let recognitionMaximumSide = 3_000

  /// The text of every page. A page with no stored text is read from a picture of it when
  /// `languages` is not empty. Errors from `TextRecognizer` are passed on.
  public static func extract(from data: Data, recognising languages: [String] = [])
    throws -> Extraction
  {
    let document = try PDFKitAccess.open(data)
    var source: PDFSourcePages?
    var texts: [String] = []
    var recognised = 0
    for index in 0..<document.pageCount {
      var text =
        document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if text.isEmpty, !languages.isEmpty {
        source = try source ?? PDFSourcePages(data)
        let read = try recognise(source, page: index, languages: languages)
        if !read.isEmpty { recognised += 1 }
        text = read
      }
      texts.append(text)
    }
    return Extraction(pages: texts, recognisedPages: recognised)
  }

  private static func recognise(
    _ source: PDFSourcePages?, page index: Int, languages: [String]
  ) throws -> String {
    guard
      let picture = source?.render(
        index, scale: recognitionScale, maximumSide: recognitionMaximumSide)
    else { throw PDFEditFailure.unreadable }
    return try TextRecognizer.recognize(picture, languages: languages)
      .map(\.text).joined(separator: "\n")
  }
}
