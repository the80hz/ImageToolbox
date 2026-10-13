import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Marble and Wood textures")
struct ClassicMarbleWoodTests {
  private func catalogue(_ id: String) throws -> TexturePreset {
    try #require(TexturePresets.preset(id: id))
  }

  /// A Marble or Wood preset with the given parameters, on the scale of the catalogue.
  private func custom(
    _ kind: ClassicKind,
    scale: Double = 32,
    _ parameters: [(String, Double)]
  ) -> TexturePreset {
    TexturePreset(
      id: "Custom\(kind)", category: .abstract, source: .classic(kind), scale: scale,
      colours: [],
      parameters: parameters.map { TextureParameter($0.0, $0.1) })
  }

  private func render(
    _ preset: TexturePreset,
    seed: UInt64 = 1,
    width: Int = 64,
    height: Int = 64
  ) -> RasterImage? {
    TexturePresetRenderer.render(preset, seed: seed, width: width, height: height)
  }

  /// The pixel at `(x, y)` as 0xAARRGGBB.
  private func argb(_ image: RasterImage, _ x: Int, _ y: Int) -> UInt32 {
    let index = (y * image.width + x) * 4
    return UInt32(image.pixels[index + 3]) << 24 | UInt32(image.pixels[index]) << 16
      | UInt32(image.pixels[index + 1]) << 8 | UInt32(image.pixels[index + 2])
  }

  @Test("the catalogue holds Marble and Wood with the Android defaults")
  func catalogueEntries() throws {
    let marble = try catalogue("Marble")
    #expect(marble.source == .classic(.marble))
    #expect(marble.scale == 32)
    #expect(marble.value("turbulenceFactor") == 0.4)
    let wood = try catalogue("Wood")
    #expect(wood.source == .classic(.wood))
    #expect(wood.scale == 32)
    #expect(wood.value("rings") == 2)
    #expect(!marble.isApproximation)
    #expect(!wood.isApproximation)
  }

  @Test("the same seed gives the same picture")
  func deterministic() throws {
    for id in ["Marble", "Wood"] {
      let preset = try catalogue(id)
      let first = render(preset, seed: 42)?.pixels
      #expect(first != nil, "\(id) did not render")
      #expect(first == render(preset, seed: 42)?.pixels, "\(id) is not deterministic")
    }
  }

  @Test("the seed does not change the picture, as in the native code")
  func seedIndependent() throws {
    for id in ["Marble", "Wood"] {
      let preset = try catalogue(id)
      #expect(render(preset, seed: 1)?.pixels == render(preset, seed: 2)?.pixels, "\(id)")
    }
  }

  @Test("a 64 by 64 picture is opaque and has detail")
  func sixtyFourByFour() throws {
    for id in ["Marble", "Wood"] {
      let image = try #require(render(try catalogue(id)))
      #expect(image.width == 64)
      #expect(image.height == 64)
      #expect(image.pixels.count == 64 * 64 * 4)
      var alphas = Set<UInt8>()
      var colours = Set<UInt32>()
      for y in 0..<64 {
        for x in 0..<64 {
          alphas.insert(image.pixels[(y * 64 + x) * 4 + 3])
          colours.insert(argb(image, x, y))
        }
      }
      #expect(alphas == [255], "\(id) has transparent pixels")
      #expect(colours.count > 8, "\(id) has only \(colours.count) colours")
    }
  }

  @Test("Marble is grey and runs from dark to light")
  func marbleRange() throws {
    let image = try #require(render(try catalogue("Marble")))
    var grey = true
    var lowest = 255
    var highest = 0
    for y in 0..<64 {
      for x in 0..<64 {
        let colour = argb(image, x, y)
        let red = Int((colour >> 16) & 0xff)
        let green = Int((colour >> 8) & 0xff)
        let blue = Int(colour & 0xff)
        grey = grey && red == green && green == blue
        lowest = min(lowest, red)
        highest = max(highest, red)
      }
    }
    #expect(grey, "Marble has a tint")
    #expect(lowest < 64)
    #expect(highest > 192)
  }

  @Test("Wood stays between its two colours")
  func woodRange() throws {
    let image = try #require(render(try catalogue("Wood")))
    var inside = true
    for y in 0..<64 {
      for x in 0..<64 {
        let colour = argb(image, x, y)
        let red = Int((colour >> 16) & 0xff)
        let green = Int((colour >> 8) & 0xff)
        let blue = Int(colour & 0xff)
        // The colour map runs from 0xffe5c494 to 0xff987b51.
        inside =
          inside && (152...229).contains(red) && (123...196).contains(green)
          && (81...148).contains(blue)
      }
    }
    #expect(inside)
  }

