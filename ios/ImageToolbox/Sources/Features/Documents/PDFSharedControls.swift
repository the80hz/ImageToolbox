import ImageToolboxKit
import SwiftUI

/// Share and save buttons for a finished PDF, with the identifiers `id.share` and `id.save`.
struct PDFExportButtons: View {
  let data: Data
  let fileName: String
  let id: String
  var share: LocalizedStringKey = "Share PDF"

  var body: some View {
    ShareFileButton(title: share, data: data, fileName: fileName)
      .accessibilityIdentifier("\(id).share")

    SaveFileButton(title: "Save to Files", data: data, fileName: fileName)
      .accessibilityIdentifier("\(id).save")
  }
}

/// A picker for the paper sizes of `PDFPageSize.all`.
struct PDFPaperPicker: View {
  @Binding var size: PDFPageSize

  var body: some View {
    Picker("Paper size", selection: $size) {
      ForEach(PDFPageSize.all) { paper in
        Text(verbatim: paper.name).tag(paper)
      }
    }
  }
}
