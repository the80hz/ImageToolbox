import CoreGraphics
import Foundation

/// A collage as the user arranges it: the pixel sizes of the pictures, the cells they go in (a template or a free
/// layout), how each picture sits in its cell, the shape of each cell and the spacing and export size. It holds no
/// pixels, so the app keeps the pictures and passes them to `render`. Pictures, placements, masks and free cells always
/// have the same count.
public struct CollageComposition: Equatable, Sendable {

  /// Whether the pictures fill the cells of a template or the cells of the free layout.
  public enum Arrangement: CaseIterable, Hashable, Sendable {
    case template
    case free
  }

  /// The aspect ratio of the collage, one of the Android presets.
  public var aspect = CollageExportSize.defaultAspect
  /// The output scale of the export, from 0.1 to 1. See `CollageExportSize`.
  public var exportScale = CollageExportSize.defaultScale
  /// The arrangement in use.
  public var arrangement = Arrangement.template
  /// The template in use. `effectiveTemplate` is what is drawn: the grid when this one does not fit. Changing the
  /// template drops the moved dividers.
  public var template = CollageTemplate.grid {
    didSet { if template != oldValue { customCells = nil } }
  }
  /// The gap between cells and the margin around them, in pixels of the design canvas. The background in these
  /// settings is not used; the style passed to `render` draws it.
  public var settings = CollageLayout.Settings()
  /// The cells of the free layout, one per picture. Nil without pictures.
  public var freeLayout: FreeCollageLayout?
  /// The pixel size of each picture, in the order of the pictures.
  public private(set) var pictureSizes: [CGSize] = []
  /// How each picture sits in its cell, one per picture.
  public private(set) var placements: [CollagePhotoPlacement] = []
  /// The shape of each picture's cell, one per picture. The shapes of a template's own cells are part of the cells.
  public private(set) var masks: [CollageMask] = []
  /// The unit-square cells after the user moved a divider. Nil while the template is as it was made.
  public private(set) var customCells: [[CGPoint]]?

  public init() {}

  /// The longer side of the design canvas in pixels: the size the layout is worked out on, and the preview is drawn at.
  public var designLongSide = CollageExportSize.designLongSide

  /// The width of the design canvas in pixels.
  public var canvasWidth: Int {
    CollageExportSize.dimensions(aspect: aspect, longSide: designLongSide).width
  }

  /// The height of the design canvas in pixels.
  public var canvasHeight: Int {
    CollageExportSize.dimensions(aspect: aspect, longSide: designLongSide).height
  }

  /// The size of the export in pixels, from the largest picture and `exportScale`.
  public var exportSize: (width: Int, height: Int) {
    let largest =
      pictureSizes.map { max($0.width, $0.height) }.max()
      ?? CGFloat(CollageExportSize.designLongSide)
    return CollageExportSize.exportDimensions(
      aspect: aspect, sourceLongSide: Int(largest), scale: exportScale)
  }

  // MARK: - Pictures

  /// Takes the pixel sizes of the pictures. Each picture starts as the aspect fill and unmasked, the free cells start
  /// as a grid, and a template that does not take that many pictures is replaced by the grid.
  public mutating func setPictureSizes(_ sizes: [CGSize]) {
    pictureSizes = sizes
    placements = Array(repeating: .identity, count: sizes.count)
    masks = Array(repeating: .none, count: sizes.count)
    customCells = nil
    freeLayout = FreeCollageLayout.grid(count: sizes.count)
    if !fits(template) { template = .grid }
  }

  /// Puts the free cells back in a grid, one per picture.
  public mutating func resetFreeLayout() {
    freeLayout = FreeCollageLayout.grid(count: pictureSizes.count)
  }

  /// Swaps two pictures together with their placements and masks. The cells stay where they are.
  public mutating func swapPictures(_ first: Int, _ second: Int) {
    guard first != second, pictureSizes.indices.contains(first),
      pictureSizes.indices.contains(second)
    else { return }
    pictureSizes.swapAt(first, second)
    placements.swapAt(first, second)
    masks.swapAt(first, second)
  }

  // MARK: - Placements and masks

  /// Replaces the placement of picture `index`. Ignored for an index out of range.
  public mutating func setPlacement(_ placement: CollagePhotoPlacement, at index: Int) {
    guard placements.indices.contains(index) else { return }
    placements[index] = placement
  }

