import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class FormatConversionToolModel {
  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// The format the picture is converted to. Only available targets can be chosen.
  var target = ConversionTarget.png {
    didSet { changed() }
  }

  /// Lossy quality in 0.1...1. Only the lossy containers use it.
  var quality = 0.9 {
    didSet { changed() }
  }

  private(set) var source: LoadedImage?
  private(set) var exportData: Data?
  private(set) var exportFileName = "converted.png"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// Converts one picture of a batch to the target, with the metadata when the settings keep it.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item,
    target: ConversionTarget,
    quality: Double,
    keepMetadata: Bool
  ) -> BatchFile? {
    let metadata =
      keepMetadata ? ImageMetadataTools.carriedProperties(from: item.picture.data) : [:]
    guard
      let data = try? FormatConverter.convert(
        item.picture.image, to: target, quality: quality, metadata: metadata)
    else { return nil }
    let fileName = ExportNaming.fileName(
      stem: "converted-\(item.index + 1)", fileExtension: target.fileExtension, data: data)
    return BatchFile(fileName: fileName, data: data)
  }

  /// Converts the picture to the current target. Runs after a short pause from the view.
  func refresh() async {
    guard let source else { return }
    let target = target
    let quality = quality
    let keepMetadata = AppSettings.load(from: .standard).keepMetadata
    let sourceData = source.data
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<Data, FormatConverter.Failure> in
      let metadata = keepMetadata ? ImageMetadataTools.carriedProperties(from: sourceData) : [:]
      do {
        return .success(
          try FormatConverter.convert(
            source.image, to: target, quality: quality, metadata: metadata))
      } catch let failure as FormatConverter.Failure {
        return .failure(failure)
      } catch {
        return .failure(.encodingFailed)
      }
    }.value
    guard !Task.isCancelled else { return }

    switch result {
    case .success(let data):
      exportData = data
      exportFileName = ExportNaming.fileName(
        stem: "converted", fileExtension: target.fileExtension, data: data)
      errorMessage = nil
    case .failure(let failure):
      exportData = nil
      errorMessage = Self.message(for: failure, target: target)
    }
  }

  private static func message(
    for failure: FormatConverter.Failure, target: ConversionTarget
  ) -> LocalizedStringKey {
    switch failure {
    case .unavailable: "This format cannot be written on this device."
    case .tooLarge: "The file is larger than this format allows."
    case .encodingFailed: "The image could not be encoded as \(target.fileExtension.uppercased())."
    }
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
