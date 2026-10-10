import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Markup layers, rendering and hit testing")
struct MarkupTests {

  private let white = RGBA(red: 255, green: 255, blue: 255)
  private let black = RGBA(red: 0, green: 0, blue: 0)
  private let red = RGBA(red: 255, green: 0, blue: 0)

  // MARK: - Layer stack

  @Test("layers are added on top, removed by index and moved, and every edit returns a new value")
  func layerStackEdits() {
    let first = label("a")
    let second = label("b")
    let third = label("c")
    let stack = MarkupDocument().add(first).add(second).add(third)
    #expect(stack.layers.map(\.id) == [first.id, second.id, third.id])

    let moved = stack.move(from: 0, to: 2)
    #expect(moved.layers.map(\.id) == [second.id, third.id, first.id])
    #expect(stack.layers.map(\.id) == [first.id, second.id, third.id])

    let removed = stack.remove(at: 1)
    #expect(removed.layers.map(\.id) == [first.id, third.id])
    #expect(stack.layers.count == 3)
  }

  @Test("invalid indices leave the document unchanged")
  func invalidIndices() {
    let stack = MarkupDocument().add(label("a")).add(label("b"))
    #expect(stack.remove(at: 5) == stack)
    #expect(stack.remove(at: -1) == stack)
    #expect(stack.move(from: 0, to: 9) == stack)
    #expect(stack.move(from: 1, to: 1) == stack)
    #expect(stack.setVisible(false, at: 2) == stack)
  }

  @Test("setVisible changes only the layer it names")
  func visibility() {
    let doc = MarkupDocument().add(label("a")).add(label("b"))
    let hidden = doc.setVisible(false, at: 1)
    #expect(hidden.layers[1].isVisible == false)
    #expect(hidden.layers[0].isVisible == true)
    #expect(doc.layers[1].isVisible == true)
    #expect(hidden.setVisible(true, at: 1) == doc)
  }

  @Test("documents with the same layers compare equal, and sticker pixels count")
  func equality() {
    let id = UUID()
    let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    let sticker = { (pixels: [UInt8]) in
      MarkupLayer(
        id: id, name: "s",
        content: .sticker(
          raster: RasterImage(width: 1, height: 1, pixels: pixels), frame: frame))
    }
    let same = MarkupDocument().add(sticker([255, 0, 0, 255]))
    #expect(same == MarkupDocument().add(sticker([255, 0, 0, 255])))
    #expect(same != MarkupDocument().add(sticker([0, 255, 0, 255])))
  }

  @Test("documents work as UndoHistory values")
  func undoHistory() {
    var history = UndoHistory(MarkupDocument())
    let drawn = MarkupDocument().add(label("a"))
    history.record(drawn)
    history.undo()
    #expect(history.current == MarkupDocument())
    history.redo()
    #expect(history.current == drawn)
  }

  // MARK: - Rendering

