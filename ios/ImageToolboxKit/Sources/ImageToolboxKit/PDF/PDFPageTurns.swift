import Foundation

/// Turns the text a person types to turn single pages, such as `3:90, 5:270`, into one turn for
/// every page of the document.
public enum PDFPageTurns {

  /// The turn of each of `pageCount` pages, in degrees clockwise, 0 for a page that is not named.
  /// An entry is a page number counting from 1, a colon and a turn that is a multiple of 90,
  /// positive or negative. Entries are separated by commas, semicolons or spaces. A page may be
  /// named once.
  ///
  /// Blank text, an entry of another form, a turn that is not a multiple of 90 or a page named
  /// twice throws `invalidParameter`. A page number outside the document throws `pageOutOfRange`.
  public static func degrees(from text: String, pageCount: Int) throws -> [Int] {
    let separators = CharacterSet(charactersIn: ",; \t\n")
    let entries = text.components(separatedBy: separators).filter { !$0.isEmpty }
    guard !entries.isEmpty else { throw PDFEditFailure.invalidParameter }
    var degrees = [Int](repeating: 0, count: pageCount)
    var named = Set<Int>()
    for entry in entries {
      let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, let number = Int(parts[0]), let turn = Int(parts[1]), turn % 90 == 0
      else { throw PDFEditFailure.invalidParameter }
      guard number >= 1, number <= pageCount else { throw PDFEditFailure.pageOutOfRange }
      guard named.insert(number).inserted else { throw PDFEditFailure.invalidParameter }
      degrees[number - 1] = turn
    }
    return degrees
  }
}
