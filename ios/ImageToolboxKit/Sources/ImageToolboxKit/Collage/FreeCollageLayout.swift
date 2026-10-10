import CoreGraphics
import Foundation

/// A free collage layout: one rectangle per picture, stored as fractions of the usable area of the canvas (the
/// canvas without its margin), so it keeps its shape when the canvas size changes. Cells may overlap. Later cells
/// in `drawOrder` are drawn on top of earlier ones.
///
/// The layout is a value. Editing methods return a changed copy, so a drag gesture can start from a snapshot of
/// the layout and apply the whole translation to it each time the finger moves.
public struct FreeCollageLayout: Equatable, Sendable {

  /// A corner of a cell that can be dragged to resize it. The opposite corner stays where it is.
  public enum Handle: CaseIterable, Hashable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
  }

  /// The smallest width or height of a cell, as a fraction of the usable area. The Android dividers stop at
  /// the same size.
  public static let minimumSize = 0.05

  /// One rectangle per picture, in the order of the pictures. Origins are at the top left.
  public private(set) var rects: [CGRect]
  /// Picture indices from the back to the front.
  public private(set) var drawOrder: [Int]

  /// Makes a layout from rectangles in the unit square. A rectangle that is too small or reaches outside the
  /// unit square is moved and resized to fit. Nil for no rectangles or a rectangle that is not a finite number.
  /// A `drawOrder` that is not a permutation of the picture indices is replaced by the order of the pictures.
  public init?(rects: [CGRect], drawOrder: [Int]? = nil) {
    guard !rects.isEmpty else { return nil }
    var fitted: [CGRect] = []
    for rect in rects {
      guard let value = Self.fit(rect) else { return nil }
      fitted.append(value)
    }
    self.rects = fitted
    if let drawOrder, drawOrder.sorted() == Array(rects.indices) {
      self.drawOrder = drawOrder
    } else {
      self.drawOrder = Array(rects.indices)
    }
  }

  /// The grid of `CollageLayout` as free cells, the natural starting point for editing: as square as possible
  /// and without gaps. Nil for no pictures or more than 36.
  public static func grid(count: Int) -> FreeCollageLayout? {
    guard let (columns, rows) = CollageLayout.grid(for: count) else { return nil }
    let cellWidth = 1 / Double(columns)
    let cellHeight = 1 / Double(rows)
    let rects = (0..<count).map { index in
      CGRect(
        x: Double(index % columns) * cellWidth, y: Double(index / columns) * cellHeight,
        width: cellWidth, height: cellHeight)
    }
    return FreeCollageLayout(rects: rects)
  }

  /// The number of cells.
  public var count: Int { rects.count }

  // MARK: - Editing

  /// The layout with cell `index` moved by `delta`, in fractions of the usable area. The cell stops at the
  /// edges of the usable area. An index out of range changes nothing.
  public func moving(_ index: Int, by delta: CGVector) -> FreeCollageLayout {
    guard rects.indices.contains(index), delta.dx.isFinite, delta.dy.isFinite else { return self }
    var copy = self
    let rect = rects[index]
    copy.rects[index] = CGRect(
      x: min(max(rect.minX + delta.dx, 0), 1 - rect.width),
      y: min(max(rect.minY + delta.dy, 0), 1 - rect.height),
      width: rect.width, height: rect.height)
    return copy
  }

  /// The layout with cell `index` resized by dragging `handle` by `delta`, in fractions of the usable area.
  /// The opposite corner stays in place, the cell stays inside the usable area and keeps at least the
  /// minimum size. An index out of range changes nothing.
  public func resizing(_ index: Int, handle: Handle, by delta: CGVector) -> FreeCollageLayout {
    guard rects.indices.contains(index), delta.dx.isFinite, delta.dy.isFinite else { return self }
    var copy = self
    let rect = rects[index]
    var left = rect.minX
    var right = rect.maxX
    var top = rect.minY
    var bottom = rect.maxY
    let minimum = Self.minimumSize

    switch handle {
    case .topLeft, .bottomLeft:
      left = min(max(left + delta.dx, 0), right - minimum)
    case .topRight, .bottomRight:
      right = min(max(right + delta.dx, left + minimum), 1)
    }
    switch handle {
    case .topLeft, .topRight:
      top = min(max(top + delta.dy, 0), bottom - minimum)
    case .bottomLeft, .bottomRight:
      bottom = min(max(bottom + delta.dy, top + minimum), 1)
    }
    copy.rects[index] = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    return copy
  }

  /// The layout with cell `index` drawn on top of all others.
  public func bringingToFront(_ index: Int) -> FreeCollageLayout {
    guard rects.indices.contains(index) else { return self }
    var copy = self
    copy.drawOrder.removeAll { $0 == index }
    copy.drawOrder.append(index)
    return copy
  }

  /// The layout with cell `index` drawn below all others.
  public func sendingToBack(_ index: Int) -> FreeCollageLayout {
    guard rects.indices.contains(index) else { return self }
    var copy = self
    copy.drawOrder.removeAll { $0 == index }
    copy.drawOrder.insert(index, at: 0)
    return copy
  }

  /// The topmost cell that contains `point`, given as fractions of the usable area. Nil when no cell does.
  public func hitTest(_ point: CGPoint) -> Int? {
    drawOrder.last { rects[$0].contains(point) }
  }

  // MARK: - Pixels

  /// The area cells are laid out in: the canvas without its margin. Nil when the margin leaves no room.
  public static func usableRect(width: Double, height: Double, margin: Double) -> CGRect? {
    let usable = CGRect(
      x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)
    return usable.width > 0 && usable.height > 0 ? usable : nil
  }

  /// The cells as paths in top-left pixel coordinates, in the order of the pictures. A side of a cell that is
  /// not on the edge of the usable area is moved in by half of the gap, so cells that touch end up one gap
  /// apart. A cell never becomes smaller than a pixel. Nil when the margin leaves no room.
  public func cellPaths(width: Double, height: Double, settings: CollageLayout.Settings)
    -> [CGPath]?
  {
    guard let usable = Self.usableRect(width: width, height: height, margin: settings.margin)
    else { return nil }
    let edge = 1e-9
    let half = settings.gap / 2
    return rects.map { rect in
      let box = CGRect(
        x: usable.minX + rect.minX * usable.width, y: usable.minY + rect.minY * usable.height,
        width: rect.width * usable.width, height: rect.height * usable.height)
      let (left, right) = Self.shrink(
        box.minX, box.maxX, by: half, insetLow: rect.minX > edge, insetHigh: rect.maxX < 1 - edge)
      let (top, bottom) = Self.shrink(
        box.minY, box.maxY, by: half, insetLow: rect.minY > edge, insetHigh: rect.maxY < 1 - edge)
      return CGPath(
        rect: CGRect(x: left, y: top, width: right - left, height: bottom - top), transform: nil)
    }
  }

  // MARK: - Helpers

  /// Moves the ends of a span in by `amount` where `insetLow` and `insetHigh` say so, keeping at least one pixel.
  private static func shrink(
    _ low: Double, _ high: Double, by amount: Double, insetLow: Bool, insetHigh: Bool
  ) -> (Double, Double) {
    let newLow = insetLow ? low + amount : low
    let newHigh = insetHigh ? high - amount : high
    guard newHigh - newLow < 1 else { return (newLow, newHigh) }
    let middle = (low + high) / 2
    return (middle - 0.5, middle + 0.5)
  }

  /// `rect` made at least the minimum size and moved inside the unit square. Nil when it is not finite.
  private static func fit(_ rect: CGRect) -> CGRect? {
    guard !rect.isNull, !rect.isInfinite, rect.origin.x.isFinite, rect.origin.y.isFinite,
      rect.width.isFinite, rect.height.isFinite
    else { return nil }
    let standard = rect.standardized
    let width = min(max(standard.width, minimumSize), 1)
    let height = min(max(standard.height, minimumSize), 1)
    return CGRect(
      x: min(max(standard.minX, 0), 1 - width), y: min(max(standard.minY, 0), 1 - height),
      width: width, height: height)
  }
}
