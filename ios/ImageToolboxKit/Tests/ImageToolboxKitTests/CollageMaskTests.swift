import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage masks")
struct CollageMaskTests {

  private static var cell: CGPath {
    CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: 100), transform: nil)
  }

  private static var square: CGPath {
    CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: 200), transform: nil)
  }

  @Test("the plain mask leaves the cell as it is")
  func plainMask() {
    let mask = CollageMask.none
    #expect(mask.isIdentity)
    #expect(mask.path(in: Self.cell) == Self.cell)
    #expect(mask.outline(in: Self.cell) == Self.cell)
  }

  @Test("a negative corner radius is treated as none")
  func negativeRadius() {
    #expect(CollageMask(shape: .rectangle, cornerRadius: -5).cornerRadius == 0)
    #expect(CollageMask(shape: .heart, cornerRadius: 10).isIdentity == false)
  }

  @Test("a rounded rectangle cuts off the corners and keeps the sides")
  func roundedRectangle() {
    let path = CollageMask(shape: .rectangle, cornerRadius: 30).path(in: Self.cell)
    #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 200, height: 100))
    #expect(!path.contains(CGPoint(x: 1, y: 1)))
    #expect(!path.contains(CGPoint(x: 199, y: 99)))
    #expect(path.contains(CGPoint(x: 100, y: 1)))
    #expect(path.contains(CGPoint(x: 1, y: 50)))
    #expect(path.contains(CGPoint(x: 30, y: 30)))
  }

  @Test("the corner radius is limited to half of the shorter side")
  func radiusIsLimited() {
    let path = CollageMask(shape: .rectangle, cornerRadius: 10_000).path(in: Self.cell)
    #expect(path.boundingBox.width.rounded() == 200)
    #expect(path.boundingBox.height.rounded() == 100)
    // A full-height pill: the middle of the long sides is still inside.
    #expect(path.contains(CGPoint(x: 100, y: 2)))
    #expect(path.contains(CGPoint(x: 100, y: 98)))
    #expect(!path.contains(CGPoint(x: 2, y: 2)))
  }

  @Test("an ellipse fills the cell and leaves the corners")
  func ellipse() {
    let path = CollageMask(shape: .ellipse).path(in: Self.cell)
    #expect(path.boundingBox == Self.cell.boundingBox)
    #expect(path.contains(CGPoint(x: 100, y: 50)))
    #expect(path.contains(CGPoint(x: 190, y: 50)))
    #expect(!path.contains(CGPoint(x: 5, y: 5)))
  }

  @Test("a circle is as large as the shorter side and centred")
  func circle() {
    let box = CollageMask(shape: .circle).path(in: Self.cell).boundingBox
    #expect(box == CGRect(x: 50, y: 0, width: 100, height: 100))
  }

  @Test("a hexagon is regular, points left and right, and fits the cell")
  func hexagon() throws {
    let path = CollageMask(shape: .hexagon).path(in: Self.square)
    let points = try #require(CollageMask.polygonPoints(of: path))
    #expect(points.count == 6)
    let box = path.boundingBox
    #expect(abs(box.width - 200) < 1e-6)
    #expect(abs(box.height - 200 * 3.0.squareRoot() / 2) < 1e-6)
    #expect(abs(box.midX - 100) < 1e-6 && abs(box.midY - 100) < 1e-6)
    // All sides have the same length.
    let sides = points.indices.map {
      hypot(points[($0 + 1) % 6].x - points[$0].x, points[($0 + 1) % 6].y - points[$0].y)
    }
    #expect(sides.allSatisfy { abs($0 - 100) < 1e-6 })
    #expect(path.contains(CGPoint(x: 100, y: 100)))
    #expect(!path.contains(CGPoint(x: 5, y: 5)))
  }

  @Test("a hexagon in a wide cell is limited by the height")
  func wideHexagon() {
    let wide = CGPath(rect: CGRect(x: 0, y: 0, width: 400, height: 100), transform: nil)
    let box = CollageMask(shape: .hexagon).path(in: wide).boundingBox
    #expect(abs(box.height - 100) < 1e-6)
    #expect(box.width < 400)
    #expect(abs(box.midX - 200) < 1e-6)
  }

  @Test("rounding the hexagon keeps it inside the sharp one")
  func roundedHexagon() {
    let sharp = CollageMask(shape: .hexagon).path(in: Self.square)
    let rounded = CollageMask(shape: .hexagon, cornerRadius: 20).path(in: Self.square)
    // The tip of the sharp hexagon at the left is cut off in the rounded one.
    #expect(sharp.contains(CGPoint(x: 1, y: 100)))
    #expect(!rounded.contains(CGPoint(x: 1, y: 100)))
    #expect(rounded.contains(CGPoint(x: 100, y: 100)))
    #expect(rounded.boundingBox.width < 200)
  }

  @Test("a heart is centred, has a cleft on top and a point at the bottom")
  func heart() {
    let path = CollageMask(shape: .heart).path(in: Self.square)
    let box = path.boundingBox
    #expect(box.width <= 200 + 1e-6 && box.height <= 200 + 1e-6)
    #expect(max(box.width, box.height) > 199)
    #expect(abs(box.midX - 100) < 1e-6 && abs(box.midY - 100) < 1e-6)
    #expect(path.contains(CGPoint(x: 100, y: 100)))
    #expect(path.contains(CGPoint(x: 55, y: 60)))
    // The cleft: just below the top edge, on the centre line, there is no heart.
    #expect(!path.contains(CGPoint(x: 100, y: box.minY + 2)))
    #expect(!path.contains(CGPoint(x: 5, y: 5)))
    #expect(!path.contains(CGPoint(x: 5, y: 195)))
    #expect(!path.contains(CGPoint(x: 195, y: 195)))
  }

  @Test("the outline of a shape in a triangle stays inside the triangle")
  func outlineInsideTriangle() throws {
    let triangle = CGMutablePath()
    triangle.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 200)])
    triangle.closeSubpath()
    let mask = CollageMask(shape: .ellipse)
    // Inside the ellipse of the bounding box, but beyond the long side of the triangle.
    let outside = CGPoint(x: 150, y: 150)
    #expect(mask.path(in: triangle).contains(outside))
    let outline = mask.outline(in: triangle)
    #expect(!outline.contains(outside))
    #expect(outline.contains(CGPoint(x: 60, y: 60)))
  }

  @Test("corners of a diagonal cell are rounded too")
  func roundedTriangle() throws {
    let triangle = CGMutablePath()
    triangle.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 200)])
    triangle.closeSubpath()
    let rounded = CollageMask(shape: .rectangle, cornerRadius: 20).path(in: triangle)
    #expect(triangle.contains(CGPoint(x: 1, y: 1)))
    #expect(!rounded.contains(CGPoint(x: 1, y: 1)))
    #expect(rounded.contains(CGPoint(x: 50, y: 50)))
  }

  @Test("polygon points come only from a single closed polygon of lines")
  func polygonExtraction() {
    #expect(CollageMask.polygonPoints(of: Self.cell)?.count == 4)

    #expect(
      CollageMask.polygonPoints(of: CGPath(ellipseIn: Self.cell.boundingBox, transform: nil)) == nil
    )

    let two = CGMutablePath()
    two.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
    two.addRect(CGRect(x: 20, y: 0, width: 10, height: 10))
    #expect(CollageMask.polygonPoints(of: two) == nil)

    let line = CGMutablePath()
    line.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
    #expect(CollageMask.polygonPoints(of: line) == nil)
  }

  @Test("a zero radius makes the plain polygon")
  func zeroRadiusPolygon() {
    let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
    let path = CollageMask.roundedPolygon(points, radius: 0)
    #expect(path.contains(CGPoint(x: 9, y: 2)))
    #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 10, height: 10))
  }
}
