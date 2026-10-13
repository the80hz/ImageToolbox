import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Dithering with error diffusion")
struct DitheringFilterTests {

  /// Builds the filter of `descriptor` with the given threshold and grey-scale flag, normalised as the app does.
  private func makeFilter(
    _ descriptor: FilterDescriptor, threshold: Double, grayScale: Bool = false
  ) -> any Filter {
    let step = FilterStep(
      id: descriptor.id, values: ["threshold": .number(threshold), "grayScale": .flag(grayScale)])
    return descriptor.build(FilterRegistry.values(for: step, of: descriptor))
  }

  /// Область, которую цикл Trickle заведомо обходит у любого ядра: отступы не больше 2 справа и снизу.
  private func isInside(_ x: Int, _ y: Int, width: Int, height: Int) -> Bool {
    x < width - 4 && y < height - 2
  }

  @Test(
    "every dithering filter changes a gradient, colour channels are 0 or 255, alpha is kept or 0")
  func outputIsBinaryAndChanges() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    for descriptor in DitheringFilters.descriptors {
      let output = try await makeFilter(descriptor, threshold: 128).apply(to: picture)
      #expect(output.pixels != picture.pixels, "\(descriptor.id) did not change the picture")
      for index in stride(from: 0, to: output.pixels.count, by: 4) {
        for channel in 0..<3 {
          let value = output.pixels[index + channel]
          #expect(value == 0 || value == 255, "\(descriptor.id) gave \(value)")
        }
        let alpha = output.pixels[index + 3]
        #expect(alpha == picture.pixels[index + 3] || alpha == 0)
      }
    }
  }

  @Test("white and black stay as they are at every threshold inside the processed area")
  func flatExtremesAreUnchanged() async throws {
    let white = FilterTestImages.solid(width: 10, height: 6, red: 255, green: 255, blue: 255)
    let black = FilterTestImages.solid(width: 10, height: 6, red: 0, green: 0, blue: 0)
    for descriptor in DitheringFilters.descriptors {
      for threshold in [1.0, 128, 255] {
        let whiteOutput = try await makeFilter(descriptor, threshold: threshold).apply(to: white)
        let blackOutput = try await makeFilter(descriptor, threshold: threshold).apply(to: black)
        for y in 0..<6 {
          for x in 0..<10 where isInside(x, y, width: 10, height: 6) {
            let index = (y * 10 + x) * 4
            #expect(
              Array(whiteOutput.pixels[index..<index + 4]) == [255, 255, 255, 255],
              "\(descriptor.id) at \(threshold)")
            #expect(
              Array(blackOutput.pixels[index..<index + 4]) == [0, 0, 0, 255],
              "\(descriptor.id) at \(threshold)")
          }
        }
      }
    }
  }

  @Test("pure red stays pure red inside the processed area, because each channel is 0 or 255")
  func pureColourIsUnchanged() async throws {
    let red = FilterTestImages.solid(width: 10, height: 6, red: 255, green: 0, blue: 0)
    for descriptor in DitheringFilters.descriptors {
      let output = try await makeFilter(descriptor, threshold: 128).apply(to: red)
      for y in 0..<6 {
        for x in 0..<10 where isInside(x, y, width: 10, height: 6) {
          let index = (y * 10 + x) * 4
          #expect(Array(output.pixels[index..<index + 4]) == [255, 0, 0, 255], "\(descriptor.id)")
        }
      }
    }
  }

  @Test(
    "extreme thresholds and sizes 1x1 and 5x3 run and keep the size, with and without grey scale")
  func extremesKeepSize() async throws {
    let sizes = [(1, 1), (5, 3)]
    for descriptor in DitheringFilters.descriptors {
      for (width, height) in sizes {
        let picture = FilterTestImages.gradient(width: width, height: height)
        for threshold in [1.0, 255] {
          for grayScale in [false, true] {
            let filter = makeFilter(descriptor, threshold: threshold, grayScale: grayScale)
            let output = try await filter.apply(to: picture)
            #expect(output.width == width && output.height == height, "\(descriptor.id)")
            #expect(output.pixels.count == width * height * 4, "\(descriptor.id)")
          }
        }
      }
    }
  }

  @Test("grey scale makes every pixel's red, green and blue equal")
  func greyScaleGivesEqualChannels() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    for descriptor in DitheringFilters.descriptors {
      let output = try await makeFilter(descriptor, threshold: 128, grayScale: true).apply(
        to: picture)
      for index in stride(from: 0, to: output.pixels.count, by: 4) {
        #expect(output.pixels[index] == output.pixels[index + 1], "\(descriptor.id)")
        #expect(output.pixels[index] == output.pixels[index + 2], "\(descriptor.id)")
      }
    }
  }

  @Test(
    "left to right passes the error of 100 to the right pixel, which then reaches 200 and turns white"
  )
  func leftToRightCarriesError() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 1, red: 100, green: 100, blue: 100)
    let output = try await LeftToRightDitheringFilter(threshold: 128, grayScale: false).apply(
      to: picture)
    #expect(output.pixels[0] == 0)
    #expect(output.pixels[4] == 255)
  }

  @Test("Floyd–Steinberg as in Trickle: shifted left by one, last two columns and last row empty")
  func floydSteinbergFollowsTrickleLayout() async throws {
    // Row 0 has five pixels of 100. The loop visits columns 1...3 but reads pixels 0...2.
    // Pixel 0: 100 < 128, off, error 100, 7*100/16 = 43 goes right.
    // Pixel 1: 100 + 43 = 143 >= 128, on, error -112, 7*-112/16 = -49 goes right.
    // Pixel 2: 100 - 49 = 51 < 128, off.
    let picture = FilterTestImages.solid(width: 5, height: 2, red: 100, green: 100, blue: 100)
    let output = try await FloydSteinbergDitheringFilter(threshold: 128, grayScale: false).apply(
      to: picture)
    let red = stride(from: 0, to: 20, by: 4).map { output.pixels[$0] }
    let alpha = stride(from: 3, to: 20, by: 4).map { output.pixels[$0] }
    #expect(red == [0, 255, 0, 0, 0])
    #expect(alpha == [255, 255, 255, 0, 0])
    #expect(output.pixels[20...].allSatisfy { $0 == 0 })
  }

  @Test("Sierra Lite uses the two-row Sierra kernel, as in Trickle")
  func sierraLiteEqualsTwoRowSierra() async throws {
    let picture = FilterTestImages.gradient(width: 12, height: 9)
    let lite = try await SierraLiteDitheringFilter(threshold: 128, grayScale: false).apply(
      to: picture)
    let twoRow = try await TwoRowSierraDitheringFilter(threshold: 128, grayScale: false).apply(
      to: picture)
    #expect(lite.pixels == twoRow.pixels)
  }

  @Test("grey scale takes the red channel, not the luma, as in Trickle")
  func greyScaleTakesRed() async throws {
    let picture = FilterTestImages.solid(width: 6, height: 4, red: 255, green: 0, blue: 0)
    let output = try await FloydSteinbergDitheringFilter(threshold: 128, grayScale: true).apply(
      to: picture)
    #expect(Array(output.pixels[0..<4]) == [255, 255, 255, 255])
  }

  @Test("a fractional threshold is truncated like Kotlin toInt")
  func thresholdIsTruncated() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 100, green: 100, blue: 100)
    let exact = try await LeftToRightDitheringFilter(threshold: 100, grayScale: false).apply(
      to: picture)
    let fractional = try await LeftToRightDitheringFilter(threshold: 100.9, grayScale: false)
      .apply(to: picture)
    #expect(exact.pixels == fractional.pixels)
    #expect(exact.pixels[0] == 255)
  }
}
