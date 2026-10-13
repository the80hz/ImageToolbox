import CoreGraphics
import Foundation
import ImageToolboxKit
import Observation
import SwiftUI

@MainActor
@Observable
final class WebPToolsModel {

  /// Settings that the encoding uses. A step is recorded when a slider drag ends or the format changes.
  struct Parameters: Equatable, Sendable {
    var format: OutputFormat
    var quality: Double
  }

  private(set) var history = UndoHistory(Parameters(format: .webp, quality: 0.85))

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

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
    Parameters(format: format, quality: quality)
  }

  /// Encodes one picture of a batch in the chosen format.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item,
    format: OutputFormat,
    quality: Double,
    keepMetadata: Bool,
    encoder: any ImageEncoding
  ) -> BatchFile? {
    guard
      let data = encoder.encode(
        item.picture.image, as: format, quality: quality,
        metadataSource: keepMetadata ? item.picture.data : nil)
    else { return nil }
    let fileName = ExportNaming.fileName(
      stem: "converted-\(item.index + 1)", fileExtension: format.fileExtension, data: data)
    return BatchFile(fileName: fileName, data: data)
  }

  private func restoreParameters(_ parameters: Parameters) {
    format = parameters.format
    quality = parameters.quality
  }
  private(set) var source: CGImage?
  /// The picked file as it was read. Its metadata is copied into the output when the settings ask.
  @ObservationIgnored private var sourceData: Data?
  private(set) var encoded: Data?
  private(set) var errorMessage: LocalizedStringKey?

  var format: OutputFormat = .webp {
    didSet { refreshEncoding() }
  }

  var quality: Double = 0.85 {
    didSet { refreshEncoding() }
  }

  private(set) var fileName = "converted.png"

  /// Decodes the first frame of a WebP file (or any other picked image).
  func open(_ url: URL) async {
    source = nil
    sourceData = nil
    encoded = nil
    errorMessage = nil
    let decoded = await Task.detached(priority: .userInitiated) {
      () -> (image: CGImage, data: Data)? in
      guard let data = MediaFiles.read(url), let image = ImageCodec.decode(data) else { return nil }
      return (image, data)
    }.value

    guard let decoded else {
      errorMessage = "This file could not be decoded as WebP."
      return
    }
    source = decoded.image
    sourceData = decoded.data
    refreshEncoding()
  }

  private func refreshEncoding() {
    guard let source else { return }
    encoded = ExportEncoding.encode(source, as: format, quality: quality, source: sourceData)
    fileName =
      encoded.map {
        ExportNaming.fileName(stem: "converted", fileExtension: format.fileExtension, data: $0)
      }
      ?? "converted.\(format.fileExtension)"
    if encoded == nil {
      errorMessage = "The image could not be encoded as \(format.fileExtension.uppercased())."
    } else {
      errorMessage = nil
    }
  }
}
