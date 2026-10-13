import ImageToolboxKit
import PhotosUI
import SwiftUI

struct CollageToolView: View {
  @State private var model = CollageToolModel()
  @State private var pickedItems: [PhotosPickerItem] = []

  var body: some View {
    ToolScaffold(identifier: "collage") {
      picturesSection

      if !model.pictures.isEmpty {
        previewSection
        layoutSection
        CollageSelectedPictureSection(model: model)
        backgroundSection
        borderSection
        exportSection
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .onChange(of: pickedItems) { _, items in
      Task { await model.load(items) }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  // MARK: - Sections

  private var picturesSection: some View {
    GlassSection("Pictures") {
      MultiPhotoButton(title: "Choose pictures", selection: $pickedItems, maxCount: 36)
        .accessibilityIdentifier("collage.pick")

      if model.isLoading {
        ProgressView()
      }
      if model.failedCount > 0 {
        ErrorText(message: "\(model.failedCount) pictures could not be read.")
      }
      Text("Pictures: \(model.pictures.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("collage.count")
    }
  }

  private var previewSection: some View {
    GlassSection("Preview") {
      if let image = model.previewImage {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 360)
          .overlay { CollageCellOverlay(model: model) }
          .clipShape(.rect(cornerRadius: 12))
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("collage.preview")
      } else {
        ProgressView()
          .frame(maxWidth: .infinity)
      }

      Text(previewHint)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var previewHint: LocalizedStringKey {
    switch model.arrangement {
    case .free: "Drag a picture to move it. Select it and drag a corner to resize it."
    case .template:
      model.dividers.isEmpty
        ? "Tap a picture to select it, then drag it to move the photo inside its cell."
        : "Drag a white grip between cells to move the line. Tap a picture to select it."
    }
  }

  private var layoutSection: some View {
    GlassSection("Layout") {
      Picker("Arrangement", selection: Bindable(model).arrangement) {
        ForEach(CollageComposition.Arrangement.allCases, id: \.self) { arrangement in
          Text(arrangement.title).tag(arrangement)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("collage.arrangement")

      switch model.arrangement {
      case .template:
        CollageTemplatePicker(model: model)
        if model.hasMovedDividers {
          Button("Reset lines") { model.resetDividers() }
            .buttonStyle(.glass)
            .accessibilityIdentifier("collage.dividers.reset")
        }
      case .free:
        freeControls
      }

      ParameterSlider(title: "Gap", value: Bindable(model).gap, range: 0...40)
        .accessibilityIdentifier("collage.gap")

      ParameterSlider(title: "Margin", value: Bindable(model).margin, range: 0...60)
        .accessibilityIdentifier("collage.margin")
    }
  }

  private var freeControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button("Bring to front") { model.bringSelectedToFront() }
          .accessibilityIdentifier("collage.free.front")
        Button("Send to back") { model.sendSelectedToBack() }
          .accessibilityIdentifier("collage.free.back")
      }
      .disabled(model.selectedCell == nil)

      Button("Reset layout") { model.resetFreeLayout() }
        .accessibilityIdentifier("collage.free.reset")
    }
    .buttonStyle(.glass)
  }

  private var backgroundSection: some View {
    GlassSection("Background") {
      Picker("Type", selection: Bindable(model).fill) {
        ForEach(CollageSettings.Fill.allCases, id: \.self) { fill in
          Text(fill.title).tag(fill)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("collage.background.kind")

      if model.fill == .solid {
        ColorPicker("Colour", selection: Bindable(model).startColor)
          .accessibilityIdentifier("collage.background.color")
      } else {
        ColorPicker("Start colour", selection: Bindable(model).startColor)
          .accessibilityIdentifier("collage.background.color")
        ColorPicker("End colour", selection: Bindable(model).endColor)
          .accessibilityIdentifier("collage.background.end")
      }

      if model.fill == .linear {
        ParameterSlider(title: "Angle", value: Bindable(model).gradientAngle, range: 0...360)
          .accessibilityIdentifier("collage.background.angle")
      }
    }
  }

  private var borderSection: some View {
    GlassSection("Border") {
      ParameterSlider(title: "Width", value: Bindable(model).borderWidth, range: 0...30)
        .accessibilityIdentifier("collage.border.width")

      if model.borderWidth > 0 {
        ColorPicker("Colour", selection: Bindable(model).borderColor)
          .accessibilityIdentifier("collage.border.color")
      }
    }
  }

  private var exportSection: some View {
    GlassSection("Export") {
      Picker("Aspect ratio", selection: Bindable(model).aspect) {
        ForEach(CollageExportSize.aspects, id: \.self) { aspect in
          Text(verbatim: aspect.title).tag(aspect)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("collage.aspect")

      ParameterSlider(
        title: "Output scale", value: Bindable(model).exportScale,
        range: CollageExportSize.scales, step: 0.05, format: "%.2f"
      )
      .accessibilityIdentifier("collage.scale")

      Text("Size: \(model.exportTitle) px")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("collage.size")

      if let exportData = model.exportData {
        ShareFileButton(title: "Share file", data: exportData, fileName: "collage.png")
          .accessibilityIdentifier("collage.share")

        SaveFileButton(title: "Save to Files", data: exportData, fileName: "collage.png")
          .accessibilityIdentifier("collage.save")
      }
    }
  }
}
