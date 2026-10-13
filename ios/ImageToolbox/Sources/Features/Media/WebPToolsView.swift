import ImageToolboxKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WebPToolsView: View {
  @State private var model = WebPToolsModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @Environment(\.services) private var services
  @State private var isImporting = false

  var body: some View {
    ToolScaffold(identifier: "webpTools") {
      GlassSection {
        Text(
          "This screen reads WebP and saves the picture as PNG, JPEG, HEIC or WebP. WebP is encoded with libwebp."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)

        Button("Choose WebP") { isImporting = true }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("webpTools.choose")
      }

      if let source = model.source {
        BatchSection(identifier: "webp", model: batch, pickedItems: $batchItems) {
          let format = model.format
          let quality = model.quality
          let keepMetadata = AppSettings.load(from: .standard).keepMetadata
          let encoder = services.encoder
          return { item in
            WebPToolsModel.batchFile(
              item, format: format, quality: quality, keepMetadata: keepMetadata, encoder: encoder)
          }
        }

        GlassSection("Output") {
          PictureView(image: source)
          HStack {
            Button("Undo") { model.undo() }
              .buttonStyle(.glass)
              .disabled(!model.canUndo)
              .accessibilityIdentifier("webp.undo")
            Button("Redo") { model.redo() }
              .buttonStyle(.glass)
              .disabled(!model.canRedo)
              .accessibilityIdentifier("webp.redo")
          }
          OutputFormatPicker(selection: $model.format)
            .onChange(of: model.format) { _, _ in model.commitParameters() }
          if model.format.isLossy {
            ParameterSlider(
              title: "Quality",
              value: $model.quality, onEditingEnded: model.commitParameters,
              range: 0.1...1,
              step: 0.05,
              format: "%.2f"
            )
          }
          if let encoded = model.encoded {
            ShareFileButton(title: "Share file", data: encoded, fileName: model.fileName)
              .accessibilityIdentifier("webpTools.share")
          }
        }
      }

      if let message = model.errorMessage {
        ErrorText(message: message)
      }
    }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.webP, .image],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await model.open(url) }
    }
  }
}
