import CoreGraphics
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// The collage as drawn: the picture for the preview and the export as PNG.
private struct RenderedCollage: @unchecked Sendable {
  let preview: CGImage
  let data: Data
}

/// Holds the collage tool's state: the chosen pictures, the arrangement, the look and the export. The cells,
/// placements, cell shapes and spacing live in `CollageComposition`, and the settings the Android app keeps between
/// launches in `CollageSettings`. This type adds the picked pictures and the gestures on the preview.
@MainActor
@Observable
final class CollageToolModel {

  /// The look and export settings. Every change is written to UserDefaults at once, so the next launch starts with them.
  var settings = CollageSettings.load(from: .standard) {
    didSet {
      settings.save(to: .standard)
      changed()
    }
  }

  /// The arrangement, template, spacing, export size and cells of the collage.
  private(set) var composition = CollageComposition()

  /// Whether the pictures fill the cells of a template or of the free layout.
  var arrangement: CollageComposition.Arrangement {
    get { composition.arrangement }
    set {
      composition.arrangement = newValue
      selectedCell = nil
      changed()
    }
  }

  /// The template in use. It is the grid when the chosen template does not take the pictures.
  var template: CollageTemplate {
    get { composition.effectiveTemplate }
    set {
      composition.template = newValue
      changed()
    }
  }

  private(set) var pictures: [LoadedImage] = []
  private(set) var failedCount = 0
  private(set) var isLoading = false
  private(set) var exportData: Data?
  /// The last drawn collage. It stays while the next one is drawn, so the preview does not blink.
  private(set) var previewImage: CGImage?
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  /// The picture whose cell is selected, in either arrangement.
  private(set) var selectedCell: Int?
  /// The free layout when the current drag started, so each drag step is applied to the same start.
  @ObservationIgnored private var editStart: FreeCollageLayout?
  /// The picture and its placement when the pan started.
  @ObservationIgnored private var panStart: (index: Int, placement: CollagePhotoPlacement)?
  /// The divider being dragged, with the cells it started from.
  @ObservationIgnored private var dividerStart: (divider: CollageDivider, cells: [[CGPoint]])?

  init() {
    syncComposition()
  }

  /// The templates that take the chosen pictures at the current canvas size and gaps, in order.
  var availableTemplates: [CollageTemplate] {
    composition.availableTemplates
  }

  /// Loads the chosen pictures. Pictures that cannot be decoded are counted, not kept.
  func load(_ items: [PhotosPickerItem]) async {
    isLoading = true
    let loaded = await PhotoLoader.load(items)
    pictures = loaded
    failedCount = items.count - loaded.count
    isLoading = false
    errorMessage = nil
    composition.setPictureSizes(
      loaded.map { CGSize(width: CGFloat($0.image.width), height: CGFloat($0.image.height)) })
    selectedCell = nil
    editStart = nil
    panStart = nil
    dividerStart = nil
    changed()
  }

  /// The export size in pixels as text, such as "2000 × 2000". Numbers are not translated.
  var exportTitle: String {
    let size = composition.exportSize
    return "\(size.width) × \(size.height)"
  }

  /// Draws the preview at the design size and the export at its size, and encodes the export as PNG. Runs after a
  /// short pause from the view.
  func refresh() async {
    guard !pictures.isEmpty else {
      exportData = nil
      previewImage = nil
      return
    }
    let sources = pictures
    let composition = self.composition
    let style = self.style
    let size = composition.exportSize
    let rendered = await Task.detached(priority: .userInitiated) { () -> RenderedCollage? in
      let images = sources.map(\.image)
      guard let preview = composition.render(images, style: style),
        let export = composition.render(
          images, style: style, width: size.width, height: size.height),
        let data = ExportEncoding.encode(export, as: .png, source: nil)
      else { return nil }
      return RenderedCollage(preview: preview, data: data)
    }.value
    guard !Task.isCancelled else { return }

    exportData = rendered?.data
    if let rendered { previewImage = rendered.preview }
    errorMessage = rendered == nil ? "The collage could not be drawn." : nil
  }

  // MARK: - Look

  /// The background and the border as the core style. Each cell has its own shape, see `selectedMask`.
  var style: CollageStyle {
    CollageStyle(background: settings.background, border: settings.border)
  }

  // MARK: - Cells

