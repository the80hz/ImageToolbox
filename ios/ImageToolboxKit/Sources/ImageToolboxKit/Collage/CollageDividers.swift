import CoreGraphics
import Foundation

/// A straight line between neighbouring cells that the user can drag. The Android collage moves such lines through
/// the parameters of each layout; here they come from the geometry: an interior straight side that another cell
/// shares. Moving a divider moves every vertex on its line, so the cells on both sides move together.
public struct CollageDivider: Hashable, Sendable {

  public enum Orientation: Hashable, Sendable {
    /// A line of constant x that divides cells side by side.
    case vertical
    /// A line of constant y that divides cells one above the other.
    case horizontal
  }

  public let orientation: Orientation
  /// The position of the line on its axis, in the unit square of the template, from 0 to 1.
  public let position: Double
  /// The part of the line that is shared, along the other axis, in the unit square.
  public let span: ClosedRange<Double>
}

/// Finds the dividers of a set of cells and moves them. Cells are polygons in the unit square, one per picture, in
/// the order of the pictures, the same as the frame tables of `CollageFrameLibrary`.
public enum CollageDividers {

  /// Two numbers closer than this are the same position in the unit square. The tables are written to four decimals.
  static let tolerance = 1e-3

  /// How far a divider is tried in each direction to find out whether it can move at all.
  private static let probe = 0.01

  /// The dividers of `cells`, vertical ones first, each sorted by position. Empty when the cells do not tile the
  /// unit square, and for a line that cannot move without breaking the tiling.
  public static func dividers(of cells: [[CGPoint]]) -> [CollageDivider] {
    guard tiles(cells) else { return [] }
    let sides = cells.indices.flatMap { index in
      straightSides(of: cells[index]).map { side in (cell: index, side: side) }
    }
    let shared = sides.filter { candidate in
      sides.contains { other in
        other.cell != candidate.cell && other.side.orientation == candidate.side.orientation
          && abs(other.side.position - candidate.side.position) <= tolerance
          && min(other.side.high, candidate.side.high) - max(other.side.low, candidate.side.low)
            > tolerance
      }
    }

    // Sides at the same position join one divider. A side is compared with the mean of the sides already joined.
    let ordered = shared.map(\.side).sorted { first, second in
      (rank(first.orientation), first.position) < (rank(second.orientation), second.position)
    }
    var groups: [Group] = []
    for side in ordered {
      if let last = groups.last, last.orientation == side.orientation,
        abs(last.mean - side.position) <= tolerance
      {
        groups[groups.count - 1].add(side)
      } else {
        groups.append(Group(side))
      }
    }
    let found = groups.map { group in
      CollageDivider(
        orientation: group.orientation, position: group.mean, span: group.low...group.high)
    }
    return found.filter { divider in
      moving(divider, to: divider.position + probe, in: cells) != nil
        || moving(divider, to: divider.position - probe, in: cells) != nil
    }
  }

  /// The cells after `divider` moved to `position`. The line stops short of the nearest other vertex on either side,
  /// so no cell is narrower than `minimumSize` and no cell turns inside out. Nil when the divider has no room to move,
  /// or when the moved cells would no longer cover the unit square exactly.
  public static func moving(
    _ divider: CollageDivider, to position: Double, in cells: [[CGPoint]],
    minimumSize: Double = 0.05
  ) -> [[CGPoint]]? {
    guard tiles(cells) else { return nil }
    let vertical = divider.orientation == .vertical
    func along(_ point: CGPoint) -> Double { Double(vertical ? point.x : point.y) }
    func across(_ point: CGPoint) -> Double { Double(vertical ? point.y : point.x) }
    let inSpan = { (point: CGPoint) in
      across(point) >= divider.span.lowerBound - tolerance
        && across(point) <= divider.span.upperBound + tolerance
    }

    // The vertices on the line move. The others that lie beside the line limit how far it can go.
    var onLine = false
    var below: [Double] = []
    var above: [Double] = []
    for point in cells.joined() where inSpan(point) {
      let coordinate = along(point)
      if abs(coordinate - divider.position) <= tolerance {
        onLine = true
      } else if coordinate < divider.position {
        below.append(coordinate)
      } else {
        above.append(coordinate)
      }
    }
    guard onLine else { return nil }

    let lower = (below.max() ?? 0) + minimumSize
    let upper = (above.min() ?? 1) - minimumSize
    guard lower <= upper else { return nil }
    let target = min(max(position, lower), upper)
    let moved = cells.map { cell in
      cell.map { point in
        guard abs(along(point) - divider.position) <= tolerance, inSpan(point) else { return point }
        return vertical ? CGPoint(x: target, y: point.y) : CGPoint(x: point.x, y: target)
      }
    }
    // A vertex where the line meets a side that does not follow it stretches that side too, and the cells stop
    // covering the square exactly. Such a move is refused.
    return tiles(moved) ? moved : nil
  }

  // MARK: - Helpers

  /// Whether the cells cover the unit square exactly once: every cell has an area, and the areas add up to the square.
  /// Overlapping cells or gaps between them would not add up.
  private static func tiles(_ cells: [[CGPoint]]) -> Bool {
    guard !cells.isEmpty, cells.allSatisfy({ $0.count >= 3 && area(of: $0) > 1e-9 }) else {
      return false
    }
    let total = cells.reduce(0.0) { $0 + area(of: $1) }
    return abs(total - 1) <= 1e-6
  }

  /// The area of a polygon, which is positive for both windings.
  private static func area(of polygon: [CGPoint]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let start = polygon[index]
      let end = polygon[(index + 1) % polygon.count]
      sum += Double(start.x * end.y - end.x * start.y)
    }
    return abs(sum) / 2
  }

  /// One straight side of a cell: its orientation, its position on the axis across it, and its extent along the line.
  private struct Side {
    let orientation: CollageDivider.Orientation
    let position: Double
    let low: Double
    let high: Double
  }

  /// Sides on one line: their mean position and the extent they cover along it.
  private struct Group {
    let orientation: CollageDivider.Orientation
    private var total: Double
    private var count: Double
    var low: Double
    var high: Double

    init(_ side: Side) {
      orientation = side.orientation
      total = side.position
      count = 1
      low = side.low
      high = side.high
    }

    var mean: Double { total / count }

    mutating func add(_ side: Side) {
      total += side.position
      count += 1
      low = min(low, side.low)
      high = max(high, side.high)
    }
  }

  private static func rank(_ orientation: CollageDivider.Orientation) -> Int {
    orientation == .vertical ? 0 : 1
  }

  /// The sides of `cell` that are straight and lie inside the unit square.
  private static func straightSides(of cell: [CGPoint]) -> [Side] {
    cell.indices.compactMap { index in
      let start = cell[index]
      let end = cell[(index + 1) % cell.count]
      if abs(start.x - end.x) <= tolerance {
        let position = Double(start.x + end.x) / 2
        guard position > tolerance, position < 1 - tolerance else { return nil }
        return Side(
          orientation: .vertical, position: position,
          low: Double(min(start.y, end.y)), high: Double(max(start.y, end.y)))
      }
      if abs(start.y - end.y) <= tolerance {
        let position = Double(start.y + end.y) / 2
        guard position > tolerance, position < 1 - tolerance else { return nil }
        return Side(
          orientation: .horizontal, position: position,
          low: Double(min(start.x, end.x)), high: Double(max(start.x, end.x)))
      }
      return nil
    }
  }
}
