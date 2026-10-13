import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite(
  "Markup screen options: shadow opacity and colour, arrow heads, regular shapes, line width and turn"
)
struct MarkupOptionTests {

  private let white = RGBA(red: 255, green: 255, blue: 255)
  private let black = RGBA(red: 0, green: 0, blue: 0)
  private let red = RGBA(red: 255, green: 0, blue: 0)

  // MARK: - Shadow opacity and colour

  @Test("a shadow with zero alpha draws nothing, so the layer renders as if it had no shadow")
  func transparentShadowIsInvisible() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let frame = CGRect(x: 10, y: 10, width: 10, height: 10)
    let plain = try render(MarkupDocument().add(fill(frame)), over: base)
    let clear = MarkupShadow(alpha: 0, offsetX: 0, offsetY: 6, blurRadius: 0)
    let shadowed = try render(MarkupDocument().add(fill(frame, shadow: clear)), over: base)
    #expect(shadowed.pixels == plain.pixels)
  }

  @Test("a half transparent black shadow mixes half way into white")
  func halfTransparentShadow() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let frame = CGRect(x: 10, y: 10, width: 10, height: 10)
    let shadow = MarkupShadow(alpha: 0.5, offsetX: 0, offsetY: 6, blurRadius: 0)
    let image = try render(MarkupDocument().add(fill(frame, shadow: shadow)), over: base)
    // Below the layer, inside the shadow and outside the layer itself.
    #expect((120...136).contains(Int(image.pixel(x: 15, y: 23).red)))
  }

  @Test("the colour of a shadow is the colour it is drawn in, with full alpha by default")
  func shadowColourIsDrawn() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let frame = CGRect(x: 10, y: 10, width: 10, height: 10)
    let shadow = MarkupShadow(
      colour: MarkupColour(red: 1, green: 0, blue: 0), offsetX: 0, offsetY: 6, blurRadius: 0)
    let image = try render(MarkupDocument().add(fill(frame, shadow: shadow)), over: base)
    #expect(image.pixel(x: 15, y: 23) == red)
  }

  @Test("shadow alpha is clamped to 0...1 and round trips through Codable")
  func shadowAlphaClampsAndRoundTrips() throws {
    #expect(MarkupShadow().alpha == 1)
    #expect(MarkupShadow(alpha: 3).alpha == 1)
    #expect(MarkupShadow(alpha: -1).alpha == 0)
    let shadow = MarkupShadow(alpha: 0.25)
    #expect(
      try JSONDecoder().decode(MarkupShadow.self, from: JSONEncoder().encode(shadow)) == shadow)
  }

  // MARK: - Arrow heads and regular shapes

  @Test("a larger head scale makes a wider head, which reaches further back from the tip")
  func arrowSizeScaleWidensHead() {
    let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
    let small = MarkupShapeGeometry.path(
      kind: .arrow, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(arrowSizeScale: 0.5))
    let large = MarkupShapeGeometry.path(
      kind: .arrow, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(arrowSizeScale: 8))
    let point = CGPoint(x: 25, y: 3)
    #expect(!small.contains(point))
    #expect(large.contains(point))
  }

  @Test("a smaller head angle opens the sides of the head, and a larger one flattens it")
  func arrowAngleOpensHead() {
    let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
    let open = MarkupShapeGeometry.path(
      kind: .arrow, frame: frame, strokeWidth: 0, style: MarkupShapeStyle(arrowAngle: 100))
    let flat = MarkupShapeGeometry.path(
      kind: .arrow, frame: frame, strokeWidth: 0, style: MarkupShapeStyle(arrowAngle: 175))
    let point = CGPoint(x: 38, y: 8)
    #expect(open.contains(point))
    #expect(!flat.contains(point))
  }

  @Test(
    "a regular polygon or star is inscribed in a circle, so a wide frame gives a narrower outline")
  func regularShapesFitCircle() {
    let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
    let regularPolygon = MarkupShapeGeometry.path(
      kind: .polygon, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(vertices: 4, isRegular: true))
    let stretchedPolygon = MarkupShapeGeometry.path(
      kind: .polygon, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(vertices: 4, isRegular: false))
    #expect(abs(regularPolygon.boundingBoxOfPath.width - 20) < 0.001)
    #expect(abs(stretchedPolygon.boundingBoxOfPath.width - 40) < 0.001)

    let regularStar = MarkupShapeGeometry.path(
      kind: .star, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(vertices: 5, isRegular: true))
    let stretchedStar = MarkupShapeGeometry.path(
      kind: .star, frame: frame, strokeWidth: 0,
      style: MarkupShapeStyle(vertices: 5, isRegular: false))
    #expect(regularStar.boundingBoxOfPath.width < 20)
    #expect(stretchedStar.boundingBoxOfPath.width > 35)
  }

  // MARK: - Line width and text turn

  @Test("the stroke width of a shape is set in pixels, clamped at zero, and text has none")
  func strokeWidthIsSet() {
    var shape = fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    shape.updateShapeStrokeWidth(5)
    #expect(shape.shapeStrokeWidth == 5)
    shape.updateShapeStrokeWidth(-2)
    #expect(shape.shapeStrokeWidth == 0)

    var text = label("a")
    text.updateShapeStrokeWidth(5)
    #expect(text.shapeStrokeWidth == nil)
  }

  @Test("the turn of a text layer is set in radians, and other layers have none")
  func textRotationIsSet() {
    var text = label("a")
    #expect(text.textRotation == 0)
    text.updateTextRotation(.pi / 2)
    #expect(text.textRotation == .pi / 2)

    var shape = fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    shape.updateTextRotation(.pi)
    #expect(shape.textRotation == nil)
  }

  // MARK: - Helpers

  private func render(_ document: MarkupDocument, over base: CGImage) throws -> RasterImage {
    let image = try #require(MarkupRenderer.render(base: base, document: document))
    return try #require(RasterImage(image))
  }

  private func fill(_ frame: CGRect, shadow: MarkupShadow? = nil) -> MarkupLayer {
    MarkupLayer(
      name: "fill",
      content: .shape(
        kind: .rectangle, frame: frame, strokeWidth: 0,
        strokeColour: MarkupColour(red: 0, green: 0, blue: 0),
        fillColour: MarkupColour(red: 0, green: 0, blue: 0)),
      shadow: shadow)
  }

  private func label(_ text: String) -> MarkupLayer {
    MarkupLayer(
      name: text,
      content: .text(
        string: text, fontName: "Helvetica", fontSize: 24,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: .zero, rotation: 0))
  }
}
