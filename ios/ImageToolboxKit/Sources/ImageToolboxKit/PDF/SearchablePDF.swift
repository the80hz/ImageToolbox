import CoreGraphics
import CoreText
import Foundation

/// Builds a searchable PDF: each page shows the scanned picture, and the text that Vision recognised
/// is drawn over it with invisible text rendering. The text is invisible, so it can be searched and
/// selected without showing on the page. Recognition runs on the device.
public enum SearchablePDF {

  public enum Failure: Error, Equatable {
    /// The array of pictures is empty.
    case noPictures
    case writeFailed
  }

  /// JPEG quality of the picture on each page. Recognition reads the original pixels, not this copy.
  private static let pictureQuality = 0.9
  private static let fontName = "Helvetica"

  /// One page per picture. A page is as large in points as its picture is in pixels.
  /// - Parameter languages: language codes for recognition, in order of preference. Errors from
  ///   `TextRecognizer` are passed on unchanged.
  public static func make(from pictures: [CGImage], languages: [String]) throws -> Data {
    guard !pictures.isEmpty else { throw Failure.noPictures }

    let output = try PDFPageWriter.write(pageCount: pictures.count) { index in
      let picture = pictures[index]
      let size = CGSize(width: picture.width, height: picture.height)
      let lines = try TextRecognizer.recognize(picture, languages: languages)
      let jpeg = ImageCodec.encode(picture, as: .jpeg, quality: pictureQuality)
      let image = jpeg.flatMap(PDFPageWriter.jpegBacked) ?? picture
      return PDFPageWriter.Page(size: size) { context in
        context.draw(image, in: CGRect(origin: .zero, size: size))
        for line in lines {
          drawInvisibleText(line, pageSize: size, in: context)
        }
      }
    }
    guard let pdf = output else { throw Failure.writeFailed }
    return pdf
  }

  /// Draws the line's text inside its box with invisible rendering. The font size makes the line box
  /// as tall as the recognised box, and the text is stretched to its width. Both keep the text layer
  /// over the matching words, so a search highlight lands where the word is on the picture.
  private static func drawInvisibleText(
    _ line: RecognizedLine, pageSize: CGSize, in context: CGContext
  ) {
    let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let box = line.boundingBox
    // Vision's box has its origin at the bottom left, as the PDF page does, so only the scale changes.
    let rect = CGRect(
      x: box.minX * pageSize.width, y: box.minY * pageSize.height,
      width: box.width * pageSize.width, height: box.height * pageSize.height)
    guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }

    // Ascent plus descent grows linearly with the size, so one probe at 100 points gives the size.
    let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
    let lineHeightAt100 = CTFontGetAscent(probe) + CTFontGetDescent(probe)
    let font = CTFontCreateWithName(
      fontName as CFString, rect.height * 100 / lineHeightAt100, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font
    ]
    let ctLine = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
    guard width > 0 else { return }

    context.saveGState()
    context.setTextDrawingMode(.invisible)
    context.translateBy(x: rect.minX, y: rect.minY + CTFontGetDescent(font))
    context.scaleBy(x: rect.width / width, y: 1)
    context.textPosition = .zero
    CTLineDraw(ctLine, context)
    context.restoreGState()
  }
}
