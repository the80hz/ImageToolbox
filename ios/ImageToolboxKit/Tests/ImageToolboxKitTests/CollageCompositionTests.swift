import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage composition")
struct CollageCompositionTests {

  private static let red = RGBA(red: 255, green: 0, blue: 0)
  private static let blue = RGBA(red: 0, green: 0, blue: 255)

  private static func sizes(_ count: Int) -> [CGSize] {
    Array(repeating: CGSize(width: 200, height: 100), count: count)
  }

  /// A composition on a 60 by 40 canvas with no gap or margin, holding `count` pictures.
  private static func composition(count: Int) -> CollageComposition {
    var composition = CollageComposition()
    composition.aspect = CollageExportSize.Aspect(width: 3, height: 2)
    composition.designLongSide = 60
    composition.settings = CollageLayout.Settings(gap: 0, margin: 0)
    composition.setPictureSizes(sizes(count))
    return composition
  }

  @Test("loading pictures starts each one as the aspect fill and the free cells as a grid")
  func loadingStartsPlain() {
    let composition = Self.composition(count: 3)
    #expect(composition.placements == Array(repeating: .identity, count: 3))
    #expect(composition.freeLayout?.count == 3)
    #expect(composition.pictureSizes.count == 3)
  }

  @Test("a template that does not take the new number of pictures falls back to the grid")
  func templateFallsBack() {
    var composition = Self.composition(count: 2)
    composition.template = .splitSideBySide
    #expect(composition.effectiveTemplate == .splitSideBySide)
    composition.setPictureSizes(Self.sizes(3))
    #expect(composition.template == .grid)
  }

  @Test("the templates on offer depend on the number of pictures")
  func availableTemplatesFollowCount() {
    let two = Self.composition(count: 2).availableTemplates
    #expect(two.contains(.splitSideBySide))
    #expect(two.contains(.diagonal))
    #expect(!two.contains(.twoByTwoOffset))
    let three = Self.composition(count: 3).availableTemplates
    #expect(!three.contains(.splitSideBySide))
    #expect(three.contains(.hero))
  }

  @Test("a template that does not fit the spacing is drawn as the grid")
  func effectiveTemplateRespectsSpacing() {
    var composition = Self.composition(count: 2)
    composition.template = .diagonal
    #expect(composition.effectiveTemplate == .diagonal)
    composition.settings = CollageLayout.Settings(gap: 500, margin: 0)
    #expect(composition.effectiveTemplate == .grid)
  }

  @Test("swapping pictures swaps their sizes and placements and keeps the cells")
  func swapKeepsCells() {
    var composition = Self.composition(count: 2)
    composition.setPlacement(CollagePhotoPlacement(zoom: 2), at: 0)
    let cellsBefore = composition.cellPaths?.map(\.boundingBox)
    composition.swapPictures(0, 1)
    #expect(composition.placements[1] == CollagePhotoPlacement(zoom: 2))
    #expect(composition.placements[0] == .identity)
    #expect(composition.cellPaths?.map(\.boundingBox) == cellsBefore)
  }

  @Test("swapping an index with itself or outside the pictures changes nothing")
  func swapIgnoresBadIndices() {
    var composition = Self.composition(count: 2)
    let before = composition
    composition.swapPictures(0, 0)
    composition.swapPictures(0, 5)
    composition.swapPictures(-1, 1)
    #expect(composition == before)
  }

  @Test("a placement outside the pictures is ignored")
  func placementIgnoresBadIndex() {
    var composition = Self.composition(count: 2)
    let before = composition
    composition.setPlacement(CollagePhotoPlacement(zoom: 3), at: 2)
    #expect(composition == before)
  }

  @Test("cells come one per picture and stay inside the canvas")
  func cellsStayInside() throws {
    for count in [1, 2, 5] {
      let composition = Self.composition(count: count)
      let cells = try #require(composition.normalisedCellPaths)
      #expect(cells.count == count)
      for cell in cells {
        let box = cell.boundingBox
        #expect(box.minX >= -1e-9 && box.maxX <= 1 + 1e-9)
        #expect(box.minY >= -1e-9 && box.maxY <= 1 + 1e-9)
      }
    }
  }

