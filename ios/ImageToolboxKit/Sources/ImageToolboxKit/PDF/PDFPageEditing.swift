import Foundation
import PDFKit

/// Page-level edits that keep the pages as they are, with PDFKit: deleting pages, turning chosen
/// pages, and cutting a document into parts. Splitting a range and reordering pages are
/// `PDFTools.extract` with the indices from `PDFPageRange`.
public enum PDFPageEditing {

  /// The document without the pages in `pages` (zero-based). Removing every page throws `noPages`.
  public static func remove(_ data: Data, pages: Set<Int>) throws -> Data {
    let source = try PDFKitAccess.open(data)
    guard pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) else {
      throw PDFEditFailure.pageOutOfRange
    }
    let kept = (0..<source.pageCount).filter { !pages.contains($0) }
    return try PDFKitAccess.write(PDFKitAccess.copy(source, pages: kept))
  }

  /// The document with the pages in `pages` turned clockwise by `degrees` more, on top of the
  /// turn they have. A multiple of 90, positive or negative. Nil `pages` turns every page.
  public static func rotate(_ data: Data, by degrees: Int, pages: Set<Int>? = nil) throws -> Data {
    guard degrees % 90 == 0 else { throw PDFEditFailure.invalidParameter }
    let source = try PDFKitAccess.open(data)
    if let pages, !pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) {
      throw PDFEditFailure.pageOutOfRange
    }
    for index in 0..<source.pageCount where pages?.contains(index) ?? true {
      if let page = source.page(at: index) {
        page.rotation = normalized(page.rotation, add: degrees)
      }
    }
    return try PDFKitAccess.write(source)
  }

  /// The document with page `i` turned clockwise by `degrees[i]` more. Pages past the end of the
  /// array are left as they are. Each value is a multiple of 90.
  public static func rotate(_ data: Data, degreesPerPage degrees: [Int]) throws -> Data {
    guard degrees.allSatisfy({ $0 % 90 == 0 }) else { throw PDFEditFailure.invalidParameter }
    let source = try PDFKitAccess.open(data)
    for (index, turn) in degrees.enumerated() where index < source.pageCount {
      if let page = source.page(at: index) { page.rotation = normalized(page.rotation, add: turn) }
    }
    return try PDFKitAccess.write(source)
  }

  /// The turn, in degrees, that each page needs so that all pages are turned like most of them.
  public static func alignedRotations(_ data: Data) throws -> [Int] {
    let source = try PDFKitAccess.open(data)
    let current = (0..<source.pageCount).map {
      normalized(source.page(at: $0)?.rotation ?? 0, add: 0)
    }
    let counts = Dictionary(grouping: current, by: { $0 }).mapValues(\.count)
    // The smaller angle wins a tie, so the result does not depend on dictionary order.
    let majority = counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0
    return current.map { normalized(majority, add: -$0) }
  }

  /// The document with every page turned like most of them: see `alignedRotations`.
  public static func alignRotations(_ data: Data) throws -> Data {
    try rotate(data, degreesPerPage: alignedRotations(data))
  }

  /// Parts of `size` pages each, in order. The last part holds what is left.
  public static func split(_ data: Data, every size: Int) throws -> [Data] {
    guard size > 0 else { throw PDFEditFailure.invalidParameter }
    let count = try PDFKitAccess.open(data).pageCount
    return try stride(from: 0, to: count, by: size).map { start in
      // Each part reads the data again, so no part shares page objects with another.
      let source = try PDFKitAccess.open(data)
      let indices = Array(start..<min(start + size, count))
      return try PDFKitAccess.write(PDFKitAccess.copy(source, pages: indices))
    }
  }

  /// A zip of the parts from `split`, named `baseName_1.pdf`, `baseName_2.pdf` and so on.
  public static func splitArchive(_ data: Data, every size: Int, baseName: String) throws -> Data {
    let entries = try split(data, every: size).enumerated().map { index, part in
      ZipWriter.Entry(name: "\(baseName)_\(index + 1).pdf", data: part)
    }
    do {
      return try ZipWriter.archive(entries)
    } catch {
      throw PDFEditFailure.writeFailed
    }
  }

  private static func normalized(_ rotation: Int, add degrees: Int) -> Int {
    (((rotation + degrees) % 360) + 360) % 360
  }
}
