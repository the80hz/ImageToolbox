import ImageToolboxKit
import PhotosUI
import SwiftUI

struct ImageSplittingToolView: View {
  @State private var model = ImageSplittingToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @Environment(\.services) private var services
  @State private var pickedItem: PhotosPickerItem?

  var body: some View {
    ToolScaffold(identifier: "imageSplitting") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: $pickedItem)
          .accessibilityIdentifier("imageSplitting.pick")
        if let source = model.source {
          PictureView(image: source.image, maxHeight: 240)
        }
      }

      if model.source != nil {
        GlassSection("Split") {
          HStack {
            Button("Undo") { model.undo() }
              .buttonStyle(.glass)
              .disabled(!model.canUndo)
              .accessibilityIdentifier("splitting.undo")
            Button("Redo") { model.redo() }
              .buttonStyle(.glass)
              .disabled(!model.canRedo)
              .accessibilityIdentifier("splitting.redo")
          }
          Picker("Direction", selection: $model.axis) {
            Text("Rows").tag(SliceAxis.rows)
            Text("Columns").tag(SliceAxis.columns)
          }
          .pickerStyle(.segmented)
          Stepper("Parts: \(model.parts)", value: $model.parts, in: 2...12)
          Button("Split") {
            model.commitParameters()
            Task { await model.apply() }
          }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("imageSplitting.apply")
        }
      }

      if !model.pieces.isEmpty {
        GlassSection("Batch") {
          MultiPhotoButton(title: "Choose pictures", selection: $batchItems, maxCount: 50)
            .accessibilityIdentifier("imageSplitting.batchPick")
          if !batch.pictures.isEmpty {
            if let progress = batch.progress {
              ProgressView(value: progress.fraction)
              Text("Exporting \(progress.completed) of \(progress.total)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
              Button("Cancel") { batch.cancel() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("imageSplitting.batchCancel")
            } else {
              Button("Split all \(batch.pictures.count) pictures") {
                let parts = model.parts
                let axis = model.axis
                let keepMetadata = AppSettings.load(from: .standard).keepMetadata
                let encoder = services.encoder
                batch.runMany(label: "imageSplitting") { item in
                  ImageSplittingToolModel.batchFiles(
                    item, parts: parts, axis: axis, keepMetadata: keepMetadata, encoder: encoder)
                }
              }
              .buttonStyle(.glassProminent)
              .accessibilityIdentifier("imageSplitting.batchRun")
            }
            if batch.exportFailed {
              ErrorText(message: "The batch stopped because a picture could not be split.")
            }
            if !batch.exports.isEmpty {
              ShareLink(items: batch.exports, preview: { SharePreview($0.fileName) }) {
                Label("Share all \(batch.exports.count) files", systemImage: "square.and.arrow.up")
              }
              .buttonStyle(.glass)
              .accessibilityIdentifier("imageSplitting.batchShare")
            }
          }
        }
        .onChange(of: batchItems) { _, items in
          Task { await batch.load(items) }
        }

        GlassSection("Parts") {
          ForEach(Array(model.pieces.enumerated()), id: \.offset) { index, piece in
            VStack(alignment: .leading, spacing: 8) {
              PictureView(image: piece.image, maxHeight: 200)
              ShareFileButton(title: "Share", data: piece.data, fileName: piece.fileName)
                .accessibilityIdentifier("imageSplitting.share.\(index + 1)")
            }
          }
        }
      }

      if let failure = model.failure {
        ErrorText(message: failure)
      }
    }
    .task(id: pickedItem) {
      guard let pickedItem else { return }
      await model.load(pickedItem)
    }
  }
}
