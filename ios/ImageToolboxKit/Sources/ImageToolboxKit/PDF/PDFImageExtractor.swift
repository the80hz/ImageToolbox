import CoreGraphics
import Foundation

/// Pulls the pictures out of a PDF as they are stored. A JPEG or JPEG 2000 picture is copied
/// byte for byte. Any other picture is decoded and written as PNG, with its transparency when the
/// file stores one. Pictures that use CCITT or JBIG2 compression, and colour spaces other than
/// grey, RGB, CMYK, ICC and indexed ones, are counted but skipped.
public enum PDFImageExtractor {

  /// What `extract(from:)` found.
  public struct Result: Sendable {
    /// The pictures, named `extracted_0.jpg`, `extracted_1.png` and so on, each stored once.
    public let entries: [ZipWriter.Entry]
    /// The number of pictures that could not be written.
    public let skipped: Int
  }

  private static let maximumDepth = 4
  private static let maximumPixels = 200_000_000

  /// Every picture in the document, in page order.
  public static func extract(from data: Data) throws -> Result {
    guard let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider)
    else { throw PDFEditFailure.unreadable }
    if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") {
      throw PDFEditFailure.locked
    }
    let collector = Collector()
    for number in 1...max(1, document.numberOfPages) {
      guard let page = document.page(at: number), let dictionary = page.dictionary else {
        continue
      }
      try autoreleasepool {
        try collect(resourcesOf: dictionary, depth: 0, into: collector)
      }
    }
    return Result(entries: collector.entries, skipped: collector.skipped)
  }

  /// A zip of the pictures. Throws `nothingFound` when the document holds none that can be written.
  public static func archive(from data: Data) throws -> Data {
    let result = try extract(from: data)
    guard !result.entries.isEmpty else { throw PDFEditFailure.nothingFound }
    do {
      return try ZipWriter.archive(result.entries)
    } catch {
      throw PDFEditFailure.writeFailed
    }
  }

  // MARK: - Collecting

  private final class Collector {
    var entries: [ZipWriter.Entry] = []
    var skipped = 0
    var seenObjects: Set<CGPDFStreamRef> = []
    var seenContent: Set<String> = []
  }

  /// Finds the pictures in the resources of a page or form, and follows forms into theirs.
  private static func collect(
    resourcesOf owner: CGPDFDictionaryRef, depth: Int, into collector: Collector
  ) throws {
    guard depth <= maximumDepth, let resources = inheritedResources(of: owner),
      let xObjects = PDFObjects.dictionary(resources, "XObject")
    else { return }
    let colourSpaces = PDFObjects.dictionary(resources, "ColorSpace")
    for stream in PDFObjects.streams(in: xObjects) {
      guard let dictionary = CGPDFStreamGetDictionary(stream) else { continue }
      switch PDFObjects.name(dictionary, "Subtype") {
      case "Image":
        guard collector.seenObjects.insert(stream).inserted else { continue }
        try add(stream, colourSpaces: colourSpaces, to: collector)
      case "Form":
        guard collector.seenObjects.insert(stream).inserted else { continue }
        try collect(resourcesOf: dictionary, depth: depth + 1, into: collector)
      default:
        continue
      }
    }
  }

  /// The page's own resources, or those of the nearest page tree node that has them.
  private static func inheritedResources(of owner: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
    var node: CGPDFDictionaryRef? = owner
    var steps = 0
    while let current = node, steps < 32 {
      if let resources = PDFObjects.dictionary(current, "Resources") { return resources }
      node = PDFObjects.dictionary(current, "Parent")
      steps += 1
    }
    return nil
  }

  private static func add(
    _ stream: CGPDFStreamRef, colourSpaces: CGPDFDictionaryRef?, to collector: Collector
  ) throws {
    guard let picture = bytes(of: stream, colourSpaces: colourSpaces) else {
      collector.skipped += 1
      return
    }
    // The same picture may be stored under several objects.
    let key = "\(picture.data.count):\(CRC32.checksum(picture.data)):\(picture.fileExtension)"
    guard collector.seenContent.insert(key).inserted else { return }
    let name = "extracted_\(collector.entries.count).\(picture.fileExtension)"
    collector.entries.append(ZipWriter.Entry(name: name, data: picture.data))
  }

  // MARK: - Decoding

  private static func bytes(
    of stream: CGPDFStreamRef, colourSpaces: CGPDFDictionaryRef?
  ) -> (data: Data, fileExtension: String)? {
    guard let dictionary = CGPDFStreamGetDictionary(stream) else { return nil }
    var format = CGPDFDataFormat.raw
    guard let copy = CGPDFStreamCopyData(stream, &format) else { return nil }
    let data = copy as Data
    switch format {
    case .jpegEncoded: return (data, "jpg")
    case .JPEG2000: return (data, "jp2")
    case .raw: break
    @unknown default: return nil
    }
    guard !usesUnsupportedFilter(dictionary),
      let image = PDFRawImage.make(
        data: data, dictionary: dictionary, colourSpaces: colourSpaces,
        maximumPixels: maximumPixels),
      let png = ImageCodec.encode(image, as: .png)
    else { return nil }
    return (png, "png")
  }

  /// CCITT and JBIG2 data is not decoded when the stream's data is copied.
  private static func usesUnsupportedFilter(_ dictionary: CGPDFDictionaryRef) -> Bool {
    let filters = PDFObjects.names(dictionary, "Filter")
    return filters.contains { $0 == "CCITTFaxDecode" || $0 == "JBIG2Decode" || $0 == "CCF" }
  }
}
