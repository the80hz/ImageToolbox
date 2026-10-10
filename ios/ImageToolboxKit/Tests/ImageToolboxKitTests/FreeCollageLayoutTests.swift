import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Free collage layouts")
struct FreeCollageLayoutTests {

  private static func layout(_ rects: [CGRect]) throws -> FreeCollageLayout {
    try #require(FreeCollageLayout(rects: rects))
  }

  private static let pair = [
    CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4),
    CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
  ]

  @Test("the grid start has the cells of a grid layout without gaps")
  func gridStart() throws {
    let layout = try #require(FreeCollageLayout.grid(count: 5))
    #expect(layout.count == 5)
    // Three columns and two rows.
    #expect(layout.rects[0] == CGRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5))
    #expect(layout.rects[4].minY == 0.5)
    #expect(layout.drawOrder == [0, 1, 2, 3, 4])
    #expect(FreeCollageLayout.grid(count: 0) == nil)
    #expect(FreeCollageLayout.grid(count: 37) == nil)
  }

  @Test("rectangles are fitted into the unit square and made at least the minimum size")
  func fitting() throws {
    let layout = try Self.layout([
      CGRect(x: 0.8, y: -0.2, width: 0.5, height: 0.01),
      CGRect(x: 0.5, y: 0.5, width: 3, height: 3),
      CGRect(x: 0.9, y: 0.9, width: -0.3, height: -0.3),
    ])
    #expect(layout.rects[0] == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.05))
    #expect(layout.rects[1] == CGRect(x: 0, y: 0, width: 1, height: 1))
    #expect(abs(layout.rects[2].minX - 0.6) < 1e-12 && abs(layout.rects[2].width - 0.3) < 1e-12)
  }

  @Test("no rectangles or a rectangle that is not a number make no layout")
  func invalidInput() {
    #expect(FreeCollageLayout(rects: []) == nil)
    #expect(
      FreeCollageLayout(rects: [CGRect(x: CGFloat.nan, y: 0, width: 0.5, height: 0.5)]) == nil)
    #expect(
      FreeCollageLayout(rects: [CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 0.5)]) == nil)
  }

  @Test("a draw order that is not a permutation is replaced")
  func drawOrderValidation() throws {
    let valid = try #require(FreeCollageLayout(rects: Self.pair, drawOrder: [1, 0]))
    #expect(valid.drawOrder == [1, 0])
    let repeated = try #require(FreeCollageLayout(rects: Self.pair, drawOrder: [1, 1]))
    #expect(repeated.drawOrder == [0, 1])
    let short = try #require(FreeCollageLayout(rects: Self.pair, drawOrder: [0]))
    #expect(short.drawOrder == [0, 1])
  }

  @Test("moving keeps the size and stops at the edges of the usable area")
  func moving() throws {
    let layout = try Self.layout(Self.pair)
    let moved = layout.moving(0, by: CGVector(dx: 0.2, dy: 0.1))
    #expect(abs(moved.rects[0].minX - 0.3) < 1e-12 && abs(moved.rects[0].minY - 0.2) < 1e-12)
    #expect(moved.rects[0].size == layout.rects[0].size)
    #expect(moved.rects[1] == layout.rects[1])

    let far = layout.moving(1, by: CGVector(dx: 5, dy: -5))
    #expect(abs(far.rects[1].maxX - 1) < 1e-12 && far.rects[1].minY == 0)
    let near = layout.moving(1, by: CGVector(dx: -5, dy: 5))
    #expect(near.rects[1].minX == 0 && abs(near.rects[1].maxY - 1) < 1e-12)
  }

  @Test("editing an index out of range or by a number that is not finite changes nothing")
  func ignoredEdits() throws {
    let layout = try Self.layout(Self.pair)
    #expect(layout.moving(2, by: CGVector(dx: 0.1, dy: 0.1)) == layout)
    #expect(layout.moving(-1, by: CGVector(dx: 0.1, dy: 0.1)) == layout)
    #expect(layout.moving(0, by: CGVector(dx: CGFloat.nan, dy: 0)) == layout)
    #expect(layout.resizing(5, handle: .topLeft, by: CGVector(dx: 0.1, dy: 0.1)) == layout)
    #expect(
      layout.resizing(0, handle: .topLeft, by: CGVector(dx: CGFloat.infinity, dy: 0)) == layout)
    #expect(layout.bringingToFront(9) == layout)
    #expect(layout.sendingToBack(-1) == layout)
  }

  @Test("dragging the bottom right corner resizes and keeps the top left corner")
  func resizeBottomRight() throws {
    let layout = try Self.layout(Self.pair)
    let resized = layout.resizing(0, handle: .bottomRight, by: CGVector(dx: 0.2, dy: -0.1))
    #expect(resized.rects[0].origin == layout.rects[0].origin)
    #expect(abs(resized.rects[0].width - 0.6) < 1e-12)
    #expect(abs(resized.rects[0].height - 0.3) < 1e-12)
  }

  @Test("dragging the top left corner resizes and keeps the bottom right corner")
  func resizeTopLeft() throws {
    let layout = try Self.layout(Self.pair)
    let resized = layout.resizing(1, handle: .topLeft, by: CGVector(dx: -0.1, dy: 0.1))
    #expect(abs(resized.rects[1].minX - 0.2) < 1e-12 && abs(resized.rects[1].minY - 0.4) < 1e-12)
    #expect(abs(resized.rects[1].maxX - 0.7) < 1e-12 && abs(resized.rects[1].maxY - 0.7) < 1e-12)
  }

  @Test("each corner keeps the opposite one fixed")
  func everyCornerKeepsOpposite() throws {
    let layout = try Self.layout([CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)])
    let delta = CGVector(dx: 0.1, dy: 0.05)
    let rect = layout.rects[0]
    let topRight = layout.resizing(0, handle: .topRight, by: delta).rects[0]
    #expect(abs(topRight.minX - rect.minX) < 1e-12 && abs(topRight.maxY - rect.maxY) < 1e-12)
    #expect(abs(topRight.maxX - 0.85) < 1e-12 && abs(topRight.minY - 0.3) < 1e-12)
    let bottomLeft = layout.resizing(0, handle: .bottomLeft, by: delta).rects[0]
    #expect(abs(bottomLeft.maxX - rect.maxX) < 1e-12 && abs(bottomLeft.minY - rect.minY) < 1e-12)
    #expect(abs(bottomLeft.minX - 0.35) < 1e-12 && abs(bottomLeft.maxY - 0.8) < 1e-12)
  }

  @Test("a cell cannot be resized below the minimum or outside the usable area")
  func resizeLimits() throws {
    let layout = try Self.layout(Self.pair)
    let tiny = layout.resizing(0, handle: .bottomRight, by: CGVector(dx: -5, dy: -5))
    #expect(abs(tiny.rects[0].width - FreeCollageLayout.minimumSize) < 1e-12)
    #expect(abs(tiny.rects[0].height - FreeCollageLayout.minimumSize) < 1e-12)
    let flipped = layout.resizing(0, handle: .topLeft, by: CGVector(dx: 5, dy: 5))
    #expect(abs(flipped.rects[0].maxX - 0.5) < 1e-12)
    #expect(abs(flipped.rects[0].width - FreeCollageLayout.minimumSize) < 1e-12)
    let huge = layout.resizing(1, handle: .bottomRight, by: CGVector(dx: 5, dy: 5))
    #expect(abs(huge.rects[1].maxX - 1) < 1e-12 && abs(huge.rects[1].maxY - 1) < 1e-12)
    let beyond = layout.resizing(1, handle: .topLeft, by: CGVector(dx: -5, dy: -5))
    #expect(beyond.rects[1].minX == 0 && beyond.rects[1].minY == 0)
  }

  @Test("bringing to front and sending to back reorder drawing without moving pictures")
  func reordering() throws {
    let layout = try Self.layout(Self.pair + [CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3)])
    #expect(layout.bringingToFront(0).drawOrder == [1, 2, 0])
    #expect(layout.sendingToBack(2).drawOrder == [2, 0, 1])
    #expect(layout.bringingToFront(2).drawOrder == [0, 1, 2])
    #expect(layout.bringingToFront(0).rects == layout.rects)
  }

  @Test("a hit test finds the topmost cell")
  func hitTesting() throws {
    let layout = try Self.layout(Self.pair)
    let overlap = CGPoint(x: 0.4, y: 0.4)
    #expect(layout.hitTest(overlap) == 1)
    #expect(layout.bringingToFront(0).hitTest(overlap) == 0)
    #expect(layout.hitTest(CGPoint(x: 0.15, y: 0.15)) == 0)
    #expect(layout.hitTest(CGPoint(x: 0.9, y: 0.9)) == nil)
  }

  @Test("touching cells end up one gap apart and the outer sides stay on the margin")
  func gapAndMargin() throws {
    let layout = try Self.layout([
      CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
    ])
    let settings = CollageLayout.Settings(gap: 10, margin: 10)
    let paths = try #require(layout.cellPaths(width: 120, height: 60, settings: settings))
    #expect(paths[0].boundingBox == CGRect(x: 10, y: 10, width: 45, height: 40))
    #expect(paths[1].boundingBox == CGRect(x: 65, y: 10, width: 45, height: 40))
  }

  @Test("cell paths are rectangles in the order of the pictures")
  func cellPathsAreRects() throws {
    let layout = try Self.layout(Self.pair)
    let paths = try #require(
      layout.cellPaths(width: 100, height: 100, settings: CollageLayout.Settings(gap: 0, margin: 0))
    )
    #expect(paths.count == 2)
    #expect(paths.allSatisfy { $0.isRect(nil) })
    #expect(paths[1].boundingBox == CGRect(x: 30, y: 30, width: 40, height: 40))
  }

  @Test("a huge gap still leaves a pixel for each cell, and a huge margin leaves no layout")
  func extremeSettings() throws {
    let layout = try #require(FreeCollageLayout.grid(count: 4))
    let wide = try #require(
      layout.cellPaths(
        width: 100, height: 100, settings: CollageLayout.Settings(gap: 500, margin: 0)))
    #expect(wide.allSatisfy { $0.boundingBox.width >= 1 && $0.boundingBox.height >= 1 })
    #expect(
      layout.cellPaths(
        width: 100, height: 100, settings: CollageLayout.Settings(gap: 0, margin: 50)) == nil)
  }
}
