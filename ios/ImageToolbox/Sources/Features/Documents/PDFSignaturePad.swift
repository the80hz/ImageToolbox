import PencilKit
import SwiftUI
import UIKit

/// A pad to draw a signature with a pen. Confirming gives the picture of the strokes on a transparent
/// background, which the Signature tool places on the pages.
struct PDFSignaturePad: View {
  /// Receives the picture of the signature when the user confirms a drawn signature.
  let onConfirm: (CGImage) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var canvas = PKCanvasView()
  @State private var colour = Color.black
  @State private var lineWidth = 6.0

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        SignatureCanvas(canvas: canvas)
          .frame(height: 240)
          .background(Color.white, in: .rect(cornerRadius: 16))
          .accessibilityIdentifier("pdfTools.signature.pad")

        ColorPicker("Pen colour", selection: $colour, supportsOpacity: false)
        ParameterSlider(
          title: "Line width", value: $lineWidth, range: 1...20, step: 1, format: "%.0f")

        Button("Clear") {
          canvas.drawing = PKDrawing()
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("pdfTools.signature.clear")

        Spacer(minLength: 0)
      }
      .padding()
      .navigationTitle("Draw signature")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Use signature") { confirm() }
            .accessibilityIdentifier("pdfTools.signature.use")
        }
      }
      .onChange(of: colour) { _, _ in applyPen() }
      .onChange(of: lineWidth) { _, _ in applyPen() }
    }
  }

  /// The pen for the strokes that follow, with the chosen colour and line width.
  private func applyPen() {
    canvas.tool = PKInkingTool(
      .pen, color: UIColor(colour), width: CGFloat(lineWidth))
  }

  /// Makes the picture of the strokes and closes the pad. Nothing is drawn yet, so nothing happens.
  private func confirm() {
    let drawing = canvas.drawing
    guard !drawing.bounds.isEmpty else { return }
    let frame = drawing.bounds.insetBy(dx: -8, dy: -8)
    guard let picture = drawing.image(from: frame, scale: 3).cgImage else { return }
    onConfirm(picture)
    dismiss()
  }
}

/// The PencilKit canvas of the signature pad. It takes a finger as well as the Apple Pencil.
private struct SignatureCanvas: UIViewRepresentable {
  let canvas: PKCanvasView

  func makeUIView(context: Context) -> PKCanvasView {
    canvas.drawingPolicy = .anyInput
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    canvas.tool = PKInkingTool(.pen, color: .black, width: 6)
    return canvas
  }

  func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
