import ImageToolboxKit
import SwiftUI

/// The print options of the viewer: pages per sheet, the sheet's orientation, its margin and an
/// optional fixed paper size, as the Android app prints them. The system print panel prints the
/// result. One page per sheet with no margin prints the document as it is.
struct PDFPrintSection: View {
  let data: Data
  @State private var pagesPerSheet = 1
  @State private var orientation = PDFPageLayout.SheetOrientation.original
  @State private var marginPercent = 0.0
  @State private var fixedPaper = false
  @State private var paper = PDFPageSize.a4
  @State private var isPreparing = false
  @State private var errorMessage: LocalizedStringKey?

  var body: some View {
    Picker("Pages per sheet", selection: $pagesPerSheet) {
      ForEach(PDFPageLayout.sheetCounts, id: \.self) { count in
        Text(verbatim: "\(count)").tag(count)
      }
    }
    .accessibilityIdentifier("pdfTools.print.perSheet")

    Picker("Sheet", selection: $orientation) {
      ForEach(PDFPageLayout.SheetOrientation.allCases, id: \.self) { value in
        Text(PDFToolLabels.title(for: value)).tag(value)
      }
    }
    .pickerStyle(.segmented)

    if orientation != .original {
      Toggle("Fixed paper size", isOn: $fixedPaper)
      if fixedPaper {
        PDFPaperPicker(size: $paper)
      }
    }

    ParameterSlider(
      title: "Margin, % of the shorter side", value: $marginPercent, range: 0...15, step: 0.5,
      format: "%.1f")

    Button("Print") {
      Task { await prepareAndPrint() }
    }
    .buttonStyle(.glass)
    .disabled(!PDFPrinting.isAvailable || isPreparing)
    .accessibilityIdentifier("pdfTools.print")

    if isPreparing {
      ProgressView()
    }

    if let errorMessage {
      ErrorText(message: errorMessage)
    }
  }

  /// Lays the pages out on the sheets, unless the document prints as it is, and shows the print
  /// panel for the result.
  private func prepareAndPrint() async {
    let count = pagesPerSheet
    let sheetOrientation = orientation
    let margin = marginPercent
    let sheet: PDFPageSize? = fixedPaper && orientation != .original ? paper : nil
    if count == 1, sheetOrientation == .original, margin == 0 {
      PDFPrinting.present(data, jobName: "document.pdf")
      return
    }
    isPreparing = true
    let source = data
    let laid = await Task.detached(priority: .userInitiated) { () -> Data? in
      try? PDFPageLayout.pagesPerSheet(
        source, count: count, sheet: sheet, orientation: sheetOrientation,
        marginPercent: margin)
    }.value
    isPreparing = false
    guard let laid else {
      errorMessage = "The PDF could not be written."
      return
    }
    errorMessage = nil
    PDFPrinting.present(laid, jobName: "document.pdf")
  }
}
