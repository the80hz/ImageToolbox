import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Draw scene: edits replayed in order")
struct DrawSceneTests {

  private func pen(_ points: [CGPoint], radius: Double = 3) -> DrawingEdit {
    .stroke(
      DrawingStroke(
        points: points, brush: Brush(radius: radius, hardness: 1), kind: .pen, style: .solid))
  }

  private func stroke(_ kind: DrawingPaintKind, at point: CGPoint, radius: Double) -> DrawingEdit {
    .stroke(
      DrawingStroke(
        points: [point], brush: Brush(radius: radius, hardness: 1), kind: kind, style: .solid))
  }

  private func rectangle(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat)
    -> [CGPoint]
  {
    [
      CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom),
      CGPoint(x: left, y: bottom),
    ]
  }

  @Test("no edits give a transparent picture")
  func emptyIsTransparent() {
    let picture = DrawingScene.render([], side: 8, colour: (0, 0, 0))
    #expect(picture.pixels.allSatisfy { $0 == 0 })
  }

  @Test("pen ink takes the drawing colour and is opaque on the stroke only")
  func penInk() {
    let picture = DrawingScene.render(
      [pen([CGPoint(x: 4, y: 4)])], side: 10, colour: (200, 10, 20))
    #expect(picture.pixel(x: 4, y: 4) == RGBA(red: 200, green: 10, blue: 20))
    #expect(picture.pixel(x: 0, y: 0).alpha == 0)
  }

  @Test("an eraser removes the ink drawn before it, and not the ink drawn after it")
  func eraserOnlyReachesEarlierInk() {
    let spot = CGPoint(x: 5, y: 5)
    let before = DrawingScene.render(
      [pen([spot], radius: 4), stroke(.eraser, at: spot, radius: 4)], side: 12, colour: (1, 2, 3))
    #expect(before.pixel(x: 5, y: 5).alpha == 0)

    let after = DrawingScene.render(
      [
        pen([spot], radius: 4), stroke(.eraser, at: spot, radius: 4),
        pen([spot], radius: 1),
      ],
      side: 12, colour: (1, 2, 3))
    #expect(after.pixel(x: 5, y: 5) == RGBA(red: 1, green: 2, blue: 3))
  }

  @Test("a highlighter tints at its opacity, not at full strength")
  func highlighterOpacity() {
    let picture = DrawingScene.render(
      [stroke(.highlighter, at: CGPoint(x: 3, y: 3), radius: 4)], side: 8, colour: (255, 0, 0))
    let alpha = Int(picture.pixel(x: 3, y: 3).alpha)
    #expect(abs(alpha - Int((255 * RegionEffects.highlighterOpacity).rounded())) <= 1)
    #expect(picture.pixel(x: 3, y: 3).red == 255)
  }

  @Test("a flood fill spreads over transparency and stops at ink drawn before it")
  func floodStopsAtInk() {
    // A vertical wall of ink at x = 4 and 5 splits the transparent picture in two.
    let wall = pen([CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 9)], radius: 1)
    let picture = DrawingScene.render(
      [wall, .flood(at: CGPoint(x: 0, y: 0), tolerance: 0)], side: 10, colour: (0, 0, 255))
    #expect(picture.pixel(x: 2, y: 2) == RGBA(red: 0, green: 0, blue: 255))
    #expect(picture.pixel(x: 5, y: 5) == RGBA(red: 0, green: 0, blue: 255))
    #expect(picture.pixel(x: 9, y: 9).alpha == 0)
  }

  @Test("a lasso clear removes the pixels inside its outline and keeps the rest")
  func lassoClear() {
    let picture = DrawingScene.render(
      [
        .flood(at: CGPoint(x: 0, y: 0), tolerance: 1),
        .lasso(polygon: rectangle(2, 2, 6, 6), action: .clear),
      ],
      side: 10, colour: (9, 9, 9))
    #expect(picture.pixel(x: 3, y: 3).alpha == 0)
    #expect(picture.pixel(x: 8, y: 8) == RGBA(red: 9, green: 9, blue: 9))
  }

  @Test("a lasso fill paints its pixels opaque, including transparent ones")
  func lassoFillPaintsTransparent() {
    let picture = DrawingScene.render(
      [.lasso(polygon: rectangle(2, 2, 6, 6), action: .fill)], side: 10, colour: (4, 5, 6))
    #expect(picture.pixel(x: 3, y: 3) == RGBA(red: 4, green: 5, blue: 6))
    #expect(picture.pixel(x: 8, y: 8).alpha == 0)
  }

  @Test("a committed PencilKit patch lands at its place and takes the drawing colour")
  func pencilPatchPlacement() {
    let patch = DrawingPencilPatch(x: 2, y: 1, width: 2, height: 1, coverage: [255, 128])
    let picture = DrawingScene.render([.pencil(patch)], side: 6, colour: (0, 0, 255))
    #expect(picture.pixel(x: 2, y: 1) == RGBA(red: 0, green: 0, blue: 255))
    #expect(abs(Int(picture.pixel(x: 3, y: 1).alpha) - 128) <= 1)
    #expect(picture.pixel(x: 0, y: 0).alpha == 0)
  }

  @Test("a spray drag with a fixed seed paints the same picture on every render")
  func sprayReplays() {
    let spray = DrawingSpray(
      points: [CGPoint(x: 8, y: 8)], radius: 4, density: 20, dotSize: 2, square: false, seed: 99)
    let first = DrawingScene.render([.spray(spray)], side: 16, colour: (1, 2, 3))
    let again = DrawingScene.render([.spray(spray)], side: 16, colour: (1, 2, 3))
    #expect(first.pixels == again.pixels)
    #expect(first.pixels.contains { $0 != 0 })
  }

  @Test("a warp with no samples changes nothing")
  func emptyWarpIsNoOp() {
    let warp = DrawingWarpStroke(
      samples: [], radius: 8, strength: 1, hardness: 0, mode: .swirlClockwise)
    let picture = DrawingScene.render([pen([CGPoint(x: 4, y: 4)])], side: 9, colour: (7, 7, 7))
    let warped = DrawingScene.render(
      [pen([CGPoint(x: 4, y: 4)]), .warp(warp)], side: 9, colour: (7, 7, 7))
    #expect(warped.pixels == picture.pixels)
  }

  @Test("a shape is painted with its brush after the ink before it")
  func shapePaints() {
    let line = DrawingShapeEdit(
      kind: .line, start: CGPoint(x: 1, y: 5), end: CGPoint(x: 9, y: 5), filled: false,
      brush: Brush(radius: 1, hardness: 1), options: ShapeOptions())
    let picture = DrawingScene.render([.shape(line)], side: 10, colour: (30, 40, 50))
    #expect(picture.pixel(x: 5, y: 5) == RGBA(red: 30, green: 40, blue: 50))
    #expect(picture.pixel(x: 5, y: 0).alpha == 0)
  }
}
