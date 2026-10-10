import CoreGraphics
import Foundation

/// The frame layouts of the Android collage library that are plain polygons. A layout is a list of cells, one per
/// picture, in the order of the Android code. The tables in `CollageFrameTable*.swift` hold the cells as the Android
/// code draws them at the default parameters. The layouts drawn with circles, hearts or cut-out holes are not here.
enum CollageFrameLibrary {

  /// One layout: its Android id, such as "collage_3_12", and its cells.
  struct Frame: Sendable {
    let id: String
    /// The cells in reading order. Each cell is a closed polygon: x and y pairs in 0...1 of the canvas.
    let cells: [[Double]]

    init(_ id: String, _ cells: [[Double]]) {
      self.id = id
      self.cells = cells
    }

    /// The number of pictures the layout takes.
    var count: Int { cells.count }
  }

  /// Every layout, by picture count and then by id.
  static let all: [Frame] = [
    table1, table2, table3, table4, table5, table6, table7, table8, table9, table10, table11,
    table12,
  ].flatMap { $0 }

  private static let byID: [String: Frame] = Dictionary(
    uniqueKeysWithValues: all.map { ($0.id, $0) })

  /// The layout with this Android id, or nil.
  static func frame(id: String) -> Frame? {
    byID[id]
  }

  /// The cells of `frame` in a collage whose usable area, inside the margin, is `rect`. Each cell is mapped into
  /// `rect`. Each side shared with another cell moves in by half the gap, so neighbouring cells are `gap` apart, and
  /// the sides on the edge of the layout keep their place. Nil when the cells have no room left.
  static func cells(_ frame: Frame, in rect: CGRect, gap: Double) -> [CGPath]? {
    cells(flattened: frame.cells, in: rect, gap: gap)
  }

  /// The same as `cells(_:in:gap:)` for cells that are not one of the tables, such as cells whose dividers the user
  /// has moved. Each cell is a closed polygon in the unit square.
  static func cells(unit polygons: [[CGPoint]], in rect: CGRect, gap: Double) -> [CGPath]? {
    cells(
      flattened: polygons.map { cell in
        cell.flatMap { point in [Double(point.x), Double(point.y)] }
      },
      in: rect, gap: gap)
  }

  private static func cells(flattened cells: [[Double]], in rect: CGRect, gap: Double) -> [CGPath]?
  {
    let width = Double(rect.width)
    let height = Double(rect.height)
    guard width > 0, height > 0 else { return nil }
    var paths: [CGPath] = []
    for cell in cells {
      let vertices = cell.count / 2
      guard vertices >= 3 else { return nil }
      let points = (0..<vertices).map { index in
        Point(
          x: Double(rect.minX) + cell[2 * index] * width,
          y: Double(rect.minY) + cell[2 * index + 1] * height)
      }
      let shared = (0..<vertices).map { index in
        !isOnEdge(cell, from: index, to: (index + 1) % vertices)
      }
      guard let sides = inset(points, shared: shared, distance: gap / 2) else { return nil }
      paths.append(polygon(sides))
    }
    return paths
  }

  // MARK: - Helpers

  private struct Point {
    var x: Double
    var y: Double
  }

  /// A side of a polygon moved inwards: where it starts, its unit direction and its inward normal.
  private struct Side {
    let start: Point
    let direction: Point
    let normal: Point
    let offset: Double
  }

  /// Whether the side from vertex `from` to vertex `to` lies along one edge of the unit square.
  private static func isOnEdge(_ cell: [Double], from: Int, to: Int) -> Bool {
    let tolerance = 1e-9
    let (x1, y1) = (cell[2 * from], cell[2 * from + 1])
    let (x2, y2) = (cell[2 * to], cell[2 * to + 1])
    for edge in [0.0, 1.0] {
      if abs(x1 - edge) < tolerance && abs(x2 - edge) < tolerance { return true }
      if abs(y1 - edge) < tolerance && abs(y2 - edge) < tolerance { return true }
    }
    return false
  }

  /// The polygon with each side marked `shared` moved inwards by `distance`. Neighbouring sides meet at a mitre, or
  /// at a bevel when the mitre would be more than four distances long. Nil when a side has no length or the
  /// polygon collapses.
  private static func inset(_ points: [Point], shared: [Bool], distance: Double) -> [Point]? {
    let count = points.count
    guard distance > 0 else { return points }
    // The inside lies to the left of each side when the polygon is counter-clockwise, and to the right otherwise.
    var twiceArea = 0.0
    for index in 0..<count {
      let a = points[index]
      let b = points[(index + 1) % count]
      twiceArea += a.x * b.y - b.x * a.y
    }
    let orientation: Double = twiceArea >= 0 ? 1 : -1
    var sides: [Side] = []
    for index in 0..<count {
      let a = points[index]
      let b = points[(index + 1) % count]
      let dx = b.x - a.x
      let dy = b.y - a.y
      let length = (dx * dx + dy * dy).squareRoot()
      guard length > 0 else { return nil }
      let direction = Point(x: dx / length, y: dy / length)
      let normal = Point(x: -direction.y * orientation, y: direction.x * orientation)
      let offset = shared[index] ? distance : 0
      sides.append(Side(start: a, direction: direction, normal: normal, offset: offset))
    }

    var result: [Point] = []
    for index in 0..<count {
      let before = sides[(index + count - 1) % count]
      let after = sides[index]
      let vertex = points[index]
      let cross = before.direction.x * after.direction.y - before.direction.y * after.direction.x
      if abs(cross) < 1e-12 {
        // Parallel sides: move the vertex along the normal of the side that moves.
        let side = before.offset > 0 ? before : after
        result.append(
          Point(
            x: vertex.x + side.normal.x * side.offset, y: vertex.y + side.normal.y * side.offset))
        continue
      }
      let a = Point(
        x: before.start.x + before.normal.x * before.offset,
        y: before.start.y + before.normal.y * before.offset)
      let b = Point(
        x: after.start.x + after.normal.x * after.offset,
        y: after.start.y + after.normal.y * after.offset)
      let t = ((b.x - a.x) * after.direction.y - (b.y - a.y) * after.direction.x) / cross
      let corner = Point(x: a.x + before.direction.x * t, y: a.y + before.direction.y * t)
      let limit = 4 * max(before.offset, after.offset)
      if hypot(corner.x - vertex.x, corner.y - vertex.y) <= limit + 1e-9 {
        result.append(corner)
      } else {
        result.append(
          Point(
            x: vertex.x + before.normal.x * before.offset,
            y: vertex.y + before.normal.y * before.offset))
        result.append(
          Point(
            x: vertex.x + after.normal.x * after.offset, y: vertex.y + after.normal.y * after.offset
          ))
      }
    }

    var twiceResult = 0.0
    for index in 0..<result.count {
      let a = result[index]
      let b = result[(index + 1) % result.count]
      twiceResult += a.x * b.y - b.x * a.y
    }
    guard result.count >= 3, twiceResult * orientation > 0 else { return nil }
    return result
  }

  private static func polygon(_ points: [Point]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
    path.closeSubpath()
    return path
  }
}
