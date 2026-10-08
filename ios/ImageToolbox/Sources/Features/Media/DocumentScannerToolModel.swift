import CoreGraphics
import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

private enum DocumentScanResult: Sendable {
  case corrected(PNGPicture)
  case noDocument
  case failed
}

@MainActor
@Observable
final class DocumentScannerToolModel {
  var pickedItem: PhotosPickerItem?
  private(set) var original: CGImage?
  private(set) var corrected: PNGPicture?
  private(set) var correctedFileName = "scan.png"
  private(set) var errorMessage: LocalizedStringKey?

  /// Finds the document in the photo and flattens it. The work runs off the main actor.
  /// Flattens the document in one picture of a batch. A picture without a detected page is kept as it is.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item, keepMetadata: Bool, encoder: any ImageEncoding
  ) -> BatchFile? {
    let image = item.picture.image
    let corrected =
      DocumentScanner.detectDocument(in: image).flatMap { DocumentScanner.correct(image, quad: $0) }
      ?? image
    guard
      let data = encoder.encode(
        corrected, as: .png, quality: 0.9,
        metadataSource: keepMetadata ? item.picture.data : nil)
    else { return nil }
    return BatchFile(fileName: "scan-\(item.index + 1).png", data: data)
  }

  func scan(_ item: PhotosPickerItem) async {
    corrected = nil
    errorMessage = nil
    guard let loaded = await PhotoLoader.load(item) else {
      original = nil
      errorMessage = "Could not read this photo."
      return
    }
    let image = loaded.image
    let sourceData = loaded.data
    original = image

    let result = await Task.detached(priority: .userInitiated) { () -> DocumentScanResult in
      guard let quad = DocumentScanner.detectDocument(in: image) else { return .noDocument }
      guard let flattened = DocumentScanner.correct(image, quad: quad),
        let picture = PNGPicture(flattened, metadataSource: sourceData)
      else { return .failed }
      return .corrected(picture)
    }.value

    switch result {
    case .corrected(let picture):
      corrected = picture
      correctedFileName = ExportNaming.fileName(
        stem: "scan", fileExtension: "png", data: picture.png)
    case .noDocument:
      errorMessage = "No document found"
    case .failed:
      errorMessage = "Could not correct the perspective."
    }
  }
}
