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

  @Test("every dithering filter changes a gradient, and its colour channels are only 0 or 255")
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
        #expect(output.pixels[index + 3] == picture.pixels[index + 3])
      }
    }
  }

  @Test("white and black stay as they are at every threshold, since no error is made")
  func flatExtremesAreUnchanged() async throws {
    let white = FilterTestImages.solid(width: 4, height: 3, red: 255, green: 255, blue: 255)
    let black = FilterTestImages.solid(width: 4, height: 3, red: 0, green: 0, blue: 0)
    for descriptor in DitheringFilters.descriptors {
      for threshold in [1.0, 128, 255] {
        let whiteOutput = try await makeFilter(descriptor, threshold: threshold).apply(to: white)
        let blackOutput = try await makeFilter(descriptor, threshold: threshold).apply(to: black)
        #expect(whiteOutput.pixels == white.pixels, "\(descriptor.id) at \(threshold)")
        #expect(blackOutput.pixels == black.pixels, "\(descriptor.id) at \(threshold)")
      }
    }
  }

  @Test("pure red stays pure red, because each channel is already 0 or 255")
  func pureColourIsUnchanged() async throws {
    let red = FilterTestImages.solid(width: 3, height: 2, red: 255, green: 0, blue: 0)
    for descriptor in DitheringFilters.descriptors {
      let output = try await makeFilter(descriptor, threshold: 128).apply(to: red)
      #expect(output.pixels == red.pixels, "\(descriptor.id)")
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

  @Test(
    "Floyd–Steinberg sends 7/16 of the error to the right, so a 3-pixel row of 100 gives 0, 255, 0")
  func floydSteinbergCarriesSevenSixteenths() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 100, green: 100, blue: 100)
    let output = try await FloydSteinbergDitheringFilter(threshold: 128, grayScale: false).apply(
      to: picture)
    #expect([output.pixels[0], output.pixels[4], output.pixels[8]] == [0, 255, 0])
  }
}
