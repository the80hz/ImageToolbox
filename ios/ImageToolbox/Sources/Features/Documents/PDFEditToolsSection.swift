import ImageToolboxKit
import PhotosUI
import SwiftUI

/// The Tools section: the chosen tool, its fields, the run and the file it made. The tools work on
/// the whole document, and their state is `PDFToolModel.edit`.
struct PDFEditToolsSection: View {
  let model: PDFToolModel
  @Binding var pickedStamp: PhotosPickerItem?
  @State private var showsSignaturePad = false
  /// The languages Vision reads, for the text recognition of Extract text. Loaded once.
  @State private var languages: [String] = []

  /// The tools of the Tools section, in the order of its picker.
  private static let tools: [PDFEditTool] = [
    .splitIntoParts, .removePages, .turnPages, .pageNumbers, .watermark, .stamp, .extractImages,
    .pagesToImages, .crop, .resizePages, .pagesPerSheet, .metadata, .removeAnnotations,
    .sanitize, .protect, .unlock, .grayscale, .flatten, .repair, .alignRotation, .extractText,
    .darkMode, .compare,
  ]

  /// The tools that read the Pages field.
  static let pageTools: [PDFEditTool] = [
    .removePages, .watermark, .stamp, .crop, .pagesToImages, .removeAnnotations,
  ]

  var body: some View {
    GlassSection("Tools") {
      Picker("Tool", selection: Bindable(model.edit).tool) {
        ForEach(Self.tools) { tool in
          Text(tool.title).tag(tool)
        }
      }
      .accessibilityIdentifier("pdfTools.edit.tool")

      toolControls(model.edit.tool, Bindable(model.edit).options)

      Button("Run") {
        Task { await model.edit.run() }
      }
      .buttonStyle(.glassProminent)
      .disabled(model.edit.isRunning || !model.isEditReady)
      .accessibilityIdentifier("pdfTools.edit.run")

      if model.edit.isRunning {
        ProgressView()
      }

      if let output = model.edit.output {
        LabeledContent("Result", value: PDFToolLabels.sizeText(output.data.count))
          .accessibilityIdentifier("pdfTools.edit.result")

        if let count = output.count, let title = PDFToolLabels.countTitle(for: output.tool) {
          LabeledContent(title, value: count.formatted())
            .accessibilityIdentifier("pdfTools.edit.count")
        }

        PDFExportButtons(
          data: output.data, fileName: output.fileName(baseName: "document"), id: "pdfTools.edit",
          share: "Share")
      }

      if let failure = model.edit.failure {
        ErrorText(message: PDFToolLabels.message(for: failure))
      }
    }
    .task { await loadLanguages() }
  }

