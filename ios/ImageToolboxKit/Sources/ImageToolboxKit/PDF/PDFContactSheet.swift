import CoreGraphics
import Foundation

/// Lays pictures out on pages in a grid, each with lines of caption under it, like a contact
/// sheet of a roll of film.
public struct PDFContactSheet: Equatable, Sendable {

  /// A picture and the lines of text under it.
  public struct Item: @unchecked Sendable {
    public let image: CGImage
    public let captions: [String]

    public init(image: CGImage, captions: [String] = []) {
      self.image = image
      self.captions = captions
    }
  }

  public var columns: Int
  public var rows: Int
  public var pageSize: PDFPageSize
  /// The empty border around the grid, in points.
  public var margin: Double
  /// The gap between cells, in points.
  public var spacing: Double
  /// JPEG quality in 0...1.
  public var quality: Double

  public init(
    columns: Int = 3, rows: Int = 4, pageSize: PDFPageSize = .a4, margin: Double = 24,
    spacing: Double = 8, quality: Double = 0.85
  ) {
    self.columns = columns
    self.rows = rows
    self.pageSize = pageSize
    self.margin = margin
    self.spacing = spacing
    self.quality = quality
  }

  private static let captionSize: CGFloat = 9
  private static let captionLeading: CGFloat = 11
  private static let captionGap: CGFloat = 4
  /// Pictures are stored at this many pixels to a point of the cell.
  private static let pixelsPerPoint: CGFloat = 300 / 72

  /// The document, with `columns` x `rows` pictures to a page. An empty array throws `noPages`;
  /// a grid that leaves no room for a picture throws `invalidParameter`.
  public func make(from items: [Item]) throws -> Data {
    guard !items.isEmpty else { throw PDFEditFailure.noPages }
    guard (1...10).contains(columns), (1...10).contains(rows), margin >= 0, spacing >= 0,
      quality > 0, quality <= 1
    else { throw PDFEditFailure.invalidParameter }
    let page = pageSize.size
    let cell = CGSize(
      width: (page.width - 2 * margin - spacing * Double(columns - 1)) / Double(columns),
      height: (page.height - 2 * margin - spacing * Double(rows - 1)) / Double(rows))
    let lines = items.map(\.captions.count).max() ?? 0
    let captionHeight = lines == 0 ? 0 : Self.captionGap + CGFloat(lines) * Self.captionLeading
    let pictureHeight = cell.height - captionHeight
    guard cell.width > 0, pictureHeight > 1 else { throw PDFEditFailure.invalidParameter }

    let perPage = columns * rows
    let pageCount = (items.count + perPage - 1) / perPage
    let output = try PDFPageWriter.write(pageCount: pageCount) { pageIndex in
      PDFPageWriter.Page(size: page) { context in
        let first = pageIndex * perPage
        for (slot, item) in items[first..<min(first + perPage, items.count)].enumerated() {
          // Cells fill from the top left, and the page's origin is at the bottom left.
          let originX = margin + Double(slot % columns) * (cell.width + spacing)
          let top = page.height - margin - Double(slot / columns) * (cell.height + spacing)
          let area = CGRect(
            x: originX, y: top - pictureHeight, width: cell.width, height: pictureHeight)
          try draw(item, in: area, captionHeight: captionHeight, context: context)
        }
      }
    }
    guard let data = output else { throw PDFEditFailure.writeFailed }
    return data
  }

  private func draw(
    _ item: Item, in area: CGRect, captionHeight: CGFloat, context: CGContext
  ) throws {
    let fitted = ImageGeometry.fitSize(
      width: item.image.width, height: item.image.height, within: area.size, allowUpscale: true)
    let stored = ImageGeometry.fitSize(
      width: item.image.width, height: item.image.height,
      within: CGSize(
        width: min(4_096, area.width * Self.pixelsPerPoint),
        height: min(4_096, area.height * Self.pixelsPerPoint)))
    guard let flat = flattened(item.image, size: stored),
      let jpeg = ImageCodec.encode(flat, as: .jpeg, quality: quality)
    else { throw PDFEditFailure.encodeFailed }
    let picture = PDFPageWriter.jpegBacked(jpeg) ?? flat
    let target = CGRect(
      x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2, width: fitted.width,
      height: fitted.height)
    context.draw(picture, in: target)

    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    for (index, caption) in item.captions.enumerated() {
      guard let line = Self.fitted(caption, width: area.width) else { continue }
      let baseline =
        target.minY - Self.captionGap - Self.captionSize - CGFloat(index) * Self.captionLeading
      line.draw(at: CGPoint(x: area.midX - line.width / 2, y: baseline), in: context)
    }
  }

  /// The picture at `size` on white, so a transparent picture does not turn black as a JPEG.
  private func flattened(_ image: CGImage, size: CGSize) -> CGImage? {
    let width = Int(size.width)
    let height = Int(size.height)
    guard let context = ImageGeometry.makeContext(width: width, height: height) else { return nil }
    context.interpolationQuality = .high
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// The caption set at the caption size, shortened with an ellipsis until it fits `width`.
  private static func fitted(_ caption: String, width: CGFloat) -> PDFTextLine? {
    var text = caption.unicodeScalars.map {
      $0.properties.generalCategory == .control ? " " : String($0)
    }
    .joined().trimmingCharacters(in: .whitespaces)
    while !text.isEmpty {
      guard let line = PDFTextLine(text, fontSize: captionSize) else { return nil }
      if line.width <= width { return line }
      text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
      if let shortened = PDFTextLine(text + "…", fontSize: captionSize), shortened.width <= width {
        return shortened
      }
    }
    return nil
  }
}
