import CoreGraphics
import Foundation

/// The frame layouts of the Android collage library that cut a disc, a heart, a hexagon or a square out of their
/// cells. `CollageFrameLibrary` holds the layouts whose cells are plain polygons. Here a cell is either a rectangle
/// with an optional figure cut out of it, or a figure that is the picture's cell itself. The cells are in the order
/// of the Android code, so picture `i` goes to cell `i`.
enum CollageShapedFrameLibrary {

  /// A figure of a collage. A rectangle is given as fractions of the usable area, from its top left corner. A disc,
  /// heart or hexagon is centred on the usable area and sized as the Android code sizes it, to fit the box `fitting`
  /// given as fractions of the usable area. A disc or heart has the smaller side of that box, in pixels, as its side.
  /// A hexagon has the smaller of 0.866 times the box width and the box height as its width. So a disc stays round on
  /// a canvas of any shape.
  enum Figure: Sendable {
    case rectangle(CGRect)
    case disc(fitting: CGSize)
    case heart(fitting: CGSize)
    case hexagon(fitting: CGSize)
  }

  /// A cell. An `outline` is a rectangle, given as fractions of the usable area, with the `hole` cut out of it. A
  /// `figure` cell is the figure itself.
  enum Cell: Sendable {
    case outline(CGRect, hole: Figure?)
    case figure(Figure)
  }

  /// A layout: its Android id, such as "collage_3_1", and its cells in the order of the pictures.
  struct Frame: Sendable {
    let id: String
    let cells: [Cell]

    /// The number of pictures the layout takes.
    var count: Int { cells.count }
  }

  // MARK: - Shapes of the layouts, as fractions of the usable area

