import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Procedural textures")
struct TextureTests {

  static let red = SIMD3<Double>(1, 0, 0)
  static let blue = SIMD3<Double>(0, 0, 1)

  private func render(
    _ kind: TextureKind,
    seed: UInt64 = 1,
    scale: Double = 12,
    octaves: Int = 4,
    angle: Double = 0,
    width: Int = 48,
    height: Int = 32,
    colourA: SIMD3<Double> = TextureTests.red,
    colourB: SIMD3<Double> = TextureTests.blue
  ) -> RasterImage? {
    ProceduralTexture.render(
      TextureSettings(
        kind: kind, seed: seed, scale: scale, octaves: octaves,
        colourA: colourA, colourB: colourB, angle: angle),
      width: width,
      height: height
    )
  }

  @Test("same seed gives the same picture for every kind")
  func sameSeedRepeats() {
    for kind in TextureKind.allCases {
      let first = render(kind, seed: 9)
      let second = render(kind, seed: 9)
      #expect(first != nil)
      #expect(first?.pixels == second?.pixels, "\(kind) is not deterministic")
    }
  }

  @Test("another seed changes every kind that uses randomness")
  func differentSeedDiffers() {
    for kind in [TextureKind.noise, .turbulence, .marble, .wood, .voronoi] {
      #expect(render(kind, seed: 1)?.pixels != render(kind, seed: 2)?.pixels, "\(kind)")
    }
  }

  @Test("every pixel is opaque and lies between the two colours")
  func valuesStayInRange() throws {
    let colourA = SIMD3<Double>(0.2, 0.4, 0.6)
    let colourB = SIMD3<Double>(0.8, 0.5, 0.1)
    let lower = pointwiseMin(colourA, colourB) * 255 - 1
    let upper = pointwiseMax(colourA, colourB) * 255 + 1

    for kind in TextureKind.allCases {
      let image = try #require(
        render(kind, width: 40, height: 30, colourA: colourA, colourB: colourB))
      var outside = 0
      for index in stride(from: 0, to: image.pixels.count, by: 4) {
        if image.pixels[index + 3] != 255 { outside += 1 }
        for channel in 0..<3 {
          let value = Double(image.pixels[index + channel])
          if value < lower[channel] || value > upper[channel] { outside += 1 }
        }
      }
      #expect(outside == 0, "\(kind) left the colour range")
    }
  }

  @Test("output size matches the request, and an empty size gives nil")
  func outputSize() throws {
    for kind in TextureKind.allCases {
      let image = try #require(render(kind, width: 37, height: 23))
      #expect(image.width == 37)
      #expect(image.height == 23)
      #expect(image.pixels.count == 37 * 23 * 4)
    }
    #expect(render(.noise, width: 0, height: 5) == nil)
    #expect(render(.noise, width: 5, height: -1) == nil)
  }

  @Test("checkerboard has two colours in a chequer pattern")
  func checkerboardPattern() throws {
    let width = 64
    let height = 48
    let cell = 8
    let image = try #require(
      render(.checkerboard, scale: Double(cell), width: width, height: height))

    var colours = Set<RGBA>()
    for y in 0..<height {
      for x in 0..<width {
        colours.insert(image.pixel(x: x, y: y))
      }
    }
    #expect(colours == [RGBA(red: 255, green: 0, blue: 0), RGBA(red: 0, green: 0, blue: 255)])

    // Neighbouring cells differ, and cells two steps apart match in both directions.
    var mismatches = 0
    for y in 0..<(height - cell) {
      for x in 0..<(width - cell) {
        if image.pixel(x: x, y: y) == image.pixel(x: x + cell, y: y) { mismatches += 1 }
        if image.pixel(x: x, y: y) != image.pixel(x: x + cell, y: y + cell) { mismatches += 1 }
      }
    }
    #expect(mismatches == 0)
  }

  @Test("stripes at zero angle do not change down a column")
  func stripesAtZeroAngle() throws {
    let width = 50
    let height = 40
    let image = try #require(render(.stripes, scale: 10, angle: 0, width: width, height: height))

    var changedDownColumns = 0
    for x in 0..<width {
      for y in 1..<height where image.pixel(x: x, y: y) != image.pixel(x: x, y: 0) {
        changedDownColumns += 1
      }
    }
    #expect(changedDownColumns == 0)

    let firstRow = Set((0..<width).map { image.pixel(x: $0, y: 0) })
    #expect(firstRow.count > 1, "stripes should vary across the row")
  }

  @Test("one octave differs from four octaves on the same seed")
  func octavesChangeNoise() {
    let one = render(.noise, seed: 5, octaves: 1)
    let four = render(.noise, seed: 5, octaves: 4)
    #expect(one?.pixels != four?.pixels)
    #expect(
      render(.turbulence, seed: 5, octaves: 1)?.pixels
        != render(.turbulence, seed: 5, octaves: 4)?.pixels)
  }

  @Test("dots put colour B at each cell centre and colour A between dots")
  func dotsLayout() throws {
    let scale = 16
    let image = try #require(render(.dots, scale: Double(scale), width: 32, height: 32))
    // Cell centres fall between pixels 23 and 24 of a 32-pixel image, so pixel 23 is inside a dot.
    #expect(image.pixel(x: 23, y: 23) == RGBA(red: 0, green: 0, blue: 255))
    #expect(image.pixel(x: 0, y: 0) == RGBA(red: 255, green: 0, blue: 0))

    var mismatches = 0
    for y in 0..<(32 - scale) {
      for x in 0..<(32 - scale)
      where image.pixel(x: x, y: y) != image.pixel(x: x + scale, y: y + scale) {
        mismatches += 1
      }
    }
    #expect(mismatches == 0)
  }

  @Test("voronoi gives each cell its own colour")
  func voronoiPalette() throws {
    let image = try #require(render(.voronoi, scale: 16, width: 64, height: 64))
    let colours = Set((0..<64).flatMap { y in (0..<64).map { image.pixel(x: $0, y: y) } })
    #expect(colours.count >= 3)
  }

  @Test("normalized() clamps every value into its range")
  func normalizedClamps() {
    let raw = TextureSettings(
      kind: .dots, seed: 3, scale: 0, octaves: 20,
      colourA: SIMD3<Double>(2, -1, 0.5),
      colourB: SIMD3<Double>(.nan, 0.25, 1.5),
      angle: .infinity)
    let clean = raw.normalized()
    #expect(clean.scale == 1)
    #expect(clean.octaves == 8)
    #expect(clean.colourA == SIMD3<Double>(1, 0, 0.5))
    #expect(clean.colourB == SIMD3<Double>(0, 0.25, 1))
    #expect(clean.angle == 0)
    #expect(TextureSettings(octaves: 0).normalized().octaves == 1)
    #expect(TextureSettings(scale: 1e9).normalized().scale == 4096)
  }
}
