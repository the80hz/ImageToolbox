import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Text recognition with Vision")
struct TextRecognizerTests {

  /// Draws `text` in large black letters on white, so the recogniser has clean input.
  private static func picture(of text: String) throws -> CGImage {
    let width = 900
    let height = 220
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 96, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
        red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: 40, y: 60)
    CTLineDraw(line, context)
    return try #require(context.makeImage())
  }

  @Test("printed English text is read back as text")
  func readsPrintedText() throws {
    let image = try Self.picture(of: "HELLO 2026")
    let lines = try TextRecognizer.recognize(image, languages: ["en-US"])
    let joined = lines.map(\.text).joined(separator: " ").uppercased()
    #expect(joined.contains("HELLO"))
    #expect(lines.allSatisfy { (0...1).contains($0.confidence) })
  }

  @Test("a blank picture has no lines of text")
  func blankPicture() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let lines = try TextRecognizer.recognize(try #require(context.makeImage()))
    #expect(lines.isEmpty)
  }
}
