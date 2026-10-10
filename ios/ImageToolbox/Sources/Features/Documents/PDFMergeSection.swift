import SwiftUI

/// The Merge PDFs section: joins the chosen PDFs into one, in the order they were chosen.
struct PDFMergeSection: View {
  let merger: PDFMergeModel
  @State private var isImporting = false

  var body: some View {
    GlassSection("Merge PDFs") {
      Button("Choose PDFs") {
        isImporting = true
      }
      .buttonStyle(.glass)
      .accessibilityIdentifier("pdfTools.merge.pick")

      Text("Files: \(merger.files.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("pdfTools.merge.count")

      Button("Merge") {
        Task { await merger.merge() }
      }
      .buttonStyle(.glassProminent)
      .disabled(merger.files.count < 2 || merger.isMerging)
      .accessibilityIdentifier("pdfTools.merge.run")

      if !merger.files.isEmpty {
        Button("Clear files") {
          merger.clear()
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("pdfTools.merge.clear")
      }

      if merger.isMerging {
        ProgressView()
      }

      if let merged = merger.merged {
        LabeledContent("Result", value: PDFToolLabels.sizeText(merged.count))
          .accessibilityIdentifier("pdfTools.merge.result")

        PDFExportButtons(data: merged, fileName: "merged.pdf", id: "pdfTools.merge")
      }

      if let mergeError = merger.errorMessage {
        ErrorText(message: mergeError)
      }
    }
    .fileImporter(
      isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true
    ) { result in
      guard case .success(let urls) = result else { return }
      merger.add(urls.map(MediaFiles.read))
    }
  }
}
