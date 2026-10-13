import CoreGraphics
import Foundation

/// Collage templates. Each template divides the collage into cells with the margin and gap rules of
/// `CollageLayout`, and each picture fills its cell by aspect fill.
public enum CollageTemplate: Hashable, Sendable {
  /// Equal cells in reading order, as `CollageLayout`. Takes 1...36 pictures.
  case grid
  /// Two halves side by side, divided by a vertical line. Takes 2 pictures.
  case splitSideBySide
  /// Two halves one above the other, divided by a horizontal line. Takes 2 pictures.
  case splitStacked
  /// One large cell on top and the other pictures in a row below. Takes 2...9 pictures.
  case hero
  /// Two triangles divided by the diagonal from the bottom left to the top right corner. Takes 2 pictures.
  case diagonal
  /// Four cells whose dividers cross off the centre, at 60% across and 44% down. Takes 4 pictures.
  case twoByTwoOffset
  /// Equal cells in one row, like the frames of a film strip. Takes 2...8 pictures.
  case filmstrip
  /// One of the frame layouts of the Android app, by its id such as "collage_3_12". It takes the number of
  /// pictures of that layout.
  case frame(String)

  /// The templates in picker order: the seven above, then the frame layouts by picture count. A shaped layout
  /// comes after the polygon layouts that take the same number of pictures.
  public static let allCases: [CollageTemplate] =
    [.grid, .splitSideBySide, .splitStacked, .hero, .diagonal, .twoByTwoOffset, .filmstrip]
    + frameIDsByCount.map { .frame($0) }

  /// The ids of every frame layout by picture count. Within a count the polygon layouts come first, in library order.
  private static let frameIDsByCount: [String] = {
    let frames =
      CollageFrameLibrary.all.map { (count: $0.count, id: $0.id) }
      + CollageShapedFrameLibrary.all.map { (count: $0.count, id: $0.id) }
    return frames.enumerated()
      .sorted { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }
      .map(\.element.id)
  }()
}

/// Cell geometry and rendering for `CollageTemplate`. Cells are paths in top-left coordinates.
public enum CollageTemplates {

  /// Where the dividers of `twoByTwoOffset` cross, as fractions of the usable width and height.
  private static let crossX = 0.6
  private static let crossY = 0.44

  /// The cells for `count` pictures, in reading order. Nil when the template does not take that many
  /// pictures, or when the gaps leave no room for the cells.
  public static func cells(
    _ template: CollageTemplate, count: Int, width: Double, height: Double,
    settings: CollageLayout.Settings
  ) -> [CGPath]? {
    let usable = CGRect(
      x: settings.margin, y: settings.margin,
      width: width - 2 * settings.margin, height: height - 2 * settings.margin)
    guard usable.width > 0, usable.height > 0 else { return nil }
    let gap = settings.gap

    switch template {
    case .grid:
      return CollageLayout.cells(count: count, width: width, height: height, settings: settings)?
        .map { CGPath(rect: $0, transform: nil) }
    case .splitSideBySide:
      guard count == 2 else { return nil }
      return rectPaths(grid(in: usable, columns: 2, rows: 1, gap: gap))
    case .splitStacked:
      guard count == 2 else { return nil }
      return rectPaths(grid(in: usable, columns: 1, rows: 2, gap: gap))
    case .hero:
      guard (2...9).contains(count) else { return nil }
      return rectPaths(hero(in: usable, count: count, gap: gap))
    case .diagonal:
      guard count == 2 else { return nil }
      return diagonal(in: usable, gap: gap)
    case .twoByTwoOffset:
      guard count == 4 else { return nil }
      return rectPaths(twoByTwoOffset(in: usable, gap: gap))
    case .filmstrip:
      guard (2...8).contains(count) else { return nil }
      return rectPaths(grid(in: usable, columns: count, rows: 1, gap: gap))
    case .frame(let id):
      if let frame = CollageFrameLibrary.frame(id: id) {
        guard frame.count == count else { return nil }
        return CollageFrameLibrary.cells(frame, in: usable, gap: gap)
      }
      guard let shaped = CollageShapedFrameLibrary.frame(id: id), shaped.count == count else {
        return nil
      }
      return CollageShapedFrameLibrary.cells(shaped, in: usable, gap: gap)
    }
  }

  /// The cells of `template` in the unit square, with no margin and no gap: one polygon per picture, in order. Nil when
  /// the template does not take `count` pictures, or when a cell is not a single polygon, as with the shaped layouts
  /// that have a hole.
  public static func unitCells(_ template: CollageTemplate, count: Int) -> [[CGPoint]]? {
    guard
      let paths = cells(
        template, count: count, width: 1, height: 1,
        settings: CollageLayout.Settings(gap: 0, margin: 0))
    else { return nil }
    var polygons: [[CGPoint]] = []
    for path in paths {
      guard let corners = CollageMask.polygonPoints(of: path) else { return nil }
      polygons.append(corners)
    }
    return polygons
  }

