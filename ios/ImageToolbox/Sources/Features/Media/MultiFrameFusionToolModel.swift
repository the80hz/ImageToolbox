import CoreGraphics
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// The fused picture and the file it is exported as.
struct FusionPreview: Sendable {
  let image: CGImage
  let data: Data
  let fileName: String
}

@MainActor
@Observable
final class MultiFrameFusionToolModel {

  /// Settings that the undo history keeps. A step is recorded when a slider drag ends or a mode
  /// changes.
  private(set) var history = UndoHistory(FusionParams())

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

  var params = FusionParams() {
    didSet { changed() }
  }

  private(set) var frames: [LoadedImage] = []
  private(set) var failedCount = 0
  private(set) var isLoading = false
  private(set) var isFusing = false
  private(set) var preview: FusionPreview?
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0

  func commit() {
    history.record(params)
  }

  func undo() {
    guard history.undo() else { return }
    params = history.current
  }

  func redo() {
    guard history.redo() else { return }
    params = history.current
  }

  func load(_ items: [PhotosPickerItem]) async {
    isLoading = true
    let loaded = await PhotoLoader.load(items)
    frames = loaded
    failedCount = items.count - loaded.count
    isLoading = false
    changed()
  }

  /// Aligns and fuses the frames with the current settings, then encodes the result. Runs off the
  /// main actor, and a result from an older run is dropped.
  func refresh() async {
    guard frames.count >= FusionParams.minimumImages else {
      preview = nil
      errorMessage = nil
      isFusing = false
      return
    }
    let frames = frames
    let params = params
    isFusing = true
    let result = await Task.detached(priority: .userInitiated) { () -> FusionPreview? in
      let images = frames.map(\.image)
      let aligned: [RasterImage]?
      if params.alignImages {
        aligned = FrameAlignment.align(images, cropToOverlap: params.cropToOverlap)
      } else {
        aligned = images.compactMap { RasterImage($0) }
      }
      guard
        let aligned,
        let fused = FrameFusion.fuse(aligned, params: params),
        let image = fused.toCGImage(),
        let data = ExportEncoding.encode(image, as: .png, source: frames.first?.data)
      else { return nil }
      let fileName = ExportNaming.fileName(stem: "fused", fileExtension: "png", data: data)
      return FusionPreview(image: image, data: data, fileName: fileName)
    }.value
    isFusing = false
    guard !Task.isCancelled else { return }

    preview = result
    errorMessage =
      result == nil
      ? "The frames could not be fused. They must overlap and have the same size." : nil
  }

  private func changed() {
    preview = nil
    revision += 1
  }
}
