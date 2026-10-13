import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Colour-blindness simulation filters")
struct ColourMatrixFilterTests {

  /// Все восемь фильтров группы с их именами для сообщений тестов.
  private static let allFilters: [(name: String, filter: any Filter)] = [
    ("ProtanopiaFilter", ProtanopiaFilter()),
    ("DeuteranopiaFilter", DeuteranopiaFilter()),
    ("TritanopiaFilter", TritanopiaFilter()),
    ("AchromatopsiaFilter", AchromatopsiaFilter()),
    ("ProtonomalyFilter", ProtonomalyFilter()),
    ("DeutaromalyFilter", DeutaromalyFilter()),
    ("TritonomalyFilter", TritonomalyFilter()),
    ("AchromatomalyFilter", AchromatomalyFilter()),
  ]

  @Test("every filter changes a colourful picture")
  func changesColours() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    for (name, filter) in Self.allFilters {
      let output = try await filter.apply(to: picture)
      #expect(output.pixels != picture.pixels, "\(name) did not change the picture")
    }
  }

  @Test("every filter keeps the size on a 1x1 and a 5x3 picture")
  func keepsSize() async throws {
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for (name, filter) in Self.allFilters {
        let output = try await filter.apply(to: picture)
        #expect(output.width == width, "\(name) changed the width")
        #expect(output.height == height, "\(name) changed the height")
        #expect(output.pixels.count == width * height * 4, "\(name) changed the buffer size")
      }
    }
  }

  @Test("grey stays grey under every matrix, because each matrix row sums to 1")
  func greyStaysGrey() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 100, green: 100, blue: 100)
    for (name, filter) in Self.allFilters {
      let output = try await filter.apply(to: picture)
      for channel in 0..<3 {
        #expect(
          abs(Int(output.pixels[channel]) - 100) <= 1,
          "\(name) moved grey channel \(channel) to \(output.pixels[channel])")
      }
      #expect(output.pixels[3] == 255, "\(name) changed alpha")
    }
  }

  @Test("achromatopsia makes every pixel a single grey level")
  func achromatopsiaRemovesColour() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 10, green: 200, blue: 0)
    let output = try await AchromatopsiaFilter().apply(to: picture)
    #expect(output.pixels[0] == output.pixels[1])
    #expect(output.pixels[1] == output.pixels[2])
    #expect(output.pixels[0] > 0)
  }
}