  /// Replaces the shape of the cell of picture `index`. Ignored for an index out of range.
  public mutating func setMask(_ mask: CollageMask, at index: Int) {
    guard masks.indices.contains(index) else { return }
    masks[index] = mask
  }

  /// Gives every cell the same shape.
  public mutating func setMaskForAll(_ mask: CollageMask) {
    masks = Array(repeating: mask, count: masks.count)
  }

  /// The placement of picture `index` after it was dragged by `translation` points on a preview of `previewSize`
  /// points, from the placement `start` the drag began with. The preview shows the canvas at its own scale. Nil when
  /// there is no such picture or cell.
  public func placement(
    panning start: CollagePhotoPlacement, at index: Int, previewTranslation translation: CGSize,
    previewSize: CGSize
  ) -> CollagePhotoPlacement? {
    guard pictureSizes.indices.contains(index), let cells = cellPaths,
      cells.indices.contains(index), previewSize.width > 0, previewSize.height > 0
    else { return nil }
    let box = CollageComposer.pictureBox(in: cells[index], mask: masks[index])
    let delta = CGVector(
      dx: translation.width / previewSize.width * CGFloat(canvasWidth),
      dy: translation.height / previewSize.height * CGFloat(canvasHeight))
    return start.panned(by: delta, picture: pictureSizes[index], into: box)
  }

  /// The change to a free layout for a drag of `translation` points on a preview of `previewSize` points, in
  /// fractions of the usable area, which is what the free layout stores. Nil when the preview or the usable area
  /// has no size.
  public func freeLayoutDelta(previewTranslation translation: CGSize, previewSize: CGSize)
    -> CGVector?
  {
    guard previewSize.width > 0, previewSize.height > 0,
      let usable = FreeCollageLayout.usableRect(
        width: Double(canvasWidth), height: Double(canvasHeight), margin: settings.margin)
    else { return nil }
    return CGVector(
      dx: translation.width / previewSize.width * CGFloat(canvasWidth) / usable.width,
      dy: translation.height / previewSize.height * CGFloat(canvasHeight) / usable.height)
  }

  // MARK: - Dividers

  /// The unit-square cells in use: the moved ones, else those of the template. Nil in the free arrangement and for a
  /// template whose cells are not single polygons.
  public var unitCells: [[CGPoint]]? {
    guard arrangement == .template else { return nil }
    if let customCells { return customCells }
    return CollageTemplates.unitCells(effectiveTemplate, count: pictureSizes.count)
  }

  /// The dividers that can be dragged in the template arrangement. Empty when there are none.
  public var dividers: [CollageDivider] {
    unitCells.map(CollageDividers.dividers(of:)) ?? []
  }

  /// Replaces the unit-square cells after a divider moved. Ignored unless there is one cell per picture.
  public mutating func setUnitCells(_ cells: [[CGPoint]]) {
    guard cells.count == pictureSizes.count else { return }
    customCells = cells
  }

  /// Puts the template back as it was made, undoing the moved dividers.
  public mutating func resetDividers() {
    customCells = nil
  }

  /// The ends of `divider` as fractions of the canvas, for drawing its handle over the preview.
  public func dividerLine(_ divider: CollageDivider) -> (start: CGPoint, end: CGPoint) {
    let low = divider.span.lowerBound
    let high = divider.span.upperBound
    switch divider.orientation {
    case .vertical:
      return (
        canvasFraction(CGPoint(x: divider.position, y: low)),
        canvasFraction(CGPoint(x: divider.position, y: high))
      )
    case .horizontal:
      return (
        canvasFraction(CGPoint(x: low, y: divider.position)),
        canvasFraction(CGPoint(x: high, y: divider.position))
      )
    }
  }

  /// How far a divider moves in the unit square for a drag of `translation` points on a preview of `previewSize`
  /// points. Nil when the preview or the usable area has no size.
  public func dividerDelta(
    previewTranslation translation: CGSize, previewSize: CGSize,
    orientation: CollageDivider.Orientation
  ) -> Double? {
    guard previewSize.width > 0, previewSize.height > 0 else { return nil }
    let margin = CGFloat(settings.margin)
    let usableWidth = CGFloat(canvasWidth) - 2 * margin
    let usableHeight = CGFloat(canvasHeight) - 2 * margin
    guard usableWidth > 0, usableHeight > 0 else { return nil }
    switch orientation {
    case .vertical:
      return Double(translation.width / previewSize.width * CGFloat(canvasWidth) / usableWidth)
    case .horizontal:
      return Double(translation.height / previewSize.height * CGFloat(canvasHeight) / usableHeight)
    }
  }

