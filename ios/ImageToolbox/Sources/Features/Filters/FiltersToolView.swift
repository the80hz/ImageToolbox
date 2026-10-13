import CoreGraphics
import ImageToolboxKit
import PhotosUI
import SwiftUI

struct FiltersToolView: View {
  @State private var model = FiltersToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @State private var isAddingPresented = false
  @Environment(\.services) private var services

  var body: some View {
    ToolScaffold(identifier: "filters") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("filters.pick")
      }

      BatchSection(identifier: "filters", model: batch, pickedItems: $batchItems) {
        let chain = model.chain
        let format = model.format
        let quality = model.quality
        let keepMetadata = AppSettings.load(from: .standard).keepMetadata
        let encoder = services.encoder
        return { item in
          await FiltersToolModel.batchFile(
            item, chain: chain, format: format, quality: quality,
            keepMetadata: keepMetadata, encoder: encoder)
        }
      }

      if model.source != nil {
        chainSection
        if let step = model.selectedStep, let descriptor = FilterRegistry.descriptor(for: step.id) {
          GlassSection(LocalizedStringKey(descriptor.titleKey)) {
            FilterParametersView(descriptor: descriptor, step: step, model: model)
          }
        }
      }

      if let preview = model.preview {
        GlassSection("Result") {
          PictureView(image: preview)
        }
        exportSection
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .sheet(isPresented: $isAddingPresented) {
      AddFilterSheet { descriptor in
        model.add(descriptor)
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  // MARK: - Chain

  private var chainSection: some View {
    GlassSection("Chain") {
      if model.chain.steps.isEmpty {
        Text(
          "Add filters one after another. The result shows the picture with all of them applied."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      ForEach(Array(model.chain.steps.enumerated()), id: \.offset) { index, step in
        stepRow(index: index, step: step)
      }

      Button("Add filter") {
        isAddingPresented = true
      }
      .buttonStyle(.glassProminent)
      .accessibilityIdentifier("filters.add")

      HStack {
        Button("Undo") { model.undo() }
          .buttonStyle(.glass)
          .disabled(!model.canUndo)
          .accessibilityIdentifier("filters.undo")
        Button("Redo") { model.redo() }
          .buttonStyle(.glass)
          .disabled(!model.canRedo)
          .accessibilityIdentifier("filters.redo")
      }
    }
  }

  /// One step of the chain: its name, which selects it, and move and remove buttons.
  private func stepRow(index: Int, step: FilterStep) -> some View {
    let isSelected = model.selectedIndex == index
    let count = model.chain.steps.count
    return HStack(spacing: 8) {
      let name =
        FilterRegistry.descriptor(for: step.id).map { LocalizedStringKey($0.titleKey) }
        ?? LocalizedStringKey(step.id)
      if isSelected {
        Button {
          model.selectedIndex = index
        } label: {
          Text(name).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("filters.step.\(index)")
      } else {
        Button {
          model.selectedIndex = index
        } label: {
          Text(name).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("filters.step.\(index)")
      }

      Button {
        model.move(at: index, by: -1)
      } label: {
        Image(systemName: "arrow.up")
      }
      .buttonStyle(.glass)
      .disabled(index == 0)
      .accessibilityLabel("Move up")

      Button {
        model.move(at: index, by: 1)
      } label: {
        Image(systemName: "arrow.down")
      }
      .buttonStyle(.glass)
      .disabled(index == count - 1)
      .accessibilityLabel("Move down")

      Button {
        model.remove(at: index)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.glass)
      .accessibilityLabel("Remove")
    }
  }

  // MARK: - Export

  private var exportSection: some View {
    GlassSection("Export") {
      OutputFormatPicker(selection: Bindable(model).format)

      if model.format.isLossy {
        ParameterSlider(
          title: "Quality",
          value: Bindable(model).quality,
          range: 0.1...1,
          step: 0.05,
          format: "%.2f"
        )
      }

      if let exportData = model.exportData {
        ShareFileButton(
          title: "Share file",
          data: exportData,
          fileName: model.exportFileName
        )
        .accessibilityIdentifier("filters.share")

        SaveFileButton(
          title: "Save to Files",
          data: exportData,
          fileName: model.exportFileName
        )
        .accessibilityIdentifier("filters.save")
      }
    }
  }
}

/// Lists every filter under its section, with a search field. Picking one adds it to the chain.
private struct AddFilterSheet: View {
  let onPick: (FilterDescriptor) -> Void
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(FilterCategory.allCases, id: \.self) { category in
          let filters = matches(in: category)
          if !filters.isEmpty {
            Section(Self.title(for: category)) {
              ForEach(filters, id: \.id) { descriptor in
                Button {
                  onPick(descriptor)
                  dismiss()
                } label: {
                  Text(LocalizedStringKey(descriptor.titleKey))
                }
                .accessibilityIdentifier("filters.add.\(descriptor.id)")
              }
            }
          }
        }
      }
      .searchable(text: $query, prompt: "Search filters")
      .navigationTitle("Add filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  /// Filters of one section whose name or keywords contain the search text.
  private func matches(in category: FilterCategory) -> [FilterDescriptor] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    return FilterRegistry.descriptors.filter { descriptor in
      guard descriptor.category == category else { return false }
      guard !needle.isEmpty else { return true }
      let name = String(localized: String.LocalizationValue(descriptor.titleKey)).lowercased()
      return name.contains(needle)
        || descriptor.keywords.contains { $0.lowercased().contains(needle) }
    }
  }

  private static func title(for category: FilterCategory) -> LocalizedStringKey {
    switch category {
    case .lightAndColour: "Light and colour"
    case .blur: "Blur"
    case .sharpenAndNoise: "Sharpen and noise"
    case .colourMatrix: "Colour matrix"
    case .lut: "LUT"
    case .dithering: "Dithering"
    case .morphology: "Morphology"
    case .toneMapping: "Tone mapping"
    case .histogram: "Histogram"
    case .distortion: "Distortion"
    case .glitchAndCRT: "Glitch and CRT"
    }
  }
}
