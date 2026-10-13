import ImageToolboxKit
import PhotosUI
import SwiftUI

struct DocumentScannerToolView: View {
  @State private var model = DocumentScannerToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @Environment(\.services) private var services

  var body: some View {
    ToolScaffold(identifier: "documentScanner") {
      BatchSection(identifier: "scanner", model: batch, pickedItems: $batchItems) {
        let keepMetadata = AppSettings.load(from: .standard).keepMetadata
        let encoder = services.encoder
        return { item in
          DocumentScannerToolModel.batchFile(item, keepMetadata: keepMetadata, encoder: encoder)
        }
      }

      GlassSection {
        SinglePhotoButton(title: "Choose document photo", selection: $model.pickedItem)
          .accessibilityIdentifier("documentScanner.choose")

        if let corrected = model.corrected {
          PictureView(image: corrected.image)
          ShareFileButton(
            title: "Share PNG", data: corrected.png, fileName: model.correctedFileName
          )
          .accessibilityIdentifier("documentScanner.share")
        } else if let original = model.original {
          PictureView(image: original)
        }

        if let message = model.errorMessage {
          ErrorText(message: message)
        }
      }
    }
    .onChange(of: model.pickedItem) { _, item in
      guard let item else { return }
      Task { await model.scan(item) }
    }
  }
}
