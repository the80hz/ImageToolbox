import CoreGraphics
import Foundation

/// A tool of the PDF screen that works on one document and gives one file back.
public enum PDFEditTool: String, CaseIterable, Sendable, Identifiable {
  case removePages, rotatePages, turnPages, alignRotation, splitIntoParts, crop, resizePages
  case pagesPerSheet, pageNumbers, watermark, stamp
  case pagesToImages, extractImages, extractText, flatten, grayscale, darkMode
  case metadata, removeAnnotations, sanitize, repair, protect, unlock, compare

  public var id: String { rawValue }

  /// The word added to the file name of the result.
  public var fileSuffix: String {
    switch self {
    case .removePages: "trimmed"
    case .rotatePages, .turnPages, .alignRotation: "rotated"
    case .splitIntoParts: "parts"
    case .crop: "cropped"
    case .resizePages: "resized"
    case .pagesPerSheet: "sheets"
    case .pageNumbers: "numbered"
    case .watermark: "watermarked"
    case .stamp: "stamped"
    case .pagesToImages: "pages"
    case .extractImages: "images"
    case .extractText: "text"
    case .flatten: "flattened"
    case .grayscale: "grayscale"
    case .darkMode: "dark"
    case .metadata: "info"
    case .removeAnnotations: "clean"
    case .sanitize: "sanitized"
    case .repair: "repaired"
    case .protect: "protected"
    case .unlock: "unlocked"
    case .compare: "comparison"
    }
  }
}

/// Everything the tools in `PDFEditTool` can be set with. Each tool reads its own fields and
/// ignores the others, so a screen keeps one value and changes the fields that the chosen tool
/// shows.
public struct PDFEditOptions: Sendable {
  /// The pages a tool works on, such as `1,3-5`. Blank means every page.
  public var pagesText = ""
  /// A turn of the chosen pages, clockwise, in degrees. A multiple of 90.
  public var degrees = 90
  /// Turns of single pages for `turnPages`, such as `3:90, 5:270`. See `PDFPageTurns`.
  public var pageTurnsText = ""
  /// Pages in each part of a split document.
  public var partSize = 1
  public var crop = PDFPageLayout.Crop()
  public var pageSize = PDFPageSize.a4
  public var fitMode = PDFPageLayout.FitMode.fit
  public var matchOrientation = true
  public var pagesOnSheet = 2
  public var sheetOrientation = PDFPageLayout.SheetOrientation.original
  /// Sets the paper size of a sheet to `pageSize`. Otherwise a sheet is as large as its first page.
  public var sheetUsesPageSize = false
  public var sheetMarginPercent = 0.0
  public var numbers = PDFPageNumbers()
  public var watermark = PDFTextWatermark()
  public var stampImage: CGImage?
  public var stampCentre = CGPoint(x: 0.5, y: 0.5)
  public var stampWidth = 0.25
  public var stampOpacity = 1.0
  public var imageFormat = PDFImageExport.Format.png
  public var imageScale = 2.0
  public var imageQuality = 0.9
  public var flattenQuality = 0.7
  public var darkMode = PDFColourTransform.DarkMode()
  public var metadata = PDFMetadata()
  public var annotationKinds: Set<PDFCleanup.AnnotationKind> = [.link]
  public var sanitize = PDFCleanup.Sanitize()
  public var password = ""
  /// The second document of `compare`.
  public var otherDocument: Data?
  public var highlight = RGBA(red: 255, green: 48, blue: 48)
  /// How `compare` judges two pages to differ, and the tolerance it reads. See `PDFComparison`.
  public var comparisonMetric = PDFComparisonMetric.absoluteError
  public var comparisonTolerance = 0.06
  /// Language codes for reading pages that hold only a picture. Empty skips recognition.
  public var recognitionLanguages: [String] = []
  /// The start of the names inside an archive.
  public var baseName = "page"

  public init() {}
}

/// The file a tool made.
public struct PDFEditOutput: Sendable {
  public enum Kind: Sendable {
    case document
    case archive
    case text
  }

  public let data: Data
  public let kind: Kind
  public let tool: PDFEditTool
  /// A count that belongs to the tool: annotations removed, pictures skipped, pages that differ
  /// or pages read from a picture. Nil for the other tools.
  public let count: Int?

  public var fileExtension: String {
    switch kind {
    case .document: "pdf"
    case .archive: "zip"
    case .text: "txt"
    }
  }

  /// The name for the file, such as `report_numbered.pdf`.
  public func fileName(baseName: String) -> String {
    "\(baseName)_\(tool.fileSuffix).\(fileExtension)"
  }
}

/// Runs a `PDFEditTool` on a document.
public enum PDFEditPipeline {

  /// The result of `tool` on `data`. Errors are `PDFEditFailure`, except the ones of
  /// `TextRecognizer`.
  public static func run(
    _ tool: PDFEditTool, on data: Data, options: PDFEditOptions
  ) throws -> PDFEditOutput {
    if tool == .unlock {
      return make(tool, .document, try PDFSecurity.unlock(data, password: options.password))
    }
    if tool == .repair { return make(tool, .document, try PDFCleanup.repair(data)) }
    let count = try PDFKitAccess.open(data).pageCount
    let indices = try pages(options.pagesText, count: count)
    let chosen = options.pagesText.isEmpty ? nil : Set(indices)

    switch tool {
    case .removePages, .rotatePages, .turnPages, .alignRotation, .splitIntoParts, .crop,
      .resizePages, .pagesPerSheet:
      return try layoutTool(tool, data, options, chosen)
    case .pageNumbers, .watermark, .stamp, .grayscale, .darkMode, .flatten, .protect:
      return try documentTool(tool, data, options, chosen)
    case .pagesToImages, .extractImages, .extractText, .metadata, .removeAnnotations, .sanitize,
      .compare, .unlock, .repair:
      return try otherTool(tool, data, options, chosen, indices)
    }
  }

