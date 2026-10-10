import PencilKit
import SwiftUI
import UIKit

/// A PencilKit canvas over the picture. It takes Apple Pencil and finger strokes while Pencil mode
/// is on. The strokes are kept in drawing units, the same units as the model, so no conversion is
/// needed when they are copied in or out.
struct DrawingPencilCanvas: UIViewRepresentable {
  let model: DrawingToolModel
  /// The strokes that the model holds. A change to them is copied into the canvas.
  let strokes: PKDrawing
  let ink: UIColor
  /// Width of the ink in drawing units.
  let inkWidth: CGFloat
  /// Whether the canvas takes touches. It is switched off in the other modes.
  let isActive: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(model: model)
  }

  func makeUIView(context: Context) -> PencilCanvasHost {
    let host = PencilCanvasHost()
    host.canvas.delegate = context.coordinator
    update(host, coordinator: context.coordinator)
    return host
  }

  func updateUIView(_ host: PencilCanvasHost, context: Context) {
    update(host, coordinator: context.coordinator)
  }

  private func update(_ host: PencilCanvasHost, coordinator: Coordinator) {
    host.isUserInteractionEnabled = isActive

    if coordinator.ink != ink || coordinator.inkWidth != inkWidth {
      coordinator.ink = ink
      coordinator.inkWidth = inkWidth
      // Monoline ink has the same width along a stroke, like the brush's radius.
      host.canvas.tool = PKInkingTool(.monoline, color: ink, width: inkWidth)
    }

    if host.canvas.drawing != strokes {
      // The copy must not be copied back by the delegate.
      coordinator.isApplying = true
      host.canvas.drawing = strokes
      coordinator.isApplying = false
    }
  }

  @MainActor
  final class Coordinator: NSObject, PKCanvasViewDelegate {
    let model: DrawingToolModel
    var ink: UIColor?
    var inkWidth: CGFloat = 0
    /// True while the model's strokes are being copied into the canvas.
    var isApplying = false

    init(model: DrawingToolModel) {
      self.model = model
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      guard !isApplying else { return }
      model.setPencilStrokes(canvasView.drawing)
    }
  }
}

/// Holds a PencilKit canvas in drawing units and scales it to the square on screen. The canvas
/// keeps the size of the drawing, so strokes keep their place when the square is resized.
final class PencilCanvasHost: UIView {
  let canvas = PKCanvasView()

  init() {
    super.init(frame: .zero)
    backgroundColor = .clear
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    // Fingers draw as well as the Pencil. The canvas does not scroll, because the square is fixed.
    canvas.drawingPolicy = .anyInput
    canvas.isScrollEnabled = false
    addSubview(canvas)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let side = min(bounds.width, bounds.height)
    guard side > 0 else { return }
    let units = CGFloat(DrawingToolModel.canvasSide)
    canvas.transform = .identity
    canvas.bounds = CGRect(x: 0, y: 0, width: units, height: units)
    canvas.contentSize = canvas.bounds.size
    canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
    canvas.transform = CGAffineTransform(scaleX: side / units, y: side / units)
  }
}
