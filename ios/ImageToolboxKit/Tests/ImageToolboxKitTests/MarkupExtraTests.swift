import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Markup text wrapping, text and line transparency, and shape hit testing")
struct MarkupExtraTests {

  private let white = RGBA(red: 255, green: 255, blue: 255)
  private let black = RGBA(red: 0, green: 0, blue: 0)
  private let red = RGBA(red: 255, green: 0, blue: 0)

  // MARK: - Text wrapping

  @Test("a paragraph breaks at word boundaries into lines that fit the width")
  func wrapsAtWords() {
    let text = "one two three four five six seven"
    let unwrapped = layout(text)
    let width = unwrapped.width / 3
    let wrapped = layout(text, wrapWidth: width)

    #expect(unwrapped.lines.count == 1)
    #expect(wrapped.lines.count >= 3)
    for line in wrapped.lines {
      #expect(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= width)
    }
    // Every character lands on exactly one line, and the lines follow each other.
    var expectedStart = 0
    for line in wrapped.lines {
      let range = CTLineGetStringRange(line)
      #expect(range.location == expectedStart)
      expectedStart += range.length
    }
    #expect(expectedStart == text.utf16.count)
  }

  @Test("newlines still start lines when text is wrapped, and an empty paragraph keeps its line")
  func newlinesSurviveWrapping() {
    #expect(layout("one\ntwo", wrapWidth: 1000).lines.count == 2)
    #expect(layout("one two\nthree", wrapWidth: 1000).lines.count == 2)
    #expect(layout("a\n\nb", wrapWidth: 1000).lines.count == 3)
    #expect(layout("one two\nthree four five six", wrapWidth: 40).lines.count >= 3)
  }

  @Test("without a positive width, only newlines break lines")
  func noWidthNoWrap() {
    let text = "one two three four five six seven eight"
    #expect(layout(text).lines.count == 1)
    #expect(layout(text, wrapWidth: 0).lines.count == 1)
    #expect(layout(text, wrapWidth: -5).lines.count == 1)
  }

  @Test("wrapped text draws lower, and hit testing follows the wrapped block")
  func wrappedRenderAndHitTest() throws {
    let base = TestImages.solid(white, width: 200, height: 200)
    let text = "one two three four"
    let plain = paragraph(text, wrapWidth: nil)
    let wrapped = paragraph(text, wrapWidth: 60)

    // The second wrapped line sits between one and two line heights below the origin.
    let lineHeight = layout(text, wrapWidth: 60).lineHeight
    let secondLine = CGPoint(x: 12, y: 10 + lineHeight * 1.5)
    #expect(MarkupDocument().add(plain).layerIndex(at: secondLine) == nil)
    #expect(MarkupDocument().add(wrapped).layerIndex(at: secondLine) == 0)

    let plainImage = try render(MarkupDocument().add(plain), over: base)
    let wrappedImage = try render(MarkupDocument().add(wrapped), over: base)
    #expect(lowestInk(plainImage) < lowestInk(wrappedImage))
  }

  @Test("layers that differ only in wrap width are not equal")
  func wrapWidthIsPartOfValue() {
    let id = UUID()
    let make = { (wrapWidth: Double?) in
      MarkupLayer(id: id, name: "text", content: paragraph("text", wrapWidth: wrapWidth).content)
    }
    #expect(make(nil) == make(nil))
    #expect(make(nil) != make(100))
    #expect(make(100) != make(200))
  }

  // MARK: - Text transparency

  @Test("text at half opacity mixes its ink half way into the background")
  func textTransparency() throws {
    let base = TestImages.solid(white, width: 120, height: 60)
    let solid = try render(MarkupDocument().add(bigText(opacity: 1)), over: base)
    let faded = try render(MarkupDocument().add(bigText(opacity: 0.5)), over: base)

    let ink = try #require(firstFullyInked(solid))
    let mixed = faded.pixel(x: ink.x, y: ink.y)
    #expect(abs(Int(mixed.red) - 128) <= 2)
    #expect(abs(Int(mixed.green) - 128) <= 2)
    #expect(mixed.alpha == 255)
  }

