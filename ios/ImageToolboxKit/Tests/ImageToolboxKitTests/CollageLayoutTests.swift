import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Grid collage layouts")
struct CollageLayoutTests {

  @Test("the grid is as square as possible for each count")
  func gridShape() {
    #expect(CollageLayout.grid(for: 1)?.columns == 1)
    #expect(CollageLayout.grid(for: 4)! == (2, 2))
    #expect(CollageLayout.grid(for: 5)! == (3, 2))
    #expect(CollageLayout.grid(for: 9)! == (3, 3))
    #expect(CollageLayout.grid(for: 0) == nil)
    #expect(CollageLayout.grid(for: 37) == nil)
  }

  @Test("cells fill the collage without overlapping and keep the margin")
  func cellsFit() throws {
    let settings = CollageLayout.Settings(gap: 10, margin: 20)
    let cells = try #require(
      CollageLayout.cells(count: 4, width: 300, height: 200, settings: settings))
    #expect(cells.count == 4)
    #expect(cells[0].minX == 20 && cells[0].minY == 20)
    #expect(cells[3].maxX == 280 && cells[3].maxY == 180)
    #expect(!cells[0].intersects(cells[1]))
    #expect(!cells[0].intersects(cells[2]))
  }

  @Test("a collage of two solid pictures is split into two colours")
  func renderSplitsColours() throws {
    let red = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 10, height: 10)
    let blue = TestImages.solid(RGBA(red: 0, green: 0, blue: 255), width: 10, height: 10)
    let settings = CollageLayout.Settings(gap: 0, margin: 0, background: (0, 0, 0))
    let collage = try #require(
      CollageLayout.render([red, blue], width: 40, height: 20, settings: settings))
    let raster = try #require(RasterImage(collage))
    // The first cell is the left half. Its top row is the top of the image.
    #expect(raster.pixel(x: 5, y: 2).red > 200)
    #expect(raster.pixel(x: 35, y: 2).blue > 200)
  }

  @Test("aspect fill covers the cell and centres the picture")
  func aspectFillCovers() {
    let rect = CollageLayout.aspectFill(
      width: 200, height: 100, into: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(rect.width == 200 && rect.height == 100)
    #expect(rect.midX == 50)
    #expect(rect.minX <= 0 && rect.maxX >= 100)
  }
}
