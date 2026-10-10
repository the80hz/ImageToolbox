import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage frame library")
struct CollageFrameLibraryTests {

  /// Layouts whose Android id gives a count that differs from their cells. Android sizes them by their cells.
  private static let cellCounts = ["collage_15_2": 17]

  /// Layouts that Android draws with circles, hearts or cut-out holes, which are not polygons. They are left out.
  private static let notPolygons = [
    "collage_2_7", "collage_3_1", "collage_3_4", "collage_3_6", "collage_3_8", "collage_3_13",
    "collage_5_5", "collage_5_7",
  ]

  /// Layouts that leave open gaps on purpose, so their cells do not fill the canvas.
  private static let openGaps = ["collage_5_1", "collage_5_6", "collage_5_32"]

  /// Area of a polygon given as x and y pairs, from the shoelace formula.
  private static func area(_ cell: [Double]) -> Double {
    let count = cell.count / 2
    var sum = 0.0
    for index in 0..<count {
      let next = (index + 1) % count
      sum += cell[2 * index] * cell[2 * next + 1] - cell[2 * next] * cell[2 * index + 1]
    }
    return abs(sum) / 2
  }

  /// The bounding box of a polygon as minimum x, minimum y, maximum x and maximum y.
  private static func box(of cell: [Double]) -> (Double, Double, Double, Double) {
    var box = (cell[0], cell[1], cell[0], cell[1])
    for index in 0..<(cell.count / 2) {
      box.0 = min(box.0, cell[2 * index])
      box.1 = min(box.1, cell[2 * index + 1])
      box.2 = max(box.2, cell[2 * index])
      box.3 = max(box.3, cell[2 * index + 1])
    }
    return box
  }

  private static func isIn(_ box: (Double, Double, Double, Double), _ x: Double, _ y: Double)
    -> Bool
  {
    x >= box.0 && x <= box.2 && y >= box.1 && y <= box.3
  }

  /// Area of a polygon path, from the shoelace formula over its vertices.
  private static func pathArea(of path: CGPath) -> Double {
    var points: [CGPoint] = []
    path.applyWithBlock { element in
      switch element.pointee.type {
      case .moveToPoint, .addLineToPoint:
        points.append(element.pointee.points[0])
      default:
        break
      }
    }
    var sum = 0.0
    for index in points.indices {
      let current = points[index]
      let next = points[(index + 1) % points.count]
      sum += Double(current.x * next.y - next.x * current.y)
    }
    return abs(sum) / 2
  }

  /// Whether the point lies inside the polygon, by the even-odd rule.
  private static func contains(_ cell: [Double], _ x: Double, _ y: Double) -> Bool {
    let count = cell.count / 2
    var inside = false
    for index in 0..<count {
      let next = (index + 1) % count
      let (x1, y1) = (cell[2 * index], cell[2 * index + 1])
      let (x2, y2) = (cell[2 * next], cell[2 * next + 1])
      if (y1 > y) != (y2 > y), x < x1 + (y - y1) * (x2 - x1) / (y2 - y1) {
        inside.toggle()
      }
    }
    return inside
  }

  @Test("the library holds the 308 layouts that are plain polygons")
  func holdsPolygonLayouts() {
    #expect(CollageFrameLibrary.all.count == 308)
    #expect(Set(CollageFrameLibrary.all.map(\.id)).count == 308)
    for id in Self.notPolygons {
      #expect(CollageFrameLibrary.frame(id: id) == nil, "\(id)")
    }
    #expect(CollageFrameLibrary.frame(id: "collage_99_0") == nil)
  }

  @Test("each layout takes the number of pictures in its id")
  func countsMatchIds() {
    for frame in CollageFrameLibrary.all {
      let declared = Int(frame.id.split(separator: "_")[1]) ?? -1
      #expect(frame.count == (Self.cellCounts[frame.id] ?? declared), "\(frame.id)")
    }
  }

  @Test("every cell is a polygon of at least three points inside the canvas")
  func cellsLieInCanvas() {
    var bad: [String] = []
    for frame in CollageFrameLibrary.all {
      for cell in frame.cells {
        let inside = cell.count >= 6 && cell.count.isMultiple(of: 2)
        if !inside || cell.contains(where: { $0 < 0 || $0 > 1 }) {
          bad.append(frame.id)
        }
      }
    }
    #expect(bad.isEmpty, "\(bad)")
  }

