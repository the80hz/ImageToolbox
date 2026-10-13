import CoreGraphics
import Foundation
import ImageIO

/// Converts a comic archive (CBZ, a zip of page pictures, or CBR, a RAR of them) into a PDF with one page per picture.
public enum ComicConverter {

  public enum Failure: Error, Equatable {
    /// The data is not a zip or RAR archive, or its directory or headers are damaged.
    case malformedArchive
    /// The archive uses something the zip reader does not support: Zip64, encryption, split archives
    /// or a compression method other than stored and deflate.
    case unsupportedArchive
    /// The archive lists more entries than the converter accepts, or a picture exceeds the size limit.
    case archiveTooLarge
    /// The archive holds no picture in a format the converter reads, or the options leave none.
    case noPictures
    /// A picture entry could not be decoded. `name` is its path in the archive.
    case undecodablePicture(name: String)
    /// The JPEG quality is outside 0 < quality <= 1.
    case invalidParameter
    case writeFailed
  }

  /// How the pictures of a comic are ordered and made into pages.
  public struct Options: Equatable, Sendable {
    /// Reads the last picture first.
    public var reversesOrder: Bool
    /// Leaves out the first picture in name order, which is the cover.
    public var skipsCover: Bool
    /// Splits a picture wider than 1.2 times its height into two pages.
    public var splitsWidePictures: Bool
    /// Reads the two halves of a split picture right half first.
    public var rightToLeft: Bool
    /// The paper size of every page, with each picture fitted to it. Nil makes each page as large as
    /// its picture, one pixel to a point, with the longer side at most 14,400 points.
    public var pageSize: PDFPageSize?
    /// JPEG quality in 0 < quality <= 1. At 1 an upright JPEG is copied into the PDF as it is.
    public var quality: Double

    public init(
      reversesOrder: Bool = false, skipsCover: Bool = false, splitsWidePictures: Bool = false,
      rightToLeft: Bool = false, pageSize: PDFPageSize? = nil, quality: Double = 1
    ) {
      self.reversesOrder = reversesOrder
      self.skipsCover = skipsCover
      self.splitsWidePictures = splitsWidePictures
      self.rightToLeft = rightToLeft
      self.pageSize = pageSize
      self.quality = quality
    }
  }

  private static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
  private static let maximumEntries = 65_535
  /// "Rar!", the first four bytes of every RAR 4 and RAR 5 archive.
  private static let rarSignature: [UInt8] = [0x52, 0x61, 0x72, 0x21]
  private static let maximumPictureSize = 256 * 1024 * 1024
  /// A picture is split when it is wider than this many times its height.
  private static let spreadRatio = 1.2
  /// The longer side of an automatic page, in points. PDF viewers do not show larger pages.
  private static let maximumPageSide: CGFloat = 14_400

  /// A PDF with one page per picture, in natural name order ("page 2" before "page 10"). Each page is
  /// as large as its picture in points, so one pixel is one point, unless `options` sets a paper size.
  /// An upright JPEG is copied into the PDF as it is, without being decoded and encoded again, when
  /// the quality is 1 and the picture is not split.
  public static func pdf(fromArchive data: Data, options: Options = Options()) throws -> Data {
    guard options.quality > 0, options.quality <= 1 else { throw Failure.invalidParameter }
    var pictures = try pictureEntries(in: data).sorted { naturalOrder($0.name, $1.name) }
    if options.skipsCover, !pictures.isEmpty { pictures.removeFirst() }
    if options.reversesOrder { pictures.reverse() }
    guard !pictures.isEmpty else { throw Failure.noPictures }

    let pages = plan(for: pictures, options: options)
    let source = PictureSource(pictures)
    let output = try PDFPageWriter.write(pageCount: pages.count) { index in
      let picture = try source.image(for: pages[index], quality: options.quality)
      let size = CGSize(width: picture.width, height: picture.height)
      let page = pageSize(of: size, options: options)
      let scale = min(page.width / size.width, page.height / size.height)
      let drawn = CGRect(
        x: (page.width - size.width * scale) / 2, y: (page.height - size.height * scale) / 2,
        width: size.width * scale, height: size.height * scale)
      return PDFPageWriter.Page(size: page) { context in context.draw(picture, in: drawn) }
    }
    guard let pdf = output else { throw Failure.writeFailed }
    return pdf
  }

  /// One page of the PDF: a picture, or one half of a split picture.
  private struct PagePlan: Equatable {
    enum Half: Equatable { case left, right }

    /// The index of the picture in the name order, after the cover and the reversal.
    let picture: Int
    let half: Half?
  }

  /// The pages in reading order: each picture is one page, or two when it is split.
  private static func plan(
    for pictures: [(name: String, data: Data)], options: Options
  ) -> [PagePlan] {
    var pages: [PagePlan] = []
    for (index, picture) in pictures.enumerated() {
      guard options.splitsWidePictures, isWide(picture.data) else {
        pages.append(PagePlan(picture: index, half: nil))
        continue
      }
      let halves: [PagePlan.Half] = options.rightToLeft ? [.right, .left] : [.left, .right]
      pages += halves.map { PagePlan(picture: index, half: $0) }
    }
    return pages
  }

  /// Whether the picture is wider than a spread. A picture ImageIO cannot read is not wide, so it
  /// fails later with its name.
  private static func isWide(_ data: Data) -> Bool {
    guard let size = pixelSize(of: data) else { return false }
    return size.width > size.height * spreadRatio
  }