  @Test("the free arrangement uses the free cells, and resetting them makes a grid again")
  func freeArrangement() throws {
    var composition = Self.composition(count: 3)
    composition.arrangement = .free
    let grid = try #require(composition.cellPaths)
    #expect(grid.count == 3)
    composition.freeLayout = FreeCollageLayout(rects: [
      CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
      CGRect(x: 0, y: 0, width: 1, height: 0.5),
    ])
    let custom = try #require(composition.cellPaths)
    #expect(custom[2].boundingBox == CGRect(x: 0, y: 0, width: 60, height: 20))
    composition.resetFreeLayout()
    #expect(composition.freeLayout == FreeCollageLayout.grid(count: 3))
  }

  @Test("a drag on the preview pans by the canvas distance it stands for")
  func pannedThroughComposition() throws {
    // The canvas is 60 by 40 and the preview is half that size, so 15 preview points are 30 canvas pixels. The
    // single cell is the whole canvas, and the picture (zoom 2) travels 50 pixels from its centre on the x axis.
    let composition = Self.composition(count: 1)
    let preview = CGSize(width: 30, height: 20)
    let moved = try #require(
      composition.placement(
        panning: CollagePhotoPlacement(zoom: 2), at: 0,
        previewTranslation: CGSize(width: 15, height: 0), previewSize: preview))
    #expect(abs(moved.offset.dx - 0.6) < 1e-9)
    #expect(moved.zoom == 2)

    let far = try #require(
      composition.placement(
        panning: CollagePhotoPlacement(zoom: 2), at: 0,
        previewTranslation: CGSize(width: 1000, height: 0), previewSize: preview))
    #expect(far.offset.dx == 1)
    #expect(
      composition.placement(
        panning: .identity, at: 4, previewTranslation: .zero, previewSize: preview) == nil)
    #expect(
      composition.placement(
        panning: .identity, at: 0, previewTranslation: .zero, previewSize: .zero) == nil)
  }

  @Test("a drag on a free layout is a fraction of the usable area of the canvas")
  func freeDragDelta() throws {
    // The canvas is 60 by 40 with no margin, so the usable area is the whole canvas. A drag of 6 points on a
    // preview as wide as the canvas is a tenth of the width. Half-size previews give the same fraction.
    let composition = Self.composition(count: 2)
    let full = try #require(
      composition.freeLayoutDelta(
        previewTranslation: CGSize(width: 6, height: 0), previewSize: CGSize(width: 60, height: 40))
    )
    #expect(abs(full.dx - 0.1) < 1e-9)
    #expect(full.dy == 0)
    let half = try #require(
      composition.freeLayoutDelta(
        previewTranslation: CGSize(width: 3, height: 0), previewSize: CGSize(width: 30, height: 20))
    )
    #expect(abs(half.dx - 0.1) < 1e-9)
    #expect(
      composition.freeLayoutDelta(previewTranslation: .zero, previewSize: .zero) == nil)
  }

  @Test("render returns an image of the canvas size, and nil when the pictures do not match")
  func renderSizeAndMismatch() throws {
    let composition = Self.composition(count: 2)
    let pictures = [
      TestImages.solid(Self.red, width: 16, height: 16),
      TestImages.solid(Self.blue, width: 16, height: 16),
    ]
    let image = try #require(composition.render(pictures, style: CollageStyle()))
    #expect(image.width == 60)
    #expect(image.height == 40)
    #expect(composition.render(Array(pictures.prefix(1)), style: CollageStyle()) == nil)
  }

  @Test("the free arrangement renders with the placements of its pictures")
  func renderFreeArrangement() throws {
    var composition = Self.composition(count: 2)
    composition.arrangement = .free
    composition.setPlacement(CollagePhotoPlacement(zoom: 2), at: 1)
    let pictures = [
      TestImages.solid(Self.red, width: 16, height: 16),
      TestImages.solid(Self.blue, width: 16, height: 16),
    ]
    #expect(composition.render(pictures, style: CollageStyle()) != nil)
  }
}
