import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Markup shape kinds, flips, locks, blend modes and picture corners")
struct MarkupShapeTests {

  private let white = RGBA(red: 255, green: 255, blue: 255)
  private let black = RGBA(red: 0, green: 0, blue: 0)
  private let red = RGBA(red: 255, green: 0, blue: 0)
  private let blue = RGBA(red: 0, green: 0, blue: 255)
  private let inkBlack = MarkupColour(red: 0, green: 0, blue: 0)

  /// The frame that every hit test uses: a 100 by 100 square in the middle of a 200 pixel picture.
  private let square = CGRect(x: 50, y: 50, width: 100, height: 100)

  // MARK: - Shape kinds

  @Test("every shape kind draws ink, filled when it is closed and stroked when it is open")
  func everyKindDraws() throws {
    let base = TestImages.solid(white, width: 200, height: 200)
    for kind in MarkupLayer.Content.ShapeKind.allCases {
      let image = try render(MarkupDocument().add(shape(kind, filled: kind.isClosed)), over: base)
      #expect(inkCount(image) > 50, "\(kind) drew too little ink")
    }
  }

  @Test("every shape kind is hit at its centre and missed in a far corner")
  func everyKindHitTest() {
    for kind in MarkupLayer.Content.ShapeKind.allCases {
      let fills = kind.isClosed ? [true, false] : [false]
      for filled in fills {
        let document = MarkupDocument().add(shape(kind, filled: filled))
        #expect(document.layerIndex(at: CGPoint(x: 100, y: 100)) == 0, "\(kind) at centre")
        #expect(document.layerIndex(at: CGPoint(x: 190, y: 10)) == nil, "\(kind) far corner")
      }
    }
  }

  @Test("a triangle has its apex at the top centre and empty bottom corners")
  func triangleOutline() {
    let triangle = MarkupDocument().add(shape(.triangle, filled: true))
    #expect(triangle.layerIndex(at: CGPoint(x: 100, y: 140)) == 0)
    #expect(triangle.layerIndex(at: CGPoint(x: 100, y: 52)) == 0)
    #expect(triangle.layerIndex(at: CGPoint(x: 51, y: 51)) == nil)
    #expect(triangle.layerIndex(at: CGPoint(x: 49, y: 149)) == nil)
  }

  @Test("a star with a smaller inner radius covers less ink than one with a larger inner radius")
  func starInnerRadius() throws {
    let base = TestImages.solid(white, width: 200, height: 200)
    let sharp = MarkupShapeStyle(innerRadiusRatio: 0.2)
    let blunt = MarkupShapeStyle(innerRadiusRatio: 0.9)
    let sharpInk = try inkCount(
      render(MarkupDocument().add(shape(.star, filled: true, style: sharp)), over: base))
    let bluntInk = try inkCount(
      render(MarkupDocument().add(shape(.star, filled: true, style: blunt)), over: base))
    #expect(sharpInk < bluntInk)
  }

  @Test("a polygon with more corners covers a rounder area")
  func polygonCorners() throws {
    let base = TestImages.solid(white, width: 200, height: 200)
    let triangle = MarkupShapeStyle(vertices: 3, isRegular: true)
    let hexagon = MarkupShapeStyle(vertices: 6, isRegular: true)
    let triangleInk = try inkCount(
      render(MarkupDocument().add(shape(.polygon, filled: true, style: triangle)), over: base))
    let hexagonInk = try inkCount(
      render(MarkupDocument().add(shape(.polygon, filled: true, style: hexagon)), over: base))
    #expect(triangleInk != hexagonInk)
    #expect(triangleInk > 50)
  }

  // MARK: - Rectangle rotation and corners

  @Test("a rectangle turned by 90 degrees covers the vertical band through its centre")
  func rectangleRotation() {
    let flat = CGRect(x: 50, y: 90, width: 100, height: 20)
    let plain = MarkupDocument().add(shape(.rectangle, frame: flat, filled: true))
    let turned = MarkupDocument().add(
      shape(.rectangle, frame: flat, filled: true, style: MarkupShapeStyle(rotationDegrees: 90)))
    #expect(plain.layerIndex(at: CGPoint(x: 100, y: 140)) == nil)
    #expect(turned.layerIndex(at: CGPoint(x: 100, y: 140)) == 0)
    #expect(turned.layerIndex(at: CGPoint(x: 100, y: 100)) == 0)
  }

