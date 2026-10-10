import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Ordered, clustered, random and simple threshold dithering")
struct OrderedDitheringFilterTests {

  /// Пиксели результата только 0 или 255 в каждом канале (альфа не трогается).
  private func isBinary(_ image: RasterImage) -> Bool {
    stride(from: 0, to: image.pixels.count, by: 4).allSatisfy { index in
      (0..<3).allSatisfy { image.pixels[index + $0] == 0 || image.pixels[index + $0] == 255 }
    }
  }

  @Test("Bayer 2x2 matrix is the classic one, Bayer 4x4 and 8x8 keep every rank once")
  func bayerMatrices() {
    #expect(DitherMatrix.bayer(2) == [0, 2, 3, 1])
    #expect(DitherMatrix.bayer(4) == [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5])
    for size in [2, 4, 8] {
      #expect(Set(DitherMatrix.bayer(size)) == Set(0..<(size * size)))
    }
    #expect(Set(DitherMatrix.dispersed(3)) == Set(0..<9))
    #expect(Set(DitherMatrix.clustered(4)) == Set(0..<16))
  }

  @Test("Bayer two changes the gradient and keeps only black and white levels")
  func bayerTwoChanges() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    let output = try await BayerTwoDitheringFilter(threshold: 128, grayScale: false)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
    #expect(isBinary(output))
  }

  @Test("Bayer three, four and eight change the gradient")
  func bayerLargerChange() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    let three = try await BayerThreeDitheringFilter(threshold: 128, grayScale: false)
      .apply(to: picture)
    let four = try await BayerFourDitheringFilter(threshold: 128, grayScale: false)
      .apply(to: picture)
    let eight = try await BayerEightDitheringFilter(threshold: 128, grayScale: false)
      .apply(to: picture)
    #expect(three.pixels != picture.pixels)
    #expect(four.pixels != picture.pixels)
    #expect(eight.pixels != picture.pixels)
  }

  @Test("grey scale makes every output pixel grey")
  func greyScaleIsGrey() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await BayerFourDitheringFilter(threshold: 128, grayScale: true)
      .apply(to: picture)
    for index in stride(from: 0, to: output.pixels.count, by: 4) {
      #expect(output.pixels[index] == output.pixels[index + 1])
      #expect(output.pixels[index] == output.pixels[index + 2])
    }
  }

  @Test("clustered filters change the gradient and keep binary levels")
  func clusteredChanges() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    let outputs = [
      try await Clustered2x2DitheringFilter(grayScale: false).apply(to: picture),
      try await Clustered4x4DitheringFilter(grayScale: false).apply(to: picture),
      try await Clustered8x8DitheringFilter(grayScale: false).apply(to: picture),
    ]
    for output in outputs {
      #expect(output.pixels != picture.pixels)
      #expect(isBinary(output))
    }
  }

  @Test("random dithering is repeatable for the same picture")
  func randomIsDeterministic() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    let filter = RandomDitheringFilter(threshold: 128, grayScale: false)
    let first = try await filter.apply(to: picture)
    let second = try await filter.apply(to: picture)
    #expect(first.pixels == second.pixels)
    #expect(first.pixels != picture.pixels)
    #expect(isBinary(first))
  }

  @Test("simple threshold keeps white at the threshold and black below it")
  func simpleThresholdSplits() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 1, red: 100, green: 100, blue: 100)
    let above = try await SimpleThresholdDitheringFilter(threshold: 100, grayScale: false)
      .apply(to: picture)
    let below = try await SimpleThresholdDitheringFilter(threshold: 101, grayScale: false)
      .apply(to: picture)
    #expect(Array(above.pixels[0..<3]) == [255, 255, 255])
    #expect(Array(below.pixels[0..<3]) == [0, 0, 0])
  }

  @Test("simple threshold at 1 keeps black and at 255 keeps white")
  func simpleThresholdNeutralEnds() async throws {
    let black = FilterTestImages.solid(width: 3, height: 2, red: 0, green: 0, blue: 0)
    let white = FilterTestImages.solid(width: 3, height: 2, red: 255, green: 255, blue: 255)
    let blackOut = try await SimpleThresholdDitheringFilter(threshold: 1, grayScale: false)
      .apply(to: black)
    let whiteOut = try await SimpleThresholdDitheringFilter(threshold: 255, grayScale: false)
      .apply(to: white)
    #expect(blackOut.pixels == black.pixels)
    #expect(whiteOut.pixels == white.pixels)
  }

  @Test("every ordered filter survives threshold extremes on 1x1 and 5x3 pictures")
  func extremesKeepSize() async throws {
    let pictures = [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    let filters: [(Double) -> any Filter] = [
      { BayerTwoDitheringFilter(threshold: $0, grayScale: false) },
      { BayerThreeDitheringFilter(threshold: $0, grayScale: true) },
      { BayerFourDitheringFilter(threshold: $0, grayScale: false) },
      { BayerEightDitheringFilter(threshold: $0, grayScale: true) },
      { RandomDitheringFilter(threshold: $0, grayScale: false) },
      { SimpleThresholdDitheringFilter(threshold: $0, grayScale: true) },
    ]
    for make in filters {
      for threshold in [1.0, 255.0] {
        for picture in pictures {
          let output = try await make(threshold).apply(to: picture)
          #expect(output.width == picture.width)
          #expect(output.height == picture.height)
          #expect(output.pixels.count == picture.pixels.count)
        }
      }
    }
    for make in [
      { Clustered2x2DitheringFilter(grayScale: $0) },
      { Clustered4x4DitheringFilter(grayScale: $0) },
      { Clustered8x8DitheringFilter(grayScale: $0) },
    ] as [(Bool) -> any Filter] {
      for flag in [false, true] {
        for picture in pictures {
          let output = try await make(flag).apply(to: picture)
          #expect(output.width == picture.width)
          #expect(output.height == picture.height)
          #expect(output.pixels.count == picture.pixels.count)
        }
      }
    }
  }
}
