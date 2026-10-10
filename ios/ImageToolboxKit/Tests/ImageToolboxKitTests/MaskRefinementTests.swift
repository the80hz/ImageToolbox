import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Hand refinement of subject masks")
struct MaskRefinementTests {

  /// An opaque picture of one colour.
  private static func opaque(width: Int, height: Int, color: RGBA) -> RasterImage {
    var pixels: [UInt8] = []
    for _ in 0..<(width * height) {
      pixels += [color.red, color.green, color.blue, color.alpha]
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  @Test("erase makes the centre transparent, softens the rim and leaves distant pixels alone")
  func eraseCentre() {
    var mask = SubjectMask(width: 16, height: 16, alpha: Array(repeating: 1, count: 256))
    // The centre of pixel (8, 8), so its distance to the centre is zero.
    mask.erase(at: CGPoint(x: 8.5, y: 8.5), radius: 4)
    #expect(mask.alpha[8 * 16 + 8] == 0)
    // Two pixels from the centre the weight is (1 - 2/4) squared, so the opacity is 0.75.
    #expect(abs(mask.alpha[8 * 16 + 10] - 0.75) < 1e-9)
    #expect(mask.alpha[0] == 1)
    #expect(mask.alpha[15 * 16 + 15] == 1)
    // Pixel (13, 8) has its centre 5 pixels away, outside the radius.
    #expect(mask.alpha[8 * 16 + 13] == 1)
  }

  @Test("restore brings back the opacity of the source under the brush")
  func restoreOpacity() {
    var mask = SubjectMask(width: 16, height: 16, alpha: Array(repeating: 0, count: 256))
    let source = Self.opaque(width: 16, height: 16, color: RGBA(red: 10, green: 20, blue: 30))
    mask.restore(at: CGPoint(x: 8.5, y: 8.5), radius: 4, source: source)
    #expect(mask.alpha[8 * 16 + 8] == 1)
    #expect(mask.alpha[0] == 0)
  }

  @Test("restore takes the opacity of the source, so transparent source pixels stay transparent")
  func restoreFollowsSource() {
    var mask = SubjectMask(width: 16, height: 16, alpha: Array(repeating: 0, count: 256))
    var pixels = Self.opaque(width: 16, height: 16, color: RGBA(red: 0, green: 0, blue: 0)).pixels
    for y in 0..<16 {
      for x in 0..<8 { pixels[(y * 16 + x) * 4 + 3] = 0 }
    }
    let source = RasterImage(width: 16, height: 16, pixels: pixels)
    mask.restore(at: CGPoint(x: 8.5, y: 8.5), radius: 4, source: source)
    #expect(mask.alpha[8 * 16 + 7] == 0)
    #expect(mask.alpha[8 * 16 + 8] == 1)
  }

  @Test("the mask reads the alpha channel of a cut-out")
  func readsCutout() throws {
    let cutout = TestImages.image(width: 4, height: 1) { x, _ in
      RGBA(red: 0, green: 0, blue: 0, alpha: UInt8(x * 85))
    }
    let mask = try #require(SubjectMask(cutout: cutout))
    #expect(mask.width == 4 && mask.height == 1)
    #expect(abs(mask.alpha[0]) < 1e-9)
    #expect(abs(mask.alpha[1] - 85.0 / 255) < 1e-9)
    #expect(abs(mask.alpha[3] - 1) < 1e-9)
  }

  @Test("applied keeps the colour of the source and takes the mask as alpha")
  func appliedKeepsColour() {
    // Premultiplied pixels: opaque red, then opaque blue.
    let source = RasterImage(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 0, 255, 255])
    let mask = SubjectMask(width: 2, height: 1, alpha: [0.5, 1])
    let result = mask.applied(to: source)
    // Half opacity: straight red at alpha 128 (127.5 rounded up).
    #expect(result.pixel(x: 0, y: 0) == RGBA(red: 255, green: 0, blue: 0, alpha: 128))
    #expect(result.pixel(x: 1, y: 0) == RGBA(red: 0, green: 0, blue: 255, alpha: 255))
  }

  @Test("applied with a zero mask makes the picture transparent")
  func appliedZero() {
    let source = RasterImage(width: 1, height: 1, pixels: [200, 100, 50, 255])
    let mask = SubjectMask(width: 1, height: 1, alpha: [0])
    #expect(mask.applied(to: source).pixels == [0, 0, 0, 0])
  }
}
