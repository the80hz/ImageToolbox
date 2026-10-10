import ImageToolboxKit
import SwiftUI
import UIKit

/// The square drawing area. The last rendered picture sits under the edits that are not rendered
/// yet, so a finished edit stays visible until the picture catches up.
struct DrawingCanvasView: View {
  let model: DrawingToolModel

  var body: some View {
    GeometryReader { proxy in
      let side = proxy.size.width
      ZStack {
        Rectangle()
          .fill(.white)

        if let preview = model.preview {
          Image(decorative: preview, scale: 1)
            .resizable()
            .scaledToFit()
        }

        Canvas { context, size in
          drawPendingEdits(in: &context, size: size)
        }

        // Kept in every mode, so that PencilKit is set up once. It takes touches only in Pencil
        // mode, and the other modes draw through the gesture below.
        DrawingPencilCanvas(
          model: model,
          strokes: model.pencilStrokes,
          ink: UIColor(model.colour),
          inkWidth: CGFloat(model.radius) * 2,
          isActive: model.mode == .pencil
        )
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            model.drag(to: canvasPoint(value.location, side: side))
          }
          .onEnded { _ in
            model.endDrag()
          },
        including: model.mode == .pencil ? .none : .all
      )
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(.rect(cornerRadius: 16))
    .accessibilityElement()
    .accessibilityLabel("Drawing canvas")
    .accessibilityIdentifier("drawing.canvas")
  }

  /// Draws the edits the preview does not show yet, then the lasso outline. Edits that change
  /// pixels (eraser, blur, spray, fill, lasso, spot healing, warp) show as an approximation, or
  /// not at all, until the next refresh renders them exactly.
  private func drawPendingEdits(in context: inout GraphicsContext, size: CGSize) {
    let scale = size.width / CGFloat(DrawingToolModel.canvasSide)
    for edit in model.pendingEdits {
      switch edit {
      case .stroke(let stroke):
        drawStroke(stroke, in: &context, scale: scale)

      case .shape(let shape):
        drawShape(shape, in: &context, scale: scale)

      case .pencil(let patch):
        drawPencilPatch(patch, in: &context, scale: scale)

      case .spray, .flood, .lasso, .heal, .warp:
        break
      }
    }
    drawLassoOutline(in: &context, scale: scale)
  }

  /// Draws committed PencilKit ink in the drawing colour. It shows until the preview is rendered,
  /// so the strokes do not vanish for the short pause before the refresh.
  private func drawPencilPatch(
    _ patch: DrawingToolModel.PencilPatch, in context: inout GraphicsContext, scale: CGFloat
  ) {
    guard let image = patch.raster(colour: model.rgbComponents).toCGImage() else { return }
    let rect = CGRect(
      x: CGFloat(patch.x) * scale, y: CGFloat(patch.y) * scale,
      width: CGFloat(patch.width) * scale, height: CGFloat(patch.height) * scale)
    context.draw(Image(decorative: image, scale: 1), in: rect)
  }

  /// Draws a stroke as round-capped lines, broken up by its line style. Its width is the brush
  /// diameter. The effect kinds are approximated: the eraser shows as white, blur and pixelation as
  /// grey, and the glow of neon is left out until the refresh.
  private func drawStroke(
    _ stroke: DrawingToolModel.Stroke, in context: inout GraphicsContext, scale: CGFloat
  ) {
    let diameter = stroke.brush.radius * 2
    let style = StrokeStyle(
      lineWidth: CGFloat(diameter) * scale, lineCap: .round, lineJoin: .round)
    let ink: Color
    switch stroke.kind {
    case .pen, .neon: ink = model.colour
    case .highlighter: ink = model.colour.opacity(RegionEffects.highlighterOpacity)
    case .eraser: ink = .white
    case .blur, .pixelate: ink = .gray.opacity(0.35)
    }
    for piece in stroke.style.pieces(of: stroke.points, diameter: diameter) {
      context.stroke(polyline(piece, scale: scale), with: .color(ink), style: style)
    }
  }

  /// Draws the shape that is being dragged out. The outline comes from the kit, so it is the same
  /// geometry that is painted on release.
  private func drawShape(
    _ shape: DrawingToolModel.ShapeEdit, in context: inout GraphicsContext, scale: CGFloat
  ) {
    let diameter = shape.brush.radius * 2
    let outline = ShapeOutline.make(
      shape.kind, from: shape.start, to: shape.end, options: shape.options, strokeWidth: diameter)

    if shape.filled, let polygon = outline.polygon {
      var path = polyline(polygon, scale: scale)
      path.closeSubpath()
      context.fill(path, with: .color(model.colour))
      return
    }
    let style = StrokeStyle(
      lineWidth: CGFloat(diameter) * scale, lineCap: .round, lineJoin: .round)
    for stroke in outline.strokes {
      for piece in shape.options.lineStyle.pieces(of: stroke, diameter: diameter) {
        context.stroke(polyline(piece, scale: scale), with: .color(model.colour), style: style)
      }
    }
  }

  /// Draws the lasso outline as a closed dashed line.
  private func drawLassoOutline(in context: inout GraphicsContext, scale: CGFloat) {
    guard model.lassoOutline.count > 1 else { return }
    var path = polyline(model.lassoOutline, scale: scale)
    path.closeSubpath()
    context.stroke(
      path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
  }

  /// An open path through `points` in drawing units, scaled to the canvas. A single point becomes
  /// a dot, because a round cap on a zero-length line is visible.
  private func polyline(_ points: [CGPoint], scale: CGFloat) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: scaled(first, by: scale))
    for point in points.dropFirst() {
      path.addLine(to: scaled(point, by: scale))
    }
    if points.count == 1 {
      path.addLine(to: scaled(first, by: scale))
    }
    return path
  }

  private func scaled(_ point: CGPoint, by scale: CGFloat) -> CGPoint {
    CGPoint(x: point.x * scale, y: point.y * scale)
  }

  /// Maps a point on the square to drawing units, so strokes keep their place when the view
  /// resizes.
  private func canvasPoint(_ location: CGPoint, side: CGFloat) -> CGPoint {
    guard side > 0 else { return location }
    let scale = CGFloat(DrawingToolModel.canvasSide) / side
    return CGPoint(x: location.x * scale, y: location.y * scale)
  }
}
