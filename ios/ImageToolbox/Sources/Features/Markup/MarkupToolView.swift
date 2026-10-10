import ImageToolboxKit
import PhotosUI
import SwiftUI

struct MarkupToolView: View {
  // Not private: the selected-layer controls live in an extension in MarkupLayerControls.swift.
  @State var model = MarkupToolModel()
  /// Width of the canvas area, measured from the section. The canvas is sized from it.
  @State private var canvasWidth: CGFloat = 0

  /// The canvas is never taller than this, so a portrait picture does not fill the whole screen.
  private static let maxCanvasHeight: CGFloat = 480
  /// How far a tap may land from a layer, in points. It is converted to picture pixels for the hit test.
  private static let touchSlop: CGFloat = 12
  static let gridColumns = [GridItem(.adaptive(minimum: 130), spacing: 8)]

  var body: some View {
    ToolScaffold(identifier: "markup") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("markup.pick")
      }

      if model.source != nil {
        canvasSection
        addSection
        layersSection
        selectedSection
      }

      if let exportData = model.exportData {
        GlassSection("Export") {
          ShareFileButton(title: "Share file", data: exportData, fileName: model.exportFileName)
            .accessibilityIdentifier("markup.share")

          SaveFileButton(title: "Save to Files", data: exportData, fileName: model.exportFileName)
            .accessibilityIdentifier("markup.save")
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  // MARK: - Sections
  private var canvasSection: some View {
    GlassSection("Canvas") {
      canvas

      Text(canvasHint)
        .font(.footnote)
        .foregroundStyle(.secondary)

      HStack {
        button("Undo", id: "markup.undo", disabled: !model.canUndo) { model.undo() }
        button("Redo", id: "markup.redo", disabled: !model.canRedo) { model.redo() }
      }
    }
  }

  private var addSection: some View {
    GlassSection("Add") {
      TextField("Text to add", text: Bindable(model).textDraft)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("markup.textField")

      LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 8) {
        button("Text", id: "markup.addText", disabled: !model.hasTextDraft) {
          model.addText(model.textDraft)
        }
        ForEach(MarkupLayer.Content.ShapeKind.allCases, id: \.self) { kind in
          button(
            LocalizedStringKey(MarkupToolModel.shapeName(kind)), id: "markup.add.\(kind)"
          ) {
            model.addShape(kind)
          }
        }
        toggle("Filled", id: "markup.filled", isOn: model.shapeFilled) {
          model.shapeFilled.toggle()
        }
        toggle("Stroke", id: "markup.stroke", isOn: model.interaction == .stroke) {
          model.interaction = .stroke
        }
        toggle("Select", id: "markup.select", isOn: model.interaction == .select) {
          model.interaction = .select
        }

        SinglePhotoButton(title: "Sticker", selection: Bindable(model).stickerSelection)
          .accessibilityIdentifier("markup.sticker")
        SinglePhotoButton(title: "Image", selection: Bindable(model).imageSelection)
          .accessibilityIdentifier("markup.image")
      }
    }
  }

  private var layersSection: some View {
    GlassSection("Layers") {
      if model.document.layers.isEmpty {
        Text("No layers yet. Add text, a shape, a stroke or a sticker.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        // The top layer is listed first, as it is drawn last.
        ForEach(model.document.layers.indices.reversed(), id: \.self) { index in
          layerRow(index)
        }
      }
    }
  }

  // MARK: - Canvas

  /// The picture at its own aspect ratio. It is as wide as the section, up to `maxCanvasHeight` tall.
  /// It takes the drags for strokes and taps for selection.
  private var canvas: some View {
    let base = model.baseSize ?? CGSize(width: 1, height: 1)
    let width = min(canvasWidth, Self.maxCanvasHeight * base.width / base.height)
    let height = width * base.height / base.width
    let size = CGSize(width: width, height: height)
    let pending = model.pendingStroke
    return ZStack {
      if let image = model.displayImage {
        Image(decorative: image, scale: 1)
          .resizable()
      }
      Canvas { context, _ in
        drawPendingStroke(pending, in: &context, size: size, base: base)
      }
    }
    .frame(width: width, height: height)
    .contentShape(Rectangle())
    .gesture(canvasGesture(size: size, base: base))
    .clipShape(.rect(cornerRadius: 16))
    .frame(maxWidth: .infinity)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      canvasWidth = newWidth
    }
    .accessibilityElement()
    .accessibilityLabel("Markup canvas")
    .accessibilityIdentifier("markup.canvas")
  }

  /// One drag gesture for both modes. A drag adds points in stroke mode. In select mode a drag moves
  /// the layer under its start, and a tap selects that layer.
  private func canvasGesture(size: CGSize, base: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        switch model.interaction {
        case .stroke:
          model.continueStroke(at: picturePoint(value.location, size: size, base: base))
        case .select:
          let tolerance = size.width > 0 ? Double(Self.touchSlop * base.width / size.width) : 0
          model.dragSelected(
            from: picturePoint(value.startLocation, size: size, base: base),
            to: picturePoint(value.location, size: size, base: base),
            tolerance: tolerance)
        }
      }
      .onEnded { _ in
        switch model.interaction {
        case .stroke:
          model.endStroke()
        case .select:
          model.endMove()
        }
      }
  }

