import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Background removal with Vision")
struct BackgroundRemoverTests {

  /// A shaded orange ball on a grey background. Vision finds a shaded subject, but not a flat shape.
  private static func picture() throws -> CGImage {
    let size = 384
    let context = try #require(
      CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let colours =
      [
        CGColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1),
        CGColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1),
      ] as CFArray
    let gradient = try #require(
      CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]))
    context.saveGState()
    context.addEllipse(in: CGRect(x: 90, y: 90, width: 204, height: 204))
    context.clip()
    context.drawRadialGradient(
      gradient, startCenter: CGPoint(x: 160, y: 200), startRadius: 0,
      endCenter: CGPoint(x: 192, y: 192), endRadius: 150, options: [])
    context.restoreGState()
    return try #require(context.makeImage())
  }

  @Test("the shaded subject stays opaque and the background becomes transparent")
  func removesBackground() throws {
    let result = try BackgroundRemover.removeBackground(from: try Self.picture())
    #expect(result.width == 384 && result.height == 384)
    let raster = try #require(RasterImage(result))
    #expect(raster.pixel(x: 8, y: 8).alpha == 0)
    #expect(raster.pixel(x: 192, y: 192).alpha == 255)
  }
}