  @Test("text at zero opacity draws nothing")
  func invisibleText() throws {
    let base = TestImages.solid(white, width: 120, height: 60)
    let plain = try render(MarkupDocument(), over: base)
    let hidden = try render(MarkupDocument().add(bigText(opacity: 0)), over: base)
    #expect(hidden.pixels == plain.pixels)
  }

  // MARK: - Line layers

  @Test("a line at half opacity mixes its stroke half way into the background")
  func lineTransparency() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let solid = try render(MarkupDocument().add(line(opacity: 1)), over: base)
    let faded = try render(MarkupDocument().add(line(opacity: 0.5)), over: base)

    let ink = try #require(firstFullyInked(solid))
    let mixed = faded.pixel(x: ink.x, y: ink.y)
    #expect(abs(Int(mixed.red) - 128) <= 2)
    #expect(mixed.alpha == 255)
  }

  @Test("a line with no stroke width draws nothing")
  func zeroWidthLine() throws {
    let base = TestImages.solid(white, width: 40, height: 40)
    let plain = try render(MarkupDocument(), over: base)
    let image = try render(MarkupDocument().add(line(strokeWidth: 0)), over: base)
    #expect(image.pixels == plain.pixels)
  }

  @Test("a line is hit along its length, and at its ends only within the stroke reach")
  func lineHitTest() {
    let document = MarkupDocument().add(
      line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 10), strokeWidth: 2))
    #expect(document.layerIndex(at: CGPoint(x: 10, y: 10)) == 0)
    #expect(document.layerIndex(at: CGPoint(x: 30, y: 10)) == 0)
    #expect(document.layerIndex(at: CGPoint(x: 20, y: 10.5)) == 0)
    #expect(document.layerIndex(at: CGPoint(x: 20, y: 12)) == nil)
    // Past the end, the nearest point is the end itself, 1.5 away. The reach is 1.
    #expect(document.layerIndex(at: CGPoint(x: 31.5, y: 10)) == nil)

    // A negative size reverses the line, so its ends swap places, but the hit area is the same.
    let reversed = MarkupDocument().add(
      line(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 10, y: 10), strokeWidth: 2))
    #expect(reversed.layerIndex(at: CGPoint(x: 10, y: 10)) == 0)
    #expect(reversed.layerIndex(at: CGPoint(x: 20, y: 12)) == nil)
  }

  // MARK: - Ellipse hit testing

  @Test("an ellipse is hit inside its outline, not in the corners of its frame")
  func ellipseHitTest() {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    let ellipse = MarkupDocument().add(shape(.ellipse, frame: frame, strokeWidth: 0))
    let rectangle = MarkupDocument().add(shape(.rectangle, frame: frame, strokeWidth: 0))

    #expect(ellipse.layerIndex(at: CGPoint(x: 50, y: 50)) == 0)
    #expect(ellipse.layerIndex(at: CGPoint(x: 50, y: 2)) == 0)
    // The corner of the frame lies outside the curve, although it is inside the rectangle.
    #expect(ellipse.layerIndex(at: CGPoint(x: 4, y: 4)) == nil)
    #expect(rectangle.layerIndex(at: CGPoint(x: 4, y: 4)) == 0)
    // Tolerance widens the ellipse as well.
    #expect(ellipse.layerIndex(at: CGPoint(x: 4, y: 4), tolerance: 20) == 0)
  }

  // MARK: - Text decorations, alignment, background, outline and lines

  @Test("bold adds ink and italic changes the glyphs")
  func boldAndItalic() throws {
    let base = TestImages.solid(white, width: 200, height: 120)
    let plain = try render(MarkupDocument().add(styled("H")), over: base)
    let bold = try render(
      MarkupDocument().add(styled("H", style: MarkupTextStyle(decorations: [.bold]))), over: base)
    let italic = try render(
      MarkupDocument().add(styled("H", style: MarkupTextStyle(decorations: [.italic]))),
      over: base)
    #expect(inkCount(bold) > inkCount(plain))
    #expect(italic.pixels != plain.pixels)
  }

  @Test("underline adds ink below the baseline, and strikethrough adds ink between the letters")
  func underlineAndStrikethrough() throws {
    let base = TestImages.solid(white, width: 200, height: 120)
    let plain = try render(MarkupDocument().add(styled("HHH")), over: base)
    let underlined = try render(
      MarkupDocument().add(styled("HHH", style: MarkupTextStyle(decorations: [.underline]))),
      over: base)
    let struck = try render(
      MarkupDocument().add(styled("HHH", style: MarkupTextStyle(decorations: [.strikethrough]))),
      over: base)
    #expect(lowestInk(underlined) > lowestInk(plain))
    #expect(inkCount(struck) > inkCount(plain))
  }

  @Test("alignment moves shorter lines to the start, the middle or the end of the block")
  func alignment() {
    let text = "ab\nabcdef"
    let start = textLayout(text, style: MarkupTextStyle(alignment: .start))
    let centre = textLayout(text, style: MarkupTextStyle(alignment: .centre))
    let end = textLayout(text, style: MarkupTextStyle(alignment: .end))
    let free = start.blockWidth - start.lineWidths[0]
    #expect(free > 0)
    #expect(start.offset(ofLine: 0) == 0)
    #expect(abs(centre.offset(ofLine: 0) - free / 2) < 0.01)
    #expect(abs(end.offset(ofLine: 0) - free) < 0.01)
    // The longest line has no free space, so it does not move.
    #expect(end.offset(ofLine: 1) == 0)
  }

  @Test("a background fills the text block behind the glyphs, and nothing outside it")
  func background() throws {
    let base = TestImages.solid(white, width: 200, height: 120)
    let backed = try render(
      MarkupDocument().add(
        styled(
          "H", style: MarkupTextStyle(backgroundColour: MarkupColour(red: 1, green: 0, blue: 0)))),
      over: base)
    #expect(backed.pixel(x: 11, y: 11) == red)
    #expect(backed.pixel(x: 5, y: 5) == white)
  }

  @Test("an outline draws its colour around the glyphs")
  func outline() throws {
    let base = TestImages.solid(white, width: 200, height: 120)
    let plain = try render(MarkupDocument().add(styled("H")), over: base)
    let outlined = try render(
      MarkupDocument().add(
        styled(
          "H",
          style: MarkupTextStyle(
            outline: MarkupTextStyle.Outline(
              colour: MarkupColour(red: 1, green: 0, blue: 0), width: 4)))),
      over: base)
    #expect(containsColour(outlined, red))
    #expect(!containsColour(plain, red))
    #expect(inkCount(outlined) > inkCount(plain))
  }

  @Test("visible lines keep the first lines only, and hit testing ignores the rest")
  func visibleLines() throws {
    let base = TestImages.solid(white, width: 200, height: 200)
    let all = styled("H\nH\nH")
    let two = MarkupLayer(name: "text", content: all.content, visibleLineCount: 2)
    let lines = try #require(two.textLayout(colour: CGColor(gray: 0, alpha: 1)))
    #expect(lines.lines.count == 2)

    // The third line starts two line heights below the origin.
    let lineHeight = try #require(all.textLayout(colour: CGColor(gray: 0, alpha: 1))).lineHeight
    let thirdLine = CGPoint(x: 12, y: 10 + lineHeight * 2.5)
    #expect(MarkupDocument().add(all).layerIndex(at: thirdLine) == 0)
    #expect(MarkupDocument().add(two).layerIndex(at: thirdLine) == nil)

    let full = try render(MarkupDocument().add(all), over: base)
    let limited = try render(MarkupDocument().add(two), over: base)
    #expect(inkCount(limited) < inkCount(full))
  }

  // MARK: - Helpers
  private func textLayout(_ text: String, style: MarkupTextStyle) -> MarkupTextLayout {
    MarkupTextLayout(
      string: text, fontName: "Helvetica", fontSize: 24, colour: CGColor(gray: 0, alpha: 1),
      style: style)
  }

  /// A black Helvetica 48 text layer at (10, 10), with the given style.
  private func styled(
    _ string: String, style: MarkupTextStyle = MarkupTextStyle()
  ) -> MarkupLayer {
    MarkupLayer(
      name: "text",
      content: .text(
        string: string, fontName: "Helvetica", fontSize: 48,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: CGPoint(x: 10, y: 10),
        rotation: 0, wrapWidth: nil, style: style))
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

  private func containsColour(_ image: RasterImage, _ colour: RGBA) -> Bool {
    for y in 0..<image.height {
      for x in 0..<image.width where image.pixel(x: x, y: y) == colour {
        return true
      }
    }
    return false
  }

  private func layout(_ text: String, wrapWidth: CGFloat? = nil) -> MarkupTextLayout {
    MarkupTextLayout(
      string: text, fontName: "Helvetica", fontSize: 24, colour: CGColor(gray: 0, alpha: 1),
      wrapWidth: wrapWidth)
  }

  private func render(_ document: MarkupDocument, over base: CGImage) throws -> RasterImage {
    let image = try #require(MarkupRenderer.render(base: base, document: document))
    return try #require(RasterImage(image))
  }

  /// A large bold H, so that some pixels are fully covered by ink.
  private func bigText(opacity: Double) -> MarkupLayer {
    MarkupLayer(
      name: "H",
      content: .text(
        string: "H", fontName: "Helvetica-Bold", fontSize: 48,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: CGPoint(x: 10, y: 5),
        rotation: 0),
      opacity: opacity)
  }

  /// A plain text layer whose origin is at the top-left corner, with an optional wrap width.
  private func paragraph(_ string: String, wrapWidth: Double?) -> MarkupLayer {
    MarkupLayer(
      name: "text",
      content: .text(
        string: string, fontName: "Helvetica", fontSize: 24,
        colour: MarkupColour(red: 0, green: 0, blue: 0), origin: CGPoint(x: 10, y: 10),
        rotation: 0, wrapWidth: wrapWidth))
  }

  private func line(
    from start: CGPoint = CGPoint(x: 5, y: 20), to end: CGPoint = CGPoint(x: 35, y: 20),
    strokeWidth: Double = 4, opacity: Double = 1
  ) -> MarkupLayer {
    let frame = CGRect(
      x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
    return MarkupLayer(
      name: "line",
      content: .shape(
        kind: .line, frame: frame, strokeWidth: strokeWidth,
        strokeColour: MarkupColour(red: 0, green: 0, blue: 0), fillColour: nil),
      opacity: opacity)
  }

  private func shape(
    _ kind: MarkupLayer.Content.ShapeKind, frame: CGRect, strokeWidth: Double
  ) -> MarkupLayer {
    MarkupLayer(
      name: "shape",
      content: .shape(
        kind: kind, frame: frame, strokeWidth: strokeWidth,
        strokeColour: MarkupColour(red: 0, green: 0, blue: 0), fillColour: nil))
  }

  /// The first pixel, in reading order, that is solid black.
  private func firstFullyInked(_ image: RasterImage) -> (x: Int, y: Int)? {
    for y in 0..<image.height {
      for x in 0..<image.width where image.pixel(x: x, y: y) == black {
        return (x, y)
      }
    }
    return nil
  }

  /// The lowest row that holds a dark pixel, or -1 when there is none.
  private func lowestInk(_ image: RasterImage) -> Int {
    var lowest = -1
    for y in 0..<image.height {
      for x in 0..<image.width where image.pixel(x: x, y: y).red < 128 {
        lowest = y
      }
    }
    return lowest
  }
}
