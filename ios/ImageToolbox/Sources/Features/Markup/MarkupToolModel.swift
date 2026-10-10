import CoreGraphics
import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// What a drag on the markup canvas does.
enum MarkupInteraction: Sendable {
  /// A tap selects the topmost visible layer under the finger.
  case select
  /// A drag adds a brush stroke.
  case stroke
}

/// Which picker a picture comes from. A sticker is a small cut-out, and an image is a photo.
enum MarkupPictureKind: Sendable {
  case sticker
  case image

  /// Longest side in pixels that the picture is scaled to before it is stored.
  var maxSide: Int {
    switch self {
    case .sticker: 1024
    case .image: 2048
    }
  }
}

/// Holds the markup tool's state: the base picture, the layer stack with undo and redo, the selected
/// layer and the rendered result.
@MainActor
@Observable
final class MarkupToolModel {
  /// Colour of every new layer.
  nonisolated static let ink = MarkupColour(red: 0.92, green: 0.16, blue: 0.2)

  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// The file picked as a sticker. It is cleared after each pick, so the same file can be picked again.
  var stickerSelection: PhotosPickerItem? {
    didSet {
      guard let item = stickerSelection else { return }
      stickerSelection = nil
      startPicture(item, as: .sticker)
    }
  }

  /// The file picked as an image layer. It is cleared after each pick, like `stickerSelection`.
  var imageSelection: PhotosPickerItem? {
    didSet {
      guard let item = imageSelection else { return }
      imageSelection = nil
      startPicture(item, as: .image)
    }
  }

  /// The text that the Text button adds.
  var textDraft = ""

  /// Whether a drag selects layers or draws strokes.
  var interaction = MarkupInteraction.select

  /// Whether new shapes are filled. An unfilled shape is drawn as an outline.
  var shapeFilled = false

  private(set) var source: LoadedImage?
  /// The layers over the picture. It matches `history.current`, except during a slider drag.
  private(set) var document = MarkupDocument()
  /// Undo and redo over the committed documents.
  private var history = UndoHistory(MarkupDocument())
  /// Index of the selected layer in `document.layers`, or nil.
  private(set) var selectedLayer: Int?
  /// Points of the stroke under the finger, in picture pixels. They join the document when the drag ends.
  private(set) var pendingStroke: [CGPoint] = []
  /// The picture with every visible layer drawn over it.
  private(set) var preview: CGImage?
  private(set) var exportData: Data?
  private(set) var exportFileName = "markup.png"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change to the picture. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var pictureTask: Task<Void, Never>?
  /// Layers added to the current picture. It keeps layer names unique after a layer is removed.
  @ObservationIgnored private var layerCount = 0
  /// The document before the drag under way in select mode, or nil between drags. The drag moves the
  /// selected layer from this document, so that the offset is never added up twice.
  @ObservationIgnored private var dragBase: MarkupDocument?

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

