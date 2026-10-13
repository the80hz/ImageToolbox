import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage cell editing")
struct CollageCellEditingTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)
  private static let white = RGBA(red: 255, green: 255, blue: 255)
  private static let flat = CollageLayout.Settings(gap: 0, margin: 0)

  /// A composition of `count` square pictures on a square canvas of 100 pixels with no gap or margin.
  private static func square(count: Int) -> CollageComposition {
    var composition = CollageComposition()
    composition.designLongSide = 100
    composition.settings = flat
    composition.setPictureSizes(Array(repeating: CGSize(width: 40, height: 40), count: count))
    return composition
  }

  private static func raster(_ image: CGImage?) throws -> RasterImage {
    let image = try #require(image)
    return try #require(RasterImage(image))
  }

  @Test("each picture starts with no shape, and a new set of pictures starts over")
  func masksStartPlain() {
    var composition = Self.square(count: 3)
    #expect(composition.masks == [.none, .none, .none])
    composition.setMask(CollageMask(shape: .circle), at: 1)
    composition.setPictureSizes([CGSize(width: 10, height: 10)])
    #expect(composition.masks == [.none])
  }

  @Test("a shape changes only the cell it is set on, and an index out of range is ignored")
  func maskIsPerCell() {
    var composition = Self.square(count: 3)
    let circle = CollageMask(shape: .circle)
    composition.setMask(circle, at: 1)
    composition.setMask(CollageMask(shape: .heart), at: 9)
    #expect(composition.masks == [.none, circle, .none])
  }

  @Test("giving every cell one shape sets all of them")
  func maskForAll() {
    var composition = Self.square(count: 2)
    let hexagon = CollageMask(shape: .hexagon, cornerRadius: 4)
    composition.setMaskForAll(hexagon)
    #expect(composition.masks == [hexagon, hexagon])
  }

  @Test("swapping two pictures swaps their shapes too")
  func swapCarriesMasks() {
    var composition = Self.square(count: 2)
    let circle = CollageMask(shape: .circle)
    composition.setMask(circle, at: 0)
    composition.swapPictures(0, 1)
    #expect(composition.masks == [.none, circle])
  }

  @Test("two cells with different shapes are drawn with their own shapes")
  func rendersPerCellShapes() throws {
    var composition = Self.square(count: 2)
    composition.aspect = CollageExportSize.Aspect(width: 2, height: 1)
    composition.designLongSide = 100
    composition.template = .splitSideBySide
    composition.setMask(CollageMask(shape: .circle), at: 0)
    let pictures = [
      TestImages.solid(Self.red, width: 16, height: 16),
      TestImages.solid(Self.blue, width: 16, height: 16),
    ]
    let image = try Self.raster(
      composition.render(pictures, style: CollageStyle(background: .solid(Self.white))))
    // The left cell is a circle of radius 25 in its 50 by 50 box; the right cell is a plain rectangle.
    #expect(image.pixel(x: 25, y: 25) == Self.red)
    #expect(image.pixel(x: 2, y: 2) == Self.white)
    #expect(image.pixel(x: 52, y: 2) == Self.blue)
  }

  @Test("the export draws the same cells at its own size, with the shapes scaled too")
  func exportMatchesPreview() throws {
    var composition = Self.square(count: 2)
    composition.aspect = CollageExportSize.Aspect(width: 2, height: 1)
    composition.designLongSide = 100
    composition.template = .splitSideBySide
    composition.setMask(CollageMask(shape: .circle), at: 0)
    let pictures = [
      TestImages.solid(Self.red, width: 16, height: 16),
      TestImages.solid(Self.blue, width: 16, height: 16),
    ]
    let style = CollageStyle(background: .solid(Self.white))
    let export = try Self.raster(
      composition.render(pictures, style: style, width: 400, height: 200))
    #expect(export.width == 400 && export.height == 200)
    #expect(export.pixel(x: 100, y: 100) == Self.red)
    #expect(export.pixel(x: 8, y: 8) == Self.white)
    #expect(export.pixel(x: 300, y: 8) == Self.blue)
  }

  @Test(
    "the export size comes from the largest picture, and the preview size from the design canvas")
  func exportSizeFromPictures() {
    var composition = CollageComposition()
    composition.setPictureSizes([
      CGSize(width: 4000, height: 3000), CGSize(width: 800, height: 600),
    ])
    #expect(composition.exportSize.width == 2000 && composition.exportSize.height == 2000)
    #expect(composition.canvasWidth == 1080 && composition.canvasHeight == 1080)
    composition.exportScale = 0.25
    #expect(composition.exportSize.width == 1000)
    composition.aspect = CollageExportSize.Aspect(width: 16, height: 9)
    #expect(composition.canvasWidth == 1080 && composition.canvasHeight == 608)
  }

  @Test("moving a divider changes the cells, and changing the template or resetting puts them back")
  func movedDividerCells() throws {
    var composition = Self.square(count: 2)
    composition.template = .splitSideBySide
    let divider = try #require(composition.dividers.first)
    #expect(divider.orientation == .vertical)
    let cells = try #require(composition.unitCells)
    let moved = try #require(CollageDividers.moving(divider, to: 0.3, in: cells))
    composition.setUnitCells(moved)
    let widths = try #require(composition.cellPaths).map { $0.boundingBox.width }
    #expect(abs(widths[0] - 30) < 1e-6)
    #expect(abs(widths[1] - 70) < 1e-6)

    composition.resetDividers()
    let back = try #require(composition.cellPaths).map { $0.boundingBox.width }
    #expect(abs(back[0] - 50) < 1e-6)

    composition.setUnitCells(moved)
    composition.template = .splitStacked
    #expect(composition.customCells == nil)
  }

  @Test("a cell layout with a wrong number of cells is not stored")
  func wrongCountIgnored() {
    var composition = Self.square(count: 2)
    composition.setUnitCells([[CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]])
    #expect(composition.customCells == nil)
  }

  @Test(
    "the dividers of a hero layout are the horizontal line under the top cell and the vertical one below it"
  )
  func heroDividers() throws {
    var composition = Self.square(count: 3)
    composition.template = .hero
    let dividers = composition.dividers
    #expect(dividers.count == 2)
    #expect(dividers[0].orientation == .vertical)
    #expect(abs(dividers[0].position - 0.5) < 1e-9)
    #expect(abs(dividers[0].span.lowerBound - 0.6) < 1e-9)
    #expect(dividers[1].orientation == .horizontal)
    #expect(abs(dividers[1].position - 0.6) < 1e-9)
  }

  @Test("a shaped layout with a hole, and the free arrangement, have no dividers to drag")
  func noDividersWhereNoneApply() throws {
    var composition = Self.square(count: 2)
    composition.arrangement = .free
    #expect(composition.dividers.isEmpty)
    #expect(composition.unitCells == nil)

    let shaped = try #require(CollageShapedFrameLibrary.all.first)
    #expect(CollageTemplates.unitCells(.frame(shaped.id), count: shaped.count) == nil)
  }

  @Test("the handle of a divider sits in the margin-less part of the canvas, shifted by the margin")
  func dividerLineWithMargin() {
    var composition = Self.square(count: 2)
    composition.settings = CollageLayout.Settings(gap: 0, margin: 10)
    composition.template = .splitSideBySide
    let line = composition.dividerLine(composition.dividers[0])
    #expect(abs(line.start.x - 0.5) < 1e-9 && abs(line.start.y - 0.1) < 1e-9)
    #expect(abs(line.end.x - 0.5) < 1e-9 && abs(line.end.y - 0.9) < 1e-9)
  }

  @Test("a drag converts to the same change of the divider position, whatever the preview size")
  func dividerDeltaMatchesCanvas() throws {
    var composition = Self.square(count: 2)
    composition.settings = CollageLayout.Settings(gap: 0, margin: 10)
    composition.template = .splitSideBySide
    // Five preview points are ten canvas pixels, which is an eighth of the 80 pixel usable width.
    let small = try #require(
      composition.dividerDelta(
        previewTranslation: CGSize(width: 5, height: 0), previewSize: CGSize(width: 50, height: 50),
        orientation: .vertical))
    #expect(abs(small - 0.125) < 1e-9)
    let big = try #require(
      composition.dividerDelta(
        previewTranslation: CGSize(width: 10, height: 0),
        previewSize: CGSize(width: 100, height: 100),
        orientation: .vertical))
    #expect(abs(big - 0.125) < 1e-9)
    #expect(
      composition.dividerDelta(
        previewTranslation: .zero, previewSize: .zero, orientation: .horizontal) == nil)
  }
}
