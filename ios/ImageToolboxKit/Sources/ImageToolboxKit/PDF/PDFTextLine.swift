import CoreGraphics
import CoreText
import Foundation

/// One line of text set with CoreText, for the tools that write onto pages. The font is Helvetica,
/// and CoreText falls back to another font for characters that Helvetica lacks, so Cyrillic and
/// other scripts are drawn too.
struct PDFTextLine {
  private static let fontName = "Helvetica"

  private let line: CTLine
  let width: CGFloat
  let ascent: CGFloat
  let descent: CGFloat

  /// The text at `fontSize` points. Nil for blank text or a size that is not positive.
  init?(_ text: String, fontSize: CGFloat) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, fontSize > 0 else { return nil }
    let font = CTFontCreateWithName(Self.fontName as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font
    ]
    line = CTLineCreateWithAttributedString(
      NSAttributedString(string: trimmed, attributes: attributes))
    width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ascent = CTFontGetAscent(font)
    descent = CTFontGetDescent(font)
    guard width > 0 else { return nil }
  }

  /// The text at the size that makes the line `width` points wide.
  init?(_ text: String, fittingWidth width: CGFloat) {
    guard width > 0, let probe = PDFTextLine(text, fontSize: 100) else { return nil }
    self.init(text, fontSize: 100 * width / probe.width)
  }

  /// Paints the text with its baseline starting at `origin`, in the context's fill colour.
  func draw(at origin: CGPoint, in context: CGContext) {
    context.saveGState()
    context.textPosition = origin
    CTLineDraw(line, context)
    context.restoreGState()
  }
}

extension RGBA {
  /// The colour in sRGB, with its alpha scaled by `opacity`.
  func cgColor(opacity: Double = 1) -> CGColor {
    CGColor(
      srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
      alpha: CGFloat(alpha) / 255 * CGFloat(min(max(opacity, 0), 1)))
  }
}
