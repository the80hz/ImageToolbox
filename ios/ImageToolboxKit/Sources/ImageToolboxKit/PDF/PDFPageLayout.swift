import CoreGraphics
import Foundation
import PDFKit

/// Changes to the size and arrangement of pages: cropping, fitting to a paper size and putting
/// several pages on a sheet. Cropping only moves the crop box, so nothing is re-encoded. The other
/// two draw the pages again into a new document, which keeps text and vector graphics but not
/// links, form fields or outlines.
public enum PDFPageLayout {

  /// The share of the page that is cut off on each side, from 0 up to but not including 1.
  /// The shares are of the page as it is shown, so a page turned on its side is cut the way it
  /// looks.
  public struct Crop: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
      self.left = left
      self.top = top
      self.right = right
      self.bottom = bottom
    }

    var isValid: Bool {
      [left, top, right, bottom].allSatisfy { $0 >= 0 && $0 < 1 }
        && left + right < 1 && top + bottom < 1
    }
  }

  /// How a page is placed on a page of another size.
  public enum FitMode: String, CaseIterable, Sendable {
    /// The whole page is shown, with empty bands where the shapes differ.
    case fit
    /// The page covers the new one, and what sticks out is cut off.
    case fill
    /// The page is stretched to the new size.
    case stretch
  }

  /// The orientation of a sheet that holds several pages.
  public enum SheetOrientation: String, CaseIterable, Sendable {
    /// Each sheet is as large as the first page on it.
    case original
    case portrait
    case landscape
  }

  /// Pages per sheet that `pagesPerSheet` accepts.
  public static let sheetCounts = [1, 2, 4, 6, 8, 9, 12, 16]

  // MARK: - Crop

  /// The document with the crop box of the chosen pages (nil is every page) moved in by `crop`.
  public static func crop(_ data: Data, by crop: Crop, pages: Set<Int>? = nil) throws -> Data {
    guard crop.isValid else { throw PDFEditFailure.invalidParameter }
    let document = try PDFKitAccess.open(data)
    if let pages, !pages.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) {
      throw PDFEditFailure.pageOutOfRange
    }
    for index in 0..<document.pageCount where pages?.contains(index) ?? true {
      guard let page = document.page(at: index) else { continue }
      page.setBounds(croppedBox(of: page, by: crop), for: .cropBox)
    }
    return try PDFKitAccess.write(document)
  }

  /// The new crop box, in the page's own unturned coordinates.
  static func croppedBox(of page: PDFPage, by crop: Crop) -> CGRect {
    let box = page.bounds(for: .cropBox)
    let turned = page.rotation % 180 != 0
    let shownWidth = turned ? box.height : box.width
    let shownHeight = turned ? box.width : box.height
    // The kept area as the page is shown, measured from its top left corner.
    let x0 = crop.left * shownWidth
    let x1 = (1 - crop.right) * shownWidth
    let y0 = crop.top * shownHeight
    let y1 = (1 - crop.bottom) * shownHeight
    let width = box.width
    let height = box.height
    let kept: CGRect
    switch page.rotation {
    case 90: kept = CGRect(x: y0, y: x0, width: y1 - y0, height: x1 - x0)
    case 180: kept = CGRect(x: width - x1, y: y0, width: x1 - x0, height: y1 - y0)
    case 270: kept = CGRect(x: width - y1, y: height - x1, width: y1 - y0, height: x1 - x0)
    default: kept = CGRect(x: x0, y: height - y1, width: x1 - x0, height: y1 - y0)
    }
    return kept.offsetBy(dx: box.minX, dy: box.minY)
  }

  // MARK: - Resize

  /// The document with every page placed on a page of `size`. With `matchOrientation`, the size is
  /// turned on its side for a page that is wider than it is tall.
  public static func resize(
    _ data: Data, to size: PDFPageSize, mode: FitMode = .fit, matchOrientation: Bool = true
  ) throws -> Data {
    guard size.width > 0, size.height > 0 else { throw PDFEditFailure.invalidParameter }
    let source = try PDFSourcePages(data)
    let targets = (0..<source.pageCount).map { index -> CGSize in
      let shown = source.displayedSize(of: index)
      let sideways = matchOrientation && shown.width > shown.height
      return sideways ? size.landscape.size : size.size
    }
    return try source.rebuild(sizes: targets) { index, context in
      let shown = source.displayedSize(of: index)
      let target = targets[index]
      let scaleX = target.width / shown.width
      let scaleY = target.height / shown.height
      let (x, y): (CGFloat, CGFloat)
      switch mode {
      case .fit: (x, y) = (min(scaleX, scaleY), min(scaleX, scaleY))
      case .fill: (x, y) = (max(scaleX, scaleY), max(scaleX, scaleY))
      case .stretch: (x, y) = (scaleX, scaleY)
      }
      let placed = CGSize(width: shown.width * x, height: shown.height * y)
      let destination = CGRect(
        x: (target.width - placed.width) / 2, y: (target.height - placed.height) / 2,
        width: placed.width, height: placed.height)
      source.draw(index, in: context, to: destination, clip: CGRect(origin: .zero, size: target))
    }
  }

  // MARK: - Pages per sheet

  /// A document with `count` pages on each sheet, in reading order. A page is made smaller to fit
  /// its cell and never larger. `sheet` is the paper size, or nil for the size of the first page on
  /// each sheet. `marginPercent` is a share of the shorter side of the sheet, left free around and
  /// between the pages.
  public static func pagesPerSheet(
    _ data: Data, count: Int, sheet: PDFPageSize? = nil,
    orientation: SheetOrientation = .original, marginPercent: Double = 0
  ) throws -> Data {
    guard sheetCounts.contains(count), marginPercent >= 0, marginPercent < 20 else {
      throw PDFEditFailure.invalidParameter
    }
    let source = try PDFSourcePages(data)
    let grid = gridSize(count: count, orientation: orientation)
    let sheetCount = (source.pageCount + count - 1) / count
    let sizes = (0..<sheetCount).map { sheetIndex -> CGSize in
      switch (sheet, orientation) {
      case (let paper?, .portrait): paper.size
      case (let paper?, .landscape): paper.landscape.size
      default: source.displayedSize(of: sheetIndex * count)
      }
    }
    return try source.rebuild(sizes: sizes) { sheetIndex, context in
      let page = sizes[sheetIndex]
      let margin = min(page.width, page.height) * marginPercent / 100
      let room = CGSize(
        width: (page.width - CGFloat(grid.columns + 1) * margin) / CGFloat(grid.columns),
        height: (page.height - CGFloat(grid.rows + 1) * margin) / CGFloat(grid.rows))
      for slot in 0..<count {
        let index = sheetIndex * count + slot
        guard index < source.pageCount else { break }
        let shown = source.displayedSize(of: index)
        let scale = min(room.width / shown.width, room.height / shown.height, 1)
        let placed = CGSize(width: shown.width * scale, height: shown.height * scale)
        let column = CGFloat(slot % grid.columns)
        let row = CGFloat(slot / grid.columns)
        // Cells fill from the top left, and the page's origin is at the bottom left.
        let centre = CGPoint(
          x: margin + column * (room.width + margin) + room.width / 2,
          y: page.height - margin - row * (room.height + margin) - room.height / 2)
        source.draw(
          index, in: context,
          to: CGRect(
            x: centre.x - placed.width / 2, y: centre.y - placed.height / 2,
            width: placed.width, height: placed.height))
      }
    }
  }

  /// Rows and columns for a sheet. A sheet turned on its side swaps them.
  static func gridSize(count: Int, orientation: SheetOrientation) -> (rows: Int, columns: Int) {
    let upright: (rows: Int, columns: Int)
    switch count {
    case 2: upright = (2, 1)
    case 4: upright = (2, 2)
    case 6: upright = (3, 2)
    case 8: upright = (4, 2)
    case 9: upright = (3, 3)
    case 12: upright = (4, 3)
    case 16: upright = (4, 4)
    default: upright = (1, 1)
    }
    return orientation == .landscape ? (upright.columns, upright.rows) : upright
  }
}
