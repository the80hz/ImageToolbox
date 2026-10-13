import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class SVGTraceToolModel {
  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// Number of colours the picture is reduced to, from 1 to 16.
  var colours = 8 {
    didSet { changed() }
  }

  /// Smooths the outlines into Bézier curves. When off, the outlines follow the pixel edges.
  var smoothCurves = true {
    didSet { changed() }
  }

  private(set) var source: LoadedImage?
  private(set) var exportData: Data?
  private(set) var exportFileName = "traced.svg"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// Traces the picture with the current number of colours, on a background thread.
  func refresh() async {
    guard let source else { return }
    let image = source.image
    let colours = colours
    let smooth = smoothCurves
    let data = await Task.detached(priority: .userInitiated) { () -> Data? in
      guard let raster = RasterImage(image) else { return nil }
      let svg =
        smooth
        ? SmoothTracer.svg(for: raster, colours: colours)
        : PixelTracer.svg(for: raster, colours: colours)
      return Data(svg.utf8)
    }.value
    guard !Task.isCancelled else { return }

    guard let data else {
      exportData = nil
      errorMessage = "The picture could not be traced."
      return
    }
    exportData = data
    exportFileName = ExportNaming.fileName(stem: "traced", fileExtension: "svg", data: data)
    errorMessage = nil
  }

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    source = loaded
    errorMessage = nil
    changed()
  }

  private func changed() {
    exportData = nil
    revision += 1
  }
}