  @Test("the triangle wave of the native code")
  func triangleWave() {
    #expect(ClassicMarbleWood.triangle(0) == 0)
    #expect(ClassicMarbleWood.triangle(0.25) == 0.5)
    #expect(ClassicMarbleWood.triangle(0.5) == 1)
    #expect(ClassicMarbleWood.triangle(0.75) == 0.5)
    #expect(ClassicMarbleWood.triangle(1) == 0)
    #expect(ClassicMarbleWood.triangle(-0.25) == 0.5)
    #expect(ClassicMarbleWood.triangle(2.5) == 1)
  }

  @Test("the Perlin noise is zero on whole lattice points, so Marble is black there")
  func marbleLattice() throws {
    let image = try #require(render(try catalogue("Marble")))
    #expect(argb(image, 0, 0) == 0xff00_0000)
    #expect(argb(image, 32, 0) == 0xff00_0000)
    #expect(argb(image, 0, 32) == 0xff00_0000)
  }

  @Test("without turbulence, Marble is a triangle wave of x over the scale")
  func marbleWave() throws {
    let preset = custom(.marble, [("turbulenceFactor", 0)])
    let image = try #require(render(preset, width: 40, height: 10))
    // The coordinate along the grain is x / 32. Halfway up the triangle is 127 of 255.
    #expect(argb(image, 8, 5) == 0xff7f_7f7f)
    #expect(argb(image, 16, 9) == 0xffff_ffff)
    #expect(argb(image, 24, 0) == 0xff7f_7f7f)
    #expect(argb(image, 32, 3) == 0xff00_0000)
  }

  @Test("Wood is the light colour at the origin and on a whole ring")
  func woodLattice() throws {
    let image = try #require(render(try catalogue("Wood")))
    #expect(argb(image, 0, 0) == 0xffe5_c494)
    // The distance from the origin is 1, which is a whole ring: the light colour again.
    #expect(argb(image, 32, 0) == 0xffe5_c494)
  }

  @Test("Wood without rings is the colour of its distance from the origin")
  func woodDistance() throws {
    let preset = custom(.wood, [("rings", 0), ("stretch", 1), ("turbulence", 1)])
    let image = try #require(render(preset, width: 40, height: 40))
    // Distance 0 is the light colour, 0.25 is halfway, and 0.5 is the dark colour.
    #expect(argb(image, 0, 0) == 0xffe5_c494)
    #expect(argb(image, 8, 0) == 0xffbe_9f72)
    #expect(argb(image, 0, 16) == 0xff98_7b51)
  }

  @Test("gain and bias do not change Wood, as in the native code")
  func woodIgnoresGainAndBias() throws {
    let changed = custom(
      .wood,
      [("rings", 2), ("turbulence", 1), ("gain", 0), ("bias", 1), ("stretch", 1), ("angle", 0)])
    #expect(render(try catalogue("Wood"))?.pixels == render(changed)?.pixels)
  }

  /// FNV-1a over the RGB bytes of a picture, row 0 first.
  private func hash(_ image: RasterImage) -> UInt64 {
    var value: UInt64 = 1_469_598_103_934_665_603
    for index in stride(from: 0, to: image.pixels.count, by: 4) {
      for offset in 0..<3 {
        value ^= UInt64(image.pixels[index + offset])
        value = value &* 1_099_511_628_211
      }
    }
    return value
  }

  @Test("the Perlin table and the default pictures match the native code")
  func matchesNativeCode() throws {
    // The values come from a transliteration of the native code of the fork into C, run on the
    // same inputs. The angle is zero, so the sine and cosine are exact on every platform.
    let noise = ClassicNative.table
    #expect(noise.noise3(0.37, 1.91, 0).bitPattern == 1_053_905_924)
    #expect(noise.noise3(-3.2, 7.7, 0).bitPattern == 3_172_647_592)
    #expect(noise.turbulence3(2.3, -1.7, 0, 3).bitPattern == 1_051_300_910)
    let marble = try #require(render(try catalogue("Marble")))
    #expect(hash(marble) == 0xbc71_7d7b_4218_365a)
    let wood = try #require(render(try catalogue("Wood")))
    #expect(hash(wood) == 0x8e72_b88a_6ae6_66af)
  }
}
