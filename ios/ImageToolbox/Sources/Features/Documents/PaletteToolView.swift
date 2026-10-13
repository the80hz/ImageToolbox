import ImageToolboxKit
import SwiftUI
import UniformTypeIdentifiers

struct PaletteToolView: View {
  @State private var model = PaletteToolModel()
  @State private var isImporting = false

  var body: some View {
    ToolScaffold(identifier: "palettes") {
      GlassSection("Palette") {
        // Text only, for the same accessibility reason as OpenDataFileButton. The importer is
        // local because the file name decides the format, and OpenDataFileButton gives only bytes.
        Button("Open palette") {
          isImporting = true
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("palettes.open")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
          guard case .success(let url) = result else { return }
          // Files outside the app's sandbox need access requested for the duration of the read.
          let granted = url.startAccessingSecurityScopedResource()
          defer {
            if granted { url.stopAccessingSecurityScopedResource() }
          }
          if let data = try? Data(contentsOf: url) {
            model.open(data, fileName: url.lastPathComponent)
          } else {
            model.reportUnreadableFile()
          }
        }

        if let fileName = model.fileName {
          Text(verbatim: fileName)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityIdentifier("palettes.file")

          Picker(
            "Read as",
            selection: Binding(get: { model.readFormat }, set: { model.chooseReadFormat($0) })
          ) {
            Text("Choose format").tag(PaletteToolModel.FileFormat?.none)
            formatSections(PaletteToolModel.FileFormat.allCases.filter(\.isReadable)) {
              PaletteToolModel.FileFormat?.some($0)
            }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("palettes.readFormat")
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }

      materialSection

      if !model.colours.isEmpty {
        GlassSection("Colours") {
          Text("Colours: \(model.colours.count)")
            .font(.footnote)
            .foregroundStyle(.secondary)

          ForEach(model.colours.indices, id: \.self) { index in
            colourRow(model.colours[index])
          }
        }

        GlassSection("Export") {
          Picker("Write as", selection: Bindable(model).writeFormat) {
            formatSections(PaletteToolModel.FileFormat.allCases.filter(\.isWritable)) { $0 }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("palettes.writeFormat")

          if let exportData = model.exportData {
            ShareFileButton(title: "Share file", data: exportData, fileName: exportName)
              .accessibilityIdentifier("palettes.share")

            SaveFileButton(title: "Save to Files", data: exportData, fileName: exportName)
              .accessibilityIdentifier("palettes.save")
          }
        }
      }
    }
  }

  /// The exported file's name, with the extension of the write format.
  private var exportName: String {
    "palette.\(model.writeFormat.fileExtension)"
  }

  /// A Material You scheme built from a picture's seed colour, shown as swatches. Export puts the
  /// swatches' colours into the palette, where the Colours and Export sections save them.
  private var materialSection: some View {
    GlassSection("Material You") {
      SinglePhotoButton(title: "Choose image", selection: Bindable(model).materialSelection)
        .accessibilityIdentifier("palettes.material.pick")

      if let picture = model.materialPicture {
        PictureView(image: picture.image, maxHeight: 160)
      }

      if let scheme = model.materialScheme {
        Toggle("Dark mode", isOn: Bindable(model).materialDark)
          .accessibilityIdentifier("palettes.material.dark")

        Picker("Style", selection: Bindable(model).materialStyle) {
          ForEach(MaterialSchemeStyle.allCases, id: \.self) { style in
            Text(Self.styleName(style)).tag(style)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("palettes.material.style")

        HStack(spacing: 8) {
          Circle()
            .fill(Color(rgba: scheme.seed))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
          Text("Seed colour")
          Spacer()
          Text(verbatim: scheme.seed.hexString)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
        }

        swatchGrid(scheme)

        Button("Export palette") {
          model.useMaterialScheme()
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("palettes.material.export")
      } else if model.materialErrorMessage == nil {
        Text("Choose a picture to build a scheme from its main colour.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let errorMessage = model.materialErrorMessage {
        ErrorText(message: errorMessage)
      }
    }
  }

  /// The roles in the Android swatch grid order, four columns to a row. Shorter rows keep the
  /// column width with empty space at the end.
  private func swatchGrid(_ scheme: MaterialColourScheme) -> some View {
    VStack(spacing: 12) {
      ForEach(MaterialColourRole.paletteToolRows.indices, id: \.self) { index in
        let row = MaterialColourRole.paletteToolRows[index]
        HStack(alignment: .top, spacing: 8) {
          ForEach(row, id: \.self) { role in
            swatch(role, in: scheme)
          }
          ForEach(row.count..<4, id: \.self) { _ in
            Color.clear.frame(maxWidth: .infinity)
          }
        }
      }
    }
  }

  /// One role: its colour, a sample of its content colour, then the role name and hex value.
  private func swatch(_ role: MaterialColourRole, in scheme: MaterialColourScheme) -> some View {
    let colour = scheme[role]
    let hex = colour.hexString
    let sampleColour = role.contentRole.map { Color(rgba: scheme[$0]) } ?? Color.primary
    return VStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(rgba: colour))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
        }
        .overlay {
          Text(verbatim: "Aa")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(sampleColour)
        }
        .frame(height: 44)

      Text(verbatim: role.displayName)
        .font(.caption2)
        .multilineTextAlignment(.center)
        .lineLimit(2)

      Text(verbatim: hex)
        .font(.caption2.monospaced())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "\(role.displayName), \(hex)"))
  }

  /// The picker name of a style, using the Android app's names in sentence case.
  private static func styleName(_ style: MaterialSchemeStyle) -> LocalizedStringKey {
    switch style {
    case .tonalSpot: "Tonal spot"
    case .neutral: "Neutral"
    case .vibrant: "Vibrant"
    case .expressive: "Expressive"
    case .rainbow: "Rainbow"
    case .fruitSalad: "Fruit salad"
    case .monochrome: "Monochrome"
    case .fidelity: "Fidelity"
    case .content: "Content"
    }
  }

  /// The formats in a picker, one section per family. Sections without formats are left out.
  private func formatSections<Tag: Hashable>(
    _ formats: [PaletteToolModel.FileFormat],
    tag: @escaping (PaletteToolModel.FileFormat) -> Tag
  ) -> some View {
    ForEach(PaletteToolModel.FileFormat.Family.allCases, id: \.self) { family in
      let members = formats.filter { $0.family == family }
      if !members.isEmpty {
        Section(family.title) {
          ForEach(members, id: \.self) { format in
            Text(verbatim: format.name).tag(tag(format))
          }
        }
      }
    }
  }

  /// One colour: a swatch, its hex value and its name when the file has one.
  private func colourRow(_ colour: PaletteColour) -> some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 8)
        .fill(
          Color(
            red: Double(colour.red) / 255,
            green: Double(colour.green) / 255,
            blue: Double(colour.blue) / 255
          )
          .opacity(Double(colour.alpha) / 255)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(
          verbatim: RGBA(
            red: colour.red, green: colour.green, blue: colour.blue, alpha: colour.alpha
          ).hexString
        )
        .font(.system(.body, design: .monospaced))

        if let name = colour.name {
          Text(verbatim: name)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