  // MARK: - Cells and drawing

  /// The template that is drawn: `template` when it takes the pictures at this canvas and spacing, else the grid.
  public var effectiveTemplate: CollageTemplate {
    fits(template) ? template : .grid
  }

  /// The templates that take the pictures at this canvas and spacing, in order.
  public var availableTemplates: [CollageTemplate] {
    CollageTemplate.allCases.filter(fits)
  }

  /// The cell of each picture in design-canvas pixels with the top left at the origin, for the arrangement in use. Nil
  /// when there is no layout.
  public var cellPaths: [CGPath]? {
    cells(width: canvasWidth, height: canvasHeight)
  }

  /// The cell of each picture on a canvas of `width` by `height` pixels, for the arrangement in use. The spacing and the
  /// margin grow with the canvas, so the export looks like the preview. Nil when there is no layout.
  public func cells(width: Int, height: Int) -> [CGPath]? {
    let factor = Double(width) / Double(canvasWidth)
    let scaled = CollageLayout.Settings(
      gap: settings.gap * factor, margin: settings.margin * factor)
    switch arrangement {
    case .template:
      if let customCells,
        let paths = Self.movedCells(customCells, width: width, height: height, settings: scaled)
      {
        return paths
      }
      return CollageTemplates.cells(
        effectiveTemplate, count: pictureSizes.count, width: Double(width), height: Double(height),
        settings: scaled)
    case .free:
      return freeLayout?.cellPaths(width: Double(width), height: Double(height), settings: scaled)
    }
  }

  /// The cells as paths in fractions of the canvas, so a view can scale them to any preview size. Nil when there is no
  /// layout.
  public var normalisedCellPaths: [CGPath]? {
    guard let cells = cellPaths else { return nil }
    var scale = CGAffineTransform(
      scaleX: 1 / CGFloat(canvasWidth), y: 1 / CGFloat(canvasHeight))
    return cells.map { $0.copy(using: &scale) ?? $0 }
  }

  /// Draws the pictures into their cells at the design size, for the preview. Nil when the pictures do not match the
  /// composition, or there is no layout.
  public func render(_ pictures: [CGImage], style: CollageStyle) -> CGImage? {
    render(pictures, style: style, width: canvasWidth, height: canvasHeight)
  }

  /// Draws the pictures into their cells on a canvas of `width` by `height` pixels, which is the design size for the
  /// preview and `exportSize` for the export. Nil when the pictures do not match the composition, or there is no
  /// layout.
  public func render(_ pictures: [CGImage], style: CollageStyle, width: Int, height: Int)
    -> CGImage?
  {
    guard pictures.count == pictureSizes.count, let cells = cells(width: width, height: height)
    else { return nil }
    let factor = Double(width) / Double(canvasWidth)
    return CollageComposer.render(
      pictures, cells: cells,
      drawOrder: arrangement == .free ? freeLayout?.drawOrder : nil,
      placements: placements, masks: masks.map { $0.scaled(by: factor) },
      style: style.scaled(by: factor), width: width, height: height)
  }

  // MARK: - Helpers

  /// Whether `template` has cells for the pictures at this canvas and spacing.
  private func fits(_ template: CollageTemplate) -> Bool {
    CollageTemplates.cells(
      template, count: pictureSizes.count, width: Double(canvasWidth),
      height: Double(canvasHeight), settings: settings) != nil
  }

  /// The cells after a divider moved, drawn on a canvas of `width` by `height` pixels. Nil when they do not fit, which
  /// happens when the spacing is too wide for them.
  private static func movedCells(
    _ cells: [[CGPoint]], width: Int, height: Int, settings: CollageLayout.Settings
  ) -> [CGPath]? {
    let margin = settings.margin
    let usable = CGRect(
      x: margin, y: margin, width: Double(width) - 2 * margin, height: Double(height) - 2 * margin)
    return CollageFrameLibrary.cells(unit: cells, in: usable, gap: settings.gap)
  }

  /// A point of the unit square as a fraction of the design canvas, where the margin sits around the usable area.
  private func canvasFraction(_ point: CGPoint) -> CGPoint {
    let margin = settings.margin
    let width = Double(canvasWidth)
    let height = Double(canvasHeight)
    return CGPoint(
      x: (margin + Double(point.x) * (width - 2 * margin)) / width,
      y: (margin + Double(point.y) * (height - 2 * margin)) / height)
  }
}