  /// The cell of each picture as a path in fractions of the canvas, so the preview can scale it.
  var cellOutlines: [CGPath] {
    composition.normalisedCellPaths ?? []
  }

  /// The picture indices from the back to the front.
  var drawOrder: [Int] {
    composition.arrangement == .free
      ? (composition.freeLayout?.drawOrder ?? []) : Array(pictures.indices)
  }

  func selectCell(_ index: Int?) {
    guard selectedCell != index else { return }
    selectedCell = index
  }

  /// Moves a free cell by a drag of `translation` points on a preview of `previewSize` points. Every call of one
  /// drag applies the whole translation so far to the layout the drag started from.
  func dragCell(_ index: Int, translation: CGSize, previewSize: CGSize) {
    guard
      let delta = composition.freeLayoutDelta(
        previewTranslation: translation, previewSize: previewSize),
      let start = editStart ?? composition.freeLayout
    else { return }
    editStart = start
    updateFreeLayout(start.moving(index, by: delta))
  }

  /// Resizes a free cell by dragging one of its corners. Works like `dragCell`.
  func dragCorner(
    _ index: Int, handle: FreeCollageLayout.Handle, translation: CGSize, previewSize: CGSize
  ) {
    guard
      let delta = composition.freeLayoutDelta(
        previewTranslation: translation, previewSize: previewSize),
      let start = editStart ?? composition.freeLayout
    else { return }
    editStart = start
    updateFreeLayout(start.resizing(index, handle: handle, by: delta))
  }

  /// Pans picture `index` by a drag of `translation` points on a preview of `previewSize` points. Like `dragCell`,
  /// every step applies the whole drag to the placement the drag started from.
  func panPicture(_ index: Int, translation: CGSize, previewSize: CGSize) {
    guard composition.placements.indices.contains(index) else { return }
    if panStart?.index != index {
      panStart = (index, composition.placements[index])
    }
    guard let start = panStart?.placement,
      let placement = composition.placement(
        panning: start, at: index, previewTranslation: translation, previewSize: previewSize),
      placement != composition.placements[index]
    else { return }
    composition.setPlacement(placement, at: index)
    changed()
  }

  /// Ends the drag, so the next drag starts from the layout and placement as they are now.
  func endDrag() {
    editStart = nil
    panStart = nil
  }

  func bringSelectedToFront() {
    guard let selectedCell, let layout = composition.freeLayout else { return }
    composition.freeLayout = layout.bringingToFront(selectedCell)
    changed()
  }

  func sendSelectedToBack() {
    guard let selectedCell, let layout = composition.freeLayout else { return }
    composition.freeLayout = layout.sendingToBack(selectedCell)
    changed()
  }

  /// Puts the free cells back in a grid.
  func resetFreeLayout() {
    composition.resetFreeLayout()
    selectedCell = nil
    editStart = nil
    changed()
  }

  // MARK: - Dividers

  /// The dividers that can be dragged in the template arrangement.
  var dividers: [CollageDivider] {
    composition.dividers
  }

  /// Where a divider lies on the preview, as fractions of the canvas.
  func dividerLine(_ divider: CollageDivider) -> (start: CGPoint, end: CGPoint) {
    composition.dividerLine(divider)
  }

  /// Whether a divider has been moved, so the template is not as it was made.
  var hasMovedDividers: Bool {
    composition.customCells != nil
  }

  /// Moves a divider by a drag of `translation` points on a preview of `previewSize` points. Like `dragCell`, every step
  /// applies the whole drag to the cells the drag started from.
  func dragDivider(_ divider: CollageDivider, translation: CGSize, previewSize: CGSize) {
    if dividerStart == nil {
      guard let cells = composition.unitCells else { return }
      dividerStart = (divider, cells)
    }
    guard let start = dividerStart,
      let delta = composition.dividerDelta(
        previewTranslation: translation, previewSize: previewSize,
        orientation: start.divider.orientation),
      let moved = CollageDividers.moving(
        start.divider, to: start.divider.position + delta, in: start.cells),
      moved != composition.unitCells
    else { return }
    composition.setUnitCells(moved)
    changed()
  }

  /// Ends the drag of a divider, so the next one starts from the cells as they are now.
  func endDividerDrag() {
    dividerStart = nil
  }

  /// Puts the template back as it was made, undoing the moved dividers.
  func resetDividers() {
    composition.resetDividers()
    dividerStart = nil
    changed()
  }

