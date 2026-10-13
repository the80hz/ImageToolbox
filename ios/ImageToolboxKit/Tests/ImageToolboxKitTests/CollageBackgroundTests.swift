import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage backgrounds")
struct CollageBackgroundTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)

  /// Draws `background` on a canvas and reads the pixels back, row 0 at the top.
  private static func raster(_ background: CollageBackground, width: Int, height: Int) throws
    -> RasterImage
  {
    let context = try #require(ImageGeometry.makeContext(width: width, height: height))
    background.draw(in: context, width: width, height: height)
    let image = try #require(context.makeImage())
    return try #require(RasterImage(image))
  }

  private static func isClose(_ actual: UInt8, _ expected: Int, tolerance: Int = 6) -> Bool {
    abs(Int(actual) - expected) <= tolerance
  }

  @Test("a solid background fills every pixel")
  func solid() throws {
    let raster = try Self.raster(.solid(Self.red), width: 8, height: 6)
    for (x, y) in [(0, 0), (7, 0), (0, 5), (7, 5), (3, 3)] {
      #expect(raster.pixel(x: x, y: y) == Self.red)
    }
  }

  @Test("a solid background keeps its alpha")
  func solidAlpha() throws {
    let raster = try Self.raster(
      .solid(RGBA(red: 0, green: 0, blue: 0, alpha: 0)), width: 4, height: 4)
    #expect(raster.pixel(x: 2, y: 2).alpha == 0)
    let half = try Self.raster(
      .solid(RGBA(red: 255, green: 255, blue: 255, alpha: 128)), width: 4, height: 4)
    #expect(half.pixel(x: 2, y: 2).alpha == 128)
  }

  @Test("transparency is reported for solid colours and every gradient stop")
  func transparency() {
    #expect(!CollageBackground.white.hasTransparency)
    #expect(CollageBackground.solid(RGBA(red: 1, green: 2, blue: 3, alpha: 200)).hasTransparency)
    #expect(
      !CollageBackground.linearGradient(from: Self.red, to: Self.blue, angle: 0).hasTransparency)
    let faded = RGBA(red: 0, green: 0, blue: 255, alpha: 0)
    #expect(CollageBackground.linearGradient(from: Self.red, to: faded, angle: 0).hasTransparency)
    #expect(CollageBackground.radialGradient(from: faded, to: Self.red).hasTransparency)
  }

  @Test("a gradient at 0 degrees runs from left to right")
  func gradientLeftToRight() throws {
    let raster = try Self.raster(
      .linearGradient(from: Self.red, to: Self.blue, angle: 0), width: 101, height: 20)
    #expect(Self.isClose(raster.pixel(x: 0, y: 10).red, 255))
    #expect(Self.isClose(raster.pixel(x: 100, y: 10).blue, 255))
    #expect(Self.isClose(raster.pixel(x: 50, y: 10).red, 128, tolerance: 8))
    #expect(Self.isClose(raster.pixel(x: 50, y: 10).blue, 128, tolerance: 8))
    // Every row is the same.
    #expect(raster.pixel(x: 30, y: 0) == raster.pixel(x: 30, y: 19))
  }

  @Test("a gradient at 90 degrees runs from top to bottom")
  func gradientTopToBottom() throws {
    let raster = try Self.raster(
      .linearGradient(from: Self.red, to: Self.blue, angle: 90), width: 20, height: 101)
    #expect(Self.isClose(raster.pixel(x: 10, y: 0).red, 255))
    #expect(Self.isClose(raster.pixel(x: 10, y: 100).blue, 255))
    #expect(raster.pixel(x: 0, y: 40) == raster.pixel(x: 19, y: 40))
  }

  @Test("a gradient at 45 degrees runs from the top left corner to the bottom right corner")
  func gradientDiagonal() throws {
    let raster = try Self.raster(
      .linearGradient(from: Self.red, to: Self.blue, angle: 45), width: 100, height: 100)
    #expect(Self.isClose(raster.pixel(x: 0, y: 0).red, 255, tolerance: 8))
    #expect(Self.isClose(raster.pixel(x: 99, y: 99).blue, 255, tolerance: 8))
    // The other diagonal is at the middle of the gradient.
    #expect(Self.isClose(raster.pixel(x: 99, y: 0).red, 128, tolerance: 10))
    #expect(Self.isClose(raster.pixel(x: 0, y: 99).red, 128, tolerance: 10))
  }

  @Test("the gradient line passes through the centre and spans the canvas along the angle")
  func gradientLine() {
    let flat = CollageBackground.linearLine(angle: 0, width: 200, height: 100)
    #expect(flat.start == CGPoint(x: 0, y: 50) && flat.end == CGPoint(x: 200, y: 50))
    let down = CollageBackground.linearLine(angle: 90, width: 200, height: 100)
    #expect(abs(down.start.x - 100) < 1e-9 && abs(down.start.y) < 1e-9)
    #expect(abs(down.end.x - 100) < 1e-9 && abs(down.end.y - 100) < 1e-9)
    let diagonal = CollageBackground.linearLine(angle: 45, width: 100, height: 100)
    #expect(abs(diagonal.start.x) < 1e-9 && abs(diagonal.start.y) < 1e-9)
    #expect(abs(diagonal.end.x - 100) < 1e-9 && abs(diagonal.end.y - 100) < 1e-9)
    let broken = CollageBackground.linearLine(angle: .nan, width: 200, height: 100)
    #expect(broken.start == flat.start && broken.end == flat.end)
  }

  @Test("stops out of order are sorted and a middle stop shows up in the middle")
  func gradientStops() throws {
    let green = RGBA(red: 0, green: 255, blue: 0)
    let stops = [
      GradientStop(color: Self.blue, location: 1),
      GradientStop(color: green, location: 0.5),
      GradientStop(color: Self.red, location: 0),
    ]
    let raster = try Self.raster(.linearGradient(stops: stops, angle: 0), width: 101, height: 4)
    #expect(Self.isClose(raster.pixel(x: 0, y: 2).red, 255))
    #expect(Self.isClose(raster.pixel(x: 50, y: 2).green, 255, tolerance: 8))
    #expect(Self.isClose(raster.pixel(x: 100, y: 2).blue, 255))
  }

  @Test("a radial gradient starts in the centre and ends at the corners")
  func radial() throws {
    let raster = try Self.raster(
      .radialGradient(from: Self.red, to: Self.blue), width: 101, height: 101)
    #expect(Self.isClose(raster.pixel(x: 50, y: 50).red, 255, tolerance: 8))
    #expect(Self.isClose(raster.pixel(x: 0, y: 0).blue, 255, tolerance: 8))
    #expect(Self.isClose(raster.pixel(x: 100, y: 100).blue, 255, tolerance: 8))
  }

  @Test("a gradient with one stop is that colour, and with none draws nothing")
  func degenerateGradients() throws {
    let one = try Self.raster(
      .linearGradient(stops: [GradientStop(color: Self.red, location: 0.3)], angle: 0),
      width: 6, height: 6)
    #expect(one.pixel(x: 3, y: 3) == Self.red)
    let none = try Self.raster(.radialGradient(stops: []), width: 6, height: 6)
    #expect(none.pixel(x: 3, y: 3).alpha == 0)
  }
}
