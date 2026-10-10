import PhotosUI
import SwiftUI

struct PDFToolView: View {
  @State private var model = PDFToolModel()
  @State private var pickedStamp: PhotosPickerItem?

  var body: some View {
    ToolScaffold(identifier: "pdfTools") {
      GlassSection("Document") {
        OpenDataFileButton(
          title: "Open PDF",
          onData: { data in Task { await model.open(data) } },
          onFailure: { model.reportUnreadableFile() }
        )
        .accessibilityIdentifier("pdfTools.open")

        if let pageCount = model.pageCount {
          Text("Pages: \(pageCount)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("pdfTools.pageCount")
        }
      }

      if model.pageCount != nil {
        GlassSection("Pages") {
          TextField("Pages", text: Bindable(model).pagesText)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .accessibilityIdentifier("pdfTools.pages")

          Text(
            "Numbers start at 1 and are separated by commas, such as 1,3,2. The order sets the order of the result. Empty keeps every page."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        GlassSection("Rotation") {
          Stepper(
            "Clockwise: \(model.quarterTurns * 90)°",
            value: Bindable(model).quarterTurns,
            in: 0...3
          )
          .accessibilityIdentifier("pdfTools.rotate")
        }

        if let preview = model.preview {
          GlassSection("Result") {
            PictureView(image: preview, maxHeight: 420)
              .accessibilityIdentifier("pdfTools.preview")

            Text("First page of the result.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        if let exportData = model.exportData {
          GlassSection("Export") {
            PDFExportButtons(data: exportData, fileName: "document.pdf", id: "pdfTools")
          }
        }

        if let viewed = model.viewerData {
          GlassSection("Viewer") {
            PDFDocumentViewer(data: viewed)
              .frame(height: 420)
              .clipShape(.rect(cornerRadius: 16))
              .accessibilityIdentifier("pdfTools.viewer")

            Text(
              "Shows the result, or the opened PDF when there is none. Swipe or tap a thumbnail to turn pages."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            PDFPrintSection(data: viewed)
          }
        }
      }

      if model.edit.document != nil {
        PDFEditToolsSection(model: model, pickedStamp: $pickedStamp)
      }

      PDFCompressSection(compression: model.compression)
      PDFComicSection(comic: model.comic)
      PDFPictureSection(pictures: model.pictures)
      PDFMergeSection(merger: model.merger)

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
    .onChange(of: pickedStamp) { _, item in
      if let item { Task { await model.loadStamp(item) } }
    }
    .onChange(of: model.edit.tool) { _, tool in
      // The pipeline reads the page field for every tool, so a stale range must not reach a tool
      // that does not show it.
      if !PDFEditToolsSection.pageTools.contains(tool) { model.edit.options.pagesText = "" }
    }
  }
}
