import ImageToolboxKit
import SwiftUI

/// The labels and messages of the PDF screen, shared by its sections.
enum PDFToolLabels {
  /// A byte count in the system's file size style, such as "1.2 MB".
  static func sizeText(_ bytes: Int) -> String {
    Int64(bytes).formatted(.byteCount(style: .file))
  }

  static func title(for position: PDFPageNumbers.Position) -> LocalizedStringKey {
    switch position {
    case .topLeft: "Top left"
    case .topCenter: "Top center"
    case .topRight: "Top right"
    case .centerLeft: "Middle left"
    case .center: "Middle center"
    case .centerRight: "Middle right"
    case .bottomLeft: "Bottom left"
    case .bottomCenter: "Bottom center"
    case .bottomRight: "Bottom right"
    }
  }

  static func title(for mode: PDFPageLayout.FitMode) -> LocalizedStringKey {
    switch mode {
    case .fit: "Fit"
    case .fill: "Fill"
    case .stretch: "Stretch"
    }
  }

  static func title(for orientation: PDFPageLayout.SheetOrientation) -> LocalizedStringKey {
    switch orientation {
    case .original: "First page"
    case .portrait: "Portrait"
    case .landscape: "Landscape"
    }
  }

  static func title(for kind: PDFCleanup.AnnotationKind) -> LocalizedStringKey {
    switch kind {
    case .link: "Links"
    case .fileAttachment: "File attachments"
    case .line: "Line annotations"
    case .popup: "Popups"
    case .stamp: "Stamps"
    case .shape: "Rectangles and ellipses"
    case .note: "Sticky notes"
    case .textMarkup: "Highlights and underlines"
    case .freeText: "Free text"
    case .ink: "Ink drawings"
    case .widget: "Form fields"
    case .other: "Other annotations"
    }
  }

  static func title(for rule: ImagesToPDF.WidthRule) -> LocalizedStringKey {
    switch rule {
    case .none: "Each picture's own width"
    case .widest: "Widest picture"
    case .narrowest: "Narrowest picture"
    }
  }

  static func title(for field: PDFCaptionField) -> LocalizedStringKey {
    switch field {
    case .sequenceNumber: "Number"
    case .imageDimensions: "Size in pixels"
    case .fileSize: "File size"
    case .cameraModel: "Camera"
    case .lens: "Lens"
    case .exposureSettings: "Exposure settings"
    case .dateTaken: "Date taken"
    case .customText: "Custom text"
    }
  }

  static func title(for theme: PDFDarkTheme) -> LocalizedStringKey {
    switch theme {
    case .warm: "Warm"
    case .classic: "Classic"
    case .graphite: "Graphite"
    case .midnight: "Midnight"
    case .blue: "Blue"
    case .green: "Green"
    case .sepia: "Sepia"
    case .purple: "Purple"
    case .burgundy: "Burgundy"
    case .slate: "Slate"
    case .negative: "Negative"
    case .custom: "Custom"
    }
  }

  static func title(for blend: PDFBlendMode) -> LocalizedStringKey {
    switch blend {
    case .screen: "Screen"
    case .multiply: "Multiply"
    case .overlay: "Overlay"
    case .darken: "Darken"
    case .lighten: "Lighten"
    case .softLight: "Soft light"
    case .difference: "Difference"
    case .exclusion: "Exclusion"
    case .hue: "Hue"
    case .saturation: "Saturation"
    case .color: "Colour"
    case .luminosity: "Luminosity"
    }
  }

  static func title(for metric: PDFComparisonMetric) -> LocalizedStringKey {
    switch metric {
    case .absoluteError: "Absolute error"
    case .meanAbsoluteError: "Mean absolute error"
    case .rootMeanSquaredError: "Root mean squared error"
    case .peakSignalToNoiseRatio: "Peak signal-to-noise ratio"
    case .structuralSimilarity: "Structural similarity (SSIM)"
    case .normalizedCrossCorrelation: "Cross-correlation (NCC)"
    }
  }

  /// The label of the count a tool reports with its result, or nil for a tool that reports none.
  static func countTitle(for tool: PDFEditTool) -> LocalizedStringKey? {
    switch tool {
    case .removeAnnotations: "Annotations removed"
    case .compare: "Pages that differ"
    default: nil
    }
  }

  static func message(for failure: PDFEditFailure) -> LocalizedStringKey {
    switch failure {
    case .unreadable: "This file is not a readable PDF."
    case .locked: "This PDF is locked. Use the unlock tool first."
    case .wrongPassword: "The password is wrong."
    case .noPages: "No pages are left to keep."
    case .pageOutOfRange: "One of the page numbers is outside the document."
    case .invalidParameter: "Check the values entered for this tool."
    case .nothingFound: "Nothing for this tool was found in the PDF."
    case .encodeFailed, .writeFailed: "The file could not be written."
    }
  }
}

extension PDFEditTool {
  var title: LocalizedStringKey {
    switch self {
    case .splitIntoParts: "Split into parts"
    case .removePages: "Remove pages"
    case .turnPages: "Rotate single pages"
    case .pageNumbers: "Page numbers"
    case .watermark: "Watermark"
    case .extractImages: "Extract images"
    case .pagesToImages: "PDF to images"
    case .crop: "Crop"
    case .metadata: "Metadata"
    case .protect: "Lock with password"
    case .unlock: "Unlock"
    case .grayscale: "Grayscale"
    case .flatten: "Flatten"
    case .repair: "Repair"
    case .alignRotation: "Align rotation"
    case .extractText: "Extract text"
    case .darkMode: "Dark mode"
    case .resizePages: "Resize pages"
    case .pagesPerSheet: "Pages per sheet"
    case .stamp: "Signature"
    case .removeAnnotations: "Remove annotations"
    case .sanitize: "Sanitize"
    case .compare: "Compare PDFs"
    default: "PDF tool"
    }
  }
}
