import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Tone mapping approximations: change, black, monotonic and extremes")
struct ToneMappingFilterTests {

  static let filters: [any Filter] = [
    AcesFilmicFilter(exposure: 1),
    HableFilmicFilter(exposure: 1),
    HejlBurgessFilter(exposure: 1),
    LogarithmicFilter(exposure: 1),
    UchimuraFilter(scale: 1),
    DragoFilter(scale: 1, whitePoint: 250),
  ]

  /// 240 lies on Uchimura's shoulder. With contrast a = 1 its linear middle is the identity, so mid
  /// greys are not a valid test for it.
  @Test("every operator changes a light grey picture at its default setting")
  func changesLightGrey() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 240, green: 240, blue: 240)
    for filter in Self.filters {
      let output = try await filter.apply(to: picture)
      #expect(output.pixels != picture.pixels)
    }
  }

  @Test("black stays black for every operator")
  func blackStaysBlack() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 0, green: 0, blue: 0)
    for filter in Self.filters {
      let output = try await filter.apply(to: picture)
      #expect(output.pixels.prefix(3).allSatisfy { $0 == 0 })
    }
  }

  @Test("ACES output rises with the input along a ramp")
  func acesIsMonotonic() async throws {
    var pixels: [UInt8] = []
    for value in stride(from: 0, through: 255, by: 17) {
      pixels += [UInt8(value), UInt8(value), UInt8(value), 255]
    }
    let ramp = RasterImage(width: pixels.count / 4, height: 1, pixels: pixels)
    let output = try await AcesFilmicFilter(exposure: 0).apply(to: ramp)
    let greens = stride(from: 1, to: output.pixels.count, by: 4).map { output.pixels[$0] }
    #expect(zip(greens, greens.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test("the lowest and highest settings keep the size on 1x1 and 5x3 pictures")
  func extremes() async throws {
    let pictures = [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    let filters: [any Filter] = [
      AcesFilmicFilter(exposure: -4), AcesFilmicFilter(exposure: 4),
      HableFilmicFilter(exposure: -4), HableFilmicFilter(exposure: 4),
      HejlBurgessFilter(exposure: 0), HejlBurgessFilter(exposure: 4),
      LogarithmicFilter(exposure: 0), LogarithmicFilter(exposure: 4),
      UchimuraFilter(scale: 0), UchimuraFilter(scale: 2),
      DragoFilter(scale: 0, whitePoint: 0), DragoFilter(scale: 2, whitePoint: 500),
    ]
    for filter in filters {
      for picture in pictures {
        let output = try await filter.apply(to: picture)
        #expect(output.width == picture.width)
        #expect(output.height == picture.height)
      }
    }
  }
}
