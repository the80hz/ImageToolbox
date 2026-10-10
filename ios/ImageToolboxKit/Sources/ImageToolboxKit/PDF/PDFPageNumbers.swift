import CoreGraphics
import Foundation

/// Writes a number on each page of a document. The pages are drawn again into a new document, so
/// text and vector graphics stay, but links, form fields and outlines are not kept.
public struct PDFPageNumbers: Equatable, Sendable {

  /// Where on the page the label goes.
  public enum Position: String, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
  }

  /// The label. `{n}` becomes the page number and `{total}` the number of pages.
  public var format: String
  public var position: Position
  /// Text size in points.
  public var fontSize: Double
  public var colour: RGBA
  /// The number on the first page.
  public var firstNumber: Int

  public init(
    format: String = "Page {n} of {total}", position: Position = .bottomCenter,
    fontSize: Double = 12, colour: RGBA = RGBA(red: 110, green: 110, blue: 110),
    firstNumber: Int = 1
  ) {
    self.format = format
    self.position = position
    self.fontSize = fontSize
    self.colour = colour
    self.firstNumber = firstNumber
  }

  private static let sideMargin: CGFloat = 16
  private static let edgeMargin: CGFloat = 20

  /// The document with the label on every page. A label that is blank on every page, or a size
  /// that is not positive, throws `invalidParameter`.
  public func apply(to data: Data) throws -> Data {
    guard fontSize > 0 else { throw PDFEditFailure.invalidParameter }
    let source = try PDFSourcePages(data)
    let total = source.pageCount
    guard PDFTextLine(label(page: 0, of: total), fontSize: fontSize) != nil else {
      throw PDFEditFailure.invalidParameter
    }
    return try source.overlay(pages: nil) { index, size, context in
      guard let line = PDFTextLine(label(page: index, of: total), fontSize: fontSize) else {
        return
      }
      context.setFillColor(colour.cgColor())
      line.draw(at: origin(of: line, on: size), in: context)
    }
  }

  /// The label for the page at the zero-based `index`.
  func label(page index: Int, of total: Int) -> String {
    format.replacingOccurrences(of: "{total}", with: String(total))
      .replacingOccurrences(of: "{n}", with: String(index + firstNumber))
  }

  /// The start of the text's baseline, so that the text sits at `position`.
  private func origin(of line: PDFTextLine, on page: CGSize) -> CGPoint {
    let x: CGFloat
    switch position {
    case .topLeft, .centerLeft, .bottomLeft: x = Self.sideMargin
    case .topCenter, .center, .bottomCenter: x = (page.width - line.width) / 2
    case .topRight, .centerRight, .bottomRight: x = page.width - Self.sideMargin - line.width
    }
    let y: CGFloat
    switch position {
    case .topLeft, .topCenter, .topRight: y = page.height - Self.edgeMargin - line.ascent
    case .centerLeft, .center, .centerRight: y = page.height / 2 - (line.ascent - line.descent) / 2
    case .bottomLeft, .bottomCenter, .bottomRight: y = Self.edgeMargin + line.descent
    }
    return CGPoint(x: x, y: y)
  }
}
