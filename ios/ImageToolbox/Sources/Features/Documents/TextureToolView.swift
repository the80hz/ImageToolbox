import ImageToolboxKit
import SwiftUI

struct TextureToolView: View {
  @State private var model = TextureToolModel()

  var body: some View {
    ToolScaffold(identifier: "textures") {
      GlassSection {
        if let image = model.image {
          PictureView(image: image)
        } else if model.isGenerating {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        }

        if model.generationFailed {
          ErrorText(message: "The picture could not be generated.")
        }
      }

      GlassSection("Kind") {
        Picker("Kind", selection: $model.choice) {
          ForEach(TextureKind.allCases, id: \.self) { kind in
            Text(title(for: kind)).tag(TextureChoice.kind(kind))
          }
          ForEach(TextureCategory.allCases, id: \.self) { category in
            Section(LocalizedStringKey(category.title)) {
              ForEach(TexturePresets.presets(in: category)) { preset in
                Text(verbatim: preset.title).tag(TextureChoice.preset(preset.id))
              }
            }
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("textures.kind")
      }

      GlassSection("Colours") {
        ColorPicker("First colour", selection: $model.colourA, supportsOpacity: false)
          .disabled(model.isPreset)
          .accessibilityIdentifier("textures.colourA")

        ColorPicker("Second colour", selection: $model.colourB, supportsOpacity: false)
          .disabled(model.isPreset)
          .accessibilityIdentifier("textures.colourB")
      }

      GlassSection("Parameters") {
        if model.isPreset {
          Text("Presets set their own colours and parameters.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        ParameterSlider(title: "Scale", value: $model.scale, range: 4...512)
          .disabled(model.isPreset)
          .accessibilityIdentifier("textures.scale")

        ParameterSlider(title: "Octaves", value: $model.octaves, range: 1...8)
          .disabled(!model.usesOctaves)
          .accessibilityIdentifier("textures.octaves")

        ParameterSlider(title: "Angle", value: $model.angle, range: -180...180, format: "%.0f°")
          .disabled(model.isPreset)
          .accessibilityIdentifier("textures.angle")

        seedControls
      }

      GlassSection("Export") {
        if let pngData = model.pngData {
          ShareFileButton(title: "Share file", data: pngData, fileName: model.pngFileName)
            .accessibilityIdentifier("textures.share")

          SaveFileButton(title: "Save to Files", data: pngData, fileName: model.pngFileName)
            .accessibilityIdentifier("textures.save")
        }
      }
    }
    .task(id: model.revision) {
      // Waits for a pause in the changes, so a slider drag draws once at its end.
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  private var seedControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Seed")
        Spacer()
        Text(String(model.seed))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityIdentifier("textures.seed")
      }

      Button("Shuffle seed") {
        model.shuffleSeed()
      }
      .buttonStyle(.glass)
      .accessibilityIdentifier("textures.shuffle")
    }
  }

  /// The picker label of a kind. Each name is translated.
  private func title(for kind: TextureKind) -> LocalizedStringKey {
    switch kind {
    case .noise: "Noise"
    case .turbulence: "Turbulence"
    case .marble: "Marble"
    case .wood: "Wood"
    case .voronoi: "Voronoi"
    case .stripes: "Stripes"
    case .checkerboard: "Checkerboard"
    case .dots: "Dots"
    }
  }
}
