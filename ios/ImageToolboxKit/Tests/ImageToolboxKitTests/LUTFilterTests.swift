import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Colour lookup tables: 512 × 512 lookup and .cube")
struct LUTFilterTests {

  @Test("an identity table changes nothing, at any strength")
  func identityIsNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let table = try #require(identityTable(size: 5))
    for intensity in [0.0, 0.5, 1.0] {
      let output = try await LUT512x512Filter(table: table, intensity: intensity).apply(to: picture)
      #expect(maxChannelDifference(output.pixels, picture.pixels) <= 1)
    }
  }

  @Test("a full-strength inverted table inverts the colours")
  func invertedTableInverts() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 10, green: 200, blue: 0)
    let table = try #require(invertedTable(size: 5))
    let output = try await CubeLutFilter(table: table, intensity: 1).apply(to: picture)
    let expected: [UInt8] = [245, 55, 255, 255]
    #expect(maxChannelDifference(Array(output.pixels[0..<4]), expected) <= 1)
  }

  @Test("zero strength leaves the inverted table without effect")
  func zeroStrengthIsNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let table = try #require(invertedTable(size: 5))
    let output = try await LUT512x512Filter(table: table, intensity: 0).apply(to: picture)
    #expect(maxChannelDifference(output.pixels, picture.pixels) <= 1)
  }

  @Test("half strength moves black halfway to white by the formula (0 + 1) / 2")
  func halfStrengthMixesLinearly() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 0, green: 0, blue: 0)
    let table = try #require(invertedTable(size: 5))
    let output = try await LUT512x512Filter(table: table, intensity: 0.5).apply(to: picture)
    // 0.5 * 255 = 127.5, so 127 or 128 after rounding.
    #expect((126...129).contains(Int(output.pixels[0])))
  }

  @Test("extreme strengths keep the size of 1x1 and 5x3 pictures")
  func extremesKeepSize() async throws {
    let table = try #require(invertedTable(size: 5))
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      for intensity in [0.0, 1.0] {
        let lut = try await LUT512x512Filter(table: table, intensity: intensity).apply(to: picture)
        let cube = try await CubeLutFilter(table: table, intensity: intensity).apply(to: picture)
        #expect(lut.width == picture.width && lut.height == picture.height)
        #expect(cube.width == picture.width && cube.height == picture.height)
      }
    }
  }

  @Test("a 512 × 512 lookup image with the identity layout gives the identity table")
  func lookupLayoutIsIdentity() throws {
    let image = identityLookupImage()
    let table = try #require(LUTTable(lookup: image))
    #expect(table.size == 64)
    let expected = try #require(identityTable(size: 64))
    #expect(zip(table.values, expected.values).allSatisfy { abs($0 - $1) < 0.01 })
  }

  @Test("a lookup image that is not 512 × 512 is rejected")
  func lookupRejectsOtherSizes() {
    let picture = FilterTestImages.gradient(width: 64, height: 64)
    #expect(LUTTable(lookup: picture) == nil)
  }

  @Test("a .cube text with identity entries parses to the same table")
  func cubeTextParses() throws {
    let text = """
      # identity
      TITLE "identity"
      LUT_3D_SIZE 2
      DOMAIN_MIN 0.0 0.0 0.0
      DOMAIN_MAX 1.0 1.0 1.0
      0 0 0
      1 0 0
      0 1 0
      1 1 0
      0 0 1
      1 0 1
      0 1 1
      1 1 1
      """
    let table = try #require(LUTTable(cubeText: text))
    #expect(table.size == 2)
    #expect(
      table.values == [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1])
  }

  @Test("a .cube text with too few entries or another domain is rejected")
  func cubeTextRejectsBadInput() {
    #expect(LUTTable(cubeText: "LUT_3D_SIZE 2\n0 0 0\n1 1 1") == nil)
    #expect(
      LUTTable(
        cubeText: "LUT_3D_SIZE 2\nDOMAIN_MAX 2 2 2\n" + String(repeating: "0 0 0\n", count: 8))
        == nil)
  }
}

/// Identity table `size` × `size` × `size`: each channel equals its grid index divided by `size - 1`.
private func identityTable(size: Int) -> LUTTable? {
  var values: [Float] = []
  for blue in 0..<size {
    for green in 0..<size {
      for red in 0..<size {
        values += [Float(red), Float(green), Float(blue)].map { $0 / Float(size - 1) }
      }
    }
  }
  return LUTTable(size: size, values: values)
}

/// The identity table with every channel turned around: `1 - identity`.
private func invertedTable(size: Int) -> LUTTable? {
  guard let identity = identityTable(size: size) else { return nil }
  return LUTTable(size: size, values: identity.values.map { 1 - $0 })
}

/// A 512 × 512 lookup image whose pixels encode the identity table in the 8 × 8 tile layout.
private func identityLookupImage() -> RasterImage {
  var pixels = [UInt8](repeating: 0, count: 512 * 512 * 4)
  for y in 0..<512 {
    for x in 0..<512 {
      let blue = (y / 64) * 8 + x / 64
      let red = x % 64
      let green = y % 64
      let index = (y * 512 + x) * 4
      pixels[index] = UInt8(red * 255 / 63)
      pixels[index + 1] = UInt8(green * 255 / 63)
      pixels[index + 2] = UInt8(blue * 255 / 63)
      pixels[index + 3] = 255
    }
  }
  return RasterImage(width: 512, height: 512, pixels: pixels)
}

/// Largest difference over the colour channels (alpha skipped) between two pixel buffers.
private func maxChannelDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
  var worst = 0
  for index in stride(from: 0, to: min(lhs.count, rhs.count), by: 4) {
    for channel in 0..<3 {
      worst = max(worst, abs(Int(lhs[index + channel]) - Int(rhs[index + channel])))
    }
  }
  return worst
}
