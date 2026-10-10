import CoreGraphics
import Foundation

/// Turns the pages of a PDF into pictures, and into pages that are one picture each.
public enum PDFImageExport {

  /// The picture format of a page.
  public enum Format: String, CaseIterable, Sendable {
    case png
    case jpeg

    /// The file name extension, without a dot.
    public var fileExtension: String { self == .png ? "png" : "jpg" }
  }

  /// No picture of a page is larger than this on its longer side, in pixels.
  public static let maximumSide = 8_192

  /// One page drawn upright over white, at `scale` pixels to a point, so 1 is 72 dpi. A page that
  /// would be larger than `maximumSide` pixels is made smaller.
  public static func render(_ data: Data, page index: Int, scale: Double) throws -> CGImage {
    let source = try PDFSourcePages(data)
    guard index >= 0, index < source.pageCount else { throw PDFEditFailure.pageOutOfRange }
    guard scale > 0 else { throw PDFEditFailure.invalidParameter }
    guard let image = source.render(index, scale: scale, maximumSide: maximumSide) else {
      throw PDFEditFailure.unreadable
    }
    return image
  }

  /// A zip with one picture for each chosen page (nil is every page), named `baseName_001.png`
  /// and so on, counting from the page number. `quality` applies to JPEG only.
  public static func archive(
    of data: Data, pages: [Int]? = nil, format: Format, scale: Double = 2, quality: Double = 0.9,
    baseName: String = "page"
  ) throws -> Data {
    let source = try PDFSourcePages(data)
    let indices = pages ?? Array(0..<source.pageCount)
    guard !indices.isEmpty else { throw PDFEditFailure.noPages }
    guard scale > 0 else { throw PDFEditFailure.invalidParameter }
    let digits = max(3, String(source.pageCount).count)

    var entries: [ZipWriter.Entry] = []
    for index in indices {
      guard index >= 0, index < source.pageCount else { throw PDFEditFailure.pageOutOfRange }
      try autoreleasepool {
        guard let image = source.render(index, scale: scale, maximumSide: maximumSide) else {
          throw PDFEditFailure.unreadable
        }
        guard
          let bytes = ImageCodec.encode(
            image, as: format == .png ? .png : .jpeg, quality: quality)
        else { throw PDFEditFailure.encodeFailed }
        let number = String(index + 1).leftPadded(to: digits)
        entries.append(
          ZipWriter.Entry(name: "\(baseName)_\(number).\(format.fileExtension)", data: bytes))
      }
    }
    do {
      return try ZipWriter.archive(entries)
    } catch {
      throw PDFEditFailure.writeFailed
    }
  }

  /// A document where each page is one JPEG picture of the original page. Text and vector
  /// graphics become pixels, so the result cannot be searched or selected, and links, form fields
  /// and annotations are baked in or lost. `quality` in 0...1 sets both the JPEG quality and the
  /// resolution, from 72 dpi up to 300 dpi.
  public static func flatten(_ data: Data, quality: Double) throws -> Data {
    guard quality > 0, quality <= 1 else { throw PDFEditFailure.invalidParameter }
    let source = try PDFSourcePages(data)
    let scale = (72 + 228 * quality) / 72
    let sizes = (0..<source.pageCount).map(source.displayedSize(of:))
    return try source.rebuild(sizes: sizes) { index, context in
      guard let picture = source.render(index, scale: scale, maximumSide: 5_000) else {
        throw PDFEditFailure.unreadable
      }
      guard let jpeg = ImageCodec.encode(picture, as: .jpeg, quality: quality) else {
        throw PDFEditFailure.encodeFailed
      }
      let image = PDFPageWriter.jpegBacked(jpeg) ?? picture
      context.draw(image, in: CGRect(origin: .zero, size: sizes[index]))
    }
  }
}

extension String {
  fileprivate func leftPadded(to length: Int) -> String {
    String(repeating: "0", count: max(0, length - count)) + self
  }
}