  @Test("no two cells of a layout overlap, sampled on a 100 by 100 grid")
  func cellsDoNotOverlap() {
    for frame in CollageFrameLibrary.all {
      let boxes = frame.cells.map { Self.box(of: $0) }
      var overlapping = 0
      for column in 0..<100 {
        for row in 0..<100 {
          // The offsets keep the sample points from falling exactly on a side.
          let x = (Double(column) + 0.37) / 100
          let y = (Double(row) + 0.61) / 100
          var hits = 0
          for index in frame.cells.indices where Self.isIn(boxes[index], x, y) {
            if Self.contains(frame.cells[index], x, y) {
              hits += 1
            }
          }
          if hits > 1 {
            overlapping += 1
          }
        }
      }
      #expect(overlapping == 0, "\(frame.id)")
    }
  }

  @Test(
    "the cells of every layout cover no more than the canvas, up to the rounding of the corners")
  func cellAreaWithinCanvas() {
    // The corners are rounded to four decimals, so a shared side can be off by 0.0001: the total area can then
    // exceed the canvas by a few hundredths of a percent. A real overlap would be far larger.
    for frame in CollageFrameLibrary.all {
      let total = frame.cells.reduce(0) { $0 + Self.area($1) }
      #expect(total <= 1 + 1e-3, "\(frame.id): \(total)")
    }
  }

  @Test(
    "without a gap the cells of a layout fill the usable area, except the layouts with open gaps")
  func cellsFillWithoutGap() throws {
    let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
    for frame in CollageFrameLibrary.all where !Self.openGaps.contains(frame.id) {
      let paths = try #require(CollageFrameLibrary.cells(frame, in: rect, gap: 0), "\(frame.id)")
      let total = paths.reduce(0.0) { $0 + Self.pathArea(of: $1) }
      #expect(abs(total - 240_000) < 240_000 * 2e-3, "\(frame.id): \(total)")
    }
  }

  @Test("neighbouring cells are a gap apart and the margin keeps them off the edge")
  func gapBetweenCells() throws {
    let frame = try #require(CollageFrameLibrary.frame(id: "collage_2_0"))
    let rect = CGRect(x: 8, y: 8, width: 584, height: 384)
    let paths = try #require(CollageFrameLibrary.cells(frame, in: rect, gap: 4))
    let left = paths[0].boundingBoxOfPath
    let right = paths[1].boundingBoxOfPath
    #expect(abs(left.minX - 8) < 1e-9)
    #expect(abs(left.minY - 8) < 1e-9)
    #expect(abs(right.maxX - 592) < 1e-9)
    #expect(abs(right.maxY - 392) < 1e-9)
    #expect(abs((right.minX - left.maxX) - 4) < 1e-9)
  }

  @Test("a gap too large for the cells leaves no room, so the layout is refused")
  func refusesTooLargeGap() throws {
    let frame = try #require(CollageFrameLibrary.frame(id: "collage_2_0"))
    let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
    #expect(CollageFrameLibrary.cells(frame, in: rect, gap: 1000) == nil)
  }

  @Test("a frame layout takes only the number of pictures it has")
  func rejectsOtherCounts() {
    let settings = CollageLayout.Settings(gap: 0, margin: 0)
    #expect(
      CollageTemplates.cells(
        .frame("collage_2_0"), count: 3, width: 60, height: 40, settings: settings)
        == nil)
    #expect(
      CollageTemplates.cells(
        .frame("collage_99_0"), count: 99, width: 60, height: 40, settings: settings)
        == nil)
    #expect(
      CollageTemplates.cells(
        .frame("collage_15_2"), count: 17, width: 60, height: 40, settings: settings)
        != nil)
  }

  @Test("frame layouts are offered for the picture count they take")
  func offeredByCount() {
    var composition = CollageComposition()
    composition.setPictureSizes(Array(repeating: CGSize(width: 200, height: 100), count: 2))
    let two = composition.availableTemplates
    #expect(two.contains(.frame("collage_2_0")))
    #expect(!two.contains(.frame("collage_3_0")))
    #expect(CollageTemplate.allCases.count == 7 + 308 + 8)
  }

  @Test("a frame layout renders each picture into its cell")
  func renderFrame() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 10, height: 10)
    let blue = TestImages.solid(RGBA(red: 0, green: 0, blue: 255), width: 10, height: 10)
    let settings = CollageLayout.Settings(gap: 0, margin: 0, background: (0, 0, 0))
    let collage = try #require(
      CollageTemplates.render(
        [red, blue], template: .frame("collage_2_0"), width: 60, height: 40, settings: settings))
    let raster = try #require(RasterImage(collage))
    #expect(raster.pixel(x: 5, y: 20).red > 200)
    #expect(raster.pixel(x: 55, y: 20).blue > 200)
  }
}
