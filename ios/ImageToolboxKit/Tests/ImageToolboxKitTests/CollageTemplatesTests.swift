import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage templates")
struct CollageTemplatesTests {

  /// A 600 by 400 collage with the usable area 584 by 384 after the margin.
  private static let width = 600.0
  private static let height = 400.0
  private static let settings = CollageLayout.Settings(gap: 4, margin: 8, background: (0, 0, 0))

  /// Each template with a count it takes.
  private static let cases: [(CollageTemplate, Int)] = [
    (.grid, 4), (.splitSideBySide, 2), (.splitStacked, 2), (.hero, 3),
    (.diagonal, 2), (.twoByTwoOffset, 4), (.filmstrip, 3),
  ]

  /// Area of a polygon path, from the shoelace formula over its vertices.
  private static func area(of path: CGPath) -> Double {
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

  @Test("each template makes the number of cells asked for, and they cover the usable area")
  func cellsCoverArea() throws {
    let usable = (Self.width - 16) * (Self.height - 16)
    for (template, count) in Self.cases {
      let paths = try #require(
        CollageTemplates.cells(
          template, count: count, width: Self.width, height: Self.height, settings: Self.settings),
        "\(template)")
      #expect(paths.count == count, "\(template)")
      let total = paths.reduce(0) { $0 + Self.area(of: $1) }
      // The gaps take about 1.7% of the usable area here, so 2% is the tolerance.
      #expect(abs(total - usable) <= usable * 0.02, "\(template): \(total) of \(usable)")
    }
  }

  @Test("without gaps the cells fill the usable area exactly")
  func cellsFillWithoutGaps() throws {
    let flat = CollageLayout.Settings(gap: 0, margin: 8, background: (0, 0, 0))
    let usable = (Self.width - 16) * (Self.height - 16)
    for (template, count) in Self.cases {
      let paths = try #require(
        CollageTemplates.cells(
          template, count: count, width: Self.width, height: Self.height, settings: flat),
        "\(template)")
      let total = paths.reduce(0) { $0 + Self.area(of: $1) }
      #expect(abs(total - usable) < usable * 1e-6, "\(template)")
    }
  }

  @Test("templates reject counts they do not take")
  func rejectsOtherCounts() {
    let size = (width: Self.width, height: Self.height)
    let settings = Self.settings
    func cells(_ template: CollageTemplate, _ count: Int) -> [CGPath]? {
      CollageTemplates.cells(
        template, count: count, width: size.width, height: size.height, settings: settings)
    }
    #expect(cells(.grid, 0) == nil)
    #expect(cells(.grid, 37) == nil)
    #expect(cells(.splitSideBySide, 3) == nil)
    #expect(cells(.splitStacked, 1) == nil)
    #expect(cells(.hero, 1) == nil)
    #expect(cells(.diagonal, 3) == nil)
    #expect(cells(.twoByTwoOffset, 3) == nil)
    #expect(cells(.filmstrip, 9) == nil)
  }

  @Test("the grid template matches the grid layout cells")
  func gridMatchesLayout() throws {
    let paths = try #require(
      CollageTemplates.cells(
        .grid, count: 6, width: Self.width, height: Self.height, settings: Self.settings))
    let rects = try #require(
      CollageLayout.cells(
        count: 6, width: Self.width, height: Self.height, settings: Self.settings))
    for (path, rect) in zip(paths, rects) {
      #expect(path.boundingBoxOfPath == rect)
    }
  }

  @Test("diagonal cells lie on either side of the divider")
  func diagonalSides() throws {
    let paths = try #require(
      CollageTemplates.cells(
        .diagonal, count: 2, width: Self.width, height: Self.height, settings: Self.settings))
    // Centroids of the two triangles, which lie inside their own cell only.
    let topLeftCentre = CGPoint(x: 8 + 584.0 / 3, y: 8 + 384.0 / 3)
    let bottomRightCentre = CGPoint(x: 8 + 584.0 * 2 / 3, y: 8 + 384.0 * 2 / 3)
    #expect(paths[0].contains(topLeftCentre))
    #expect(!paths[1].contains(topLeftCentre))
    #expect(paths[1].contains(bottomRightCentre))
    #expect(!paths[0].contains(bottomRightCentre))
  }

  @Test("split stacked puts the first picture on top")
  func renderStackedOrder() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 10, height: 10)
    let blue = TestImages.solid(RGBA(red: 0, green: 0, blue: 255), width: 10, height: 10)
    let settings = CollageLayout.Settings(gap: 0, margin: 0, background: (0, 0, 0))
    let collage = try #require(
      CollageTemplates.render(
        [red, blue], template: .splitStacked, width: 60, height: 40, settings: settings))
    #expect(collage.width == 60 && collage.height == 40)
    let raster = try #require(RasterImage(collage))
    #expect(raster.pixel(x: 30, y: 5).red > 200)
    #expect(raster.pixel(x: 30, y: 35).blue > 200)
  }

  @Test("diagonal render puts each picture on its own side of the divider")
  func renderDiagonal() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 10, height: 10)
    let blue = TestImages.solid(RGBA(red: 0, green: 0, blue: 255), width: 10, height: 10)
    let settings = CollageLayout.Settings(gap: 0, margin: 0, background: (0, 0, 0))
    let collage = try #require(
      CollageTemplates.render(
        [red, blue], template: .diagonal, width: 120, height: 60, settings: settings))
    let raster = try #require(RasterImage(collage))
    #expect(raster.pixel(x: 2, y: 2).red > 200)
    #expect(raster.pixel(x: 117, y: 57).blue > 200)
  }

  @Test("render returns nil when the picture count does not fit the template")
  func renderRejectsCount() {
    let picture = TestImages.solid(RGBA(red: 0, green: 0, blue: 0), width: 4, height: 4)
    #expect(
      CollageTemplates.render(
        [picture], template: .splitSideBySide, width: 60, height: 40, settings: Self.settings)
        == nil)
  }
}