  private static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
  private static let top = CGRect(x: 0, y: 0, width: 1, height: 0.5)
  private static let bottom = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
  private static let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
  private static let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
  private static let topLeft = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
  private static let topRight = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
  private static let bottomRight = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
  private static let bottomLeft = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
  /// A square at the centre, half the width and half the height of the usable area.
  private static let centre = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  /// A square in the lower right corner that the picture of the small cell fills.
  private static let lowerRight = CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3)
  /// The boxes that the figures are fitted to: a top or bottom half, a left or right half, and a quarter.
  private static let halfWide = CGSize(width: 1, height: 0.5)
  private static let halfTall = CGSize(width: 0.5, height: 1)
  private static let quarter = CGSize(width: 0.5, height: 0.5)

  /// Points per side of a disc, and per quadratic curve of a heart.
  private static let discSides = 360
  private static let heartSteps = 24
  /// The width of a regular hexagon over its height is sqrt(3) / 2, which is also the cosine of 30 degrees.
  private static let hexagonRatio = CGFloat(3).squareRoot() / 2

  /// Every layout, in the order of the Android code: by picture count, then by id.
  static let all: [Frame] = [
    Frame(
      id: "collage_2_7",
      cells: [
        .outline(whole, hole: .rectangle(lowerRight)),
        .figure(.rectangle(lowerRight)),
      ]),
    Frame(
      id: "collage_3_1",
      cells: [
        .outline(top, hole: .disc(fitting: halfWide)),
        .outline(bottom, hole: .disc(fitting: halfWide)),
        .figure(.disc(fitting: halfWide)),
      ]),
    Frame(
      id: "collage_3_4",
      cells: [
        .outline(top, hole: .heart(fitting: halfWide)),
        .outline(bottom, hole: .heart(fitting: halfWide)),
        .figure(.heart(fitting: halfWide)),
      ]),
    Frame(
      id: "collage_3_6",
      cells: [
        .outline(left, hole: .hexagon(fitting: halfTall)),
        .outline(right, hole: .hexagon(fitting: halfTall)),
        .figure(.hexagon(fitting: halfTall)),
      ]),
    Frame(
      id: "collage_3_8",
      cells: [
        .outline(left, hole: .disc(fitting: halfTall)),
        .outline(right, hole: .disc(fitting: halfTall)),
        .figure(.disc(fitting: halfTall)),
      ]),
    Frame(
      id: "collage_3_13",
      cells: [
        .outline(left, hole: .rectangle(centre)),
        .outline(right, hole: .rectangle(centre)),
        .figure(.rectangle(centre)),
      ]),
    Frame(
      id: "collage_5_5",
      cells: [
        .outline(topLeft, hole: .heart(fitting: quarter)),
        .outline(topRight, hole: .heart(fitting: quarter)),
        .outline(bottomRight, hole: .heart(fitting: quarter)),
        .outline(bottomLeft, hole: .heart(fitting: quarter)),
        .figure(.heart(fitting: quarter)),
      ]),
    Frame(
      id: "collage_5_7",
      cells: [
        .outline(topLeft, hole: .disc(fitting: quarter)),
        .outline(topRight, hole: .disc(fitting: quarter)),
        .outline(bottomRight, hole: .disc(fitting: quarter)),
        .outline(bottomLeft, hole: .disc(fitting: quarter)),
        .figure(.disc(fitting: quarter)),
      ]),
  ]

  /// The layout with this Android id, or nil.
  static func frame(id: String) -> Frame? {
    all.first { $0.id == id }
  }

  /// The cell paths of `frame` in a collage whose usable area is `rect`, in pixels. A cut-out is a second closed
  /// subpath that runs the other way round, so the nonzero rule that clips a picture leaves it out. The gap is applied
  /// as in `CollageFrameLibrary`: a side shared with a neighbour moves in by half the gap, a hole grows by half the gap
  /// and a figure shrinks by half the gap. Nil when the gap leaves no room for a cell.
  static func cells(_ frame: Frame, in rect: CGRect, gap: Double) -> [CGPath]? {
    guard rect.width > 0, rect.height > 0 else { return nil }
    var paths: [CGPath] = []
    for cell in frame.cells {
      guard let path = cellPath(cell, in: rect, gap: gap) else { return nil }
      paths.append(path)
    }
    return paths
  }

  // MARK: - Helpers

  private static func cellPath(_ cell: Cell, in rect: CGRect, gap: Double) -> CGPath? {
    let half = CGFloat(gap) / 2
    let path = CGMutablePath()
    switch cell {
    case .outline(let box, let hole):
      guard let outline = outlineRect(box, in: rect, half: half) else { return nil }
      let corners = rectangleCorners(outline)
      addPolygon(corners, to: path)
      if let hole {
        guard let figure = points(of: hole, in: rect, offset: half) else { return nil }
        var cut = clip(figure, to: outline)
        if cut.count >= 3 {
          // The cut-out runs the other way round, so the nonzero rule removes it from the outline.
          if signedArea(cut) * signedArea(corners) > 0 { cut.reverse() }
          addPolygon(cut, to: path)
        }
      }
    case .figure(let figure):
      guard let points = points(of: figure, in: rect, offset: -half) else { return nil }
      addPolygon(points, to: path)
    }
    return path
  }

  /// The rectangle of an outline in the usable area. A side on the edge of the usable area stays where it is. Every
  /// other side is shared with a neighbour and moves in by `half`.
  private static func outlineRect(_ box: CGRect, in rect: CGRect, half: CGFloat) -> CGRect? {
    let minX = rect.minX + box.minX * rect.width + (box.minX > 0 ? half : 0)
    let maxX = rect.minX + box.maxX * rect.width - (box.maxX < 1 ? half : 0)
    let minY = rect.minY + box.minY * rect.height + (box.minY > 0 ? half : 0)
    let maxY = rect.minY + box.maxY * rect.height - (box.maxY < 1 ? half : 0)
    guard maxX > minX, maxY > minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// The points of `figure` in the usable area, grown outwards by `offset` pixels, or shrunk when it is negative. Nil
  /// when nothing of the figure is left.
  private static func points(of figure: Figure, in rect: CGRect, offset: CGFloat) -> [CGPoint]? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    switch figure {
    case .rectangle(let box):
      let area = CGRect(
        x: rect.minX + box.minX * rect.width, y: rect.minY + box.minY * rect.height,
        width: box.width * rect.width, height: box.height * rect.height
      ).insetBy(dx: -offset, dy: -offset)
      guard area.width > 0, area.height > 0 else { return nil }
      return rectangleCorners(area)
    case .disc(let fitting):
      let radius = (fittedSide(fitting, in: rect) + 2 * offset) / 2
      guard radius > 0 else { return nil }
      return (0..<discSides).map { (index: Int) -> CGPoint in
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(discSides)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
      }
    case .heart(let fitting):
      let side = fittedSide(fitting, in: rect) + 2 * offset
      guard side > 0 else { return nil }
      return heartPoints(
        in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
    case .hexagon(let fitting):
      let width = min(hexagonRatio * fitting.width * rect.width, fitting.height * rect.height)
      // Each side of the hexagon is an apothem away from the centre, and cos 30 degrees of the radius is one apothem.
      let radius = width / 2 + offset / hexagonRatio
      guard radius > 0 else { return nil }
      return (0..<6).map { (index: Int) -> CGPoint in
        let angle = CGFloat(index) * CGFloat.pi / 3
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
      }
    }
  }

  /// The side of a disc or heart that fits `fitting`: the smaller side of the box, in pixels.
  private static func fittedSide(_ fitting: CGSize, in rect: CGRect) -> CGFloat {
    min(fitting.width * rect.width, fitting.height * rect.height)
  }

  /// The outline of Android's heart in `box`, from the quadratic curves of its `createHeartItem`. The heart is drawn in
  /// the unit square and then fitted to the box, and each curve is sampled `heartSteps` times.
  private static func heartPoints(in box: CGRect) -> [CGPoint] {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }
    var points: [CGPoint] = [point(0, 0.25)]
    var current: (x: CGFloat, y: CGFloat) = (0, 0.25)
    func quadratic(control: (x: CGFloat, y: CGFloat), end: (x: CGFloat, y: CGFloat)) {
      for step in 1...heartSteps {
        let t = CGFloat(step) / CGFloat(heartSteps)
        let u = 1 - t
        points.append(
          point(
            u * u * current.x + 2 * u * t * control.x + t * t * end.x,
            u * u * current.y + 2 * u * t * control.y + t * t * end.y))
      }
      current = end
    }
    func line(to end: (x: CGFloat, y: CGFloat)) {
      points.append(point(end.x, end.y))
      current = end
    }
    quadratic(control: (0, 0), end: (0.25, 0))
    quadratic(control: (0.5, 0), end: (0.5, 0.25))
    quadratic(control: (0.5, 0), end: (0.75, 0))
    quadratic(control: (1, 0), end: (1, 0.25))
    quadratic(control: (1, 0.5), end: (0.75, 0.75))
    line(to: (0.5, 1))
    line(to: (0.25, 0.75))
    // The last curve ends at the first point, which closes the outline, so that point is not repeated.
    quadratic(control: (0, 0.5), end: (0, 0.25))
    points.removeLast()
    return points
  }

  private static func rectangleCorners(_ rect: CGRect) -> [CGPoint] {
    [
      CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
    ]
  }

  private static func addPolygon(_ points: [CGPoint], to path: CGMutablePath) {
    guard let first = points.first else { return }
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    path.closeSubpath()
  }

  /// Twice the signed area of a polygon, from the shoelace formula. Its sign tells the direction the polygon runs.
  private static func signedArea(_ points: [CGPoint]) -> Double {
    var sum = 0.0
    for index in points.indices {
      let current = points[index]
      let next = points[(index + 1) % points.count]
      sum += Double(current.x * next.y - next.x * current.y)
    }
    return sum
  }

  /// The polygon clipped to the rectangle `rect`, one side at a time (Sutherland-Hodgman against a convex window).
  private static func clip(_ polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
    var result = CollageTemplates.clip(polygon) { Double($0.x - rect.minX) }
    result = CollageTemplates.clip(result) { Double(rect.maxX - $0.x) }
    result = CollageTemplates.clip(result) { Double($0.y - rect.minY) }
    return CollageTemplates.clip(result) { Double(rect.maxY - $0.y) }
  }
}
