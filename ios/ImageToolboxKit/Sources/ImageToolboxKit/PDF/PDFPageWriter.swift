import CoreGraphics
import Foundation
import ImageIO

/// Writes a PDF page by page with Core Graphics. Each page has its own media box, in points. The PDF
/// tools in this folder share it, so none of them repeats the context set-up.
enum PDFPageWriter {

  /// One page: its size in points and the code that paints it into the page.
  struct Page {
    let size: CGSize
    let paint: (CGContext) throws -> Void
  }

  /// The PDF bytes, or nil when Core Graphics cannot create the document. `makePage` runs once per
  /// page inside its own autorelease pool, so decoded pictures are released page by page. `info` is
  /// the auxiliary information of the document: its title, author and other keys of Core Graphics.
  ///
  /// Each page is begun with its own media box through `beginPage(mediaBox:)`. The media box in the
  /// page-info dictionary of `beginPDFPage` is not used: every page after the first then keeps the
  /// size of the first page, so pages of different sizes come out clipped or stretched.
  static func write(
    pageCount: Int, info: [String: Any]? = nil, makePage: (Int) throws -> Page
  ) throws -> Data? {
    guard pageCount > 0 else { return nil }
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
    var defaultBox = CGRect(x: 0, y: 0, width: 1, height: 1)
    guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, info as CFDictionary?)
    else {
      return nil
    }
    for index in 0..<pageCount {
      try autoreleasepool {
        let page = try makePage(index)
        var box = CGRect(origin: .zero, size: page.size)
        context.beginPage(mediaBox: &box)
        try page.paint(context)
        context.endPage()
      }
    }
    context.closePDF()
    return output as Data
  }

  /// An image that Quartz writes into a PDF as these JPEG bytes, not as re-encoded pixels, so the
  /// file keeps the JPEG's size. Nil when the bytes are not a JPEG, or when EXIF orientation would
  /// need a transform, because the PDF would show the picture unrotated.
  static func jpegBacked(_ bytes: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      (CGImageSourceGetType(source) as String?) == "public.jpeg",
      ImageCodec.exifOrientation(of: source) == 1,
      let provider = CGDataProvider(data: bytes as CFData)
    else { return nil }
    return CGImage(
      jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
      intent: .defaultIntent)
  }
}
