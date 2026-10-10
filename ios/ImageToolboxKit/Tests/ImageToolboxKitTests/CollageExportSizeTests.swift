import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage export size")
struct CollageExportSizeTests {

  private static let square = CollageExportSize.Aspect(width: 1, height: 1)

  @Test("the aspect presets are the Android numeric ones, starting with the square")
  func presets() {
    #expect(CollageExportSize.aspects.count == 23)
    #expect(CollageExportSize.aspects.first == Self.square)
    #expect(CollageExportSize.defaultAspect == Self.square)
    #expect(CollageExportSize.Aspect(width: 9, height: 16).title == "9:16")
    #expect(CollageExportSize.Aspect(width: 18.5, height: 9).title == "18.5:9")
  }

  @Test("a ratio part that is not a positive number becomes 1")
  func badRatioParts() {
    #expect(CollageExportSize.Aspect(width: 0, height: -3) == Self.square)
    #expect(
      CollageExportSize.Aspect(width: .nan, height: 2)
        == CollageExportSize.Aspect(width: 1, height: 2))
  }

  @Test("the longer side of a size is the given side, and the shorter side follows the ratio")
  func dimensions() {
    let portrait = CollageExportSize.dimensions(
      aspect: CollageExportSize.Aspect(width: 9, height: 16), longSide: 1080)
    #expect(portrait.width == 608)
    #expect(portrait.height == 1080)
    let landscape = CollageExportSize.dimensions(
      aspect: CollageExportSize.Aspect(width: 16, height: 9), longSide: 1080)
    #expect(landscape.width == 1080)
    #expect(landscape.height == 608)
    let square = CollageExportSize.dimensions(aspect: Self.square, longSide: 1080)
    #expect(square.width == 1080 && square.height == 1080)
  }

  @Test("the export is the largest picture's longer side times the output scale, as on Android")
  func scaledFromSource() {
    let size = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 4000, scale: 0.5)
    #expect(size.width == 2000 && size.height == 2000)
    let full = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 3024, scale: 1)
    #expect(full.width == 3024 && full.height == 3024)
  }

  @Test("the export stays within the longest side and the pixel budget")
  func limits() {
    let huge = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 20_000, scale: 1)
    #expect(max(huge.width, huge.height) <= CollageExportSize.maximumLongSide)
    #expect(huge.width * huge.height <= CollageExportSize.maximumPixels)

    let dense = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 8000, scale: 1)
    #expect(dense.width == dense.height)
    #expect(dense.width * dense.height <= CollageExportSize.maximumPixels)
    #expect(dense.width > 5600)
  }

  @Test(
    "the scale is kept within the slider's range, and a scale that is not a number is the default")
  func scaleRange() {
    let low = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 1000, scale: 0)
    #expect(low.width == 100)
    let high = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 1000, scale: 5)
    #expect(high.width == 1000)
    let unset = CollageExportSize.exportDimensions(
      aspect: Self.square, sourceLongSide: 1000, scale: .nan)
    #expect(unset.width == 500)
  }
}
