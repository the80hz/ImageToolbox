import ImageToolboxKit
import SwiftUI

/// The Compress PDF section: re-encodes the pages of the chosen PDF at the chosen quality.
struct PDFCompressSection: View {
  let compression: PDFCompressionModel

  var body: some View {
    GlassSection("Compress PDF") {
      OpenDataFileButton(
        title: "Open PDF to compress",
        onData: { data in compression.open(data) },
        onFailure: { compression.reportUnreadable() }
      )
      .accessibilityIdentifier("pdfTools.compress.open")

      if let source = compression.source {
        LabeledContent("Original", value: PDFToolLabels.sizeText(source.count))
          .accessibilityIdentifier("pdfTools.compress.original")

        ParameterSlider(
          title: "Quality",
          value: Bindable(compression).quality,
          range: 0.1...1,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("pdfTools.compress.quality")

        Button("Compress") {
          Task { await compression.compress() }
        }
        .buttonStyle(.glassProminent)
        .disabled(compression.isCompressing)
        .accessibilityIdentifier("pdfTools.compress.run")

        if compression.isCompressing {
          ProgressView()
        }
      }

      if let compressed = compression.compressed {
        LabeledContent("Result", value: PDFToolLabels.sizeText(compressed.data.count))
          .accessibilityIdentifier("pdfTools.compress.result")

        if compressed.keptOriginal {
          Text("The compressed PDF would not be smaller, so the original is kept.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("pdfTools.compress.kept")
        }

        PDFExportButtons(
          data: compressed.data, fileName: "compressed.pdf", id: "pdfTools.compress")
      }

      if let errorMessage = compression.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
  }
}

/// The Comic to PDF section: one page per picture in a ZIP, CBZ or CBR archive, with the order,
/// the cover, the wide pages, the page size and the JPEG quality as options.
struct PDFComicSection: View {
  let comic: PDFComicModel

  var body: some View {
    GlassSection("Comic to PDF") {
      OpenDataFileButton(
        title: "Open archive",
        onData: { data in Task { await comic.open(data) } },
        onFailure: { comic.reportUnreadableArchive() }
      )
      .accessibilityIdentifier("pdfTools.comic.open")

      Text("Each picture (JPEG, PNG, WebP or GIF) in the archive becomes one page, in name order.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Toggle("Reverse page order", isOn: Bindable(comic).options.reversesOrder)
        .accessibilityIdentifier("pdfTools.comic.reverse")
      Toggle("Skip the cover", isOn: Bindable(comic).options.skipsCover)
        .accessibilityIdentifier("pdfTools.comic.skipCover")
      Toggle("Split wide pages", isOn: Bindable(comic).options.splitsWidePictures)
        .accessibilityIdentifier("pdfTools.comic.split")
      if comic.options.splitsWidePictures {
        Toggle("Right to left", isOn: Bindable(comic).options.rightToLeft)
          .accessibilityIdentifier("pdfTools.comic.rightToLeft")
      }
      Toggle("Fixed page size", isOn: Bindable(comic).fixedPaper)
        .accessibilityIdentifier("pdfTools.comic.fixedPaper")
      if comic.fixedPaper {
        PDFPaperPicker(size: Bindable(comic).paper)
      }
      ParameterSlider(
        title: "Quality", value: Bindable(comic).options.quality, range: 0.1...1, step: 0.05,
        format: "%.2f"
      )
      .accessibilityIdentifier("pdfTools.comic.quality")

      if comic.isConverting {
        ProgressView()
      }

      if let pdf = comic.pdf {
        LabeledContent("Result", value: PDFToolLabels.sizeText(pdf.count))
          .accessibilityIdentifier("pdfTools.comic.result")

        PDFExportButtons(data: pdf, fileName: "comic.pdf", id: "pdfTools.comic")
      }

      if let errorMessage = comic.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
  }
}