  @Test("a rounded rectangle with a corner radius of half its side is a circle")
  func rectangleCornerRadius() {
    let rounded = MarkupDocument().add(
      shape(.rectangle, filled: true, style: MarkupShapeStyle(cornerRadius: 0.5)))
    let sharp = MarkupDocument().add(shape(.rectangle, filled: true))
    #expect(rounded.layerIndex(at: CGPoint(x: 51, y: 51)) == nil)
    #expect(rounded.layerIndex(at: CGPoint(x: 100, y: 52)) == 0)
    #expect(sharp.layerIndex(at: CGPoint(x: 51, y: 51)) == 0)
  }

  // MARK: - Arrows

  @Test("a filled arrow narrows towards its tip, which points right")
  func filledArrowHead() {
    let arrow = MarkupDocument().add(shape(.arrow, filled: true))
    #expect(arrow.layerIndex(at: CGPoint(x: 148, y: 100)) == 0)
    #expect(arrow.layerIndex(at: CGPoint(x: 148, y: 95)) == nil)
    #expect(arrow.layerIndex(at: CGPoint(x: 51, y: 51)) == nil)
  }

  @Test("a line arrow has its head on the far end, and the head is hit within its stroke")
  func lineArrowHead() {
    // The head rays leave the tip at 150 degrees from the line, so (44.8, 23) lies on one of them.
    let frame = CGRect(x: 10, y: 20, width: 40, height: 0)
    let arrow = MarkupLayer(
      name: "arrow",
      content: .shape(
        kind: .lineArrow, frame: frame, strokeWidth: 2, strokeColour: inkBlack, fillColour: nil))
    #expect(MarkupDocument().add(arrow).layerIndex(at: CGPoint(x: 44.8, y: 23)) == 0)
    // The far end has no head, so the other side of the tip is empty.
    #expect(MarkupDocument().add(arrow).layerIndex(at: CGPoint(x: 55, y: 20)) == nil)
  }

  // MARK: - Flips

  @Test("a horizontal flip mirrors a sticker, and hit testing follows the mirror")
  func flippedSticker() throws {
    let raster = RasterImage(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 0, 255, 255])
    let layer = MarkupLayer(
      name: "sticker",
      content: .sticker(raster: raster, frame: CGRect(x: 10, y: 10, width: 40, height: 20)))
    let base = TestImages.solid(white, width: 100, height: 100)

    let plain = try render(MarkupDocument().add(layer), over: base)
    #expect(plain.pixel(x: 15, y: 20) == red)
    #expect(plain.pixel(x: 45, y: 20) == blue)