  @Test("a hidden layer is not drawn")
  func hiddenLayerIsSkipped() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let plain = try render(MarkupDocument(), over: base)
    let hidden = try render(
      MarkupDocument().add(fill(CGRect(x: 10, y: 10, width: 10, height: 10), hidden: true)),
      over: base)
    let visible = try render(
      MarkupDocument().add(fill(CGRect(x: 10, y: 10, width: 10, height: 10))),
      over: base)
    #expect(hidden.pixels == plain.pixels)
    #expect(visible.pixels != plain.pixels)
  }

  @Test("opacity 0.5 mixes black half way into white")
  func halfOpacity() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let document = MarkupDocument().add(
      fill(CGRect(x: 10, y: 10, width: 10, height: 10), opacity: 0.5))
    let image = try render(document, over: base)
    let pixel = image.pixel(x: 15, y: 15)
    #expect(abs(Int(pixel.red) - 128) <= 2)
    #expect(abs(Int(pixel.green) - 128) <= 2)
    #expect(pixel.alpha == 255)
  }

  @Test("a filled rectangle changes the pixels inside its frame and no others")
  func rectangleFill() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let layer = MarkupLayer(
      name: "rectangle",
      content: .shape(
        kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 10, height: 10),
        strokeWidth: 0, strokeColour: MarkupColour(red: 0, green: 0, blue: 0),
        fillColour: MarkupColour(red: 1, green: 0, blue: 0)))
    let image = try render(MarkupDocument().add(layer), over: base)

    var mismatches = 0
    for y in 0..<40 {
      for x in 0..<40 {
        let inside = (10..<20).contains(x) && (10..<20).contains(y)
        if image.pixel(x: x, y: y) != (inside ? red : white) { mismatches += 1 }
      }
    }
    #expect(mismatches == 0)
  }

  @Test("a line runs from the frame origin to its far corner")
  func lineShape() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let layer = MarkupLayer(
      name: "line",
      content: .shape(
        kind: .line, frame: CGRect(x: 5, y: 5, width: 10, height: 10),
        strokeWidth: 2, strokeColour: MarkupColour(red: 0, green: 0, blue: 0), fillColour: nil))
    let image = try render(MarkupDocument().add(layer), over: base)
    #expect(image.pixel(x: 10, y: 10).red < 128)
    #expect(image.pixel(x: 10, y: 30).red == 255)
  }

  @Test("text draws ink at its origin, and none above or left of it")
  func textInk() throws {
    let base = TestImages.solid(white, width: 120, height: 40)
    let document = MarkupDocument().add(
      label("Hello", at: CGPoint(x: 10, y: 5), rotation: 0))
    let image = try render(document, over: base)

    var inkInBlock = 0
    var inkOutside = 0
    for y in 0..<40 {
      for x in 0..<120 where image.pixel(x: x, y: y).red < 128 {
        if x >= 10 && y >= 5 { inkInBlock += 1 } else { inkOutside += 1 }
      }
    }
    #expect(inkInBlock > 100)
    #expect(inkOutside == 0)
  }

  @Test("rotated text turns clockwise around its origin, and hit testing follows the drawing")
  func rotatedTextAndHitTest() throws {
    let base = TestImages.solid(white, width: 120, height: 120)
    let document = MarkupDocument().add(
      label("Hello", at: CGPoint(x: 60, y: 20), rotation: .pi / 2))
    let image = try render(document, over: base)

    // Clockwise on screen, the text reads downwards, so its ink lies left of x = 60 and below y = 20.
    var inkRight = 0
    var inkAbove = 0
    var firstInk: CGPoint?
    for y in 0..<120 {
      for x in 0..<120 where image.pixel(x: x, y: y).red < 128 {
        if x > 61 { inkRight += 1 }
        if y < 19 { inkAbove += 1 }
        if firstInk == nil { firstInk = CGPoint(x: x, y: y) }
      }
    }
    #expect(inkRight == 0)
    #expect(inkAbove == 0)

    let ink = try #require(firstInk)
    #expect(document.layerIndex(at: CGPoint(x: ink.x + 0.5, y: ink.y + 0.5)) == 0)
    #expect(document.layerIndex(at: CGPoint(x: 70, y: 30)) == nil)
  }

  @Test("a sticker is scaled into its frame, with its top row at the top")
  func stickerFrame() throws {
    // Row 0 of a RasterImage is the top row: red above, blue below.
    let sticker = RasterImage(
      width: 2, height: 2,
      pixels: [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255])
    let layer = MarkupLayer(
      name: "sticker",
      content: .sticker(
        raster: sticker, frame: CGRect(x: 10, y: 5, width: 20, height: 10)))
    let base = TestImages.solid(white, width: 40, height: 40)
    let image = try render(MarkupDocument().add(layer), over: base)

    let top = image.pixel(x: 15, y: 6)
    let bottom = image.pixel(x: 15, y: 13)
    #expect(top.red > 200 && top.blue < 60)
    #expect(bottom.blue > 200 && bottom.red < 60)
    #expect(image.pixel(x: 15, y: 4) == white)
    #expect(image.pixel(x: 15, y: 15) == white)
    #expect(image.pixel(x: 9, y: 6) == white)
    #expect(image.pixel(x: 30, y: 6) == white)
  }

  @Test("a stroke is drawn on its points, in top-left coordinates")
  func strokeOrientation() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let layer = MarkupLayer(
      name: "pen",
      content: .stroke(
        points: [CGPoint(x: 5, y: 5), CGPoint(x: 30, y: 5)],
        brush: Brush(radius: 2, hardness: 1, opacity: 1, spacing: 0.25),
        colour: MarkupColour(red: 0, green: 0, blue: 0)))
    let image = try render(MarkupDocument().add(layer), over: base)

    #expect(image.pixel(x: 15, y: 5).red < 50)
    #expect(image.pixel(x: 15, y: 34) == white)
    #expect(image.pixel(x: 15, y: 35) == white)
    #expect(image.pixel(x: 15, y: 20) == white)
  }

  @Test("tolerance widens the hit area, which helps with thin lines")
  func tolerance() {
    let layer = MarkupLayer(
      name: "line",
      content: .shape(
        kind: .line, frame: CGRect(x: 0, y: 0, width: 100, height: 0),
        strokeWidth: 2, strokeColour: MarkupColour(red: 0, green: 0, blue: 0), fillColour: nil))
    let document = MarkupDocument().add(layer)
    #expect(document.layerIndex(at: CGPoint(x: 50, y: 5)) == nil)
    #expect(document.layerIndex(at: CGPoint(x: 50, y: 5), tolerance: 5) == 0)
  }

  @Test("layerIndex returns the topmost visible layer under the point")
  func topmostHit() {
    let bottom = fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    let top = fill(CGRect(x: 10, y: 10, width: 20, height: 20))
    let document = MarkupDocument().add(bottom).add(top)
    #expect(document.layerIndex(at: CGPoint(x: 15, y: 15)) == 1)
    #expect(document.layerIndex(at: CGPoint(x: 5, y: 5)) == 0)
    #expect(document.layerIndex(at: CGPoint(x: 50, y: 50)) == nil)
    #expect(document.setVisible(false, at: 1).layerIndex(at: CGPoint(x: 15, y: 15)) == 0)
  }

  // MARK: - Shadows and gradients

  @Test("a shadow is drawn below its layer, shifted by its y offset, and changes the render")
  func shadowIsDrawnBelowLayer() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let frame = CGRect(x: 10, y: 10, width: 10, height: 10)
    let plain = try render(MarkupDocument().add(fill(frame)), over: base)
    let shadow = MarkupShadow(offsetX: 0, offsetY: 6, blurRadius: 0)
    let shadowed = try render(MarkupDocument().add(fill(frame, shadow: shadow)), over: base)
    #expect(shadowed.pixels != plain.pixels)
    #expect(shadowed.pixel(x: 15, y: 23) == black)  // below the layer, inside the shadow
    #expect(shadowed.pixel(x: 15, y: 27) == white)  // past the end of the shadow
    #expect(shadowed.pixel(x: 15, y: 8) == white)  // above the layer, where no shadow falls
  }

  @Test("a horizontal flip does not mirror the shadow")
  func flipKeepsShadowInPlace() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let frame = CGRect(x: 10, y: 10, width: 10, height: 10)
    let shadow = MarkupShadow(offsetX: 4, offsetY: 0, blurRadius: 0)
    var flipped = fill(frame, shadow: shadow)
    flipped.isFlippedHorizontally = true
    let plain = try render(MarkupDocument().add(fill(frame, shadow: shadow)), over: base)
    let mirrored = try render(MarkupDocument().add(flipped), over: base)
    #expect(mirrored.pixels == plain.pixels)
    #expect(mirrored.pixel(x: 22, y: 15) == black)  // right of the layer, inside the shadow
  }

  @Test("a gradient runs from its start colour to its end colour across the frame")
  func gradientRunsAcrossFrame() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let image = try render(
      MarkupDocument().add(gradientShape(.rectangle, angle: 0)), over: base)
    #expect(image.pixel(x: 11, y: 20).red > 200 && image.pixel(x: 11, y: 20).blue < 60)
    #expect(image.pixel(x: 28, y: 20).blue > 200 && image.pixel(x: 28, y: 20).red < 60)
    #expect(image.pixel(x: 5, y: 20) == white)
    #expect(image.pixel(x: 35, y: 20) == white)
  }

  @Test("an angle of 90 degrees runs the gradient from top to bottom")
  func gradientAngleTurnsDown() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let image = try render(
      MarkupDocument().add(gradientShape(.rectangle, angle: 90)), over: base)
    #expect(image.pixel(x: 20, y: 11).red > 200)
    #expect(image.pixel(x: 20, y: 28).blue > 200)
  }

  @Test("a gradient is clipped to the outline, so the corners of an ellipse stay white")
  func gradientIsClippedToOutline() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let image = try render(
      MarkupDocument().add(gradientShape(.ellipse, angle: 0)), over: base)
    #expect(image.pixel(x: 11, y: 11) == white)
    #expect(image.pixel(x: 20, y: 20) != white)
  }

  @Test("shadows and gradients round trip through Codable, and layers start without a shadow")
  func codableRoundTrip() throws {
    let shadow = MarkupShadow(
      colour: MarkupColour(red: 0.2, green: 0.4, blue: 0.6), offsetX: -3, offsetY: 5,
      blurRadius: 9)
    let gradient = MarkupGradient(
      startColour: MarkupColour(red: 1, green: 0, blue: 0), endColour: .white, angleDegrees: 45)
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    #expect(try decoder.decode(MarkupShadow.self, from: encoder.encode(shadow)) == shadow)
    #expect(try decoder.decode(MarkupGradient.self, from: encoder.encode(gradient)) == gradient)
    #expect(fill(CGRect(x: 0, y: 0, width: 1, height: 1)).shadow == nil)
    #expect(
      MarkupShadow()
        == MarkupShadow(
          colour: MarkupColour(red: 0, green: 0, blue: 0), offsetX: 0, offsetY: 6, blurRadius: 12))
  }

  @Test("only closed shapes with a fill count as filled")
  func filledShapes() {
    let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
    let colour = MarkupColour(red: 0, green: 0, blue: 0)
    let open = MarkupLayer(
      name: "line",
      content: .shape(
        kind: .line, frame: frame, strokeWidth: 2, strokeColour: colour, fillColour: colour))
    #expect(!open.isFilledShape)
    #expect(gradientShape(.rectangle, angle: 0).isFilledShape)
    #expect(!label("a").isFilledShape)
  }

  // MARK: - Helpers

  private func render(_ document: MarkupDocument, over base: CGImage) throws -> RasterImage {
    let image = try #require(MarkupRenderer.render(base: base, document: document))
    return try #require(RasterImage(image))
  }

  private func label(_ text: String, at origin: CGPoint = .zero, rotation: Double = 0)
    -> MarkupLayer
  {
    MarkupLayer(
      name: text,
      content: .text(
        string: text, fontName: "Helvetica", fontSize: 24,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: origin, rotation: rotation))
  }

  private func fill(
    _ frame: CGRect, opacity: Double = 1, hidden: Bool = false, shadow: MarkupShadow? = nil
  ) -> MarkupLayer {
    MarkupLayer(
      name: "fill",
      content: .shape(
        kind: .rectangle, frame: frame, strokeWidth: 0,
        strokeColour: MarkupColour(red: 0, green: 0, blue: 0),
        fillColour: MarkupColour(red: 0, green: 0, blue: 0)),
      isVisible: !hidden, opacity: opacity, shadow: shadow)
  }

  /// A 20 by 20 pixel shape at (10, 10) filled with a gradient from red to blue.
  private func gradientShape(_ kind: MarkupLayer.Content.ShapeKind, angle: Double) -> MarkupLayer {
    let gradient = MarkupGradient(
      startColour: MarkupColour(red: 1, green: 0, blue: 0),
      endColour: MarkupColour(red: 0, green: 0, blue: 1), angleDegrees: angle)
    return MarkupLayer(
      name: "gradient",
      content: .shape(
        kind: kind, frame: CGRect(x: 10, y: 10, width: 20, height: 20), strokeWidth: 0,
        strokeColour: MarkupColour(red: 0, green: 0, blue: 0),
        fillColour: MarkupColour(red: 1, green: 0, blue: 0),
        style: MarkupShapeStyle(fillGradient: gradient)))
  }
}
