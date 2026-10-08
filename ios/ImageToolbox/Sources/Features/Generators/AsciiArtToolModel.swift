import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class AsciiArtToolModel {

  /// Settings that the undo history keeps. A step is recorded when a slider drag ends, a choice
  /// changes, or the operation starts.
  struct Parameters: Equatable, Sendable {
    var columns: Double
    var invert: Bool
  }

  private(set) var history = UndoHistory(Parameters(columns: 80, invert: false))

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

  /// Renders one picture of a batch as ASCII art text with the settings the tool has when it starts.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item, columns: Double, invert: Bool
  ) -> BatchFile? {
    guard let raster = RasterImage(item.picture.image) else { return nil }
    let text = AsciiArt.render(raster, columns: Int(columns.rounded()), invert: invert)
    return BatchFile(fileName: "ascii-\(item.index + 1).txt", data: Data(text.utf8))
  }

  func commitParameters() {
    history.record(currentParameters)
  }

  func undo() {
    guard history.undo() else { return }
    restoreParameters(history.current)
  }

  func redo() {
    guard history.redo() else { return }
    restoreParameters(history.current)
  }

  private var currentParameters: Parameters {
    Parameters(columns: columns, invert: invert)
  }

  private func restoreParameters(_ parameters: Parameters) {
    columns = parameters.columns
    invert = parameters.invert
  }
  var columns: Double = 80
  var invert = false

  private(set) var text = ""
  private(set) var failed = false

  @ObservationIgnored private var source: RasterImage?
  @ObservationIgnored private var renderTask: Task<Void, Never>?

  func load(_ item: PhotosPickerItem) async {
    guard let loaded = await PhotoLoader.load(item) else {
      failed = true
      return
    }
    let decoded = await Task.detached(priority: .userInitiated) {
      RasterImage(loaded.image)
    }.value
    guard let raster = decoded else {
      failed = true
      return
    }
    failed = false
    source = raster
    refresh()
  }

  /// Re-renders the text for the current settings. A newer call cancels the one still pending.
  func refresh() {
    renderTask?.cancel()
    guard let source else { return }
    let columnCount = Int(columns.rounded())
    let inverted = invert
    renderTask = Task {
      let rendered = await Task.detached(priority: .userInitiated) {
        AsciiArt.render(source, columns: columnCount, invert: inverted)
      }.value
      guard !Task.isCancelled else { return }
      self.text = rendered
    }
  }
}
