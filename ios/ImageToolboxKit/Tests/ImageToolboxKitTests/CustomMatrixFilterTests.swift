import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Custom colour matrices 3x3 and 4x4, and simple solarize")
struct CustomMatrixFilterTests {

  @Test("the identity matrix changes nothing, in 3x3 and 4x4")
  func identityIsNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let three = try await ColorMatrix3x3Filter(matrix: ColourMatrixMath.identityRows(size: 3))
      .apply(to: picture)
    #expect(three.pixels == picture.pixels)
    let four = try await ColorMatrix4x4Filter(matrix: ColourMatrixMath.identityRows(size: 4))
      .apply(to: picture)
    #expect(four.pixels == picture.pixels)
  }

  @Test("a red and blue swap moves the channels, alpha stays")
  func swapRedAndBlue() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 200, green: 100, blue: 20)
    let three = try await ColorMatrix3x3Filter(matrix: [0, 0, 1, 0, 1, 0, 1, 0, 0]).apply(
      to: picture)
    #expect(Array(three.pixels[0..<4]) == [20, 100, 200, 255])
    let four = try await ColorMatrix4x4Filter(
      matrix: [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]
    ).apply(to: picture)
    #expect(Array(four.pixels[0..<4]) == [20, 100, 200, 255])
  }

  @Test("a negative result clamps to 0 and a result above 255 to 255")
  func clampsToRange() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 200, green: 100, blue: 20)
    let three = try await ColorMatrix3x3Filter(matrix: [-1, 0, 0, 0, 3, 0, 0, 0, 1]).apply(
      to: picture)
    #expect(Array(three.pixels) == [0, 255, 20, 255])
    let four = try await ColorMatrix4x4Filter(
      matrix: [-1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ).apply(to: picture)
    #expect(Array(four.pixels) == [0, 255, 20, 255])
  }

  @Test("zero and large matrices keep the size on 1x1 and 5x3 pictures")
  func matricesSurviveExtremes() async throws {
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      for value in [0.0, 1000.0] {
        let three = try await ColorMatrix3x3Filter(matrix: Array(repeating: value, count: 9))
          .apply(to: picture)
        #expect(three.width == picture.width)
        #expect(three.pixels.count == picture.pixels.count)
        let four = try await ColorMatrix4x4Filter(matrix: Array(repeating: value, count: 16))
          .apply(to: picture)
        #expect(four.width == picture.width)
        #expect(four.pixels.count == picture.pixels.count)
      }
    }
  }

  @Test("a matrix of the wrong size takes the default, a non-finite cell takes its default cell")
  func matrixNormalisation() throws {
    let descriptor = try #require(FilterRegistry.descriptor(for: "ColorMatrix3x3Filter"))
    let identity = ColourMatrixMath.identityRows(size: 3)
    let short = FilterStep(id: descriptor.id, values: ["value": .matrix([1, 2])])
    #expect(FilterRegistry.values(for: short, of: descriptor).matrix("value") == identity)

    var cells = Array(repeating: 2.0, count: 9)
    cells[4] = .nan
    let broken = FilterStep(id: descriptor.id, values: ["value": .matrix(cells)])
    var expected = Array(repeating: 2.0, count: 9)
    expected[4] = 1
    #expect(FilterRegistry.values(for: broken, of: descriptor).matrix("value") == expected)
  }

  @Test("a matrix value survives a JSON round trip")
  func matrixCodable() throws {
    let value = FilterValue.matrix([1.5, -0.25, 0, 0, 1, 0, 0, 0, 1])
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(FilterValue.self, from: data) == value)
  }

  @Test("simple solarize folds each channel around middle grey, black and white stay white")
  func simpleSolarizeFolds() async throws {
    let black = FilterTestImages.solid(width: 1, height: 1, red: 0, green: 0, blue: 0)
    let folded = try await SimpleSolarizeFilter().apply(to: black)
    #expect(folded.pixels == [255, 255, 255, 255])
    let white = FilterTestImages.solid(width: 1, height: 1, red: 255, green: 255, blue: 255)
    #expect(try await SimpleSolarizeFilter().apply(to: white).pixels == [255, 255, 255, 255])
    // Середина 128 даёт 2 * (128/255 - 0.5) * 255 = 1: почти чёрный, не белый.
    let grey = FilterTestImages.solid(width: 1, height: 1, red: 128, green: 128, blue: 128)
    #expect(try await SimpleSolarizeFilter().apply(to: grey).pixels[0] <= 1)
  }

  @Test("simple solarize keeps the size on 1x1 and 5x3 pictures")
  func simpleSolarizeSurvivesExtremes() async throws {
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      let output = try await SimpleSolarizeFilter().apply(to: picture)
      #expect(output.width == picture.width)
      #expect(output.height == picture.height)
      #expect(output.pixels.count == picture.pixels.count)
    }
  }
}
