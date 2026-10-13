import ImageToolboxKit
import SwiftUI

/// Controls of the selected layer: stacking, appearance, the options of its content, and its shadow
/// and gradient. Each control changes the layer through the model, one undo step per change.
extension MarkupToolView {
  private static let black = MarkupColour(red: 0, green: 0, blue: 0)

  var selectedSection: some View {
    GlassSection("Selected layer") {
      if let layer = model.selectedLayerValue, let index = model.selectedLayer {
        ParameterSlider(
          title: "Opacity",
          value: Binding(
            get: { model.selectedOpacity },
            set: { value in model.previewSelected { $0.opacity = value } }
          ),
          onEditingEnded: { model.finishSliderEdit() },
          range: 0...1,
          step: 0.05,
          format: "%.2f"
        )
        .accessibilityIdentifier("markup.opacity")

        toggle("Locked", id: "markup.lock", isOn: layer.isLocked) {
          model.toggleSelectedLock()
        }

        // A locked layer refuses these edits, so their controls are disabled too.
        Group {
          let isTop = index == model.document.layers.count - 1
          LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 8) {
            button("Move up", id: "markup.moveUp", disabled: isTop) { model.moveSelected(by: 1) }
            button("Move down", id: "markup.moveDown", disabled: index == 0) {
              model.moveSelected(by: -1)
            }
            button(layer.isVisible ? "Hide layer" : "Show layer", id: "markup.toggleVisibility") {
              model.toggleSelectedVisibility()
            }
            button("Delete layer", id: "markup.delete") { model.removeSelected() }
          }

          appearanceControls(layer)
          if let style = layer.textStyle { textControls(layer, style: style) }
          if let kind = layer.shapeKind, let style = layer.shapeStyle {
            shapeControls(layer, kind: kind, style: style)
            if layer.isFilledShape { gradientControls(style.fillGradient) }
          }
          shadowControls(layer.shadow)
        }
        .disabled(layer.isLocked)
      } else {
        Text("Select a layer on the picture or in the list.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Flips, blend mode and, for pictures and text, the corner radius.
  @ViewBuilder
  func appearanceControls(_ layer: MarkupLayer) -> some View {
    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 8) {
      toggle("Flip horizontally", id: "markup.flipHorizontal", isOn: layer.isFlippedHorizontally) {
        model.changeSelected { $0.isFlippedHorizontally.toggle() }
      }
      toggle("Flip vertically", id: "markup.flipVertical", isOn: layer.isFlippedVertically) {
        model.changeSelected { $0.isFlippedVertically.toggle() }
      }
    }

    Picker("Blend mode", selection: blendModeBinding(layer.blendMode)) {
      ForEach(MarkupBlendMode.allCases, id: \.self) { mode in
        Text(Self.title(for: mode)).tag(mode)
      }
    }
    .pickerStyle(.menu)
    .accessibilityIdentifier("markup.blendMode")

    if layer.supportsCornerRadius {
      slider("Corner radius", Double(layer.cornerRadiusPercent), 0...50, format: "%.0f%%") {
        target, value in
        target.cornerRadiusPercent = Int(value.rounded())
      }
      .accessibilityIdentifier("markup.cornerRadius")
    }
  }

  /// Decorations, background, outline, alignment and line limit of a text layer.
  @ViewBuilder
  private func textControls(_ layer: MarkupLayer, style: MarkupTextStyle) -> some View {
    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 8) {
      ForEach(MarkupTextStyle.Decoration.allCases, id: \.self) { decoration in
        let isOn = style.decorations.contains(decoration)
        toggle(Self.title(for: decoration), id: "markup.decoration.\(decoration)", isOn: isOn) {
          model.changeSelected { $0.updateTextStyle { $0.toggleDecoration(decoration) } }
        }
      }
      toggle("Background", id: "markup.background", isOn: style.backgroundColour != nil) {
        model.changeSelected { $0.updateTextStyle { $0.toggleBackground() } }
      }
      toggle("Outline", id: "markup.outline", isOn: style.outline != nil) {
        let width = model.baseSize.map { MarkupLayerDefaults.outlineWidth(for: $0) } ?? 2
        model.changeSelected { $0.updateTextStyle { $0.toggleOutline(width: width) } }
      }
    }

    Picker("Alignment", selection: alignmentBinding(style)) {
      ForEach(MarkupTextStyle.Alignment.allCases, id: \.self) { alignment in
        Text(Self.title(for: alignment)).tag(alignment)
      }
    }
    .pickerStyle(.segmented)

    if let rotation = layer.textRotation {
      slider("Rotation", rotation * 180 / .pi, 0...360, format: "%.0f°") { target, value in
        target.updateTextRotation(value * .pi / 180)
      }
      .accessibilityIdentifier("markup.textRotation")
    }

    if (layer.textLineCount ?? 1) > 1 { lineLimitControls(layer) }
  }

  /// Shows only the first lines of a text layer. The count is kept while the limit is off.
  @ViewBuilder
  private func lineLimitControls(_ layer: MarkupLayer) -> some View {
    let total = layer.textLineCount ?? 1
    toggle("Limit lines", id: "markup.limitLines", isOn: layer.visibleLineCount != nil) {
      model.changeSelected { $0.visibleLineCount = $0.visibleLineCount == nil ? 1 : nil }
    }
    if let visible = layer.visibleLineCount {
      slider("Visible lines", Double(visible), 1...Double(total), format: "%.0f") {
        target, value in
        target.visibleLineCount = Int(value.rounded())
      }
      .accessibilityIdentifier("markup.visibleLines")
    }
  }

  /// Line width, the length and angle of an arrow head, rotation, the corner radius of a rectangle,
  /// the vertices, inner radius and regularity of a polygon or star.
  @ViewBuilder
  private func shapeControls(
    _ layer: MarkupLayer, kind: MarkupLayer.Content.ShapeKind, style: MarkupShapeStyle
  ) -> some View {
    if let width = layer.shapeStrokeWidth {
      // An open shape needs a stroke to be seen, so its width starts at 1.
      let widths: ClosedRange<Double> = kind.isClosed ? 0...64 : 1...64
      slider("Line width", width, widths, format: "%.0f") {
        target, value in
        target.updateShapeStrokeWidth(value)
      }
      .accessibilityIdentifier("markup.lineWidth")
    }
    if [.arrow, .doubleArrow, .lineArrow, .doubleLineArrow].contains(kind) {
      slider("Head length scale", style.arrowSizeScale, 0.5...8, step: 0.1, format: "%.1f") {
        target, value in
        target.updateShapeStyle { $0.arrowSizeScale = value }
      }
      .accessibilityIdentifier("markup.arrowSize")
      // The angle is shown as drawn: the head is clamped to 100...175 degrees.
      slider("Angle", style.arrowAngle, 100...175, format: "%.0f°") { target, value in
        target.updateShapeStyle { $0.arrowAngle = value }
      }
      .accessibilityIdentifier("markup.arrowAngle")
    }
    if [.rectangle, .polygon, .star].contains(kind) {
      slider("Rotation", style.rotationDegrees, 0...360, format: "%.0f°") { target, value in
        target.updateShapeStyle { $0.rotationDegrees = value }
      }
    }
    if kind == .rectangle {
      slider("Corner radius", style.cornerRadius, 0...0.5, step: 0.01, format: "%.2f") {
        target, value in
        target.updateShapeStyle { $0.cornerRadius = value }
      }
    }
    if kind == .polygon || kind == .star {
      slider("Vertices", Double(style.vertices), 3...24, format: "%.0f") { target, value in
        target.updateShapeStyle { $0.vertices = Int(value.rounded()) }
      }
      .accessibilityIdentifier("markup.vertices")
    }
    if kind == .star {
      slider("Inner radius", style.innerRadiusRatio, 0...1, step: 0.05, format: "%.2f") {
        target, value in
        target.updateShapeStyle { $0.innerRadiusRatio = value }
      }
      .accessibilityIdentifier("markup.innerRadius")
    }
    if kind == .polygon || kind == .star {
      let title: LocalizedStringKey = kind == .polygon ? "Regular polygon" : "Regular star"
      toggle(title, id: "markup.regular", isOn: style.isRegular) {
        model.changeSelected { target in
          target.updateShapeStyle { $0.isRegular.toggle() }
        }
      }
    }
  }

  /// A linear gradient for a filled shape: its on or off state, its angle, and whether it fades to
  /// black. A new gradient runs from the ink colour to white.
  @ViewBuilder
  private func gradientControls(_ gradient: MarkupGradient?) -> some View {
    toggle("Gradient", id: "markup.gradient", isOn: gradient != nil) {
      model.changeSelected { target in
        target.updateShapeStyle { style in
          style.fillGradient =
            style.fillGradient == nil
            ? MarkupGradient(startColour: MarkupToolModel.ink, endColour: .white) : nil
        }
      }
    }
    if let gradient {
      slider("Gradient angle", gradient.angleDegrees, 0...360, format: "%.0f°") {
        target, value in
        target.updateShapeStyle { $0.fillGradient?.angleDegrees = value }
      }
      .accessibilityIdentifier("markup.gradientAngle")
      toggle(
        "Fade to black", id: "markup.gradientBlack", isOn: gradient.endColour == Self.black
      ) {
        model.changeSelected { target in
          target.updateShapeStyle { style in
            let isBlack = style.fillGradient?.endColour == Self.black
            style.fillGradient?.endColour = isBlack ? .white : Self.black
          }
        }
      }
    }
  }

  /// A drop shadow under any layer: its on or off state, its offsets and its blur.
  @ViewBuilder
  private func shadowControls(_ shadow: MarkupShadow?) -> some View {
    toggle("Shadow", id: "markup.shadow", isOn: shadow != nil) {
      model.changeSelected { $0.shadow = $0.shadow == nil ? MarkupShadow() : nil }
    }
    if let shadow {
      Text("Shadow colour")
        .font(.footnote)
        .foregroundStyle(.secondary)
      shadowColourRow(shadow)
      slider("Shadow opacity", shadow.alpha, 0...1, step: 0.05, format: "%.2f") { target, value in
        target.shadow?.alpha = value
      }
      .accessibilityIdentifier("markup.shadowAlpha")
      slider("Shadow offset X", shadow.offsetX, -64...64, format: "%.0f") { target, value in
        target.shadow?.offsetX = value
      }
      .accessibilityIdentifier("markup.shadowOffsetX")
      slider("Shadow offset Y", shadow.offsetY, -64...64, format: "%.0f") { target, value in
        target.shadow?.offsetY = value
      }
      .accessibilityIdentifier("markup.shadowOffsetY")
      slider("Shadow blur", shadow.blurRadius, 0...100, format: "%.0f") { target, value in
        target.shadow?.blurRadius = value
      }
      .accessibilityIdentifier("markup.shadowBlur")
    }
  }

  /// Colour swatches for the shadow, as in the Android editor's colour row. The swatch that matches
  /// the shadow is outlined.
  private func shadowColourRow(_ shadow: MarkupShadow) -> some View {
    HStack(spacing: 12) {
      shadowSwatch("Black", id: "black", Self.black, current: shadow.colour)
      shadowSwatch("White", id: "white", .white, current: shadow.colour)
      shadowSwatch(
        "Grey", id: "grey", MarkupColour(red: 0.5, green: 0.5, blue: 0.5), current: shadow.colour)
      shadowSwatch("Red", id: "red", MarkupToolModel.ink, current: shadow.colour)
      shadowSwatch(
        "Blue", id: "blue", MarkupColour(red: 0.1, green: 0.3, blue: 0.9), current: shadow.colour)
    }
  }

  private func shadowSwatch(
    _ name: LocalizedStringKey, id: String, _ colour: MarkupColour, current: MarkupColour
  ) -> some View {
    let isSelected = colour == current
    return Button {
      model.changeSelected { $0.shadow?.colour = colour }
    } label: {
      Circle()
        .fill(Color(red: colour.red, green: colour.green, blue: colour.blue))
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
        .overlay {
          Circle()
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(-4)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("markup.shadowColour.\(id)")
  }

  private func alignmentBinding(_ style: MarkupTextStyle) -> Binding<MarkupTextStyle.Alignment> {
    Binding(
      get: { style.alignment },
      set: { alignment in model.changeSelected { $0.updateTextStyle { $0.alignment = alignment } } }
    )
  }

  private func blendModeBinding(_ mode: MarkupBlendMode) -> Binding<MarkupBlendMode> {
    Binding(
      get: { mode },
      set: { next in model.changeSelected { $0.blendMode = next } }
    )
  }

  private static func title(for decoration: MarkupTextStyle.Decoration) -> LocalizedStringKey {
    switch decoration {
    case .bold: "Bold"
    case .italic: "Italic"
    case .underline: "Underline"
    case .strikethrough: "Strikethrough"
    }
  }

  private static func title(for alignment: MarkupTextStyle.Alignment) -> LocalizedStringKey {
    switch alignment {
    case .start: "Start"
    case .centre: "Centre"
    case .end: "End"
    }
  }

  private static func title(for mode: MarkupBlendMode) -> LocalizedStringKey {
    switch mode {
    case .srcOver: "Normal"
    case .src: "Source"
    case .clear: "Clear"
    case .dstOver: "Destination over"
    case .srcIn: "Source in"
    case .dstIn: "Destination in"
    case .srcOut: "Source out"
    case .dstOut: "Destination out"
    case .srcAtop: "Source atop"
    case .dstAtop: "Destination atop"
    case .xor: "Xor"
    case .plus: "Plus"
    case .screen: "Screen"
    case .overlay: "Overlay"
    case .darken: "Darken"
    case .lighten: "Lighten"
    case .colorDodge: "Colour dodge"
    case .colorBurn: "Colour burn"
    case .hardLight: "Hard light"
    case .softLight: "Soft light"
    case .difference: "Difference"
    case .exclusion: "Exclusion"
    case .multiply: "Multiply"
    case .hue: "Hue"
    case .saturation: "Saturation"
    case .color: "Colour"
    case .luminosity: "Luminosity"
    }
  }
}