  // MARK: - Pictures in cells

  /// The placement of the selected picture: the aspect fill when nothing is selected.
  var selectedPlacement: CollagePhotoPlacement {
    guard let selectedCell, composition.placements.indices.contains(selectedCell) else {
      return .identity
    }
    return composition.placements[selectedCell]
  }

  /// The turn of the selected picture in degrees, clockwise on the screen.
  var selectedRotation: Double {
    Double(selectedPlacement.rotation) * 180 / .pi
  }

  /// The shape of the selected cell. Without a selection it is the plain cell.
  var selectedMask: CollageMask {
    guard let selectedCell, composition.masks.indices.contains(selectedCell) else { return .none }
    return composition.masks[selectedCell]
  }

  /// The pictures other than the selected one, for the swap menu.
  var otherPictureIndices: [Int] {
    guard let selectedCell else { return [] }
    return pictures.indices.filter { $0 != selectedCell }
  }

  /// Zooms the selected picture. The zoom is limited to the range of `CollagePhotoPlacement`.
  func setSelectedZoom(_ zoom: Double) {
    editSelected { $0.zoomed(to: CGFloat(zoom)) }
  }

  /// Moves the selected picture along one or both axes, in the range -1 to 1. A nil value keeps that axis.
  func setSelectedOffset(x: Double? = nil, y: Double? = nil) {
    editSelected { placement in
      placement.positioned(
        at: CGVector(
          dx: x.map { CGFloat($0) } ?? placement.offset.dx,
          dy: y.map { CGFloat($0) } ?? placement.offset.dy))
    }
  }

  /// Turns the selected picture to `degrees`, clockwise on the screen.
  func setSelectedRotation(_ degrees: Double) {
    editSelected { $0.rotated(to: CGFloat(degrees) * .pi / 180) }
  }

  /// Puts the selected picture back to the aspect fill, unturned.
  func resetSelectedPlacement() {
    editSelected { _ in .identity }
  }

  /// Swaps the selected picture with picture `other`, with its zoom, pan, turn and cell shape. The cells stay where
  /// they are.
  func swapSelected(with other: Int) {
    guard let selectedCell, pictures.indices.contains(other) else { return }
    pictures.swapAt(selectedCell, other)
    composition.swapPictures(selectedCell, other)
    changed()
  }

  /// Gives the selected cell another shape. Its corner radius is kept.
  func setSelectedShape(_ shape: CollageMask.Shape) {
    editSelectedMask { CollageMask(shape: shape, cornerRadius: $0.cornerRadius) }
  }

  /// Rounds the corners of the selected cell, where its shape has corners.
  func setSelectedCornerRadius(_ radius: Double) {
    editSelectedMask { CollageMask(shape: $0.shape, cornerRadius: radius) }
  }

  /// Gives every cell the shape of the selected one.
  func applySelectedShapeToAll() {
    guard selectedCell != nil else { return }
    composition.setMaskForAll(selectedMask)
    changed()
  }

  // MARK: - Helpers

  /// Keeps an edited free layout. A touch that moved nothing leaves the collage as it is.
  private func updateFreeLayout(_ layout: FreeCollageLayout) {
    guard layout != composition.freeLayout else { return }
    composition.freeLayout = layout
    changed()
  }

  private func editSelected(_ edit: (CollagePhotoPlacement) -> CollagePhotoPlacement) {
    guard let selectedCell, composition.placements.indices.contains(selectedCell) else { return }
    let current = composition.placements[selectedCell]
    let placement = edit(current)
    guard placement != current else { return }
    composition.setPlacement(placement, at: selectedCell)
    changed()
  }

  private func editSelectedMask(_ edit: (CollageMask) -> CollageMask) {
    guard let selectedCell, composition.masks.indices.contains(selectedCell) else { return }
    let current = composition.masks[selectedCell]
    let mask = edit(current)
    guard mask != current else { return }
    composition.setMask(mask, at: selectedCell)
    changed()
  }

  /// Copies the settings that shape the layout and the export into the composition.
  func syncComposition() {
    composition.aspect = settings.aspect
    composition.exportScale = settings.exportScale
    composition.settings.gap = settings.gap
    composition.settings.margin = settings.margin
  }

  func changed() {
    syncComposition()
    exportData = nil
    revision += 1
  }
}
