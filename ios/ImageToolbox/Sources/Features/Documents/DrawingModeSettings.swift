import ImageToolboxKit
import SwiftUI

/// The settings for the current mode of the drawing tool. Each mode shows only the controls it uses.
struct DrawingModeSettings: View {
  @Bindable var model: DrawingToolModel

  var body: some View {
    switch model.mode {
    case .brush:
      brushSettings

    case .shape:
      shapeSettings

    case .spray:
      GlassSection("Spray") {
        radiusSlider

        ParameterSlider(
          title: "Density",
          value: intBinding(\.sprayDensity),
          range: 1...200,
          step: 1
        )
        .accessibilityIdentifier("drawing.sprayDensity")

        ParameterSlider(
          title: "Dot size",
          value: $model.sprayDotSize,
          range: 1...20,
          step: 1
        )
        .accessibilityIdentifier("drawing.sprayDotSize")

        Toggle("Square dots", isOn: $model.spraySquare)
          .accessibilityIdentifier("drawing.spraySquare")

        colourPicker
      }

    case .fill:
      GlassSection("Fill") {
        ParameterSlider(
          title: "Tolerance",
          value: $model.fillTolerance,
          range: 0...1,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("drawing.fillTolerance")

        colourPicker
      }

    case .lasso:
      GlassSection("Lasso") {
        HStack {
          Button("Clear inside") {
            model.applyLasso(.clear)
          }
          .buttonStyle(.glass)
          .accessibilityIdentifier("drawing.lassoClear")

          Button("Fill inside") {
            model.applyLasso(.fill)
          }
          .buttonStyle(.glass)
          .accessibilityIdentifier("drawing.lassoFill")
        }
        .disabled(!model.canApplyLasso)

        Button("Deselect") {
          model.dropLasso()
        }
        .buttonStyle(.glass)
        .disabled(model.lassoOutline.isEmpty)
        .accessibilityIdentifier("drawing.lassoDeselect")

        colourPicker
      }

    case .spotHealing:
      GlassSection("Spot healing") {
        radiusSlider
      }

    case .warp:
      GlassSection("Warp") {
        Picker("Mode", selection: $model.warpMode) {
          ForEach(WarpMode.allCases, id: \.self) { mode in
            Text(warpName(mode)).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("drawing.warpMode")

        radiusSlider

        ParameterSlider(
          title: "Strength",
          value: $model.warpStrength,
          range: 0...1,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("drawing.warpStrength")

        ParameterSlider(
          title: "Hardness",
          value: $model.warpHardness,
          range: 0...1,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("drawing.warpHardness")
      }

    case .pencil:
      GlassSection("Pencil") {
        radiusSlider

        colourPicker

        Button("Commit strokes") {
          model.commitPencilStrokes()
        }
        .buttonStyle(.glass)
        .disabled(!model.hasPencilStrokes)
        .accessibilityIdentifier("drawing.commitStrokes")
      }
    }
  }

  // MARK: - Sections

  private var brushSettings: some View {
    GlassSection("Brush") {
      Picker("Kind", selection: $model.paintKind) {
        ForEach(DrawingToolModel.PaintKind.allCases, id: \.self) { kind in
          Text(paintName(kind)).tag(kind)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("drawing.paintKind")

      radiusSlider

      if model.paintKind != .highlighter {
        hardnessSlider
      }

      if model.paintKind == .pen || model.paintKind == .neon {
        lineStylePicker
      }

      if model.paintKind == .pen || model.paintKind == .highlighter || model.paintKind == .neon {
        colourPicker
      }
    }
  }

  private var shapeSettings: some View {
    GlassSection("Shape") {
      Picker("Kind", selection: $model.shapeKind) {
        ForEach(ShapeKind.allCases, id: \.self) { kind in
          Text(shapeName(kind)).tag(kind)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("drawing.shapeKind")

      if Self.isClosed(model.shapeKind) {
        Toggle("Filled", isOn: $model.shapeFilled)
          .accessibilityIdentifier("drawing.shapeFilled")
      }

      if model.shapeKind == .polygon || model.shapeKind == .star {
        ParameterSlider(
          title: "Sides",
          value: intBinding(\.shapeSides),
          range: 3...12,
          step: 1
        )
        .accessibilityIdentifier("drawing.shapeSides")

        Toggle("Regular", isOn: $model.shapeRegular)
          .accessibilityIdentifier("drawing.shapeRegular")
      }

      if model.shapeKind == .star {
        ParameterSlider(
          title: "Inner radius",
          value: $model.shapeInnerRatio,
          range: 0.1...0.9,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("drawing.shapeInnerRatio")
      }

      if Self.isTurnable(model.shapeKind) {
        ParameterSlider(
          title: "Rotation",
          value: $model.shapeRotation,
          range: -180...180,
          step: 5,
          format: "%.0f°"
        )
        .accessibilityIdentifier("drawing.shapeRotation")
      }

      if model.shapeKind == .rectangle {
        ParameterSlider(
          title: "Corner rounding",
          value: $model.shapeCornerRadius,
          range: 0...0.5,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("drawing.shapeCornerRadius")
      }

      if model.shapeKind == .arrow || model.shapeKind == .doubleArrow {
        ParameterSlider(
          title: "Arrowhead angle",
          value: $model.arrowAngle,
          range: 30...170,
          step: 5,
          format: "%.0f°"
        )
        .accessibilityIdentifier("drawing.arrowAngle")

        ParameterSlider(
          title: "Arrowhead size",
          value: $model.arrowScale,
          range: 1...10,
          step: 0.5,
          format: "%.1f"
        )
        .accessibilityIdentifier("drawing.arrowScale")
      }

      radiusSlider
      hardnessSlider
      lineStylePicker
      colourPicker
    }
  }

  // MARK: - Controls

  private var radiusSlider: some View {
    ParameterSlider(
      title: "Radius",
      value: $model.radius,
      range: 1...120,
      step: 1
    )
    .accessibilityIdentifier("drawing.radius")
  }

  private var hardnessSlider: some View {
    ParameterSlider(
      title: "Hardness",
      value: $model.hardness,
      range: 0...1,
      step: 0.05,
      format: "%.2f"
    )
    .accessibilityIdentifier("drawing.hardness")
  }

  private var lineStylePicker: some View {
    Picker("Line style", selection: $model.lineStyle) {
      ForEach(LineStyle.allCases, id: \.self) { style in
        Text(lineStyleName(style)).tag(style)
      }
    }
    .pickerStyle(.menu)
    .accessibilityIdentifier("drawing.lineStyle")
  }

  private var colourPicker: some View {
    ColorPicker("Colour", selection: $model.colour, supportsOpacity: false)
      .accessibilityIdentifier("drawing.colour")
  }

  /// A whole-number model value, as the slider's Double.
  private func intBinding(_ keyPath: ReferenceWritableKeyPath<DrawingToolModel, Int>) -> Binding<
    Double
  > {
    Binding(
      get: { Double(model[keyPath: keyPath]) },
      set: { model[keyPath: keyPath] = Int($0.rounded()) }
    )
  }

  // MARK: - Names

  private static func isClosed(_ kind: ShapeKind) -> Bool {
    kind != .line && kind != .arrow && kind != .doubleArrow
  }

  private static func isTurnable(_ kind: ShapeKind) -> Bool {
    kind == .rectangle || kind == .polygon || kind == .star
  }

  private func paintName(_ kind: DrawingToolModel.PaintKind) -> LocalizedStringKey {
    switch kind {
    case .pen: "Pen"
    case .highlighter: "Highlighter"
    case .neon: "Neon"
    case .eraser: "Eraser"
    case .blur: "Blur"
    case .pixelate: "Pixelate"
    }
  }

  private func shapeName(_ kind: ShapeKind) -> LocalizedStringKey {
    switch kind {
    case .rectangle: "Rectangle"
    case .ellipse: "Ellipse"
    case .line: "Line"
    case .triangle: "Triangle"
    case .polygon: "Polygon"
    case .star: "Star"
    case .arrow: "Arrow"
    case .doubleArrow: "Double arrow"
    }
  }

  private func lineStyleName(_ style: LineStyle) -> LocalizedStringKey {
    switch style {
    case .solid: "Solid"
    case .dashed: "Dashed"
    case .dotDashed: "Dot-dashed"
    case .zigZag: "Zigzag"
    }
  }

  private func warpName(_ mode: WarpMode) -> LocalizedStringKey {
    switch mode {
    case .push: "Push"
    case .grow: "Grow"
    case .shrink: "Shrink"
    case .swirlClockwise: "Swirl clockwise"
    case .swirlCounterclockwise: "Swirl counter-clockwise"
    }
  }
}