  /// Maps a point on the canvas to picture pixels. The canvas shows the whole picture, so one scale
  /// applies to both axes.
  private func picturePoint(_ location: CGPoint, size: CGSize, base: CGSize) -> CGPoint {
    guard size.width > 0, size.height > 0 else { return .zero }
    return CGPoint(
      x: location.x / size.width * base.width,
      y: location.y / size.height * base.height)
  }

  /// Draws the stroke under the finger as round-capped lines. It is not a layer until the drag ends.
  private func drawPendingStroke(
    _ points: [CGPoint], in context: inout GraphicsContext, size: CGSize, base: CGSize
  ) {
    guard let brush = model.brush, let first = points.first, base.width > 0 else { return }
    let scale = size.width / base.width
    let scaled = points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
    var path = Path()
    path.move(to: scaled[0])
    for point in scaled.dropFirst() {
      path.addLine(to: point)
    }
    // A single point becomes a dot, because a round cap on a zero-length line is visible.
    if points.count == 1 {
      path.addLine(to: CGPoint(x: first.x * scale, y: first.y * scale))
    }

    let ink = MarkupToolModel.ink
    context.stroke(
      path,
      with: .color(Color(red: ink.red, green: ink.green, blue: ink.blue)),
      style: StrokeStyle(
        lineWidth: CGFloat(brush.radius) * 2 * scale,
        lineCap: .round,
        lineJoin: .round
      )
    )
  }

  // MARK: - Layers
  /// One row of the layer list. Tapping it selects the layer.
  private func layerRow(_ index: Int) -> some View {
    let layer = model.document.layers[index]
    let isSelected = model.selectedLayer == index
    return Button {
      model.selectLayer(at: index)
    } label: {
      HStack(spacing: 12) {
        Text(verbatim: layer.name)
          .font(.body.weight(isSelected ? .semibold : .regular))
        Spacer()
        if !layer.isVisible {
          Image(systemName: "eye.slash")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Hidden")
        }
        if isSelected {
          Image(systemName: "checkmark")
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("markup.layer.\(index)")
  }

  // MARK: - Helpers

  /// A glass button with an accessibility identifier.
  func button(
    _ title: LocalizedStringKey, id: String, disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(title, action: action)
      .buttonStyle(.glass)
      .disabled(disabled)
      .accessibilityIdentifier(id)
  }

  /// A button that shows an on or off state. `action` makes the change.
  func toggle(
    _ title: LocalizedStringKey, id: String, isOn: Bool, action: @escaping () -> Void
  ) -> some View {
    Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
      .toggleStyle(.button)
      .accessibilityIdentifier(id)
  }

  /// A slider for one value of the selected layer. Each move is previewed, and the drag becomes one
  /// undo step when it ends.
  func slider(
    _ title: LocalizedStringKey, _ value: Double, _ range: ClosedRange<Double>,
    step: Double = 1, format: String = "%.0f",
    set: @escaping (inout MarkupLayer, Double) -> Void
  ) -> some View {
    ParameterSlider(
      title: title,
      value: Binding(
        get: { value }, set: { newValue in model.previewSelected { set(&$0, newValue) } }),
      onEditingEnded: { model.finishSliderEdit() },
      range: range,
      step: step,
      format: format
    )
  }

  private var canvasHint: LocalizedStringKey {
    model.interaction == .stroke
      ? "Drag on the picture to draw." : "Tap a layer to select it. Drag it to move it."
  }
}
