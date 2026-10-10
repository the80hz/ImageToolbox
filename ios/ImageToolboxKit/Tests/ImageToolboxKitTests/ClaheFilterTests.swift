import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("CLAHE and adaptive histogram equalisation")
struct ClaheFilterTests {

  @Test("CLAHE changes a gradient, where the histogram has room to stretch")
  func claheChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 32, height: 24)
    let output = try await ClaheFilter(threshold: 0.5, gridX: 4, gridY: 4).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("adaptive equalisation changes a gradient")
  func equalizeChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 32, height: 24)
    let output = try await EqualizeHistogramAdaptiveFilter(gridX: 3, gridY: 3).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("adaptive equalisation keeps a one-colour picture unchanged")
  func equalizeKeepsSolidPicture() async throws {
    // Each tile holds one value, so its equalisation table is the identity.
    let picture = FilterTestImages.solid(width: 5, height: 3, red: 40, green: 120, blue: 200)
    let output = try await EqualizeHistogramAdaptiveFilter(gridX: 3, gridY: 2).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("extreme settings keep the size on 1x1 and 5x3 pictures")
  func extremesKeepSize() async throws {
    let filters: [any Filter] = [
      ClaheFilter(threshold: -10, gridX: 1, gridY: 1),
      ClaheFilter(threshold: 10, gridX: 100, gridY: 100),
      ClaheFilter(threshold: -10, gridX: 100, gridY: 1),
      ClaheFilter(threshold: 10, gridX: 1, gridY: 100),
      EqualizeHistogramAdaptiveFilter(gridX: 1, gridY: 1),
      EqualizeHistogramAdaptiveFilter(gridX: 100, gridY: 100),
    ]
    let sizes: [(Int, Int)] = [(1, 1), (5, 3)]
    for filter in filters {
      for (width, height) in sizes {
        let picture = FilterTestImages.gradient(width: width, height: height)
        let output = try await filter.apply(to: picture)
        #expect(output.width == width)
        #expect(output.height == height)
        #expect(output.pixels.count == width * height * 4)
      }
    }
  }

  @Test("the alpha channel is not changed")
  func alphaIsKept() async throws {
    let base = FilterTestImages.gradient(width: 5, height: 3)
    var pixels = base.pixels
    for index in stride(from: 3, to: pixels.count, by: 4) {
      pixels[index] = 128
    }
    let picture = RasterImage(width: base.width, height: base.height, pixels: pixels)
    let output = try await ClaheFilter(threshold: 0.5, gridX: 2, gridY: 2).apply(to: picture)
    for index in stride(from: 3, to: output.pixels.count, by: 4) {
      #expect(output.pixels[index] == 128)
    }
  }
}