    var flipped = layer
    flipped.isFlippedHorizontally = true
    let mirrored = try render(MarkupDocument().add(flipped), over: base)
    #expect(mirrored.pixel(x: 15, y: 20) == blue)
    #expect(mirrored.pixel(x: 45, y: 20) == red)
  }

  @Test("a flipped line arrow is hit where its mirror image lies, not where it was drawn")
  func flippedHitTest() {
    let frame = CGRect(x: 10, y: 20, width: 40, height: 0)
    var arrow = MarkupLayer(
      name: "arrow",
      content: .shape(
        kind: .lineArrow, frame: frame, strokeWidth: 2, strokeColour: inkBlack, fillColour: nil))
    #expect(MarkupDocument().add(arrow).layerIndex(at: CGPoint(x: 44.8, y: 23)) == 0)
    arrow.isFlippedHorizontally = true
    #expect(MarkupDocument().add(arrow).layerIndex(at: CGPoint(x: 44.8, y: 23)) == nil)
    #expect(MarkupDocument().add(arrow).layerIndex(at: CGPoint(x: 15.2, y: 23)) == 0)
  }

  // MARK: - Locks

  @Test("a locked layer ignores removal, moves, visibility and edits, but can be unlocked")
  func lockedLayerIsUnchanged() {
    let locked = MarkupLayer(name: "a", content: sticker(), isLocked: true)
    let stack = MarkupDocument().add(MarkupLayer(name: "b", content: sticker())).add(locked)
    #expect(stack.remove(at: 1) == stack)
    #expect(stack.move(from: 1, to: 0) == stack)
    #expect(stack.setVisible(false, at: 1) == stack)
    #expect(stack.updating(at: 1) { $0.opacity = 0.5 } == stack)

    // Moving another layer is still allowed, because the lock belongs to the layer.
    #expect(stack.move(from: 0, to: 1).layers[0].name == "a")

    let unlocked = stack.setLocked(false, at: 1)
    #expect(unlocked.layers[1].isLocked == false)
    #expect(unlocked.updating(at: 1) { $0.opacity = 0.5 }.layers[1].opacity == 0.5)
    #expect(unlocked.setLocked(true, at: 1).layers[1].isLocked)
  }

  @Test("an edit that changes nothing returns the same document")
  func noOpEdit() {
    let stack = MarkupDocument().add(MarkupLayer(name: "a", content: sticker()))
    #expect(stack.updating(at: 0) { $0.opacity = 1 } == stack)
    #expect(stack.updating(at: 5) { $0.opacity = 0.2 } == stack)
  }

  @Test("a locked layer is still picked, so that it can be unlocked")
  func lockedLayerIsHit() {
    let stack = MarkupDocument().add(
      MarkupLayer(name: "a", content: sticker(frame: square), isLocked: true))
    #expect(stack.layerIndex(at: CGPoint(x: 100, y: 100)) == 0)
  }

  // MARK: - Blend modes

  @Test("multiply blending darkens the layer by the picture below it")
  func multiplyBlend() throws {
    let base = TestImages.solid(RGBA(red: 128, green: 128, blue: 128), width: 200, height: 200)
    let normal = MarkupLayer(name: "fill", content: rectangleFill(square))
    var multiply = normal
    multiply.blendMode = .multiply

    let plain = try render(MarkupDocument().add(normal), over: base)
    #expect(plain.pixel(x: 100, y: 100) == red)
    let darkened = try render(MarkupDocument().add(multiply), over: base)
    let pixel = darkened.pixel(x: 100, y: 100)
    #expect(abs(Int(pixel.red) - 128) <= 2)
    #expect(pixel.green == 0)
    #expect(pixel.blue == 0)
  }

  // MARK: - Picture corners and kinds

  @Test("a picture with a corner radius of 50 percent is cut to a circle")
  func pictureCornerRadius() throws {
    let base = TestImages.solid(white, width: 60, height: 60)
    let raster = RasterImage(width: 1, height: 1, pixels: [255, 0, 0, 255])
    let frame = CGRect(x: 10, y: 10, width: 40, height: 40)
    var layer = MarkupLayer(name: "picture", content: .image(raster: raster, frame: frame))
    let square = try render(MarkupDocument().add(layer), over: base)
    #expect(square.pixel(x: 11, y: 11) == red)

    layer.cornerRadiusPercent = 50
    let round = try render(MarkupDocument().add(layer), over: base)
    #expect(round.pixel(x: 11, y: 11) == white)
    #expect(round.pixel(x: 30, y: 30) == red)
  }

  @Test("a picture and a sticker with the same pixels draw alike, but are different content")
  func imageAndStickerDiffer() throws {
    let raster = RasterImage(width: 2, height: 2, pixels: Array(repeating: 200, count: 16))
    let frame = CGRect(x: 0, y: 0, width: 20, height: 20)
    let sticker = MarkupLayer(name: "s", content: .sticker(raster: raster, frame: frame))
    let image = MarkupLayer(name: "i", content: .image(raster: raster, frame: frame))
    let base = TestImages.solid(white, width: 20, height: 20)
    let stickerImage = try render(MarkupDocument().add(sticker), over: base)
    let pictureImage = try render(MarkupDocument().add(image), over: base)
    #expect(stickerImage.pixels == pictureImage.pixels)
    #expect(sticker.content != image.content)
  }

  @Test("layer options are clamped: corner radius to 50 and visible lines to at least one")
  func clampedOptions() {
    let layer = MarkupLayer(
      name: "t", content: sticker(), cornerRadiusPercent: 80, visibleLineCount: 0)
    #expect(layer.cornerRadiusPercent == 50)
    #expect(layer.visibleLineCount == 1)
    #expect(
      MarkupLayer(name: "t", content: sticker(), cornerRadiusPercent: -4).cornerRadiusPercent == 0)
  }

  // MARK: - Defaults and style edits

  @Test("default filled shapes have a fill and no stroke, and default outlines the reverse")
  func defaultShapes() {
    let canvas = CGSize(width: 200, height: 200)
    let filled = MarkupLayerDefaults.shape(
      .triangle, canvas: canvas, colour: inkBlack, filled: true)
    let outlined = MarkupLayerDefaults.shape(
      .triangle, canvas: canvas, colour: inkBlack, filled: false)
    let line = MarkupLayerDefaults.shape(.line, canvas: canvas, colour: inkBlack, filled: true)
    guard case .shape(_, _, let filledWidth, _, let filledFill, _) = filled,
      case .shape(_, _, let outlinedWidth, _, let outlinedFill, _) = outlined,
      case .shape(_, _, let lineWidth, _, let lineFill, _) = line
    else {
      Issue.record("defaults must be shapes")
      return
    }
    #expect(filledWidth == 0 && filledFill != nil)
    #expect(outlinedWidth > 0 && outlinedFill == nil)
    #expect(lineWidth > 0 && lineFill == nil)
  }

  @Test("sticker and picture frames fit their limits and are never enlarged")
  func defaultFrames() {
    let canvas = CGSize(width: 1000, height: 1000)
    let sticker = MarkupLayerDefaults.stickerFrame(
      for: CGSize(width: 2000, height: 1000), canvas: canvas)
    #expect(sticker == CGRect(x: 300, y: 400, width: 400, height: 200))
    let small = MarkupLayerDefaults.stickerFrame(for: CGSize(width: 50, height: 50), canvas: canvas)
    #expect(small.size == CGSize(width: 50, height: 50))
    let picture = MarkupLayerDefaults.imageFrame(
      for: CGSize(width: 2000, height: 1000), canvas: canvas)
    #expect(picture == CGRect(x: 200, y: 350, width: 600, height: 300))
  }

  @Test("style edits change only the shape or text they target")
  func styleEdits() {
    var layer = shape(.rectangle, filled: true)
    layer.updateShapeStyle { $0.rotationDegrees = 90 }
    #expect(layer.shapeStyle?.rotationDegrees == 90)
    #expect(layer.shapeKind == .rectangle)
    #expect(layer.isText == false)
    layer.updateTextStyle { $0.decorations = [.bold] }
    #expect(layer.textStyle == nil)
    #expect(layer.supportsCornerRadius == false)
  }

  @Test("style toggles add and remove decorations, a background and an outline")
  func styleToggles() {
    var style = MarkupTextStyle()
    style.toggleDecoration(.bold)
    #expect(style.decorations == [.bold])
    style.toggleDecoration(.bold)
    #expect(style.decorations.isEmpty)

    style.toggleBackground()
    #expect(style.backgroundColour == MarkupColour.white)
    style.toggleBackground()
    #expect(style.backgroundColour == nil)

    style.toggleOutline(width: 3)
    #expect(style.outline == MarkupTextStyle.Outline(colour: MarkupColour.white, width: 3))
    style.toggleOutline(width: 3)
    #expect(style.outline == nil)
  }

  @Test("a text layer reports all its lines, while the visible count limits what is laid out")
  func lineCounts() {
    let layer = MarkupLayer(
      name: "text",
      content: .text(
        string: "a\nb\nc", fontName: "Helvetica", fontSize: 24,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: .zero, rotation: 0))
    var limited = layer
    limited.visibleLineCount = 2
    #expect(limited.textLineCount == 3)
    #expect(limited.textLayout(colour: CGColor(gray: 0, alpha: 1))?.lines.count == 2)
    #expect(layer.isText)
    #expect(layer.textStyle == MarkupTextStyle())
    #expect(layer.shapeKind == nil)
  }

  // MARK: - Helpers

  private func render(_ document: MarkupDocument, over base: CGImage) throws -> RasterImage {
    let image = try #require(MarkupRenderer.render(base: base, document: document))
    return try #require(RasterImage(image))
  }

  /// Pixels that are not white. Every layer in these tests is drawn over a white picture.
  private func inkCount(_ image: RasterImage) -> Int {
    var count = 0
    for y in 0..<image.height {
      for x in 0..<image.width where image.pixel(x: x, y: y) != white {
        count += 1
      }
    }
    return count
  }

  /// A black shape. A closed shape is filled when `filled` is set, and every open shape is stroked.
  private func shape(
    _ kind: MarkupLayer.Content.ShapeKind, frame: CGRect? = nil, filled: Bool,
    style: MarkupShapeStyle = MarkupShapeStyle()
  ) -> MarkupLayer {
    let fill = filled && kind.isClosed
    return MarkupLayer(
      name: "shape",
      content: .shape(
        kind: kind, frame: frame ?? square, strokeWidth: fill ? 0 : 4, strokeColour: inkBlack,
        fillColour: fill ? inkBlack : nil, style: style))
  }

  private func rectangleFill(_ frame: CGRect) -> MarkupLayer.Content {
    .shape(
      kind: .rectangle, frame: frame, strokeWidth: 0,
      strokeColour: MarkupColour(red: 1, green: 0, blue: 0),
      fillColour: MarkupColour(red: 1, green: 0, blue: 0))
  }

  private func sticker(frame: CGRect = CGRect(x: 0, y: 0, width: 4, height: 4))
    -> MarkupLayer.Content
  {
    .sticker(raster: RasterImage(width: 1, height: 1, pixels: [0, 0, 0, 255]), frame: frame)
  }
}
