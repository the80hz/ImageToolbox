import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Morphology: dilation, erosion, opening, closing, top-hat, black-hat, gradient")
struct MorphologyFilterTests {

  /// Чёрная непрозрачная картинка 5×5 с одним белым пикселем в центре (2, 2).
  private static func spot() -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: 5 * 5 * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      pixels[index + 3] = 255
    }
    let centre = (2 * 5 + 2) * 4
    pixels[centre] = 255
    pixels[centre + 1] = 255
    pixels[centre + 2] = 255
    return RasterImage(width: 5, height: 5, pixels: pixels)
  }

  /// Красный канал пикселя (x, y).
  private static func red(_ picture: RasterImage, _ x: Int, _ y: Int) -> UInt8 {
    picture.pixels[(y * picture.width + x) * 4]
  }

  @Test("dilation grows a bright spot to the 3×3 square around it")
  func dilationGrowsSpot() async throws {
    let output = try await DilationFilter(size: 3, circle: false).apply(to: Self.spot())
    for y in 0..<5 {
      for x in 0..<5 {
        let inside = abs(x - 2) <= 1 && abs(y - 2) <= 1
        #expect(Self.red(output, x, y) == (inside ? 255 : 0), "pixel \(x),\(y)")
      }
    }
  }

  @Test("erosion removes a single bright spot smaller than the kernel")
  func erosionRemovesSpot() async throws {
    let output = try await ErodeFilter(size: 3, circle: false).apply(to: Self.spot())
    #expect(output.pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 })
  }

  @Test("opening removes a spot smaller than the kernel, closing keeps it")
  func openingAndClosingOfSpot() async throws {
    let opened = try await OpeningFilter(size: 3, circle: false).apply(to: Self.spot())
    let closed = try await ClosingFilter(size: 3, circle: false).apply(to: Self.spot())
    #expect(opened.pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 })
    #expect(closed.pixels == Self.spot().pixels)
  }

  @Test("top-hat keeps a spot smaller than the kernel, black-hat finds nothing in it")
  func topHatAndBlackHatOfSpot() async throws {
    let topHat = try await TopHatFilter(size: 3, circle: false).apply(to: Self.spot())
    let blackHat = try await BlackHatFilter(size: 3, circle: false).apply(to: Self.spot())
    #expect(topHat.pixels == Self.spot().pixels)
    #expect(blackHat.pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 })
    #expect(blackHat.pixels[3] == 255)
  }

  @Test("gradient is the 3×3 square around the spot, where dilation and erosion differ")
  func gradientOfSpot() async throws {
    let gradient = MorphologicalGradientFilter(size: 3, circle: false)
    let output = try await gradient.apply(to: Self.spot())
    for y in 0..<5 {
      for x in 0..<5 {
        let inside = abs(x - 2) <= 1 && abs(y - 2) <= 1
        #expect(Self.red(output, x, y) == (inside ? 255 : 0), "pixel \(x),\(y)")
      }
    }
  }

  @Test("a kernel of size 1 changes nothing for dilation, erosion, opening and closing")
  func sizeOneIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let filters: [any Filter] = [
      DilationFilter(size: 1, circle: false),
      ErodeFilter(size: 1, circle: true),
      OpeningFilter(size: 1, circle: false),
      ClosingFilter(size: 1, circle: true),
    ]
    for filter in filters {
      let output = try await filter.apply(to: picture)
      #expect(output.pixels == picture.pixels)
    }
  }

  @Test("a uniform picture is unchanged by dilation, erosion, opening and closing")
  func uniformPictureIsUnchanged() async throws {
    let picture = FilterTestImages.solid(width: 7, height: 5, red: 90, green: 30, blue: 200)
    let filters: [any Filter] = [
      DilationFilter(size: 5, circle: true),
      ErodeFilter(size: 5, circle: false),
      OpeningFilter(size: 4, circle: true),
      ClosingFilter(size: 4, circle: false),
    ]
    for filter in filters {
      let output = try await filter.apply(to: picture)
      #expect(output.pixels == picture.pixels)
    }
  }

  @Test("a circle kernel of size 5 is the 3×3 block (radius 5/3), a box kernel is 5×5")
  func circleDiffersFromBox() async throws {
    // Aire: точки ядра-диска отстоят от центра не больше чем на size / 3 = 1.67.
    let box = try await DilationFilter(size: 5, circle: false).apply(to: Self.spot())
    let circle = try await DilationFilter(size: 5, circle: true).apply(to: Self.spot())
    #expect(Self.red(box, 0, 0) == 255)
    #expect(Self.red(circle, 0, 0) == 0)
    // (0, 1) отстоит от спота (2, 2) на (2, 1): корень из 5 > 1.67, не входит.
    #expect(Self.red(circle, 0, 1) == 0)
    // (1, 1) отстоит на (1, 1): корень из 2 < 1.67, входит.
    #expect(Self.red(circle, 1, 1) == 255)
    #expect(Self.red(circle, 2, 1) == 255)
  }

  @Test("every operation on a 1×1 and a 5×3 picture keeps the size at both extremes")
  func survivesExtremes() async throws {
    let operations: [MorphologyEngine.Operation] = [
      .erode, .dilate, .opening, .closing, .topHat, .blackHat, .gradient,
    ]
    let pictures = [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    for operation in operations {
      for size in [1, 150] {
        for circle in [false, true] {
          for picture in pictures {
            let output = MorphologyEngine.run(
              operation, on: picture, size: size, circle: circle)
            #expect(output.width == picture.width)
            #expect(output.height == picture.height)
            #expect(output.pixels.count == picture.pixels.count)
          }
        }
      }
    }
  }

  @Test("an opaque picture gets alpha 255, a picture with transparency morphs alpha too")
  func alphaFollowsAire() async throws {
    let opaque = FilterTestImages.gradient(width: 6, height: 4)
    let topHat = try await TopHatFilter(size: 3, circle: false).apply(to: opaque)
    let gradient = try await MorphologicalGradientFilter(size: 3, circle: true).apply(to: opaque)
    for index in stride(from: 3, to: topHat.pixels.count, by: 4) {
      #expect(topHat.pixels[index] == 255)
      #expect(gradient.pixels[index] == 255)
    }
    // Один прозрачный пиксель: режим RGBA, альфа считается как обычный канал.
    var pixels = opaque.pixels
    pixels[(1 * 6 + 2) * 4 + 3] = 0
    let holed = RasterImage(width: 6, height: 4, pixels: pixels)
    let dilated = try await DilationFilter(size: 3, circle: false).apply(to: holed)
    #expect(dilated.pixels[(1 * 6 + 2) * 4 + 3] == 255)
    let eroded = try await ErodeFilter(size: 3, circle: false).apply(to: holed)
    #expect(eroded.pixels[(1 * 6 + 3) * 4 + 3] == 0)
    let edge = try await MorphologicalGradientFilter(size: 3, circle: false).apply(to: holed)
    #expect(edge.pixels[(1 * 6 + 3) * 4 + 3] == 255)
  }
}
