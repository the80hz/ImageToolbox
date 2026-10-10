import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage photo placement")
struct CollagePhotoPlacementTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)

  private static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1e-6) -> Bool {
    abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
      && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
  }

  private static func covers(_ drawn: CGRect, _ box: CGRect) -> Bool {
    drawn.minX <= box.minX + 1e-6 && drawn.minY <= box.minY + 1e-6
      && drawn.maxX >= box.maxX - 1e-6 && drawn.maxY >= box.maxY - 1e-6
  }

  private static let square = CGRect(x: 0, y: 0, width: 100, height: 100)

  @Test("the identity placement draws the aspect fill of the box")
  func identityIsAspectFill() {
    let picture = CGSize(width: 200, height: 100)
    let drawn = CollagePhotoPlacement.identity.drawRect(of: picture, into: Self.square)
    let fill = CollageLayout.aspectFill(width: 200, height: 100, into: Self.square)
    #expect(Self.isClose(drawn, fill))
    #expect(Self.isClose(drawn, CGRect(x: -50, y: 0, width: 200, height: 100)))
  }

  @Test("the zoom is kept within 1 to the maximum and a bad zoom becomes 1")
  func zoomLimits() {
    #expect(CollagePhotoPlacement(zoom: 0.2).zoom == 1)
    #expect(CollagePhotoPlacement(zoom: 10).zoom == CollagePhotoPlacement.maximumZoom)
    #expect(CollagePhotoPlacement(zoom: 2.5).zoom == 2.5)
    #expect(CollagePhotoPlacement(zoom: CGFloat.nan).zoom == 1)
    #expect(CollagePhotoPlacement(zoom: CGFloat.infinity).zoom == 1)
  }

  @Test("each offset component is kept within -1 to 1 and a bad offset becomes 0")
  func offsetLimits() {
    let placement = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: 5, dy: -5))
    #expect(placement.offset == CGVector(dx: 1, dy: -1))
    let nan = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: CGFloat.nan, dy: 0.5))
    #expect(nan.offset == CGVector(dx: 0, dy: 0.5))
  }

  @Test("zooming in enlarges the picture about the centre of the box")
  func zoomAboutCentre() {
    let placement = CollagePhotoPlacement(zoom: 2)
    let drawn = placement.drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    #expect(Self.isClose(drawn, CGRect(x: -50, y: -50, width: 200, height: 200)))
  }

  @Test("the offset moves the picture to the edges of the travel")
  func offsetReachesEdges() {
    // Zoom 2 on a square picture in a square box: the travel is 50 pixels on each axis.
    let left = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: -1, dy: 0))
      .drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    #expect(left.maxX == 100)
    let right = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: 1, dy: 0))
      .drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    #expect(right.minX == 0)
    let half = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: 0.5, dy: 0))
      .drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    // The centre moves 25 pixels right, so the 200 pixel wide picture starts 25 pixels left of the box.
    #expect(abs(half.minX + 25) < 1e-6)
  }

  @Test("every zoom and offset covers the box, including the corners of the travel")
  func alwaysCovers() {
    let pictures = [
      CGSize(width: 300, height: 100), CGSize(width: 100, height: 300),
      CGSize(width: 80, height: 80),
    ]
    let boxes = [Self.square, CGRect(x: 10, y: 20, width: 160, height: 40)]
    for picture in pictures {
      for box in boxes {
        for zoom in [1.0, 1.5, 3.0, 4.0] {
          for dx in [-1.0, -0.3, 0, 0.7, 1] {
            for dy in [-1.0, 0, 1] {
              let drawn = CollagePhotoPlacement(
                zoom: zoom, offset: CGVector(dx: dx, dy: dy)
              ).drawRect(of: picture, into: box)
              #expect(Self.covers(drawn, box))
            }
          }
        }
      }
    }
  }

  @Test("an axis without travel ignores the offset")
  func noTravelIgnoresOffset() {
    // A wide picture in a square box fills the height exactly, so there is nothing to move vertically.
    let picture = CGSize(width: 200, height: 100)
    let plain = CollagePhotoPlacement.identity.drawRect(of: picture, into: Self.square)
    let moved = CollagePhotoPlacement(offset: CGVector(dx: 0, dy: 1))
      .drawRect(of: picture, into: Self.square)
    #expect(Self.isClose(plain, moved))
  }

  @Test("dragging moves the picture in the direction of the drag by the drag distance")
  func pannedFollowsDrag() {
    let zoomed = CollagePhotoPlacement(zoom: 2)
    let before = zoomed.drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    let panned = zoomed.panned(
      by: CGVector(dx: 20, dy: -10), picture: CGSize(width: 100, height: 100), into: Self.square)
    let after = panned.drawRect(of: CGSize(width: 100, height: 100), into: Self.square)
    #expect(abs(after.minX - (before.minX + 20)) < 1e-6)
    #expect(abs(after.minY - (before.minY - 10)) < 1e-6)
  }

  @Test("a drag stops at the edge of the travel")
  func pannedStopsAtEdge() {
    let zoomed = CollagePhotoPlacement(zoom: 2)
    let far = zoomed.panned(
      by: CGVector(dx: 1000, dy: 0), picture: CGSize(width: 100, height: 100), into: Self.square)
    #expect(far.offset.dx == 1)
    let back = far.panned(
      by: CGVector(dx: -1000, dy: 0), picture: CGSize(width: 100, height: 100), into: Self.square)
    #expect(back.offset.dx == -1)
  }

  @Test(
    "a drag along an axis without travel changes nothing, and a drag that is not a number is ignored"
  )
  func pannedNoOp() {
    let placement = CollagePhotoPlacement(zoom: 1)
    let wide = CGSize(width: 200, height: 100)
    let moved = placement.panned(by: CGVector(dx: 0, dy: 50), picture: wide, into: Self.square)
    #expect(moved.offset == .zero)
    let nan = placement.panned(
      by: CGVector(dx: CGFloat.nan, dy: 0), picture: wide, into: Self.square)
    #expect(nan == placement)
  }

  @Test("changing the zoom keeps the offset, and changing the offset keeps the zoom")
  func partialUpdates() {
    let placement = CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: 0.4, dy: -0.2))
    #expect(placement.zoomed(to: 3).offset == placement.offset)
    #expect(placement.zoomed(to: 3).zoom == 3)
    #expect(placement.positioned(at: CGVector(dx: 0, dy: 1)).zoom == 2)
    #expect(placement.positioned(at: CGVector(dx: 0, dy: 1)).offset == CGVector(dx: 0, dy: 1))
  }

  @Test("empty pictures and empty boxes draw the box itself")
  func degenerateInputs() {
    let drawn = CollagePhotoPlacement(zoom: 2).drawRect(of: .zero, into: Self.square)
    #expect(drawn == Self.square)
    let empty = CollagePhotoPlacement.identity.drawRect(
      of: CGSize(width: 10, height: 10), into: .zero)
    #expect(empty == .zero)
  }

  // MARK: - Composer

  /// A 40 by 40 picture, red on the left half and blue on the right half.
  private static func halves() -> CGImage {
    TestImages.image(width: 40, height: 40) { x, _ in x < 20 ? red : blue }
  }

  private static func raster(_ image: CGImage?) throws -> RasterImage {
    let image = try #require(image)
    return try #require(RasterImage(image))
  }

  @Test("the offset of a zoomed picture shows the part of the picture it points at")
  func composerShowsOffsetPart() throws {
    let cells = [CGPath(rect: CGRect(x: 0, y: 0, width: 40, height: 40), transform: nil)]
    let style = CollageStyle()
    let leftPart = try Self.raster(
      CollageComposer.render(
        [Self.halves()], cells: cells,
        placements: [
          CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: 1, dy: 0))
        ], style: style, width: 40, height: 40))
    // The left edge of the zoomed picture sits on the left edge of the cell, so the red half shows.
    #expect(leftPart.pixel(x: 5, y: 20) == Self.red)
    let rightPart = try Self.raster(
      CollageComposer.render(
        [Self.halves()], cells: cells,
        placements: [
          CollagePhotoPlacement(zoom: 2, offset: CGVector(dx: -1, dy: 0))
        ], style: style, width: 40, height: 40))
    #expect(rightPart.pixel(x: 35, y: 20) == Self.blue)
  }

  @Test("identity placements draw the same collage as no placements")
  func identityMatchesNone() throws {
    let cells = [
      CGPath(rect: CGRect(x: 0, y: 0, width: 30, height: 40), transform: nil),
      CGPath(rect: CGRect(x: 30, y: 0, width: 30, height: 40), transform: nil),
    ]
    let pictures = [Self.halves(), TestImages.solid(Self.blue, width: 16, height: 8)]
    let ellipse = CollageMask(shape: .ellipse)
    let style = CollageStyle()
    let none = try Self.raster(
      CollageComposer.render(
        pictures, cells: cells, masks: [ellipse, ellipse], style: style, width: 60, height: 40))
    let identity = try Self.raster(
      CollageComposer.render(
        pictures, cells: cells, placements: [.identity, .identity], masks: [ellipse, ellipse],
        style: style, width: 60, height: 40))
    #expect(none.pixels == identity.pixels)
  }

  @Test("placements must match the pictures in number")
  func placementCountMustMatch() {
    let cells = [CGPath(rect: CGRect(x: 0, y: 0, width: 40, height: 40), transform: nil)]
    let image = CollageComposer.render(
      [Self.halves()], cells: cells, placements: [.identity, .identity], style: CollageStyle(),
      width: 40, height: 40)
    #expect(image == nil)
  }

  @Test("the picture box of a circle is a centred square inside a wide cell")
  func pictureBoxOfCircle() {
    let cell = CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: 100), transform: nil)
    let box = CollageComposer.pictureBox(in: cell, mask: CollageMask(shape: .circle))
    #expect(Self.isClose(box, CGRect(x: 50, y: 0, width: 100, height: 100)))
    let plain = CollageComposer.pictureBox(in: cell, mask: .none)
    #expect(plain == CGRect(x: 0, y: 0, width: 200, height: 100))
  }
}
