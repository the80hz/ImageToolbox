import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

private func near(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-6) -> Bool {
  abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

@Suite("Shape outlines for triangles, polygons, stars and arrows")
struct ShapeOutlineTests {

  @Test("a triangle has its top edge between the points and its apex at the second point's height")
  func triangleVertices() {
    let outline = ShapeOutline.make(
      .triangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 40), strokeWidth: 4)
    #expect(
      outline.polygon == [
        CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 20, y: 40),
      ])
  }

  @Test("a regular four-sided polygon starts at the bottom and goes round the inscribed circle")
  func regularPolygon() throws {
    let options = ShapeOptions(sides: 4, isRegular: true)
    let outline = ShapeOutline.make(
      .polygon, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 20), options: options,
      strokeWidth: 4)
    let polygon = try #require(outline.polygon)
    #expect(polygon.count == 4)
    #expect(near(polygon[0], CGPoint(x: 10, y: 20), tolerance: 1e-9))
    #expect(near(polygon[1], CGPoint(x: 0, y: 10), tolerance: 1e-9))
    #expect(near(polygon[2], CGPoint(x: 10, y: 0), tolerance: 1e-9))
  }

  @Test("a stretched polygon fills the rectangle instead of a circle")
  func stretchedPolygonFillsRectangle() throws {
    let options = ShapeOptions(sides: 4, isRegular: false)
    let outline = ShapeOutline.make(
      .polygon, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 10), options: options,
      strokeWidth: 4)
    let polygon = try #require(outline.polygon)
    #expect(near(polygon[0], CGPoint(x: 20, y: 10), tolerance: 1e-9))
    #expect(near(polygon[1], CGPoint(x: 0, y: 5), tolerance: 1e-9))
  }

  @Test("a star alternates outer and inner vertices, and closes its outline")
  func starVertices() throws {
    let options = ShapeOptions(sides: 5, innerRatio: 0.5, isRegular: true)
    let outline = ShapeOutline.make(
      .star, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 20), options: options,
      strokeWidth: 4)
    let polygon = try #require(outline.polygon)
    #expect(polygon.count == 10)
    let centre = CGPoint(x: 10, y: 10)
    for (index, vertex) in polygon.enumerated() {
      let distance = hypot(vertex.x - centre.x, vertex.y - centre.y)
      let expected: CGFloat = index.isMultiple(of: 2) ? 10 : 5
      #expect(abs(distance - expected) < 1e-9)
    }
    #expect(outline.strokes.count == 1)
    #expect(outline.strokes[0].first == outline.strokes[0].last)
  }

  @Test("a rectangle turned by a quarter turn moves its corners about the centre")
  func rotatedRectangle() throws {
    let options = ShapeOptions(rotation: 90)
    let outline = ShapeOutline.make(
      .rectangle, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 10), options: options,
      strokeWidth: 4)
    let polygon = try #require(outline.polygon)
    // The top-right corner (20, 0) is 10 right and 5 up of the centre (10, 5). A quarter turn
    // clockwise on screen sends that offset to (5, 10), so the corner lands at (15, 15).
    #expect(near(polygon[0], CGPoint(x: 15, y: 15), tolerance: 1e-9))
  }

  @Test("a rounded rectangle keeps every point inside its bounds")
  func roundedRectangleBounds() throws {
    let outline = ShapeOutline.make(
      .rectangle, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 10),
      options: ShapeOptions(cornerRadius: 0.5), strokeWidth: 4)
    let polygon = try #require(outline.polygon)
    #expect(polygon.count > 4)
    #expect(polygon.allSatisfy { $0.x >= -1e-9 && $0.x <= 20 + 1e-9 })
    #expect(polygon.allSatisfy { $0.y >= -1e-9 && $0.y <= 10 + 1e-9 })
  }

  @Test("an arrow has a shaft and a head of two arms at its tip, each as long as the scale allows")
  func arrowHead() {
    let outline = ShapeOutline.make(
      .arrow, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0),
      options: ShapeOptions(arrowAngle: 150, arrowScale: 3), strokeWidth: 4)
    #expect(outline.polygon == nil)
    #expect(outline.strokes.count == 2)
    let head = outline.strokes[1]
    #expect(head.count == 3)
    #expect(near(head[1], CGPoint(x: 100, y: 0)))
    // The arm is 12 units long, turned 150 degrees from the shaft, so it reaches back and out.
    #expect(abs(head[0].x - (100 - 12 * 0.8660254)) < 1e-6)
    #expect(abs(head[0].y - 6) < 1e-6)
    #expect(abs(head[2].y + 6) < 1e-6)
  }

  @Test("a double arrow adds a head at the first point, pointing back along the shaft")
  func doubleArrowHeads() {
    let outline = ShapeOutline.make(
      .doubleArrow, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), strokeWidth: 4)
    #expect(outline.strokes.count == 3)
    let startHead = outline.strokes[2]
    #expect(near(startHead[1], CGPoint(x: 0, y: 0)))
    #expect(abs(startHead[0].x - 12 * 0.8660254) < 1e-6)
    #expect(abs(startHead[0].y + 6) < 1e-6)
  }

  @Test("an arrow with no length has no head")
  func zeroLengthArrow() {
    let outline = ShapeOutline.make(
      .arrow, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), strokeWidth: 4)
    #expect(outline.strokes.count == 1)
  }

  @Test("a filled triangle covers its centroid, and a filled arrow covers nothing")
  func filledShapesThroughRenderer() {
    var canvas = BrushCanvas(width: 60, height: 50)
    ShapeRenderer.draw(
      .triangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 40), filled: true,
      brush: Brush(radius: 2, hardness: 1), onto: &canvas)
    #expect(canvas.coverage[20 * 60 + 30] > 0.99)
    #expect(canvas.coverage[5 * 60 + 5] == 0)

    var arrowCanvas = BrushCanvas(width: 60, height: 50)
    ShapeRenderer.draw(
      .arrow, from: CGPoint(x: 5, y: 25), to: CGPoint(x: 55, y: 25), filled: true,
      brush: Brush(radius: 1, hardness: 1), onto: &arrowCanvas)
    // Lines and arrows have no interior: the shaft is stroked, and nothing is filled above it.
    #expect(arrowCanvas.coverage[25 * 60 + 30] > 0.99)
    #expect(arrowCanvas.coverage[10 * 60 + 30] == 0)
  }

  @Test("a dashed outline covers fewer pixels than a solid one, but not none")
  func dashedOutlineCoversLess() {
    var solid = BrushCanvas(width: 80, height: 10)
    var dashed = BrushCanvas(width: 80, height: 10)
    let brush = Brush(radius: 1, hardness: 1)
    ShapeRenderer.draw(
      .line, from: CGPoint(x: 2, y: 5), to: CGPoint(x: 78, y: 5), filled: false, brush: brush,
      onto: &solid)
    ShapeRenderer.draw(
      .line, from: CGPoint(x: 2, y: 5), to: CGPoint(x: 78, y: 5), filled: false, brush: brush,
      options: ShapeOptions(lineStyle: .dashed), onto: &dashed)
    let solidSum = solid.coverage.reduce(0, +)
    let dashedSum = dashed.coverage.reduce(0, +)
    #expect(dashedSum > 0)
    #expect(dashedSum < solidSum * 0.6)
  }
}
