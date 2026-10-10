import Charts
import ImageToolboxKit
import PhotosUI
import SwiftUI

struct CurvesToolView: View {
  @State private var model = CurvesToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []
  @State private var selectedIndex: Int?
  @Environment(\.services) private var services

  var body: some View {
    ToolScaffold(identifier: "curves") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("curves.pick")
      }

      BatchSection(identifier: "curves", model: batch, pickedItems: $batchItems) {
        let state = model.state
        let format = model.format
        let quality = model.quality
        let keepMetadata = AppSettings.load(from: .standard).keepMetadata
        let encoder = services.encoder
        return { item in
          CurvesToolModel.batchFile(
            item, state: state, format: format, quality: quality,
            keepMetadata: keepMetadata, encoder: encoder)
        }
      }

      if model.source != nil {
        editorSection
        presetSection
      }

      if let preview = model.preview {
        resultSection(preview)
        exportSection
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .onChange(of: model.mode) { _, _ in
      selectedIndex = nil
    }
    .onChange(of: model.toneChannel) { _, _ in
      selectedIndex = nil
    }
    .onChange(of: model.relationKind) { _, _ in
      selectedIndex = nil
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  // MARK: - Editor

  @ViewBuilder
  private var editorSection: some View {
    GlassSection("Editor") {
      Picker("Mode", selection: Bindable(model).mode) {
        Text("Curves").tag(CurvesEditorMode.curves)
        Text("CMYK").tag(CurvesEditorMode.cmyk)
        Text("Lab").tag(CurvesEditorMode.lab)
        Text("Hue, saturation, value").tag(CurvesEditorMode.relations)
        Text("Color wheels").tag(CurvesEditorMode.colorWheels)
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("curves.mode")
    }

    switch model.mode {
    case .curves, .cmyk, .lab:
      toneSection
    case .relations:
      relationsSection
    case .colorWheels:
      colorWheelsSection
    }
  }

  /// The RGB, CMYK or Lab curve picked in the channel control.
  private var toneSection: some View {
    GlassSection(sectionTitle) {
      Picker("Channel", selection: Bindable(model).toneChannel) {
        ForEach(ToneChannel.channels(for: model.mode), id: \.self) { channel in
          Text(channel.title).tag(channel)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("curves.channel")

      CurveEditorView(
        curve: model.tone(model.toneChannel),
        selectedIndex: $selectedIndex,
        onChange: { model.setTone($0, for: model.toneChannel) },
        onEnd: { model.commit() }
      )
      .accessibilityIdentifier("curves.editor")

      Text("Drag points. Drag empty space to add one.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      HStack {
        Button("Remove point") {
          if let selectedIndex {
            model.removeTonePoint(at: selectedIndex)
            self.selectedIndex = nil
          }
        }
        .buttonStyle(.glass)
        .disabled(!canRemoveSelectedTonePoint)
        .accessibilityIdentifier("curves.remove")

        Button("Reset channel") {
          model.resetTone()
          selectedIndex = nil
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("curves.reset")
      }

      undoRedoButtons
    }
  }

  private var sectionTitle: LocalizedStringKey {
    switch model.mode {
    case .cmyk: "CMYK"
    case .lab: "Lab"
    default: "Curves"
    }
  }

  /// One of the six curves that change hue, saturation or value. The centre line is no change.
  private var relationsSection: some View {
    GlassSection("Hue, saturation, value") {
      Picker("Curve", selection: Bindable(model).relationKind) {
        ForEach(RelationCurveKind.allCases, id: \.self) { kind in
          Text(Self.title(for: kind)).tag(kind)
        }
      }
      .accessibilityIdentifier("curves.relationKind")

      CurveEditorView(
        curve: model.relation(model.relationKind),
        selectedIndex: $selectedIndex,
        onChange: { model.setRelation($0, for: model.relationKind) },
        onEnd: { model.commit() },
        centered: true
      )
      .accessibilityIdentifier("curves.relationEditor")

      Text("The centre line means no change. Points above it strengthen, points below it weaken.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      HStack {
        Button("Remove point") {
          if let selectedIndex {
            model.removeRelationPoint(at: selectedIndex)
            self.selectedIndex = nil
          }
        }
        .buttonStyle(.glass)
        .disabled(!canRemoveSelectedRelationPoint)
        .accessibilityIdentifier("curves.relationRemove")

        Button("Reset curve") {
          model.resetRelation()
          selectedIndex = nil
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("curves.relationReset")
      }

      undoRedoButtons
    }
  }

  /// The names the Android app uses for the six curves.
  private static func title(for kind: RelationCurveKind) -> LocalizedStringKey {
    switch kind {
    case .hueVsSat: "Hue vs Sat"
    case .hueVsHue: "Hue vs Hue"
    case .hueVsLuma: "Hue vs Luma"
    case .lumaVsSat: "Luma vs Sat"
    case .lumaVsHue: "Luma vs Hue"
    case .satVsSat: "Sat vs Sat"
    }
  }

  private var colorWheelsSection: some View {
    GlassSection("Color wheels") {
      wheel("Shadows", \.shadows, identifier: "curves.wheel.shadows")
      wheel("Midtones", \.midtones, identifier: "curves.wheel.midtones")
      wheel("Highlights", \.highlights, identifier: "curves.wheel.highlights")

      ParameterSlider(
        title: "Edges",
        value: edgesBinding,
        onEditingEnded: { model.commit() },
        range: 0...1,
        step: 0.05,
        format: "%.2f"
      )
      .accessibilityIdentifier("curves.wheel.edges")

      Text(
        "Drag a dot to push its tonal range towards a colour. Edges sets how sharp the ranges are."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      HStack {
        Button("Reset wheels") {
          model.resetWheels()
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("curves.wheel.reset")
      }

      undoRedoButtons
    }
  }

  /// One colour wheel with its title. The wheel writes its own point into the state.
  private func wheel(
    _ title: LocalizedStringKey,
    _ path: WritableKeyPath<ColorWheels, ColorWheelPoint>,
    identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.footnote)
        .foregroundStyle(.secondary)
      ColorWheelEditorView(
        point: model.state.wheels[keyPath: path],
        onChange: { point in
          var wheels = model.state.wheels
          wheels[keyPath: path] = point
          model.setWheels(wheels)
        },
        onEnd: { model.commit() }
      )
      .frame(maxWidth: 220)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier(identifier)
    }
  }

  private var edgesBinding: Binding<Double> {
    Binding(
      get: { model.state.wheels.edges },
      set: { edges in
        var wheels = model.state.wheels
        wheels.edges = edges
        model.setWheels(wheels)
      })
  }

  private var undoRedoButtons: some View {
    HStack {
      Button("Undo") { model.undo() }
        .buttonStyle(.glass)
        .disabled(!model.canUndo)
        .accessibilityIdentifier("curves.undo")
      Button("Redo") { model.redo() }
        .buttonStyle(.glass)
        .disabled(!model.canRedo)
        .accessibilityIdentifier("curves.redo")
    }
  }

  /// Presets keep the RGB curves and the colour wheels, as the Android app does. Import reads the
  /// ImageToolbox JSON format, ACV, and Lightroom XMP or lrtemplate text.
  private var presetSection: some View {
    GlassSection("Preset") {
      OpenDataFileButton(
        title: "Import preset",
        onData: { model.importPreset($0) },
        onFailure: { model.reportUnreadablePreset() }
      )
      .accessibilityIdentifier("curves.importPreset")

      if let presetData = model.presetData {
        ShareFileButton(title: "Share preset", data: presetData, fileName: "curves.itcurve")
          .accessibilityIdentifier("curves.sharePreset")
        SaveFileButton(title: "Save preset", data: presetData, fileName: "curves.itcurve")
          .accessibilityIdentifier("curves.savePreset")
      }
    }
  }

  /// Endpoints cannot be removed, so only a point between the two ends can be.
  private var canRemoveSelectedTonePoint: Bool {
    guard let selectedIndex else { return false }
    let count = model.tone(model.toneChannel).points.count
    return selectedIndex > 0 && selectedIndex < count - 1
  }

  private var canRemoveSelectedRelationPoint: Bool {
    guard let selectedIndex else { return false }
    let count = model.relation(model.relationKind).points.count
    return selectedIndex > 0 && selectedIndex < count - 1
  }

  // MARK: - Result

  private func resultSection(_ preview: CurvesPreview) -> some View {
    GlassSection("Result") {
      PictureView(image: preview.image, maxHeight: 320)

      Text("Histogram")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Chart {
        if let original = model.sourceHistogram {
          ForEach(0..<256, id: \.self) { level in
            LineMark(
              x: .value("Level", level),
              y: .value("Pixels", original.luminance[level]),
              series: .value("Series", "Original")
            )
            .foregroundStyle(.secondary)
          }
        }
        ForEach(0..<256, id: \.self) { level in
          LineMark(
            x: .value("Level", level),
            y: .value("Pixels", preview.histogram.luminance[level]),
            series: .value("Series", "Result")
          )
          .foregroundStyle(Color.accentColor)
        }
      }
      .chartLegend(.hidden)
      .chartXAxis(.hidden)
      .frame(height: 120)
      .accessibilityLabel("Luminance histogram")

      Picker("Scope", selection: Bindable(model).scopeKind) {
        Text("None").tag(ColourScopeKind?.none)
        Text("Waveform").tag(ColourScopeKind?.some(.waveform))
        Text("Vectorscope").tag(ColourScopeKind?.some(.vectorscope))
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("curves.scope")

      if let scope = preview.scope {
        PictureView(image: scope, maxHeight: 280)
          .accessibilityIdentifier("curves.scopeImage")
      }
    }
  }

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
        .accessibilityIdentifier("curves.share")

        SaveFileButton(
          title: "Save to Files",
          data: exportData,
          fileName: model.exportFileName
        )
        .accessibilityIdentifier("curves.save")
      }
    }
  }
}