  /// The upright size of the first image in `data`, from its header. A picture turned a quarter
  /// turn by its EXIF orientation has its sides swapped.
  private static func pixelSize(of data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
    else { return nil }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    return (5...8).contains(orientation)
      ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  /// The page size for a picture of `size`: the paper, or the picture's own size, reduced to the
  /// longest side that PDF viewers show.
  private static func pageSize(of size: CGSize, options: Options) -> CGSize {
    if let paper = options.pageSize { return paper.size }
    let scale = min(maximumPageSide / max(size.width, size.height), 1)
    return CGSize(width: size.width * scale, height: size.height * scale)
  }

  /// Decodes the pictures one at a time, as the pages are written in order. The last picture
  /// decoded is kept, so the second half of a split picture needs no second decode.
  private final class PictureSource {
    private let pictures: [(name: String, data: Data)]
    private var decoded: (index: Int, image: CGImage)?

    init(_ pictures: [(name: String, data: Data)]) {
      self.pictures = pictures
    }

    /// The picture of one page: the whole picture, or its half, and at a quality below 1 a JPEG.
    func image(for page: PagePlan, quality: Double) throws -> CGImage {
      let entry = pictures[page.picture]
      if page.half == nil, quality >= 1, let copied = PDFPageWriter.jpegBacked(entry.data) {
        return copied
      }
      let whole = try decodedPicture(page.picture)
      let part = try page.half.map { try cut(whole, $0) } ?? whole
      guard quality < 1 else { return part }
      guard let flat = flattened(part),
        let jpeg = ImageCodec.encode(flat, as: .jpeg, quality: quality)
      else { throw Failure.writeFailed }
      return PDFPageWriter.jpegBacked(jpeg) ?? flat
    }

    private func decodedPicture(_ index: Int) throws -> CGImage {
      if let decoded, decoded.index == index { return decoded.image }
      let entry = pictures[index]
      guard let image = ImageCodec.decode(entry.data) else {
        throw Failure.undecodablePicture(name: entry.name)
      }
      decoded = (index, image)
      return image
    }

    /// The left or right half of a picture. An odd width gives the extra pixel to the right half.
    private func cut(_ image: CGImage, _ half: PagePlan.Half) throws -> CGImage {
      let leftWidth = image.width / 2
      let rect =
        half == .left
        ? CGRect(x: 0, y: 0, width: leftWidth, height: image.height)
        : CGRect(x: leftWidth, y: 0, width: image.width - leftWidth, height: image.height)
      guard let part = image.cropping(to: rect) else { throw Failure.writeFailed }
      return part
    }

    /// The picture on white, so a transparent picture does not turn black as a JPEG.
    private func flattened(_ image: CGImage) -> CGImage? {
      let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      guard let context = ImageGeometry.makeContext(width: image.width, height: image.height)
      else { return nil }
      context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
      context.fill(bounds)
      context.draw(image, in: bounds)
      return context.makeImage()
    }
  }

  /// The picture entries of a CBZ or CBR archive. The signature picks the reader: a RAR archive starts
  /// with "Rar!", and anything else is read as a zip.
  private static func pictureEntries(in data: Data) throws -> [(name: String, data: Data)] {
    if data.prefix(4).elementsEqual(rarSignature) {
      do {
        return try RARReader.entries(in: data, maximumEntries: maximumEntries)
          .filter { isPicture($0.name) }
          .map { (name: $0.name, data: $0.data) }
      } catch let failure as RARReader.Failure {
        switch failure {
        case .notRAR, .malformed: throw Failure.malformedArchive
        case .encrypted, .unsupported: throw Failure.unsupportedArchive
        case .tooLarge: throw Failure.archiveTooLarge
        }
      }
    }
    do {
      return try ZipReader.entries(
        in: data, maximumEntries: maximumEntries, maximumEntrySize: maximumPictureSize
      ) { isPicture($0) }
      .map { (name: $0.name, data: $0.data) }
    } catch let failure as ZipReader.Failure {
      switch failure {
      case .malformed: throw Failure.malformedArchive
      case .unsupported: throw Failure.unsupportedArchive
      case .tooLarge: throw Failure.archiveTooLarge
      }
    }
  }

  /// Picture entries by extension. macOS adds a `__MACOSX` folder and `._` files, which hold resource
  /// forks rather than pictures, so they are skipped along with other hidden files.
  private static func isPicture(_ name: String) -> Bool {
    let components = name.split(separator: "/")
    guard let fileName = components.last, !fileName.hasPrefix("."),
      !components.contains("__MACOSX")
    else { return false }
    let type = URL(fileURLWithPath: String(fileName)).pathExtension.lowercased()
    return pictureExtensions.contains(type)
  }

  // MARK: - Natural order

  /// Orders names so that runs of digits compare by their value, and the rest of the text
  /// case-insensitively. Names that only differ in case or leading zeros still get a fixed order.
  static func naturalOrder(_ lhs: String, _ rhs: String) -> Bool {
    let left = tokens(lhs)
    let right = tokens(rhs)
    for (a, b) in zip(left, right) where a != b {
      if isDigitRun(a), isDigitRun(b) {
        let x = a.drop { $0 == "0" }
        let y = b.drop { $0 == "0" }
        if x.count != y.count { return x.count < y.count }
        if x != y { return String(x) < String(y) }
      } else if a.lowercased() != b.lowercased() {
        return a.lowercased() < b.lowercased()
      }
    }
    if left.count != right.count { return left.count < right.count }
    return lhs < rhs
  }

  /// Splits the text into runs of digits and runs of other characters.
  private static func tokens(_ text: String) -> [String] {
    var result: [String] = []
    for character in text {
      let digit = isDigit(character)
      if let last = result.last?.last, isDigit(last) == digit {
        result[result.count - 1].append(character)
      } else {
        result.append(String(character))
      }
    }
    return result
  }

  private static func isDigit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
  }

  private static func isDigitRun(_ token: String) -> Bool {
    token.first.map(isDigit) ?? false
  }
}
