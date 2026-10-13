import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage composer")
struct CollageComposerTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)
  private static let green = RGBA(red: 0, green: 255, blue: 0)
  private static let black = RGBA(red: 0, green: 0, blue: 0)
  private static let white = RGBA(red: 255, green: 255, blue: 255)

  private static func picture(_ color: RGBA) -> CGImage {
    TestImages.solid(color, width: 16, height: 16)
  }

  private static func raster(_ image: CGImage?) throws -> RasterImage {
    let image = try #require(image)
    return try #require(RasterImage(image))
  }

  private static let flat = CollageLayout.Settings(gap: 0, margin: 0)

  @Test("the plain style draws the same collage as the grid layout")
  func plainStyleMatchesGrid() throws {
    let pictures = [Self.picture(Self.red), Self.picture(Self.blue)]
    let settings = CollageLayout.Settings(gap: 4, margin: 6, background: (0, 0, 0))
    let old = try Self.raster(
      CollageTemplates.render(pictures, template: .grid, width: 60, height: 40, settings: settings))
    let style = CollageStyle(background: .solid(Self.black))
    let new = try Self.raster(
      CollageComposer.render(
        pictures, template: .grid, settings: settings, style: style, width: 60, height: 40))
    for (x, y) in [(2, 2), (10, 20), (30, 20), (50, 30), (31, 20)] {
      #expect(old.pixel(x: x, y: y) == new.pixel(x: x, y: y))
    }
  }

  @Test("the background shows in the gaps and the margin")
  func backgroundInGaps() throws {
    let settings = CollageLayout.Settings(gap: 10, margin: 10)
    let style = CollageStyle(background: .solid(Self.green))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red), Self.picture(Self.blue)], template: .splitSideBySide,
        settings: settings, style: style, width: 100, height: 50))
    #expect(image.pixel(x: 3, y: 25) == Self.green)
    #expect(image.pixel(x: 50, y: 25) == Self.green)
    #expect(image.pixel(x: 25, y: 25) == Self.red)
    #expect(image.pixel(x: 75, y: 25) == Self.blue)
  }

  @Test("a gradient background shows in the margin")
  func gradientBackground() throws {
    let settings = CollageLayout.Settings(gap: 0, margin: 10)
    let style = CollageStyle(background: .linearGradient(from: Self.red, to: Self.blue, angle: 0))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.black)], template: .grid, settings: settings, style: style, width: 100,
        height: 100))
    #expect(image.pixel(x: 5, y: 50).red > 200)
    #expect(image.pixel(x: 95, y: 50).blue > 200)
    #expect(image.pixel(x: 50, y: 50) == Self.black)
  }

  @Test("a transparent background leaves the gaps transparent")
  func transparentBackground() throws {
    let settings = CollageLayout.Settings(gap: 0, margin: 10)
    let style = CollageStyle(background: .solid(RGBA(red: 0, green: 0, blue: 0, alpha: 0)))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: settings, style: style, width: 40,
        height: 40))
    #expect(image.pixel(x: 2, y: 2).alpha == 0)
    #expect(image.pixel(x: 20, y: 20) == Self.red)
  }

  @Test("a circle mask keeps the middle of the cell and shows the background in its corners")
  func circleMask() throws {
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: Self.flat,
        masks: [CollageMask(shape: .circle)], style: style, width: 80, height: 80))
    #expect(image.pixel(x: 40, y: 40) == Self.red)
    #expect(image.pixel(x: 40, y: 3) == Self.red)
    #expect(image.pixel(x: 2, y: 2) == Self.white)
    #expect(image.pixel(x: 77, y: 77) == Self.white)
  }

  @Test("a heart mask has a cleft on top")
  func heartMask() throws {
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: Self.flat,
        masks: [CollageMask(shape: .heart)], style: style, width: 100, height: 100))
    #expect(image.pixel(x: 50, y: 50) == Self.red)
    #expect(image.pixel(x: 50, y: 12) == Self.white)
    #expect(image.pixel(x: 3, y: 97) == Self.white)
  }

  @Test("a hexagon mask cuts the corners of a square cell")
  func hexagonMask() throws {
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: Self.flat,
        masks: [CollageMask(shape: .hexagon)], style: style, width: 100, height: 100))
    #expect(image.pixel(x: 50, y: 50) == Self.red)
    #expect(image.pixel(x: 3, y: 3) == Self.white)
    #expect(image.pixel(x: 96, y: 96) == Self.white)
    // The points of the hexagon reach the left and right sides.
    #expect(image.pixel(x: 4, y: 50) == Self.red)
  }

  @Test("rounded corners show the background in the corners of every cell")
  func roundedCorners() throws {
    let corners = CollageMask(shape: .rectangle, cornerRadius: 12)
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red), Self.picture(Self.blue)], template: .splitSideBySide,
        settings: Self.flat, masks: [corners, corners], style: style, width: 100, height: 50))
    #expect(image.pixel(x: 0, y: 0) == Self.white)
    #expect(image.pixel(x: 49, y: 49) == Self.white)
    #expect(image.pixel(x: 50, y: 0) == Self.white)
    #expect(image.pixel(x: 25, y: 25) == Self.red)
    #expect(image.pixel(x: 75, y: 25) == Self.blue)
  }

  @Test("a mask shows each picture whole in a shape smaller than the cell")
  func pictureFillsTheShape() throws {
    // A picture with a red left half and a blue right half, shown in a circle inside a wide cell.
    let halves = TestImages.halves(left: Self.red, right: Self.blue, width: 20, height: 20)
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [halves], template: .grid, settings: Self.flat, masks: [CollageMask(shape: .circle)],
        style: style, width: 200, height: 100))
    // The circle covers x 50...150. Its left part is red and its right part is blue.
    #expect(image.pixel(x: 70, y: 50) == Self.red)
    #expect(image.pixel(x: 130, y: 50) == Self.blue)
    #expect(image.pixel(x: 20, y: 50) == Self.white)
  }

  @Test("a border is drawn inside the edge of each cell")
  func borderInside() throws {
    let style = CollageStyle(border: CollageBorder(width: 4, color: Self.black))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: Self.flat, style: style, width: 40,
        height: 40))
    #expect(image.pixel(x: 1, y: 20) == Self.black)
    #expect(image.pixel(x: 3, y: 20) == Self.black)
    #expect(image.pixel(x: 6, y: 20) == Self.red)
    #expect(image.pixel(x: 20, y: 1) == Self.black)
    #expect(image.pixel(x: 20, y: 38) == Self.black)
    #expect(image.pixel(x: 38, y: 20) == Self.black)
    #expect(image.pixel(x: 20, y: 20) == Self.red)
  }

  @Test("a border does not spill into the gap")
  func borderStaysInCell() throws {
    let settings = CollageLayout.Settings(gap: 20, margin: 0)
    let style = CollageStyle(
      background: .solid(Self.white), border: CollageBorder(width: 3, color: Self.black))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red), Self.picture(Self.blue)], template: .splitSideBySide,
        settings: settings, style: style, width: 100, height: 40))
    // Each cell is 40 wide; the gap is x 40...60.
    #expect(image.pixel(x: 41, y: 20) == Self.white)
    #expect(image.pixel(x: 59, y: 20) == Self.white)
    #expect(image.pixel(x: 38, y: 20) == Self.black)
    #expect(image.pixel(x: 61, y: 20) == Self.black)
  }

  @Test("a border follows the mask shape")
  func borderFollowsMask() throws {
    let style = CollageStyle(
      background: .solid(Self.white), border: CollageBorder(width: 5, color: Self.black))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red)], template: .grid, settings: Self.flat,
        masks: [CollageMask(shape: .circle)], style: style, width: 100, height: 100))
    #expect(image.pixel(x: 50, y: 50) == Self.red)
    #expect(image.pixel(x: 50, y: 2) == Self.black)
    #expect(image.pixel(x: 2, y: 50) == Self.black)
    #expect(image.pixel(x: 3, y: 3) == Self.white)
  }

  @Test("a border with no width or no alpha changes nothing")
  func invisibleBorder() throws {
    #expect(!CollageBorder(width: 0, color: Self.black).isVisible)
    #expect(!CollageBorder(width: 5, color: RGBA(red: 0, green: 0, blue: 0, alpha: 0)).isVisible)
    #expect(CollageBorder(width: -3).width == 0)
    #expect(!CollageBorder.none.isVisible)
  }

  @Test("a free layout draws later cells on top of earlier ones")
  func freeLayoutOverlap() throws {
    let rects = [
      CGRect(x: 0, y: 0, width: 0.7, height: 0.7), CGRect(x: 0.3, y: 0.3, width: 0.7, height: 0.7),
    ]
    let layout = try #require(FreeCollageLayout(rects: rects))
    let pictures = [Self.picture(Self.red), Self.picture(Self.blue)]
    let style = CollageStyle(background: .solid(Self.white))
    let normal = try Self.raster(
      CollageComposer.render(
        pictures, layout: layout, settings: Self.flat, style: style, width: 100, height: 100))
    #expect(normal.pixel(x: 10, y: 10) == Self.red)
    #expect(normal.pixel(x: 50, y: 50) == Self.blue)
    #expect(normal.pixel(x: 90, y: 90) == Self.blue)
    #expect(normal.pixel(x: 90, y: 10) == Self.white)

    let raised = try Self.raster(
      CollageComposer.render(
        pictures, layout: layout.bringingToFront(0), settings: Self.flat, style: style, width: 100,
        height: 100))
    #expect(raised.pixel(x: 50, y: 50) == Self.red)
    #expect(raised.pixel(x: 90, y: 90) == Self.blue)
  }

  @Test("a moved and resized free cell lands where the layout says")
  func freeLayoutEdits() throws {
    var layout = try #require(FreeCollageLayout.grid(count: 2))
    layout = layout.resizing(0, handle: .bottomRight, by: CGVector(dx: -0.1, dy: -0.5))
      .moving(0, by: CGVector(dx: 0, dy: 0.25))
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red), Self.picture(Self.blue)], layout: layout, settings: Self.flat,
        style: style, width: 100, height: 100))
    // Cell 0 now covers x 0...40 and y 25...75 of the 100 by 100 canvas.
    #expect(image.pixel(x: 20, y: 50) == Self.red)
    #expect(image.pixel(x: 20, y: 10) == Self.white)
    #expect(image.pixel(x: 45, y: 50) == Self.white)
    #expect(image.pixel(x: 75, y: 50) == Self.blue)
  }

  @Test("rendering needs one cell for every picture and a canvas with area")
  func rejectsMismatches() throws {
    let pictures = [Self.picture(Self.red), Self.picture(Self.blue)]
    let style = CollageStyle()
    let oneCell = [CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)]
    #expect(
      CollageComposer.render(pictures, cells: oneCell, style: style, width: 10, height: 10) == nil)
    #expect(
      CollageComposer.render([], cells: [], style: style, width: 10, height: 10) == nil)
    let three = try #require(FreeCollageLayout.grid(count: 3))
    #expect(
      CollageComposer.render(
        pictures, layout: three, settings: Self.flat, style: style, width: 10, height: 10) == nil)
    #expect(
      CollageComposer.render(
        pictures, template: .splitStacked, settings: Self.flat, style: style, width: 0, height: 10)
        == nil)
    #expect(
      CollageComposer.render(
        pictures, template: .hero, settings: Self.flat, style: style, width: 40, height: 40) != nil)
    #expect(
      CollageComposer.render(
        pictures, cells: oneCell + oneCell, drawOrder: [0, 0], style: style, width: 10, height: 10)
        == nil)
  }

  @Test("a masked diagonal template keeps each picture on its side of the divider")
  func maskedDiagonal() throws {
    let rounded = CollageMask(shape: .rectangle, cornerRadius: 10)
    let style = CollageStyle(background: .solid(Self.white))
    let image = try Self.raster(
      CollageComposer.render(
        [Self.picture(Self.red), Self.picture(Self.blue)], template: .diagonal, settings: Self.flat,
        masks: [rounded, rounded], style: style, width: 120, height: 120))
    #expect(image.pixel(x: 25, y: 25) == Self.red)
    #expect(image.pixel(x: 95, y: 95) == Self.blue)
    #expect(image.pixel(x: 0, y: 0) == Self.white)
  }
}