  /// Whether the Text button has text to add.
  var hasTextDraft: Bool {
    !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Size of the base picture in pixels, or nil before a picture is loaded.
  var baseSize: CGSize? {
    source.map { CGSize(width: $0.image.width, height: $0.image.height) }
  }

  /// The picture on screen: the render, or the base picture until the first render is ready.
  var displayImage: CGImage? {
    preview ?? source?.image
  }

  /// The selected layer, or nil when no layer is selected.
  var selectedLayerValue: MarkupLayer? {
    guard let selectedLayer, document.layers.indices.contains(selectedLayer) else { return nil }
    return document.layers[selectedLayer]
  }

  /// Opacity of the selected layer, or 1 when no layer is selected.
  var selectedOpacity: Double {
    selectedLayerValue?.opacity ?? 1
  }

  /// The brush for strokes on this picture. Its radius follows the shorter side.
  var brush: Brush? {
    baseSize.map { Brush(radius: MarkupLayerDefaults.brushRadius(for: $0)) }
  }

  // MARK: - Adding layers

  /// Adds a text layer near the top-left corner. Text that is blank adds nothing.
  func addText(_ string: String) {
    guard let baseSize, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    addLayer(
      named: String(localized: "Text"),
      content: MarkupLayerDefaults.text(string, canvas: baseSize, colour: Self.ink))
  }

  /// Adds a shape in the middle of the picture, filled or outlined as `shapeFilled` says.
  func addShape(_ kind: MarkupLayer.Content.ShapeKind) {
    guard let baseSize else { return }
    addLayer(
      named: Self.shapeName(kind),
      content: MarkupLayerDefaults.shape(
        kind, canvas: baseSize, colour: Self.ink, filled: shapeFilled))
  }

  /// Adds a sticker or an image in the middle of the picture, scaled by its kind.
  func addPicture(_ raster: RasterImage, as kind: MarkupPictureKind) {
    guard let baseSize, raster.width > 0, raster.height > 0 else { return }
    let size = CGSize(width: raster.width, height: raster.height)
    switch kind {
    case .sticker:
      addLayer(
        named: String(localized: "Sticker"),
        content: .sticker(
          raster: raster, frame: MarkupLayerDefaults.stickerFrame(for: size, canvas: baseSize)))
    case .image:
      addLayer(
        named: String(localized: "Image"),
        content: .image(
          raster: raster, frame: MarkupLayerDefaults.imageFrame(for: size, canvas: baseSize)))
    }
  }

  /// Adds a brush stroke through `points`, in picture pixels.
  func addStroke(_ points: [CGPoint]) {
    guard let brush, !points.isEmpty else { return }
    addLayer(
      named: String(localized: "Stroke"),
      content: .stroke(points: points, brush: brush, colour: Self.ink))
  }

  /// Adds a point to the stroke under the finger. The first point starts the stroke.
  func continueStroke(at point: CGPoint) {
    guard let baseSize else { return }
    pendingStroke.append(clamped(point, to: baseSize))
  }

  /// Ends the stroke under the finger and adds it as a layer.
  func endStroke() {
    let points = pendingStroke
    pendingStroke = []
    addStroke(points)
  }

  // MARK: - Selection

  /// Selects the topmost visible layer under `point`, or clears the selection when none is there.
  func select(at point: CGPoint, tolerance: Double) {
    selectedLayer = document.layerIndex(at: point, tolerance: tolerance)
  }

  /// Selects the layer at `index`, as chosen in the layer list.
  func selectLayer(at index: Int) {
    guard document.layers.indices.contains(index) else { return }
    selectedLayer = index
  }

  /// Handles one change of a drag in select mode. The first change selects the topmost visible layer
  /// under `start`. The selected layer then follows the finger: it moves by the offset from `start` to
  /// `point`, which is previewed until `endMove()`. A locked layer does not move.
  func dragSelected(from start: CGPoint, to point: CGPoint, tolerance: Double) {
    if dragBase == nil {
      select(at: start, tolerance: tolerance)
      dragBase = document
    }
    guard let dragBase, let selectedLayer else { return }
    let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
    document = dragBase.updating(at: selectedLayer) { $0 = $0.translated(by: offset) }
    changed()
  }

  /// Ends a drag in select mode. A move that changed the layer becomes one undo step, and a tap that
  /// only selected a layer records nothing.
  func endMove() {
    guard let dragBase else { return }
    self.dragBase = nil
    guard document != dragBase else { return }
    syncHistory()
  }

  // MARK: - Editing the selected layer

  /// Removes the selected layer as one undo step. A locked layer stays.
  func removeSelected() {
    guard let selectedLayer else { return }
    commit(document.remove(at: selectedLayer))
    self.selectedLayer = nil
  }

  /// Shows or hides the selected layer as one undo step.
  func toggleSelectedVisibility() {
    guard let selectedLayer, let layer = selectedLayerValue else { return }
    commit(document.setVisible(!layer.isVisible, at: selectedLayer))
  }

  /// Locks or unlocks the selected layer as one undo step. Locking is the one change that a locked
  /// layer accepts.
  func toggleSelectedLock() {
    guard let selectedLayer, let layer = selectedLayerValue else { return }
    commit(document.setLocked(!layer.isLocked, at: selectedLayer))
  }

  /// Moves the selected layer by `offset` places in the stack. A positive offset moves it towards
  /// the front, so it is drawn later.
  func moveSelected(by offset: Int) {
    guard let index = selectedLayer else { return }
    let destination = index + offset
    if commit(document.move(from: index, to: destination)) {
      selectedLayer = destination
    }
  }

  /// Applies `change` to the selected layer as one undo step. A locked layer is left as it is.
  func changeSelected(_ change: (inout MarkupLayer) -> Void) {
    guard let selectedLayer else { return }
    commit(document.updating(at: selectedLayer, change))
  }

  /// Applies `change` to the selected layer while a slider moves. It becomes an undo step when
  /// `finishSliderEdit()` is called.
  func previewSelected(_ change: (inout MarkupLayer) -> Void) {
    guard let selectedLayer else { return }
    document = document.updating(at: selectedLayer, change)
    changed()
  }

  /// Records what a slider drag left, as one undo step.
  func finishSliderEdit() {
    syncHistory()
  }

  // MARK: - Undo and redo

  func undo() {
    syncHistory()
    guard history.undo() else { return }
    restoreFromHistory()
  }

  func redo() {
    syncHistory()
    guard history.redo() else { return }
    restoreFromHistory()
  }

  // MARK: - Rendering and export

  /// Draws every visible layer over the picture and encodes the result as PNG. Runs after a short
  /// pause from the view.
  func refresh() async {
    guard let source else { return }
    let document = document
    let rendered = await Task.detached(priority: .userInitiated) { () -> (CGImage, Data)? in
      guard
        let image = MarkupRenderer.render(base: source.image, document: document),
        let data = ExportEncoding.encode(image, as: .png, source: nil)
      else { return nil }
      return (image, data)
    }.value
    guard !Task.isCancelled else { return }

    guard let rendered else {
      preview = nil
      exportData = nil
      errorMessage = "The image could not be encoded as PNG."
      return
    }
    preview = rendered.0
    exportData = rendered.1
    exportFileName = ExportNaming.fileName(stem: "markup", fileExtension: "png", data: rendered.1)
    errorMessage = nil
  }

  // MARK: - Loading

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    // Layers are placed in the pixels of one picture, so a new picture starts with no layers.
    source = loaded
    document = MarkupDocument()
    history = UndoHistory(MarkupDocument())
    selectedLayer = nil
    pendingStroke = []
    preview = nil
    layerCount = 0
    errorMessage = nil
    changed()
  }

