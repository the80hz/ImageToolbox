import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Classic texture presets")
struct ClassicPresetTests {
  private static let classicPresets: [TexturePreset] = TexturePresets.all.filter {
    if case .classic = $0.source { return true }
    return false
  }

  /// Presets whose picture reads the seed. The other presets draw from the fixed Perlin table of
  /// the native code (`ClassicNative.tableSeed`), so their picture does not change with the seed.
  private static let seedDependent: Set<String> = [
    "OrganicFibers", "GmicReactionDiffusion", "Truchet",
  ]

  /// Presets that the Swift port does not match exactly (see `TexturePreset.isApproximation`).
  private static let approximate: Set<String> = [
    "OrganicFibers", "GmicReactionDiffusion", "Truchet",
  ]

  private func render(
    _ preset: TexturePreset,
    seed: UInt64,
    width: Int = 64,
    height: Int = 64
  ) -> RasterImage? {
    TexturePresetRenderer.render(preset, seed: seed, width: width, height: height)
  }

  @Test("the classic group keeps the twelve Android presets in order")
  func order() {
    #expect(
      Self.classicPresets.map(\.id) == [
        "BrushedMetal", "OrganicFibers", "GmicReactionDiffusion", "Truchet", "Caustics",
        "Cellular", "Check", "FBM", "Marble", "Plasma", "Quilt", "Wood",
      ])
  }

  @Test("every classic preset renders a 64 by 64 picture, opaque but for the native blend")
  func rendersAt64() {
    for preset in Self.classicPresets {
      guard let image = render(preset, seed: 1337) else {
        Issue.record("\(preset.id) did not render")
        continue
      }
      #expect(image.width == 64)
      #expect(image.height == 64)
      #expect(image.pixels.count == 64 * 64 * 4)
      var alphaValues = Set<UInt8>()
      for index in stride(from: 3, to: image.pixels.count, by: 4) {
        alphaValues.insert(image.pixels[index])
      }
      // Caustics mixes its ridges in float and truncates, so a few pixels land on 254.
      #expect(alphaValues.isSubset(of: [254, 255]), "\(preset.id) has transparent pixels")
      #expect(alphaValues.contains(255), "\(preset.id) has no opaque pixels")
    }
  }

  @Test("every classic preset is deterministic for its seed")
  func deterministic() {
    for preset in Self.classicPresets {
      let first = render(preset, seed: 42)?.pixels
      let second = render(preset, seed: 42)?.pixels
      #expect(first != nil, "\(preset.id) did not render")
      #expect(first == second, "\(preset.id) is not deterministic")
    }
  }

  @Test("pictures are not flat, and every channel stays a byte")
  func detail() {
    for preset in Self.classicPresets {
      guard let image = render(preset, seed: 5) else {
        Issue.record("\(preset.id) did not render")
        continue
      }
      var colours = Set<UInt32>()
      for index in stride(from: 0, to: image.pixels.count, by: 4) {
        let packed =
          UInt32(image.pixels[index]) << 16 | UInt32(image.pixels[index + 1]) << 8
          | UInt32(image.pixels[index + 2])
        colours.insert(packed)
      }
      // Check is a two-colour checkerboard, so it is the one preset with few colours.
      let minimum = preset.id == "Check" ? 2 : 8
      #expect(colours.count >= minimum, "\(preset.id) has only \(colours.count) colours")
    }
  }

  @Test("only the seed-dependent presets change with the seed")
  func seedDependence() {
    for preset in Self.classicPresets {
      let first = render(preset, seed: 1)?.pixels
      let second = render(preset, seed: 2)?.pixels
      if Self.seedDependent.contains(preset.id) {
        #expect(first != second, "\(preset.id) ignores the seed")
      } else {
        #expect(first == second, "\(preset.id) depends on the seed")
      }
    }
  }

  @Test("tiny pictures render with the right size and without hanging")
  func tinySizes() {
    for preset in Self.classicPresets {
      for (width, height) in [(1, 1), (1, 9), (2, 2), (5, 1)] {
        let image = render(preset, seed: 3, width: width, height: height)
        #expect(image?.pixels.count == width * height * 4, "\(preset.id) at \(width)x\(height)")
      }
    }
  }

  @Test("exactly the presets that differ from the Android app are approximations")
  func approximationFlags() {
    for preset in Self.classicPresets {
      #expect(
        preset.isApproximation == Self.approximate.contains(preset.id),
        "\(preset.id) has the wrong approximation flag")
    }
  }

  @Test("ClassicRandom draws the numbers of java.util.Random")
  func javaRandom() {
    var zero = ClassicRandom(seed: 0)
    #expect(zero.nextInt() == -1_155_484_576)
    var answer = ClassicRandom(seed: 42)
    #expect(answer.nextInt() == -1_170_105_035)
    // The first 24 bits of the first draw for seed 0 are the top 24 bits of -1155484576.
    var seeded = ClassicRandom(seed: 0)
    #expect(seeded.nextFloat() == Float(12_263_604) / 16_777_216)
  }

  @Test("the int casts and lerp follow Java")
  func javaArithmetic() {
    #expect(ClassicMath.toInt(Float(-2.7)) == -2)
    #expect(ClassicMath.toInt(Float.nan) == 0)
    #expect(ClassicMath.toInt(Float(1e20)) == Int(Int32.max))
    #expect(ClassicMath.lerp(0.5, 0, 255) == 127)
    #expect(ClassicMath.mixColours(0, 0xff00_0000, 0xffff_ffff) == 0xff00_0000)
    #expect(ClassicMath.mixColours(1, 0xff00_0000, 0xffff_ffff) == 0xffff_ffff)
  }

  @Test("gradient noise is zero on the lattice and stays bounded")
  func noiseShape() {
    let noise = ClassicNoise(seed: 5)
    #expect(noise.noise2(3, 7) == 0)
    #expect(noise.noise3(2, 4, 6) == 0)
    for index in 0..<200 {
      let x = Float(index) * 0.37 - 20
      let y = Float(index) * 0.61 - 9
      #expect(abs(noise.noise2(x, y)) <= 2.2)
      #expect(abs(noise.noise3(x, y, x - y)) <= 2.2)
    }
  }

  @Test("a rotation by zero leaves the coordinates alone")
  func identityRotation() {
    let rotation = ClassicRotation(angle: 0)
    let moved = rotation.apply(3, 4)
    #expect(moved.x == 3)
    #expect(moved.y == 4)
  }
}
