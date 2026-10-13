import ImageToolboxKit
import SwiftUI

/// The controls of the picture selected in the preview: its zoom, its place, its turn, the shape of its cell, and the
/// actions on it.
struct CollageSelectedPictureSection: View {
  let model: CollageToolModel

  var body: some View {
    GlassSection("Selected picture") {
      if model.selectedCell == nil {
        Text("Tap a picture in the preview to zoom it, turn it or change the shape of its cell.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ParameterSlider(
          title: "Zoom", value: zoomBinding, range: 1...4, step: 0.1, format: "%.1f"
        )
        .accessibilityIdentifier("collage.zoom")

        ParameterSlider(
          title: "Horizontal", value: horizontalBinding, range: -1...1, step: 0.05, format: "%.2f"
        )
        .accessibilityIdentifier("collage.shift.x")

        ParameterSlider(
          title: "Vertical", value: verticalBinding, range: -1...1, step: 0.05, format: "%.2f"
        )
        .accessibilityIdentifier("collage.shift.y")

        ParameterSlider(
          title: "Rotation", value: rotationBinding, range: -180...180, step: 1, format: "%.0f"
        )
        .accessibilityIdentifier("collage.rotation")

        Picker("Shape", selection: shapeBinding) {
          ForEach(CollageMask.Shape.allCases, id: \.self) { shape in
            Text(shape.title).tag(shape)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("collage.shape")

        // The corner radius rounds rectangles and hexagons only; the other shapes have no corners.
        if [CollageMask.Shape.rectangle, .hexagon].contains(model.selectedMask.shape) {
          ParameterSlider(title: "Corners", value: cornersBinding, range: 0...100)
            .accessibilityIdentifier("collage.corners")
        }

        HStack {
          Button("Reset picture") { model.resetSelectedPlacement() }
            .accessibilityIdentifier("collage.picture.reset")
          Menu("Swap with") {
            ForEach(model.otherPictureIndices, id: \.self) { index in
              Button("Picture \(index + 1)") { model.swapSelected(with: index) }
            }
          }
          .accessibilityIdentifier("collage.picture.swap")
        }
        .buttonStyle(.glass)

        Button("Same shape for all pictures") { model.applySelectedShapeToAll() }
          .buttonStyle(.glass)
          .accessibilityIdentifier("collage.shape.all")
      }
    }
  }

  // MARK: - Bindings to the selected picture

  private var zoomBinding: Binding<Double> {
    Binding(
      get: { Double(model.selectedPlacement.zoom) },
      set: { model.setSelectedZoom($0) })
  }

  private var horizontalBinding: Binding<Double> {
    Binding(
      get: { Double(model.selectedPlacement.offset.dx) },
      set: { model.setSelectedOffset(x: $0) })
  }

  private var verticalBinding: Binding<Double> {
    Binding(
      get: { Double(model.selectedPlacement.offset.dy) },
      set: { model.setSelectedOffset(y: $0) })
  }

  private var rotationBinding: Binding<Double> {
    Binding(
      get: { model.selectedRotation },
      set: { model.setSelectedRotation($0) })
  }

  private var shapeBinding: Binding<CollageMask.Shape> {
    Binding(
      get: { model.selectedMask.shape },
      set: { model.setSelectedShape($0) })
  }

  private var cornersBinding: Binding<Double> {
    Binding(
      get: { model.selectedMask.cornerRadius },
      set: { model.setSelectedCornerRadius($0) })
  }
}
