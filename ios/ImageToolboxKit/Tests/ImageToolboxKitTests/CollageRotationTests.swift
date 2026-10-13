import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage photo rotation")
struct CollageRotationTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)
  private static let square = CGRect(x: 0, y: 0, width: 100, height: 100)
  private static let wide = CGSize(width: 200, height: 100)

  /// Whether every corner of `box` lies inside the picture as drawn, which is what covering the box means.
  private static func covers(_ drawn: CollagePhotoPlacement.Drawn, _ box: CGRect) -> Bool {
    let cosine = cos(drawn.rotation)
    let sine = sin(drawn.rotation)
    let corners = [
      CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
      CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
    ]
    return corners.allSatisfy { corner in
      let dx = corner.x - drawn.centre.x
      let dy = corner.y - drawn.centre.y
      let u = dx * cosine + dy * sine
      let v = -dx * sine + dy * cosine
      return abs(u) <= drawn.size.width / 2 + 1e-6 && abs(v) <= drawn.size.height / 2 + 1e-6
    }
  }

  private static func raster(_ image: CGImage?) throws -> RasterImage {
    let image = try #require(image)
    return try #require(RasterImage(image))
  }

  @Test(
    "the rotation is kept within half a turn either way, and a value that is not a number is no turn"
  )
  func rotationWraps() {
    #expect(abs(CollagePhotoPlacement(rotation: 3 * .pi / 2).rotation + .pi / 2) < 1e-9)
    #expect(abs(CollagePhotoPlacement(rotation: -3 * .pi / 2).rotation - .pi / 2) < 1e-9)
    #expect(CollagePhotoPlacement(rotation: .nan).rotation == 0)
    #expect(CollagePhotoPlacement(rotation: .pi / 4).rotated(to: 0).rotation == 0)
  }

  @Test("a turned picture still covers its cell, whatever its offset")
  func turnedPictureCovers() {
    for degrees in stride(from: -180.0, through: 180.0, by: 15.0) {
      for offset in [CGVector.zero, CGVector(dx: 1, dy: -1), CGVector(dx: -1, dy: 1)] {
        let placement = CollagePhotoPlacement(
          zoom: 1, offset: offset, rotation: CGFloat(degrees * .pi / 180))
        let drawn = placement.drawn(of: Self.wide, into: Self.square)
        #expect(Self.covers(drawn, Self.square), "turned by \(degrees) degrees")
      }
    }
  }

  @Test("a quarter turn of a wide picture in a square cell keeps its size and centre")
  func quarterTurn() {
    let drawn = CollagePhotoPlacement(rotation: .pi / 2).drawn(of: Self.wide, into: Self.square)
    #expect(drawn.size == CGSize(width: 200, height: 100))
    #expect(abs(drawn.centre.x - 50) < 1e-9 && abs(drawn.centre.y - 50) < 1e-9)
    #expect(abs(drawn.rotation - .pi / 2) < 1e-9)
  }

  @Test("the rectangle around a turned picture is the picture turned, not the picture as it is")
  func drawRectOfTurnedPicture() {
    let rect = CollagePhotoPlacement(rotation: .pi / 2).drawRect(of: Self.wide, into: Self.square)
    #expect(abs(rect.width - 100) < 1e-9)
    #expect(abs(rect.height - 200) < 1e-9)
    #expect(abs(rect.midX - 50) < 1e-9 && abs(rect.midY - 50) < 1e-9)
  }

  @Test("a drag follows the turned picture's own axes")
  func dragFollowsAxes() {
    // Turned a quarter, the width of the picture runs down the screen, so a drag down moves it along its width.
    let zoomed = CollagePhotoPlacement(zoom: 2, rotation: .pi / 2)
    let before = zoomed.drawn(of: Self.wide, into: Self.square)
    let after = zoomed.panned(by: CGVector(dx: 0, dy: 10), picture: Self.wide, into: Self.square)
      .drawn(of: Self.wide, into: Self.square)
    #expect(abs(after.centre.x - before.centre.x) < 1e-6)
    #expect(abs(after.centre.y - before.centre.y - 10) < 1e-6)
    #expect(Self.covers(after, Self.square))
  }

  @Test("a turn of a half picture shows its left half at the top of the cell")
  func composerTurnsThePicture() throws {
    let halves = TestImages.halves(left: Self.red, right: Self.blue, width: 20, height: 20)
    let cell = CGPath(rect: CGRect(x: 0, y: 0, width: 40, height: 40), transform: nil)
    let image = try Self.raster(
      CollageComposer.render(
        [halves], cells: [cell], placements: [CollagePhotoPlacement(rotation: .pi / 2)],
        style: CollageStyle(), width: 40, height: 40))
    // A quarter turn clockwise on the screen carries the left side to the top.
    #expect(image.pixel(x: 20, y: 5) == Self.red)
    #expect(image.pixel(x: 20, y: 35) == Self.blue)
  }
}
