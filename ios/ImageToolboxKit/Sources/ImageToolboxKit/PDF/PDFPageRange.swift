import Foundation

/// Turns the text a person types to pick pages into page indices.
public enum PDFPageRange {

  /// Zero-based indices for text such as `1,3-5,8-`. Numbers count from 1, `a-b` is a run that
  /// counts down when `a` is larger than `b`, `a-` runs to the last page and `-b` starts at the
  /// first. Entries are separated by commas, semicolons or spaces. Pages may repeat, and the order
  /// typed is the order returned. Blank text gives every page.
  ///
  /// Nil when an entry is not a number or a run, or a number lies outside 1...`pageCount`.
  public static func indices(from text: String, pageCount: Int) -> [Int]? {
    guard pageCount > 0 else { return nil }
    let separators = CharacterSet(charactersIn: ",; \t\n")
    let entries = text.components(separatedBy: separators).filter { !$0.isEmpty }
    guard !entries.isEmpty else { return Array(0..<pageCount) }

    var result: [Int] = []
    for entry in entries {
      guard let run = run(of: entry, pageCount: pageCount) else { return nil }
      result.append(contentsOf: run)
    }
    return result
  }

  /// The same pages as `indices(from:pageCount:)`, as a set with no order. Nil text rules as above.
  public static func set(from text: String, pageCount: Int) -> Set<Int>? {
    indices(from: text, pageCount: pageCount).map(Set.init)
  }

  private static func run(of entry: String, pageCount: Int) -> [Int]? {
    if !entry.contains("-"), let number = Int(entry) {
      return (1...pageCount).contains(number) ? [number - 1] : nil
    }
    let bounds = entry.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard bounds.count == 2, !(bounds[0].isEmpty && bounds[1].isEmpty) else { return nil }
    let first = bounds[0].isEmpty ? 1 : Int(bounds[0])
    let last = bounds[1].isEmpty ? pageCount : Int(bounds[1])
    guard let first, let last, (1...pageCount).contains(first), (1...pageCount).contains(last)
    else { return nil }
    return first <= last
      ? Array((first - 1)...(last - 1)) : Array(((last - 1)...(first - 1)).reversed())
  }
}
