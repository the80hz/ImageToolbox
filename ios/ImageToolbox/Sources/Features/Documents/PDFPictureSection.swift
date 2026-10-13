import ImageToolboxKit
import PhotosUI
import SwiftUI

/// The Pictures to PDF section: one page per picture, as a PDF or as a searchable PDF with the text
/// under each picture, and a contact sheet of the pictures with captions read from each picture.
struct PDFPictureSection: View {
  let pictures: PDFPictureModel
  @State private var pickedPictures: [PhotosPickerItem] = []

  var body: some View {
    GlassSection("Pictures to PDF") {
      MultiPhotoButton(title: "Choose pictures", selection: $pickedPictures)
        .accessibilityIdentifier("pdfTools.searchable.pick")

      Text(
        "Each picture becomes one page. The searchable PDF also recognizes its text on this device."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      if pictures.isLoadingPictures {
        ProgressView()
      }

      if pictures.failedPictureCount > 0 {
        ErrorText(message: "\(pictures.failedPictureCount) pictures could not be read.")
      }

      Text("Pictures: \(pictures.searchablePictures.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      pdfControls

      Button("Make PDF") {
        Task { await pictures.makePicturePDF() }
      }
      .buttonStyle(.bordered)
      .disabled(pictures.searchablePictures.isEmpty)
      .accessibilityIdentifier("pdfTools.pictures.run")

      if let picturePDF = pictures.picturePDF {
        PDFExportButtons(data: picturePDF, fileName: "pictures.pdf", id: "pdfTools.pictures")
      }

      if let picturePDFError = pictures.picturePDFError {
        ErrorText(message: picturePDFError)
      }

      Button("Make searchable PDF") {
        Task { await pictures.makeSearchablePDF() }
      }
      .buttonStyle(.glassProminent)
      .disabled(pictures.searchablePictures.isEmpty || pictures.isMakingSearchable)
      .accessibilityIdentifier("pdfTools.searchable.run")

      if pictures.isMakingSearchable {
        ProgressView()
      }

      if let searchablePDF = pictures.searchablePDF {
        PDFExportButtons(
          data: searchablePDF, fileName: "searchable.pdf", id: "pdfTools.searchable")
      }

      if let searchableError = pictures.searchableError {
        ErrorText(message: searchableError)
      }

      contactControls

      Button("Make contact sheet") {
        Task { await pictures.makeContactSheet() }
      }
      .buttonStyle(.bordered)
      .disabled(pictures.searchablePictures.isEmpty || pictures.isMakingContactSheet)
      .accessibilityIdentifier("pdfTools.contact.run")

      if pictures.isMakingContactSheet {
        ProgressView()
      }

      if let contactPDF = pictures.contactPDF {
        PDFExportButtons(data: contactPDF, fileName: "contact-sheet.pdf", id: "pdfTools.contact")
      }

      if let contactError = pictures.contactError {
        ErrorText(message: contactError)
      }
    }
    .onChange(of: pickedPictures) { _, items in
      Task { await pictures.loadPictures(items) }
    }
  }

  /// The options of the PDF of the pictures.
  @ViewBuilder
  private var pdfControls: some View {
    ParameterSlider(
      title: "Quality", value: Bindable(pictures).pdfOptions.quality, range: 0.1...1, step: 0.05,
      format: "%.2f")
    ParameterSlider(
      title: "Scale", value: Bindable(pictures).pdfOptions.scale, range: 0.1...1, step: 0.05,
      format: "%.2f")
    Picker("Width", selection: Bindable(pictures).pdfOptions.widthRule) {
      ForEach(ImagesToPDF.WidthRule.allCases, id: \.self) { rule in
        Text(PDFToolLabels.title(for: rule)).tag(rule)
      }
    }
    Toggle("Fixed paper size", isOn: Bindable(pictures).fixedPaper)
    if pictures.fixedPaper {
      PDFPaperPicker(size: Bindable(pictures).paper)
      ParameterSlider(
        title: "Margin", value: Bindable(pictures).pdfOptions.margin, range: 0...60, step: 1,
        format: "%.0f")
    }
  }

  /// The grid, the paper and the captions of the contact sheet.
  @ViewBuilder
  private var contactControls: some View {
    Stepper(
      "Columns: \(pictures.contactSheet.columns)",
      value: Bindable(pictures).contactSheet.columns, in: 1...10)
    Stepper(
      "Rows: \(pictures.contactSheet.rows)", value: Bindable(pictures).contactSheet.rows,
      in: 1...10)
    ParameterSlider(
      title: "Margin", value: Bindable(pictures).contactSheet.margin, range: 0...60, step: 1,
      format: "%.0f")
    ParameterSlider(
      title: "Spacing", value: Bindable(pictures).contactSheet.spacing, range: 0...30, step: 1,
      format: "%.0f")
    ParameterSlider(
      title: "Quality", value: Bindable(pictures).contactSheet.quality, range: 0.1...1, step: 0.05,
      format: "%.2f")
    PDFPaperPicker(size: Bindable(pictures).contactSheet.pageSize)

    Text("Captions")
      .font(.subheadline.weight(.semibold))
    ForEach(PDFCaptionField.allCases, id: \.self) { field in
      Toggle(PDFToolLabels.title(for: field), isOn: captionBinding(field))
    }
    if pictures.contactFields.contains(.customText) {
      TextField("Custom text", text: Bindable(pictures).contactCustomText, axis: .vertical)
        .textFieldStyle(.roundedBorder)
    }
  }

  /// Whether one caption field is written under each picture.
  private func captionBinding(_ field: PDFCaptionField) -> Binding<Bool> {
    Binding(
      get: { pictures.contactFields.contains(field) },
      set: { on in
        if on {
          pictures.contactFields.insert(field)
        } else {
          pictures.contactFields.remove(field)
        }
      })
  }
}