  private func startPicture(_ item: PhotosPickerItem, as kind: MarkupPictureKind) {
    pictureTask?.cancel()
    pictureTask = Task { await loadPicture(item, as: kind) }
  }

  private func loadPicture(_ item: PhotosPickerItem, as kind: MarkupPictureKind) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    let raster = await Task.detached(priority: .userInitiated) { () -> RasterImage? in
      MarkupLayerDefaults.raster(from: loaded.image, maxSide: kind.maxSide)
    }.value
    guard !Task.isCancelled else { return }
    guard let raster else {
      errorMessage = "Could not read this photo."
      return
    }
    errorMessage = nil
    addPicture(raster, as: kind)
  }

  // MARK: - Helpers

  /// Adds `content` on top of the stack as a new layer, and selects it.
  private func addLayer(named base: String, content: MarkupLayer.Content) {
    layerCount += 1
    let layer = MarkupLayer(name: "\(base) \(layerCount)", content: content)
    guard commit(document.add(layer)) else { return }
    selectedLayer = document.layers.count - 1
  }

  /// Makes `next` the current document and records it as one undo step. Returns false when nothing
  /// changed.
  @discardableResult
  private func commit(_ next: MarkupDocument) -> Bool {
    guard next != document else { return false }
    document = next
    history.record(next)
    changed()
    return true
  }

  /// Records a change that was made without `commit`, such as a slider drag, so that undo sees it.
  private func syncHistory() {
    history.record(document)
  }

  /// Takes the document from history after an undo or redo. The selection is cleared, because its
  /// index may now point at another layer.
  private func restoreFromHistory() {
    document = history.current
    selectedLayer = nil
    changed()
  }

  private func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
    CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
  }

  /// Layer name of a shape kind, shown in the layer list.
  static func shapeName(_ kind: MarkupLayer.Content.ShapeKind) -> String {
    switch kind {
    case .rectangle: String(localized: "Rectangle")
    case .ellipse: String(localized: "Ellipse")
    case .line: String(localized: "Line")
    case .arrow: String(localized: "Arrow")
    case .doubleArrow: String(localized: "Double arrow")
    case .lineArrow: String(localized: "Line arrow")
    case .doubleLineArrow: String(localized: "Double line arrow")
    case .triangle: String(localized: "Triangle")
    case .polygon: String(localized: "Polygon")
    case .star: String(localized: "Star")
    }
  }

  private func changed() {
    exportData = nil
    revision += 1
  }
}