  private static func layoutTool(
    _ tool: PDFEditTool, _ data: Data, _ options: PDFEditOptions, _ chosen: Set<Int>?
  ) throws -> PDFEditOutput {
    switch tool {
    case .removePages:
      guard let chosen else { throw PDFEditFailure.invalidParameter }
      return make(tool, .document, try PDFPageEditing.remove(data, pages: chosen))
    case .rotatePages:
      return make(
        tool, .document, try PDFPageEditing.rotate(data, by: options.degrees, pages: chosen))
    case .turnPages:
      let count = try PDFKitAccess.open(data).pageCount
      let degrees = try PDFPageTurns.degrees(from: options.pageTurnsText, pageCount: count)
      return make(tool, .document, try PDFPageEditing.rotate(data, degreesPerPage: degrees))
    case .alignRotation:
      return make(tool, .document, try PDFPageEditing.alignRotations(data))
    case .splitIntoParts:
      let zip = try PDFPageEditing.splitArchive(
        data, every: options.partSize, baseName: options.baseName)
      return make(tool, .archive, zip)
    case .crop:
      return make(tool, .document, try PDFPageLayout.crop(data, by: options.crop, pages: chosen))
    case .resizePages:
      let resized = try PDFPageLayout.resize(
        data, to: options.pageSize, mode: options.fitMode,
        matchOrientation: options.matchOrientation)
      return make(tool, .document, resized)
    default:
      let sheet = options.sheetUsesPageSize ? options.pageSize : nil
      let sheets = try PDFPageLayout.pagesPerSheet(
        data, count: options.pagesOnSheet, sheet: sheet, orientation: options.sheetOrientation,
        marginPercent: options.sheetMarginPercent)
      return make(tool, .document, sheets)
    }
  }

  private static func documentTool(
    _ tool: PDFEditTool, _ data: Data, _ options: PDFEditOptions, _ chosen: Set<Int>?
  ) throws -> PDFEditOutput {
    let result: Data
    switch tool {
    case .pageNumbers:
      result = try options.numbers.apply(to: data)
    case .watermark:
      var watermark = options.watermark
      watermark.pages = chosen
      result = try watermark.apply(to: data)
    case .stamp:
      guard let image = options.stampImage else { throw PDFEditFailure.invalidParameter }
      result = try PDFImageStamp(
        image: image, centre: options.stampCentre, widthFraction: options.stampWidth,
        opacity: options.stampOpacity, pages: chosen
      ).apply(to: data)
    case .grayscale:
      result = try PDFColourTransform.grayscale(data)
    case .darkMode:
      result = try PDFColourTransform.darkMode(data, options: options.darkMode)
    case .flatten:
      result = try PDFImageExport.flatten(data, quality: options.flattenQuality)
    default:
      result = try PDFSecurity.protect(data, password: options.password)
    }
    return make(tool, .document, result)
  }

  private static func otherTool(
    _ tool: PDFEditTool, _ data: Data, _ options: PDFEditOptions, _ chosen: Set<Int>?,
    _ indices: [Int]
  ) throws -> PDFEditOutput {
    switch tool {
    case .pagesToImages:
      let archive = try PDFImageExport.archive(
        of: data, pages: chosen == nil ? nil : indices, format: options.imageFormat,
        scale: options.imageScale, quality: options.imageQuality, baseName: options.baseName)
      return make(tool, .archive, archive)
    case .extractImages:
      let found = try PDFImageExtractor.extract(from: data)
      guard !found.entries.isEmpty else { throw PDFEditFailure.nothingFound }
      let archive = try PDFImageExtractor.archive(from: data)
      return make(tool, .archive, archive, count: found.skipped)
    case .extractText:
      let text = try PDFText.extract(from: data, recognising: options.recognitionLanguages)
      guard !text.text.isEmpty else { throw PDFEditFailure.nothingFound }
      return make(tool, .text, Data(text.text.utf8), count: text.recognisedPages)
    case .metadata:
      return make(tool, .document, try options.metadata.write(to: data))
    case .removeAnnotations:
      let cleaned = try PDFCleanup.removeAnnotations(
        data, kinds: options.annotationKinds, pages: chosen)
      return make(tool, .document, cleaned.data, count: cleaned.removed)
    case .sanitize:
      return make(tool, .document, try PDFCleanup.sanitize(data, options.sanitize))
    default:
      guard let other = options.otherDocument else { throw PDFEditFailure.invalidParameter }
      let result = try PDFComparison.compare(
        data, with: other, highlight: options.highlight, tolerance: options.comparisonTolerance,
        metric: options.comparisonMetric)
      return make(tool, .document, result.data, count: result.differingPages)
    }
  }

  /// Zero-based indices for the typed pages. Text that does not fit the document throws
  /// `pageOutOfRange`.
  private static func pages(_ text: String, count: Int) throws -> [Int] {
    guard let indices = PDFPageRange.indices(from: text, pageCount: count) else {
      throw PDFEditFailure.pageOutOfRange
    }
    return indices
  }

  private static func make(
    _ tool: PDFEditTool, _ kind: PDFEditOutput.Kind, _ data: Data, count: Int? = nil
  ) -> PDFEditOutput {
    PDFEditOutput(data: data, kind: kind, tool: tool, count: count)
  }
}
