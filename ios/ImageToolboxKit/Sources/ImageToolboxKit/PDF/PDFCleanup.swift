import CoreGraphics
import Foundation
import PDFKit

/// Removes what rides along with the pages of a PDF: annotations, form fields, attachments,
/// scripts and metadata. It also rewrites a damaged file.
public enum PDFCleanup {

  /// A group of annotations that can be removed together.
  public enum AnnotationKind: String, CaseIterable, Sendable {
    case link
    case fileAttachment
    case line
    case popup
    case stamp
    /// Rectangles and ellipses.
    case shape
    /// Sticky notes.
    case note
    /// Highlights, underlines, strike-outs and squiggles.
    case textMarkup
    case freeText
    case ink
    /// Form fields.
    case widget
    /// Every other kind.
    case other

    /// The PDF subtypes of the kind. Nil for `other`, which holds all that no kind lists.
    var subtypes: Set<String>? {
      switch self {
      case .link: ["Link"]
      case .fileAttachment: ["FileAttachment"]
      case .line: ["Line"]
      case .popup: ["Popup"]
      case .stamp: ["Stamp"]
      case .shape: ["Square", "Circle"]
      case .note: ["Text"]
      case .textMarkup: ["Highlight", "Underline", "StrikeOut", "Squiggly"]
      case .freeText: ["FreeText"]
      case .ink: ["Ink"]
      case .widget: ["Widget"]
      case .other: nil
      }
    }
  }

  /// What `sanitize` takes out.
  public struct Sanitize: Equatable, Sendable {
    /// Title, author, subject, keywords and creator.
    public var metadata: Bool
    /// Every annotation.
    public var annotations: Bool
    /// Form fields.
    public var forms: Bool
    /// Attached files.
    public var attachments: Bool
    /// Scripts and automatic actions. This rebuilds the pages, which also removes links, form
    /// fields, attachments and outlines whatever the other switches say.
    public var scripts: Bool

    public init(
      metadata: Bool = true, annotations: Bool = true, forms: Bool = true,
      attachments: Bool = true, scripts: Bool = true
    ) {
      self.metadata = metadata
      self.annotations = annotations
      self.forms = forms
      self.attachments = attachments
      self.scripts = scripts
    }
  }

  // MARK: - Annotations

  /// The document without the annotations of the given kinds on the chosen pages (nil is every
  /// page). Returns the new document and how many annotations were removed.
  public static func removeAnnotations(
    _ data: Data, kinds: Set<AnnotationKind>, pages: Set<Int>? = nil
  ) throws -> (data: Data, removed: Int) {
    let document = try PDFKitAccess.open(data)
    if let pages, !pages.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) {
      throw PDFEditFailure.pageOutOfRange
    }
    var removed = 0
    for index in 0..<document.pageCount where pages?.contains(index) ?? true {
      guard let page = document.page(at: index) else { continue }
      for annotation in page.annotations where matches(annotation, kinds) {
        page.removeAnnotation(annotation)
        removed += 1
      }
    }
    return (try PDFKitAccess.write(document), removed)
  }

  private static func matches(_ annotation: PDFAnnotation, _ kinds: Set<AnnotationKind>) -> Bool {
    let subtype = annotation.type ?? ""
    let listed = AnnotationKind.allCases.contains { $0.subtypes?.contains(subtype) ?? false }
    return kinds.contains { kind in
      kind.subtypes?.contains(subtype) ?? !listed
    }
  }

  // MARK: - Sanitize

  /// The document with the chosen kinds of hidden content taken out.
  public static func sanitize(_ data: Data, _ options: Sanitize = Sanitize()) throws -> Data {
    if options.scripts {
      let source = try PDFSourcePages(data)
      let sizes = (0..<source.pageCount).map(source.displayedSize(of:))
      return try source.rebuild(sizes: sizes, keepInfo: !options.metadata) { index, context in
        source.draw(index, in: context, to: CGRect(origin: .zero, size: sizes[index]))
      }
    }
    var kinds: Set<AnnotationKind> = []
    if options.annotations { kinds = Set(AnnotationKind.allCases) }
    if options.forms { kinds.insert(.widget) }
    if options.attachments { kinds.insert(.fileAttachment) }
    let document = try PDFKitAccess.open(data)
    if !kinds.isEmpty {
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        for annotation in page.annotations where matches(annotation, kinds) {
          page.removeAnnotation(annotation)
        }
      }
    }
    if options.metadata { document.documentAttributes = [:] }
    return try PDFKitAccess.write(document)
  }

  // MARK: - Repair

  /// The document written again from what could be read of it, with a complete cross-reference
  /// table. A file that is cut short or has a broken table opens when its pages can be found. A
  /// file with no readable page throws `unreadable`.
  public static func repair(_ data: Data) throws -> Data {
    if let document = PDFDocument(data: data) {
      if document.isLocked { throw PDFEditFailure.locked }
      if document.pageCount > 0, let repaired = document.dataRepresentation() { return repaired }
    }
    // PDFKit gave up, so Core Graphics draws the pages it can find into a new document.
    let source = try PDFSourcePages(data)
    let sizes = (0..<source.pageCount).map(source.displayedSize(of:))
    return try source.rebuild(sizes: sizes) { index, context in
      source.draw(index, in: context, to: CGRect(origin: .zero, size: sizes[index]))
    }
  }
}
