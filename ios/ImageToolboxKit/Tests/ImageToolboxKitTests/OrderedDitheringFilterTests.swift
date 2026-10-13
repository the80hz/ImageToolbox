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

  @Test("Trickle matrices hold every rank once")
  func trickleMatrices() {
    #expect(Set(TrickleMatrix.bayer2) == Set(1...4))
    #expect(Set(TrickleMatrix.bayer3) == Set(1...9))
    #expect(Set(TrickleMatrix.bayer4) == Set(1...16))
    #expect(Set(TrickleMatrix.bayer8) == Set(1...64))
    #expect(Set(TrickleMatrix.clustered2) == Set(0..<4))
    #expect(Set(TrickleMatrix.clustered4) == Set(0..<16))
    #expect(Set(TrickleMatrix.clustered8) == Set(0..<64))
  }

  @Test("Bayer 2x2 indexes the matrix as (column, row) and adds value * cell / 5")
  func bayerTwoIndexing() async throws {
    // Matrix [[1, 3], [4, 2]] read as matrix[x % 2][y % 2]: (x,y) = (0,0) gives 1, (1,0) gives 4,
    // (0,1) gives 3, (1,1) gives 2. With value 90 and threshold 150 the result is
    // 108 (off), 162 (on), 144 (off), 126 (off). A non-transposed matrix would turn (0,1) on.
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 90, green: 90, blue: 90)
    let output = try await BayerTwoDitheringFilter(threshold: 150, grayScale: false)
      .apply(to: picture)
    let red = stride(from: 0, to: 16, by: 4).map { output.pixels[$0] }
    #expect(red == [0, 255, 0, 0])
  }

  @Test("clustered compares strictly: a value equal to the cell threshold stays off")
  func clusteredIsStrict() async throws {
    // Clustered 2x2, cell (0,0) is 0, so the threshold is 0 and value 0 stays off, 1 turns on.
    let zero = FilterTestImages.solid(width: 1, height: 1, red: 0, green: 0, blue: 0)
    let one = FilterTestImages.solid(width: 1, height: 1, red: 1, green: 1, blue: 1)
    let off = try await Clustered2x2DitheringFilter(grayScale: false).apply(to: zero)
    let on = try await Clustered2x2DitheringFilter(grayScale: false).apply(to: one)
    #expect(Array(off.pixels[0..<3]) == [0, 0, 0])
    #expect(Array(on.pixels[0..<3]) == [255, 255, 255])
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

  @Test("simple threshold in grey scale takes the red channel and truncates the threshold")
  func simpleThresholdGreyScaleTakesRed() async throws {
    // Red 200 with dark green and blue: luma is about 70, but Trickle compares red only.
    let picture = FilterTestImages.solid(width: 2, height: 1, red: 200, green: 10, blue: 10)
    let grey = try await SimpleThresholdDitheringFilter(threshold: 200.9, grayScale: true)
      .apply(to: picture)
    #expect(Array(grey.pixels[0..<4]) == [255, 255, 255, 255])
    let colour = try await SimpleThresholdDitheringFilter(threshold: 200.9, grayScale: false)
      .apply(to: picture)
    #expect(Array(colour.pixels[0..<4]) == [255, 0, 0, 255])
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
