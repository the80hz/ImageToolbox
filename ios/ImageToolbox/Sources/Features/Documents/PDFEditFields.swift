import ImageToolboxKit
import SwiftUI

/// The options of the Tools section that the core already takes but the section did not show yet:
/// the dark mode colours, the watermark colour and angle, the page number style, the quality of the
/// JPEG and flattened pages, the text recognition languages, the metadata and the comparison metric.
struct PDFEditFields: View {
  let tool: PDFEditTool
  let options: Binding<PDFEditOptions>
  /// The languages Vision reads, for the text recognition of Extract text.
  let languages: [String]

  @ViewBuilder
  var body: some View {
    switch tool {
    case .darkMode: darkModeFields
    case .watermark: watermarkFields
    case .pageNumbers: pageNumberFields
    case .pagesToImages: imageQualityField
    case .flatten:
      ParameterSlider(
        title: "Quality", value: options.flattenQuality, range: 0.1...1, step: 0.05,
        format: "%.2f")
    case .extractText: recognitionFields
    case .metadata: metadataFields
    case .compare: compareFields
    default: EmptyView()
    }
  }

  // MARK: Dark mode

  @ViewBuilder
  private var darkModeFields: some View {
    Picker("Theme", selection: options.darkMode.theme) {
      ForEach(PDFDarkTheme.allCases, id: \.self) { theme in
        Text(PDFToolLabels.title(for: theme)).tag(theme)
      }
    }
    if options.wrappedValue.darkMode.theme == .custom {
      ColorPicker(
        "Custom colour", selection: colour(options.darkMode.customColour), supportsOpacity: false)
      Picker("Blend mode", selection: options.darkMode.customBlend) {
        ForEach(PDFBlendMode.allCases, id: \.self) { blend in
          Text(PDFToolLabels.title(for: blend)).tag(blend)
        }
      }
    }
  }

  // MARK: Watermark

  @ViewBuilder
  private var watermarkFields: some View {
    ColorPicker("Colour", selection: colour(options.watermark.colour), supportsOpacity: false)
    ParameterSlider(
      title: "Width, share of the page", value: options.watermark.widthFraction, range: 0.1...1,
      step: 0.05, format: "%.2f")
    ParameterSlider(
      title: "Angle, degrees counterclockwise", value: options.watermark.angle, range: 0...360,
      step: 5, format: "%.0f")
  }

  // MARK: Page numbers

  @ViewBuilder
  private var pageNumberFields: some View {
    ParameterSlider(
      title: "Text size", value: options.numbers.fontSize, range: 6...72, step: 1, format: "%.0f")
    ColorPicker("Colour", selection: colour(options.numbers.colour), supportsOpacity: false)
    Stepper(
      "First number: \(options.wrappedValue.numbers.firstNumber)",
      value: options.numbers.firstNumber, in: 0...9_999)
  }

  // MARK: Images

  /// The JPEG quality, shown only for the JPEG format, which the quality applies to.
  @ViewBuilder
  private var imageQualityField: some View {
    if options.wrappedValue.imageFormat == .jpeg {
      ParameterSlider(
        title: "Quality", value: options.imageQuality, range: 0.1...1, step: 0.05, format: "%.2f")
    }
  }

  // MARK: Text

  /// Turns recognition of the pictures on or off, and picks the language it reads.
  @ViewBuilder
  private var recognitionFields: some View {
    Toggle("Recognize text in pictures", isOn: recognitionOn)
      .accessibilityIdentifier("pdfTools.edit.recognize")
    if options.wrappedValue.recognitionLanguages.isEmpty == false, !languages.isEmpty {
      Picker("Language", selection: recognitionLanguage) {
        ForEach(languages, id: \.self) { code in
          Text(verbatim: OCRToolModel.languageName(for: code)).tag(code)
        }
      }
    }
    Text("Pages without text are read on this device. Other pages keep their text as it is.")
      .font(.footnote)
      .foregroundStyle(.secondary)
  }

  /// The metadata fields that the Metadata tool shows beside the basic ones.
  @ViewBuilder
  private var metadataFields: some View {
    textField("Creator", options.metadata.creator)
    textField("Producer", options.metadata.producer)
  }

  // MARK: Compare

  @ViewBuilder
  private var compareFields: some View {
    Picker("Metric", selection: options.comparisonMetric) {
      ForEach(PDFComparisonMetric.allCases, id: \.self) { metric in
        Text(PDFToolLabels.title(for: metric)).tag(metric)
      }
    }
    ParameterSlider(
      title: "Tolerance, percent", value: percentBinding(options.comparisonTolerance),
      range: 0...50,
      step: 1, format: "%.0f")
    ColorPicker("Highlight colour", selection: colour(options.highlight), supportsOpacity: false)
  }

  // MARK: Bindings

  /// Whether the pictures are read for their text.
  private var recognitionOn: Binding<Bool> {
    Binding(
      get: { !options.wrappedValue.recognitionLanguages.isEmpty },
      set: { on in
        options.wrappedValue.recognitionLanguages = on ? [defaultLanguage] : []
      })
  }

  /// The language the recognition reads: the first one in the list, or the one that is set.
  private var recognitionLanguage: Binding<String> {
    Binding(
      get: { options.wrappedValue.recognitionLanguages.first ?? defaultLanguage },
      set: { options.wrappedValue.recognitionLanguages = [$0] })
  }

  /// The first language of the device that Vision reads, or the first one of the list.
  private var defaultLanguage: String {
    languages.first { Locale.preferredLanguages.contains($0) } ?? languages.first ?? "en-US"
  }

  /// A colour of the options as the SwiftUI colour that a colour picker shows.
  private func colour(_ value: Binding<RGBA>) -> Binding<Color> {
    Binding(
      get: { ColorConversion.color(value.wrappedValue) },
      set: { value.wrappedValue = ColorConversion.rgba($0) })
  }

  /// A share from 0 to 1 of the options, as a percentage on the slider.
  private func percentBinding(_ value: Binding<Double>) -> Binding<Double> {
    Binding(
      get: { value.wrappedValue * 100 },
      set: { value.wrappedValue = $0 / 100 })
  }

  private func textField(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
    TextField(title, text: text)
      .textFieldStyle(.roundedBorder)
      .autocorrectionDisabled()
  }
}
