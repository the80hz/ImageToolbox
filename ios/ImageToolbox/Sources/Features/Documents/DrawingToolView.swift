import ImageToolboxKit
import SwiftUI

struct DrawingToolView: View {
  @State private var model = DrawingToolModel()

  var body: some View {
    ToolScaffold(identifier: "drawing") {
      GlassSection("Canvas") {
        DrawingCanvasView(model: model)

        HStack {
          Button("Undo") {
            model.undo()
          }
          .buttonStyle(.glass)
          .disabled(!model.canUndo)
          .accessibilityIdentifier("drawing.undo")

          Button("Redo") {
            model.redo()
          }
          .buttonStyle(.glass)
          .disabled(!model.canRedo)
          .accessibilityIdentifier("drawing.redo")

          Button("Clear") {
            model.clear()
          }
          .buttonStyle(.glass)
          .disabled(!model.hasEdits)
          .accessibilityIdentifier("drawing.clear")
        }
      }

      GlassSection("Mode") {
        Picker("Mode", selection: Bindable(model).mode) {
          Text("Brush").tag(DrawingToolModel.Mode.brush)
          Text("Shape").tag(DrawingToolModel.Mode.shape)
          Text("Spray").tag(DrawingToolModel.Mode.spray)
          Text("Fill").tag(DrawingToolModel.Mode.fill)
          Text("Lasso").tag(DrawingToolModel.Mode.lasso)
          Text("Spot healing").tag(DrawingToolModel.Mode.spotHealing)
          Text("Warp").tag(DrawingToolModel.Mode.warp)
          Text("Pencil").tag(DrawingToolModel.Mode.pencil)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("drawing.mode")

        Text(hint)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      DrawingModeSettings(model: model)

      if let exportData = model.exportData {
        GlassSection("Export") {
          ShareFileButton(title: "Share file", data: exportData, fileName: "drawing.png")
            .accessibilityIdentifier("drawing.share")

          SaveFileButton(title: "Save to Files", data: exportData, fileName: "drawing.png")
            .accessibilityIdentifier("drawing.save")
        }
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  /// What the current mode does, in one line under the picker.
  private var hint: LocalizedStringKey {
    switch model.mode {
    case .brush: "Drag on the canvas to draw. A tap makes a dot."
    case .shape: "Drag between opposite corners."
    case .spray: "Drag to spray dots around the brush."
    case .fill: "Tap an area to fill the connected pixels of the same colour."
    case .lasso: "Drag around an area, then clear or fill it."
    case .spotHealing: "Tap or drag over a spot to heal it."
    case .warp: "Drag to push pixels along the stroke."
    case .pencil: "Draw with Apple Pencil or a finger, then commit the strokes."
    }
  }
}