  /// Draws the pictures into the cells of `template` in a collage of `width` by `height` pixels. Each picture
  /// is cropped to fill its cell. Nil when the template does not take `pictures.count` pictures.
  public static func render(
    _ pictures: [CGImage], template: CollageTemplate, width: Int, height: Int,
    settings: CollageLayout.Settings
  ) -> CGImage? {
    guard
      let cellPaths = cells(
        template, count: pictures.count, width: Double(width), height: Double(height),
        settings: settings),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(
      red: settings.background.red, green: settings.background.green,
      blue: settings.background.blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // The cells are laid out from the top, while the context origin is at the bottom left.
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
    for (picture, cell) in zip(pictures, cellPaths) {
      guard let target = cell.copy(using: &flip) else { return nil }
      context.saveGState()
      context.addPath(target)
      context.clip()
      context.draw(
        picture,
        in: CollageLayout.aspectFill(
          width: Double(picture.width), height: Double(picture.height),
          into: target.boundingBoxOfPath))
      context.restoreGState()
    }
    return context.makeImage()
  }

  // MARK: - Cell geometry. Rects and polygons are in top-left coordinates.

  private static func rectPaths(_ rects: [CGRect]?) -> [CGPath]? {
    rects?.map { CGPath(rect: $0, transform: nil) }
  }

  /// Equal cells in `columns` by `rows`, in reading order. Nil when the gaps leave no room.
  private static func grid(in rect: CGRect, columns: Int, rows: Int, gap: Double) -> [CGRect]? {
    let cellWidth = (rect.width - Double(columns - 1) * gap) / Double(columns)
    let cellHeight = (rect.height - Double(rows - 1) * gap) / Double(rows)
    guard cellWidth > 0, cellHeight > 0 else { return nil }
    return (0..<(columns * rows)).map { index in
      CGRect(
        x: rect.minX + Double(index % columns) * (cellWidth + gap),
        y: rect.minY + Double(index / columns) * (cellHeight + gap),
        width: cellWidth, height: cellHeight)
    }
  }

  /// A large cell on top, 60% of the height, and `count - 1` equal cells in a row below it.
  private static func hero(in rect: CGRect, count: Int, gap: Double) -> [CGRect]? {
    let topHeight = (rect.height - gap) * 0.6
    guard topHeight > 0 else { return nil }
    let bottomRow = CGRect(
      x: rect.minX, y: rect.minY + topHeight + gap,
      width: rect.width, height: rect.height - topHeight - gap)
    guard let bottom = grid(in: bottomRow, columns: count - 1, rows: 1, gap: gap) else {
      return nil
    }
    return [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)] + bottom
  }

  /// Four cells around a cross of dividers. Each divider is moved half a gap away from the cross on each side.
  private static func twoByTwoOffset(in rect: CGRect, gap: Double) -> [CGRect]? {
    let halfGap = gap / 2
    let leftWidth = rect.width * crossX - halfGap
    let rightWidth = rect.width * (1 - crossX) - halfGap
    let topHeight = rect.height * crossY - halfGap
    let bottomHeight = rect.height * (1 - crossY) - halfGap
    guard leftWidth > 0, rightWidth > 0, topHeight > 0, bottomHeight > 0 else { return nil }
    let rightX = rect.minX + rect.width * crossX + halfGap
    let bottomY = rect.minY + rect.height * crossY + halfGap
    return [
      CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: topHeight),
      CGRect(x: rightX, y: rect.minY, width: rightWidth, height: topHeight),
      CGRect(x: rect.minX, y: bottomY, width: leftWidth, height: bottomHeight),
      CGRect(x: rightX, y: bottomY, width: rightWidth, height: bottomHeight),
    ]
  }

  /// Two triangles divided by the diagonal from the bottom left to the top right corner. The divider is moved
  /// half a gap to each side, so the cells are clipped polygons. The top left cell comes first.
  private static func diagonal(in rect: CGRect, gap: Double) -> [CGPath]? {
    let corners = [
      CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
    ]
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let dx = rect.width
    let dy = -rect.height
    let length = (dx * dx + dy * dy).squareRoot()
    // Signed distance from the divider: negative above it, which is the top left cell.
    func distance(_ point: CGPoint) -> Double {
      (dx * (point.y - start.y) - dy * (point.x - start.x)) / length
    }
    let halfGap = gap / 2
    let topLeft = clip(corners) { -distance($0) - halfGap }
    let bottomRight = clip(corners) { distance($0) - halfGap }
    guard topLeft.count >= 3, bottomRight.count >= 3 else { return nil }
    return [polygon(topLeft), polygon(bottomRight)]
  }

  /// The part of a convex polygon where `side` is zero or more (Sutherland-Hodgman, one half-plane).
  static func clip(_ polygon: [CGPoint], keeping side: (CGPoint) -> Double) -> [CGPoint] {
    var output: [CGPoint] = []
    for index in polygon.indices {
      let current = polygon[index]
      let next = polygon[(index + 1) % polygon.count]
      let currentSide = side(current)
      let nextSide = side(next)
      if currentSide >= 0 { output.append(current) }
      if (currentSide >= 0) != (nextSide >= 0) {
        let t = currentSide / (currentSide - nextSide)
        output.append(
          CGPoint(
            x: current.x + (next.x - current.x) * t,
            y: current.y + (next.y - current.y) * t))
      }
    }
    return output
  }

  private static func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
  }
}
