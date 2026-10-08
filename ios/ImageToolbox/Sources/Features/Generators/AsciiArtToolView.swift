import ImageToolboxKit
import PhotosUI
import SwiftUI
import UIKit

struct AsciiArtToolView: View {
  @State private var model = AsciiArtToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @State private var pickedItem: PhotosPickerItem?

  var body: some View {
    ToolScaffold(identifier: "asciiArt") {
      GlassSection {
        SinglePhotoButton(title: "Choose image", selection: $pickedItem)
          .accessibilityIdentifier("asciiArt.pick")

        if model.failed {
          ErrorText(message: "The picked image could not be read.")
        }
      }

      BatchSection(identifier: "ascii", model: batch, pickedItems: $batchItems) {

        let columns = model.columns

        let invert = model.invert

        return { item in AsciiArtToolModel.batchFile(item, columns: columns, invert: invert) }

      }

      GlassSection("Settings") {
        HStack {
          Button("Undo") { model.undo() }
            .buttonStyle(.glass)
            .disabled(!model.canUndo)
            .accessibilityIdentifier("ascii.undo")
          Button("Redo") { model.redo() }
            .buttonStyle(.glass)
            .disabled(!model.canRedo)
            .accessibilityIdentifier("ascii.redo")
        }
        ParameterSlider(
          title: "Columns", value: $model.columns, onEditingEnded: model.commitParameters,
          range: 20...200)
        Toggle("Invert", isOn: $model.invert)
          .onChange(of: model.invert) { _, _ in model.commitParameters() }
      }

      if !model.text.isEmpty {
        GlassSection("Result") {
          ScrollView(.horizontal) {
            Text(model.text)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .fixedSize()
          }

          HStack {
            Button("Copy") {
              UIPasteboard.general.string = model.text
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("asciiArt.copy")

            ShareFileButton(title: "Share", data: Data(model.text.utf8), fileName: "ascii.txt")
              .accessibilityIdentifier("asciiArt.share")
          }
        }
      }
    }
    .onChange(of: pickedItem) { _, item in
      guard let item else { return }
      Task {
        await model.load(item)
        pickedItem = nil
      }
    }
    .onChange(of: model.columns) { _, _ in
      model.refresh()
    }
    .onChange(of: model.invert) { _, _ in
      model.refresh()
    }
  }
}
