import CoreGraphics
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// The filter chain as the user edits it, with the preview and the export file made from it.
@MainActor
@Observable
final class FiltersToolModel {
  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// The step whose settings the panel shows, or nil for none.
  var selectedIndex: Int?

  /// Output container. Changing it makes the export stale until `refresh()` runs.
  var format: OutputFormat = .png {
    didSet { changed() }
  }

  /// Lossy quality in 0.1...1. Only JPEG and HEIC use it.
  var quality = 0.9 {
    didSet { changed() }
  }

  private(set) var chain = FilterChain()
  /// Every change of the chain, with undo and redo over it. A step is recorded when a drag ends or
  /// a button is pressed.
  private(set) var history = UndoHistory(FilterChain())

  private(set) var source: LoadedImage?
  /// Smaller copy of the picture for the live preview, so dragging a slider stays responsive.
  @ObservationIgnored private var previewSource: RasterImage?
  private(set) var preview: CGImage?
  private(set) var exportData: Data?
  private(set) var exportFileName = "filters.png"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// The longest side of the live preview, in pixels.
  static let previewSide = 1024.0

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

  /// The selected step, or nil when no step is selected.
  var selectedStep: FilterStep? {
    guard let selectedIndex, chain.steps.indices.contains(selectedIndex) else { return nil }
    return chain.steps[selectedIndex]
  }

  // MARK: - Chain editing

  /// Appends a filter with its default settings, as one undo step.
  func add(_ descriptor: FilterDescriptor) {
    chain.append(FilterStep(id: descriptor.id))
    selectedIndex = chain.steps.count - 1
    commit()
    changed()
  }

  func remove(at index: Int) {
    chain.remove(at: index)
    selectedIndex = nil
    commit()
    changed()
  }

  /// Moves a step one place up or down, as one undo step, and follows it with the selection.
  func move(at index: Int, by offset: Int) {
    let destination = index + offset
    guard chain.steps.indices.contains(destination) else { return }
    chain.move(from: index, to: destination)
    selectedIndex = destination
    commit()
    changed()
  }

  /// Replaces one setting of the selected step while a control is dragged. Recorded by `commit()`.
  func setValue(_ value: FilterValue, forKey key: String) {
    guard let selectedIndex else { return }
    chain.setValue(value, forKey: key, at: selectedIndex)
    changed()
  }

  /// Returns every setting of the selected step to its default, as one undo step.
  func resetSelected() {
    guard let selectedIndex else { return }
    chain.resetValues(at: selectedIndex)
    commit()
    changed()
  }

  // MARK: - Undo and redo

  /// Records the current chain as one undo step. Called when a drag or a button change ends.
  func commit() {
    history.record(chain)
  }

  func undo() {
    guard history.undo() else { return }
    chain = history.current
    selectedIndex = nil
    changed()
  }

  func redo() {
    guard history.redo() else { return }
    chain = history.current
    selectedIndex = nil
    changed()
  }

  // MARK: - Rendering

  /// Runs the chain over one picture. Nil when a step fails or the result cannot be drawn.
  nonisolated static func render(_ picture: RasterImage, chain: FilterChain) async -> CGImage? {
    guard let output = try? await chain.apply(to: picture) else { return nil }
    return output.toCGImage()
  }

  /// Renders the preview from the smaller picture, and the export file from the full picture.
  /// The view calls this after a short pause, so a drag does not start a render per frame.
  func refresh() async {
    guard let source, let previewSource else { return }
    let chain = chain
    let preview = await Self.render(previewSource, chain: chain)
    guard !Task.isCancelled else { return }
    self.preview = preview
    errorMessage = preview == nil ? "The filters could not be applied." : nil

    let format = format
    let quality = quality
    let export = await Task.detached(priority: .userInitiated) { () -> (Data, String)? in
      guard
        let raster = RasterImage(source.image),
        let adjusted = await Self.render(raster, chain: chain),
        let data = ExportEncoding.encode(
          adjusted, as: format, quality: quality, source: source.data)
      else { return nil }
      let name = ExportNaming.fileName(
        stem: "filters", fileExtension: format.fileExtension, data: data)
      return (data, name)
    }.value
    guard !Task.isCancelled else { return }
    if let export {
      exportData = export.0
      exportFileName = export.1
    } else {
      exportData = nil
      errorMessage = "The image could not be encoded as \(format.fileExtension.uppercased())."
    }
  }

  // MARK: - Batch

  /// Applies the chain to one picture of a batch. The batch uses the chain the tool has when it starts.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item,
    chain: FilterChain,
    format: OutputFormat,
    quality: Double,
    keepMetadata: Bool,
    encoder: any ImageEncoding
  ) async -> BatchFile? {
    guard
      let raster = RasterImage(item.picture.image),
      let adjusted = await render(raster, chain: chain),
      let data = encoder.encode(
        adjusted, as: format, quality: quality,
        metadataSource: keepMetadata ? item.picture.data : nil)
    else { return nil }
    let fileName = ExportNaming.fileName(
      stem: "filters-\(item.index + 1)", fileExtension: format.fileExtension, data: data)
    return BatchFile(fileName: fileName, data: data)
  }

  // MARK: - Loading

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }

    let side = Self.previewSide
    let small = await Task.detached(priority: .userInitiated) { () -> RasterImage? in
      let largest = Double(max(loaded.image.width, loaded.image.height))
      let scale = min(1, side / largest)
      let width = max(1, Int(Double(loaded.image.width) * scale))
      let height = max(1, Int(Double(loaded.image.height) * scale))
      let resized = ImageGeometry.resize(loaded.image, width: width, height: height)
      return resized.flatMap { RasterImage($0) }
    }.value

    source = loaded
    previewSource = small
    chain = FilterChain()
    selectedIndex = nil
    history = UndoHistory(FilterChain())
    errorMessage = nil
    changed()
  }

  private func changed() {
    exportData = nil
    revision += 1
  }
}
