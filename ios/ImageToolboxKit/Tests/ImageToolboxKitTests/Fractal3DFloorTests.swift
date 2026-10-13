import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Fractal floor: the checkerboard under the ray-marched kinds")
struct Fractal3DFloorTests {

  private static let floor = Fractal3DFloor(
    primary: RGBA(red: 255, green: 255, blue: 255), secondary: RGBA(red: 0, green: 0, blue: 0))

  private static let down = FractalVector(0, -1, 0)

  /// The lit pixels of an opaque picture: those with a channel that is not zero.
  private static func litPixels(_ image: RasterImage) -> Int {
    stride(from: 0, to: image.pixels.count, by: 4).filter {
      image.pixels[$0] | image.pixels[$0 + 1] | image.pixels[$0 + 2] != 0
    }.count
  }

  @Test("a ray going straight down from y = 2 meets the plane y = -1.6 after 3.6")
  func hitDistance() throws {
    let distance = try #require(
      Self.floor.hit(eye: FractalVector(0, 2, 0), direction: Self.down, maxTravel: 10))
    #expect(abs(distance - 3.6) < 1e-12)
  }

  @Test(
    "no hit when the eye is at or below the plane, when the ray goes up or level, or past the range"
  )
  func noHit() {
    #expect(
      Self.floor.hit(eye: FractalVector(0, -2, 0), direction: Self.down, maxTravel: 10) == nil)
    #expect(
      Self.floor.hit(eye: FractalVector(0, 2, 0), direction: FractalVector(0, 1, 0), maxTravel: 10)
        == nil)
    #expect(
      Self.floor.hit(eye: FractalVector(0, 2, 0), direction: FractalVector(1, 0, 0), maxTravel: 10)
        == nil)
    // The plane is 3.6 away, beyond a range of 3.
    #expect(Self.floor.hit(eye: FractalVector(0, 2, 0), direction: Self.down, maxTravel: 3) == nil)
  }

  @Test("tiles alternate in x and z, and each is shaded by the light and its highlight")
  func tileColours() {
    // The cells are the sums of the floors of 1.25 x and 1.25 z. (0.1, 0.1) has cell sum 0, which is
    // the secondary tile, and (0.9, 0.1) has 1, which is the primary tile.
    let light = Fractal3D.light
    let halfway = (light - Self.down).normalized
    let lit = 0.2 + 0.7 * max(light.y, 0)
    let shine = 0.35 * pow(max(halfway.y, 0), 36)
    let white = UInt8((min(lit + shine, 1) * 255).rounded())
    let black = UInt8((min(shine, 1) * 255).rounded())
    let secondary = Self.floor.colour(
      at: FractalVector(0.1, -1.6, 0.1), direction: Self.down, travel: 0, maxTravel: 10)
    let primary = Self.floor.colour(
      at: FractalVector(0.9, -1.6, 0.1), direction: Self.down, travel: 0, maxTravel: 10)
    #expect(secondary == (black, black, black))
    #expect(primary == (white, white, white))
  }

  @Test("the floor fades to black with travel, and at the range it keeps 12 per cent")
  func fog() {
    let near = Self.floor.colour(
      at: FractalVector(0.9, -1.6, 0.1), direction: Self.down, travel: 0, maxTravel: 10)
    let far = Self.floor.colour(
      at: FractalVector(0.9, -1.6, 0.1), direction: Self.down, travel: 10, maxTravel: 10)
    #expect(far.0 < near.0)
    // The fog is at most 0.88, so the channel keeps at least 0.12 of its value, and at most 0.12 of 255.
    #expect(far.0 <= 31)
  }

  @Test("the settings keep the floor off by default, with white and black tiles")
  func defaults() {
    let settings = EscapeTimeFractal.Settings(kind: .mandelbulb)
    #expect(!settings.showFloor)
    #expect(settings.floorPrimary == RGBA(red: 255, green: 255, blue: 255))
    #expect(settings.floorSecondary == RGBA(red: 0, green: 0, blue: 0))
  }

  @Test("a floor under the Mandelbulb lights pixels that the shape alone leaves black")
  func floorAddsPixels() throws {
    let plain = EscapeTimeFractal.Settings(kind: .mandelbulb, maxIterations: 96)
    var floored = plain
    floored.showFloor = true
    let without = try #require(EscapeTimeFractal.render(plain, width: 48, height: 48))
    let with = try #require(EscapeTimeFractal.render(floored, width: 48, height: 48))
    #expect(Self.litPixels(with) > Self.litPixels(without))
  }

  @Test("the floor is ignored by the kinds that are not ray-marched")
  func floorIgnoredInTwoDimensions() throws {
    let plain = EscapeTimeFractal.Settings(kind: .mandelbrot, maxIterations: 32)
    var floored = plain
    floored.showFloor = true
    let without = try #require(EscapeTimeFractal.render(plain, width: 16, height: 16))
    let with = try #require(EscapeTimeFractal.render(floored, width: 16, height: 16))
    #expect(without.pixels == with.pixels)
  }
}
