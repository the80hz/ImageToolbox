import CoreGraphics
import CoreText
import Foundation

/// CoreText line layout shared by the renderer and hit testing, so both agree on the size of a text block.
///
/// Lines are stacked downwards from the top of the block. The baseline of line `i` is
/// `ascent + i * lineHeight` below the top, in top-left coordinates.
struct MarkupTextLayout {
  let lines: [CTLine]
  /// Distance from the top of a line to its baseline.
  let ascent: CGFloat
  /// Distance from one baseline to the next.
  let lineHeight: CGFloat
  /// Width of the widest line.
  let width: CGFloat
  /// Width that lines are aligned in: the wrap width when one is set, otherwise `width`.
  let blockWidth: CGFloat
  /// Width of each line, in the order of `lines`.
  let lineWidths: [CGFloat]
  let alignment: MarkupTextStyle.Alignment

  var height: CGFloat { CGFloat(lines.count) * lineHeight }

  /// Horizontal position of line `index` inside the block, from its left edge.
  func offset(ofLine index: Int) -> CGFloat {
    let free = max(blockWidth - lineWidths[index], 0)
    switch alignment {
    case .start: return 0
    case .centre: return free / 2
    case .end: return free
    }
  }

  /// A font that is missing falls back to the system font, as `CTFontCreateWithName` does.
  ///
  /// Newlines always start a new line. With a positive `wrapWidth`, each paragraph is also broken
  /// at word boundaries, so that its lines fit that width. A word wider than the width is broken
  /// inside the word instead. A nil or non-positive width only applies the newlines. `maxLines`
  /// keeps the first lines only, and a value below one keeps one line.
  init(
    string: String, fontName: String, fontSize: CGFloat, colour: CGColor,
    wrapWidth: CGFloat? = nil, style: MarkupTextStyle = MarkupTextStyle(), maxLines: Int? = nil
  ) {
    let font = Self.font(name: fontName, size: fontSize, decorations: style.decorations)
    let fontAscent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let leading = CTFontGetLeading(font)
    let attributes = Self.attributes(font: font, colour: colour, fontSize: fontSize, style: style)
    let builtLines = string.components(separatedBy: "\n").flatMap { text -> [CTLine] in
      let paragraph = NSAttributedString(string: text, attributes: attributes)
      guard let wrapWidth, wrapWidth > 0, paragraph.length > 0 else {
        return [CTLineCreateWithAttributedString(paragraph)]
      }
      return Self.wrap(paragraph, to: wrapWidth)
    }
    let visible = maxLines.map { Array(builtLines.prefix(max($0, 1))) } ?? builtLines
    let widths = visible.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
    let widest = widths.max() ?? 0
    lines = visible
    lineWidths = widths
    width = widest
    blockWidth = if let wrapWidth, wrapWidth > 0 { max(widest, wrapWidth) } else { widest }
    alignment = style.alignment
    ascent = fontAscent
    // A zero height would collapse empty text, so keep at least one point per line.
    lineHeight = max(fontAscent + descent + leading, 1)
  }

  /// The font with bold and italic applied. A face that does not exist keeps the plain font.
  private static func font(
    name: String, size: CGFloat, decorations: Set<MarkupTextStyle.Decoration>
  ) -> CTFont {
    let base = CTFontCreateWithName(name as CFString, size, nil)
    var traits: CTFontSymbolicTraits = []
    if decorations.contains(.bold) { traits.insert(.traitBold) }
    if decorations.contains(.italic) { traits.insert(.traitItalic) }
    guard !traits.isEmpty else { return base }
    return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
  }

  /// Attributes shared by every line. Underline and strikethrough are CoreText attributes, so
  /// CTLineDraw draws them. An outline is a negative stroke width, which fills and strokes the glyphs.
  private static func attributes(
    font: CTFont, colour: CGColor, fontSize: CGFloat, style: MarkupTextStyle
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
    ]
    let single = NSNumber(value: CTUnderlineStyle.single.rawValue)
    if style.decorations.contains(.underline) {
      attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = single
    }
    if style.decorations.contains(.strikethrough) {
      // The CoreText strikethrough constant is not declared in the Swift headers. CoreText draws
      // the Foundation key with the same value as AppKit's, which is verified by a test.
      attributes[NSAttributedString.Key("NSStrikethrough")] = single
    }
    if let outline = style.outline, outline.width > 0, fontSize > 0 {
      // CoreText measures the stroke as a percentage of the font size.
      attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] =
        NSNumber(value: -outline.width / Double(fontSize) * 100)
      attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] =
        outline.colour.cgColor
    }
    return attributes
  }

  /// Breaks one paragraph into lines that fit `width`, where CoreText finds a break. Every line
  /// takes at least one character, so the loop always moves forward.
  private static func wrap(_ paragraph: NSAttributedString, to width: CGFloat) -> [CTLine] {
    let typesetter = CTTypesetterCreateWithAttributedString(paragraph)
    var lines: [CTLine] = []
    var start = 0
    while start < paragraph.length {
      let suggested = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
      let count = min(max(suggested, 1), paragraph.length - start)
      lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
      start += count
    }
    return lines
  }
}