  /// The fields of the chosen tool. A tool without fields shows none.
  @ViewBuilder
  private func toolControls(_ tool: PDFEditTool, _ options: Binding<PDFEditOptions>) -> some View {
    if Self.pageTools.contains(tool) {
      field("Pages, empty for all", options.pagesText, numeric: true)
    }
    switch tool {
    case .splitIntoParts:
      Stepper(
        "Pages in each part: \(options.wrappedValue.partSize)", value: options.partSize,
        in: 1...max(1, model.pageCount ?? 1))
    case .turnPages:
      field("Turns, such as 3:90, 5:270", options.pageTurnsText, numeric: true)
    case .pageNumbers:
      field("Label, {n} is the number, {total} the count", options.numbers.format)
      Picker("Position", selection: options.numbers.position) {
        ForEach(PDFPageNumbers.Position.allCases, id: \.self) { position in
          Text(PDFToolLabels.title(for: position)).tag(position)
        }
      }
    case .watermark:
      field("Text", options.watermark.text)
      ParameterSlider(
        title: "Opacity", value: options.watermark.opacity, range: 0.05...1, step: 0.05,
        format: "%.2f")
    case .pagesToImages:
      Picker("Format", selection: options.imageFormat) {
        ForEach(PDFImageExport.Format.allCases, id: \.self) { format in
          Text(verbatim: format.rawValue.uppercased()).tag(format)
        }
      }
      ParameterSlider(
        title: "Scale", value: options.imageScale, range: 0.5...4, step: 0.5, format: "%.1f")
    case .crop:
      ParameterSlider(
        title: "Left", value: options.crop.left, range: 0...0.45, step: 0.01, format: "%.2f")
      ParameterSlider(
        title: "Top", value: options.crop.top, range: 0...0.45, step: 0.01, format: "%.2f")
      ParameterSlider(
        title: "Right", value: options.crop.right, range: 0...0.45, step: 0.01, format: "%.2f")
      ParameterSlider(
        title: "Bottom", value: options.crop.bottom, range: 0...0.45, step: 0.01, format: "%.2f")
    case .metadata:
      field("Title", options.metadata.title)
      field("Author", options.metadata.author)
      field("Subject", options.metadata.subject)
      field("Keywords, separated by commas", options.metadata.keywords)
    case .protect, .unlock:
      SecureField("Password", text: options.password)
        .textFieldStyle(.roundedBorder)
    case .stamp:
      SinglePhotoButton(title: "Choose picture", selection: $pickedStamp)
        .accessibilityIdentifier("pdfTools.stamp.pick")
      Button("Draw signature") {
        showsSignaturePad = true
      }
      .buttonStyle(.glass)
      .accessibilityIdentifier("pdfTools.stamp.draw")
      .sheet(isPresented: $showsSignaturePad) {
        PDFSignaturePad { picture in
          options.wrappedValue.stampImage = picture
        }
      }
      if let image = options.wrappedValue.stampImage {
        PictureView(image: image, maxHeight: 120)
      }
      if let stampError = model.stampError {
        ErrorText(message: stampError)
      }
      ParameterSlider(
        title: "Width", value: options.stampWidth, range: 0.05...1, step: 0.05, format: "%.2f")
      ParameterSlider(
        title: "Horizontal centre", value: centreBinding(options, \.x), range: 0...1, step: 0.01,
        format: "%.2f")
      ParameterSlider(
        title: "Vertical centre", value: centreBinding(options, \.y), range: 0...1, step: 0.01,
        format: "%.2f")
      ParameterSlider(
        title: "Opacity", value: options.stampOpacity, range: 0.05...1, step: 0.05, format: "%.2f")
    case .resizePages:
      PDFPaperPicker(size: options.pageSize)
      Picker("Fit mode", selection: options.fitMode) {
        ForEach(PDFPageLayout.FitMode.allCases, id: \.self) { mode in
          Text(PDFToolLabels.title(for: mode)).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      Toggle("Match orientation", isOn: options.matchOrientation)
    case .pagesPerSheet:
      Picker("Pages per sheet", selection: options.pagesOnSheet) {
        ForEach(PDFPageLayout.sheetCounts, id: \.self) { count in
          Text(verbatim: "\(count)").tag(count)
        }
      }
      Picker("Sheet", selection: sheetOrientation(options)) {
        ForEach(PDFPageLayout.SheetOrientation.allCases, id: \.self) { orientation in
          Text(PDFToolLabels.title(for: orientation)).tag(orientation)
        }
      }
      .pickerStyle(.segmented)
      if options.wrappedValue.sheetUsesPageSize {
        PDFPaperPicker(size: options.pageSize)
      }
      ParameterSlider(
        title: "Margin, % of the shorter side", value: options.sheetMarginPercent, range: 0...15,
        step: 0.5, format: "%.1f")
    case .removeAnnotations:
      ForEach(PDFCleanup.AnnotationKind.allCases, id: \.self) { kind in
        Toggle(PDFToolLabels.title(for: kind), isOn: annotationBinding(options, kind))
      }
    case .sanitize:
      Toggle("Metadata", isOn: options.sanitize.metadata)
      Toggle("Annotations", isOn: options.sanitize.annotations)
      Toggle("Forms", isOn: options.sanitize.forms)
      Toggle("Embedded attachments", isOn: options.sanitize.attachments)
      Toggle("Scripts and automatic actions", isOn: options.sanitize.scripts)
      Text("Scripts rebuilds every page, which also removes links, forms and outlines.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    case .compare:
      OpenDataFileButton(
        title: "Choose second PDF",
        onData: { data in options.otherDocument.wrappedValue = data },
        onFailure: { options.otherDocument.wrappedValue = nil }
      )
      .accessibilityIdentifier("pdfTools.edit.second")
      if let other = options.wrappedValue.otherDocument {
        LabeledContent("Second PDF", value: PDFToolLabels.sizeText(other.count))
      }
    default:
      EmptyView()
    }
    PDFEditFields(tool: tool, options: options, languages: languages)
  }

  /// Reads the languages that Vision reads, sorted by their names. Runs once.
  private func loadLanguages() async {
    guard languages.isEmpty else { return }
    let codes = await Task.detached(priority: .userInitiated) {
      TextRecognizer.supportedLanguages()
    }.value
    languages = codes.sorted {
      OCRToolModel.languageName(for: $0) < OCRToolModel.languageName(for: $1)
    }
  }

  /// The sheet orientation. A turned sheet takes the paper size, and the first page's size otherwise.
  private func sheetOrientation(
    _ options: Binding<PDFEditOptions>
  ) -> Binding<PDFPageLayout.SheetOrientation> {
    Binding(
      get: { options.wrappedValue.sheetOrientation },
      set: { value in
        options.wrappedValue.sheetOrientation = value
        options.wrappedValue.sheetUsesPageSize = value != .original
      })
  }

  /// One coordinate of the signature's centre, as the slider's value.
  private func centreBinding(
    _ options: Binding<PDFEditOptions>, _ axis: WritableKeyPath<CGPoint, CGFloat>
  ) -> Binding<Double> {
    Binding(
      get: { Double(options.wrappedValue.stampCentre[keyPath: axis]) },
      set: { options.wrappedValue.stampCentre[keyPath: axis] = CGFloat($0) })
  }

  /// Whether one annotation kind is in the kinds the tool removes.
  private func annotationBinding(
    _ options: Binding<PDFEditOptions>, _ kind: PDFCleanup.AnnotationKind
  ) -> Binding<Bool> {
    Binding(
      get: { options.wrappedValue.annotationKinds.contains(kind) },
      set: { on in
        var kinds = options.wrappedValue.annotationKinds
        if on { kinds.insert(kind) } else { kinds.remove(kind) }
        options.wrappedValue.annotationKinds = kinds
      })
  }

  /// A text field for a tool option. `numeric` shows the keyboard for page numbers and turns.
  private func field(
    _ title: LocalizedStringKey, _ text: Binding<String>, numeric: Bool = false
  ) -> some View {
    TextField(title, text: text)
      .textFieldStyle(.roundedBorder)
      .autocorrectionDisabled()
      .keyboardType(numeric ? .numbersAndPunctuation : .default)
  }
}
