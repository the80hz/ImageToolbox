import ImageToolboxKit
import PhotosUI
import SwiftUI

struct MultiFrameFusionToolView: View {
  @State private var model = MultiFrameFusionToolModel()
  @State private var pickedItems: [PhotosPickerItem] = []

  var body: some View {
    ToolScaffold(identifier: "multiFrameFusion") {
      GlassSection("Frames") {
        MultiPhotoButton(
          title: "Choose frames", selection: $pickedItems, maxCount: FusionParams.maximumImages
        )
        .accessibilityIdentifier("multiFrameFusion.pick")

        if model.isLoading {
          ProgressView()
        }
        Text("Frames loaded: \(model.frames.count)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("multiFrameFusion.count")
        if model.failedCount > 0 {
          ErrorText(message: "\(model.failedCount) frames could not be read.")
        }
      }

      if model.frames.count >= FusionParams.minimumImages {
        GlassSection("Method") {
          Picker("Method", selection: Bindable(model).params.mode) {
            Text("Exposure").tag(FusionMode.exposure)
            Text("Focus").tag(FusionMode.focus)
            Text("Median").tag(FusionMode.median)
            Text("Long exposure").tag(FusionMode.longExposure)
            Text("Light trails").tag(FusionMode.lightTrails)
            Text("Motion trails").tag(FusionMode.motionTrails)
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("multiFrameFusion.mode")

          Toggle("Align frames", isOn: Bindable(model).params.alignImages)
            .accessibilityIdentifier("multiFrameFusion.align")
          Toggle("Crop to overlap", isOn: Bindable(model).params.cropToOverlap)
            .accessibilityIdentifier("multiFrameFusion.crop")

          modeControls

          HStack {
            Button("Undo") { model.undo() }
              .buttonStyle(.glass)
              .disabled(!model.canUndo)
              .accessibilityIdentifier("multiFrameFusion.undo")
            Button("Redo") { model.redo() }
              .buttonStyle(.glass)
              .disabled(!model.canRedo)
              .accessibilityIdentifier("multiFrameFusion.redo")
          }
        }
        .onChange(of: model.params.mode) { _, _ in
          model.commit()
        }

        GlassSection("Result") {
          if model.isFusing {
            ProgressView()
            Text("Fusing frames…")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if let preview = model.preview {
            PictureView(image: preview.image, maxHeight: 420)
              .accessibilityIdentifier("multiFrameFusion.result")
            ShareFileButton(title: "Share file", data: preview.data, fileName: preview.fileName)
              .accessibilityIdentifier("multiFrameFusion.share")
            SaveFileButton(title: "Save to Files", data: preview.data, fileName: preview.fileName)
              .accessibilityIdentifier("multiFrameFusion.save")
          }
        }
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

  /// The sliders that the chosen method uses.
  @ViewBuilder
  private var modeControls: some View {
    switch model.params.mode {
    case .exposure:
      ParameterSlider(
        title: "Contrast", value: value(\.contrastWeight), onEditingEnded: { model.commit() },
        range: 0...2, step: 0.05, format: "%.2f")
      ParameterSlider(
        title: "Saturation", value: value(\.saturationWeight), onEditingEnded: { model.commit() },
        range: 0...2, step: 0.05, format: "%.2f")
      ParameterSlider(
        title: "Exposure weight", value: value(\.exposureWeight),
        onEditingEnded: { model.commit() },
        range: 0...2, step: 0.05, format: "%.2f")
    case .focus:
      ParameterSlider(
        title: "Focus radius", value: focusRadius, onEditingEnded: { model.commit() },
        range: 1...21, step: 2)
      ParameterSlider(
        title: "Focus strength", value: value(\.focusStrength), onEditingEnded: { model.commit() },
        range: 1...6, step: 0.5, format: "%.1f")
    case .median, .longExposure:
      EmptyView()
    case .lightTrails:
      ParameterSlider(
        title: "Trail threshold", value: value(\.lightTrailThreshold),
        onEditingEnded: { model.commit() }, range: 0...0.5, step: 0.01, format: "%.2f")
      ParameterSlider(
        title: "Trail strength", value: value(\.trailStrength), onEditingEnded: { model.commit() },
        range: 0...1, step: 0.05, format: "%.2f")
    case .motionTrails:
      ParameterSlider(
        title: "Trail strength", value: value(\.trailStrength), onEditingEnded: { model.commit() },
        range: 0...1, step: 0.05, format: "%.2f")
      ParameterSlider(
        title: "Trail persistence", value: value(\.trailPersistence),
        onEditingEnded: { model.commit() }, range: 0.1...1, step: 0.05, format: "%.2f")
    }
  }

  /// A slider bound to one setting of the parameters.
  private func value(_ path: WritableKeyPath<FusionParams, Double>) -> Binding<Double> {
    Binding(
      get: { model.params[keyPath: path] },
      set: { model.params[keyPath: path] = $0 })
  }

  /// The focus radius is an odd number, but the slider works in steps of two from one.
  private var focusRadius: Binding<Double> {
    Binding(
      get: { Double(model.params.focusRadius) },
      set: { model.params.focusRadius = Int($0.rounded()) })
  }
}
