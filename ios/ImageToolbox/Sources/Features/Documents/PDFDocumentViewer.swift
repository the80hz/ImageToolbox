import PDFKit
import SwiftUI
import UIKit

/// Shows a PDF in PDFKit's own view, with PDFKit's thumbnail strip for jumping between pages.
/// Read-only: the viewer scrolls, zooms and turns pages but never changes the document.
struct PDFDocumentViewer: UIViewRepresentable {
  /// The PDF to show. The document is rebuilt only when these bytes change.
  let data: Data

  /// Keeps the PDF view for as long as the screen shows the viewer, and the bytes it holds.
  @MainActor
  final class Coordinator {
    let pdfView = PDFView()
    var shown: Data?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> UIStackView {
    let pdfView = context.coordinator.pdfView
    pdfView.displayMode = .singlePage
    pdfView.displayDirection = .horizontal
    pdfView.autoScales = true
    pdfView.backgroundColor = .secondarySystemBackground
    // Swiping turns pages in PDFKit's page controller, which leaves the vertical scroll of the
    // screen alone.
    pdfView.usePageViewController(true)

    let thumbnails = PDFThumbnailView()
    thumbnails.pdfView = pdfView
    thumbnails.layoutMode = .horizontal
    thumbnails.thumbnailSize = CGSize(width: 40, height: 56)
    thumbnails.heightAnchor.constraint(equalToConstant: 64).isActive = true

    let stack = UIStackView(arrangedSubviews: [pdfView, thumbnails])
    stack.axis = .vertical
    stack.spacing = 8
    return stack
  }

  func updateUIView(_ stack: UIStackView, context: Context) {
    let coordinator = context.coordinator
    guard coordinator.shown != data else { return }
    coordinator.shown = data
    coordinator.pdfView.document = PDFDocument(data: data)
  }
}
