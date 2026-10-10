import SwiftUI

struct BackgroundRemovalToolView: View {
  @State private var model = BackgroundRemovalToolModel()
  /// Width of the canvas area, measured from the section. The canvas is sized from it.
  @State private var canvasWidth: CGFloat = 0

  /// The canvas is never taller than this, so a portrait picture does not fill the whole screen.
  private static let maxCanvasHeight: CGFloat = 480

  var body: some View {
    ToolScaffold(identifier: "backgroundRemoval") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("backgroundRemoval.pick")

        if let source = model.source {
          PictureView(image: source.image)
        }
      }

      if model.source != nil {
        GlassSection("Removal") {
          if model.engines.count > 1 {
            Picker("Method", selection: Bindable(model).engine) {
              ForEach(model.engines, id: \.self) { engine in
                Text(engine.title).tag(engine)
              }
            }
            .pickerStyle(.menu)
            .disabled(model.isRemoving)
            .accessibilityIdentifier("backgroundRemoval.engine")
          }

          Text(model.engine.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button("Remove background") {
            Task { await model.removeBackground() }
          }
          .buttonStyle(.glassProminent)
          .disabled(model.isRemoving)
          .accessibilityIdentifier("backgroundRemoval.remove")

          if model.isRemoving {
            ProgressView()
          }
        }
      }

      if let preview = model.preview {
        refineSection(preview)
      }

      if let result = model.result {
        GlassSection("Result") {
          ShareFileButton(title: "Share PNG", data: result.png, fileName: model.resultFileName)
            .accessibilityIdentifier("backgroundRemoval.share")

          SaveFileButton(title: "Save to Files", data: result.png, fileName: model.resultFileName)
            .accessibilityIdentifier("backgroundRemoval.save")
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

  private func refineSection(_ preview: CGImage) -> some View {
    GlassSection("Refine") {
      canvas(preview)

      Text("Drag to paint. Restore brings the original back, erase makes it transparent.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      if model.result == nil {
        ProgressView()
      }

      Picker("Mode", selection: Bindable(model).refineMode) {
        Text("Restore").tag(BackgroundRemovalToolModel.RefineMode.restore)
        Text("Erase").tag(BackgroundRemovalToolModel.RefineMode.erase)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("backgroundRemoval.mode")

      ParameterSlider(
        title: "Brush size",
        value: Bindable(model).brushSize,
        range: 4...80,
        step: 1
      )
      .accessibilityIdentifier("backgroundRemoval.brush")

      HStack {
        Button("Undo") {
          model.undoEdit()
        }
        .buttonStyle(.glass)
        .disabled(!model.hasEdits)
        .accessibilityIdentifier("backgroundRemoval.undo")

        Button("Reset to automatic") {
          model.resetEdits()
        }
        .buttonStyle(.glass)
        .disabled(!model.hasEdits)
        .accessibilityIdentifier("backgroundRemoval.reset")
      }
    }
  }

  // MARK: - Canvas

  /// The picture at its own aspect ratio. It is as wide as the section, up to `maxCanvasHeight`
  /// tall. It takes the drags for brush strokes. The backdrop is white, so removed areas stand out.
  private func canvas(_ image: CGImage) -> some View {
    let base = CGSize(width: image.width, height: image.height)
    let width = min(canvasWidth, Self.maxCanvasHeight * base.width / base.height)
    let height = width * base.height / base.width
    let size = CGSize(width: width, height: height)
    let pending = model.pendingEdits
    return ZStack {
      Rectangle()
        .fill(.white)

      Image(decorative: image, scale: 1)
        .resizable()

      Canvas { context, _ in
        drawPendingEdits(pending, in: &context, size: size, base: base)
      }
    }
    .frame(width: width, height: height)
    .contentShape(Rectangle())
    .gesture(brushGesture(size: size, base: base))
    .clipShape(.rect(cornerRadius: 16))
    .frame(maxWidth: .infinity)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      canvasWidth = newWidth
    }
    .accessibilityElement()
    .accessibilityLabel("Refinement canvas")
    .accessibilityIdentifier("backgroundRemoval.canvas")
  }

  /// One drag gesture paints. A drag adds points, and a tap paints a single dab.
  private func brushGesture(size: CGSize, base: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        model.continueStroke(
          at: picturePoint(value.location, size: size, base: base),
          radius: pictureRadius(size: size, base: base))
      }
      .onEnded { _ in
        model.endStroke()
      }
  }

  /// Draws the strokes the preview does not show yet, as round-capped lines. Erase strokes are red,
  /// restore strokes are green. Their width is the brush diameter.
  private func drawPendingEdits(
    _ edits: [BackgroundRemovalToolModel.MaskEdit], in context: inout GraphicsContext,
    size: CGSize, base: CGSize
  ) {
    guard base.width > 0 else { return }
    let scale = size.width / base.width
    for edit in edits {
      let points = edit.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
      guard let first = points.first else { continue }

      var path = Path()
      path.move(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
      // A single point becomes a dot, because a round cap on a zero-length line is visible.
      if points.count == 1 {
        path.addLine(to: first)
      }

      let colour: Color = edit.mode == .erase ? .red : .green
      context.stroke(
        path,
        with: .color(colour.opacity(0.5)),
        style: StrokeStyle(
          lineWidth: CGFloat(edit.radius) * 2 * scale,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
  }

  // MARK: - Mapping

  /// Maps a point on the canvas to picture pixels. The canvas shows the whole picture, so one scale
  /// applies to both axes.
  private func picturePoint(_ location: CGPoint, size: CGSize, base: CGSize) -> CGPoint {
    guard size.width > 0, size.height > 0 else { return .zero }
    return CGPoint(
      x: location.x / size.width * base.width,
      y: location.y / size.height * base.height)
  }

  /// The brush radius in picture pixels, so a stroke covers the same area on screen at any zoom.
  private func pictureRadius(size: CGSize, base: CGSize) -> Double {
    guard size.width > 0 else { return model.brushSize / 2 }
    return model.brushSize / 2 * Double(base.width / size.width)
  }
}
