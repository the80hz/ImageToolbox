import CoreGraphics
import Testing

@testable import ImageToolboxKit

@Suite("Moving a markup layer by an offset")
struct MarkupLayerMoveTests {

  private let ink = MarkupColour(red: 1, green: 0, blue: 0)
  private let offset = CGPoint(x: 10, y: -4)

  @Test("a shape moves its frame and keeps its size and style")
  func shapeMoves() {
    let layer = MarkupLayer(
      name: "Box",
      content: .shape(
        kind: .rectangle, frame: CGRect(x: 5, y: 6, width: 30, height: 20), strokeWidth: 2,
        strokeColour: ink, fillColour: nil))
    let moved = layer.translated(by: offset)

    guard case .shape(let kind, let frame, let strokeWidth, _, let fill, _) = moved.content else {
      Issue.record("the content changed kind")
      return
    }
    #expect(kind == .rectangle)
    #expect(frame == CGRect(x: 15, y: 2, width: 30, height: 20))
    #expect(strokeWidth == 2)
    #expect(fill == nil)
  }

  @Test("text moves its origin and keeps its string, size and rotation")
  func textMoves() {
    let layer = MarkupLayer(
      name: "Text",
      content: .text(
        string: "Hi", fontName: "Helvetica", fontSize: 20, colour: ink,
        origin: CGPoint(x: 1, y: 2), rotation: 0.5))
    let moved = layer.translated(by: offset)

    guard
      case .text(let string, let font, let size, _, let origin, let rotation, _, _) = moved.content
    else {
      Issue.record("the content changed kind")
      return
    }
    #expect(string == "Hi")
    #expect(font == "Helvetica")
    #expect(size == 20)
    #expect(origin == CGPoint(x: 11, y: -2))
    #expect(rotation == 0.5)
  }

  @Test("a stroke moves every point by the same offset")
  func strokeMoves() {
    let points = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 7), CGPoint(x: -2, y: 5)]
    let layer = MarkupLayer(
      name: "Stroke", content: .stroke(points: points, brush: Brush(radius: 3), colour: ink))
    let moved = layer.translated(by: offset)

    guard case .stroke(let movedPoints, let brush, _) = moved.content else {
      Issue.record("the content changed kind")
      return
    }
    #expect(movedPoints == [CGPoint(x: 10, y: -4), CGPoint(x: 13, y: 3), CGPoint(x: 8, y: 1)])
    #expect(brush == Brush(radius: 3))
  }

  @Test("moving keeps the identity, name and layer settings")
  func settingsStay() {
    let layer = MarkupLayer(
      name: "Box", content: .stroke(points: [.zero], brush: Brush(radius: 2), colour: ink),
      isVisible: false, opacity: 0.4, isFlippedHorizontally: true, cornerRadiusPercent: 12)
    let moved = layer.translated(by: offset)

    #expect(moved.id == layer.id)
    #expect(moved.name == "Box")
    #expect(moved.isVisible == false)
    #expect(moved.opacity == 0.4)
    #expect(moved.isFlippedHorizontally)
    #expect(moved.cornerRadiusPercent == 12)
  }

  @Test("a locked layer stays where it is in a document")
  func lockedLayerStays() {
    let layer = MarkupLayer(
      name: "Stroke", content: .stroke(points: [.zero], brush: Brush(radius: 2), colour: ink))
    let document = MarkupDocument().add(layer).setLocked(true, at: 0)
    let moved = document.updating(at: 0) { $0 = $0.translated(by: offset) }

    #expect(moved == document)
  }
}
