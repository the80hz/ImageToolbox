import CoreGraphics
import Foundation

/// Builds a picture from the decoded samples of a PDF image stream.
enum PDFRawImage {

  /// A colour space of the PDF and the number of samples that make a pixel.
  private struct Space {
    let space: CGColorSpace
    let components: Int
    let isIndexed: Bool
  }

  private static let maximumSpaceDepth = 4

  /// The picture, or nil when its colour space, size or samples cannot be used. `data` holds the
  /// samples after the stream's filters, as `CGPDFStreamCopyData` returns them.
  static func make(
    data: Data, dictionary: CGPDFDictionaryRef, colourSpaces: CGPDFDictionaryRef?,
    maximumPixels: Int
  ) -> CGImage? {
    let isMask = PDFObjects.boolean(dictionary, "ImageMask") ?? PDFObjects.boolean(dictionary, "IM")
    let width = PDFObjects.integer(dictionary, "Width") ?? 0
    let height = PDFObjects.integer(dictionary, "Height") ?? 0
    let bits = PDFObjects.integer(dictionary, "BitsPerComponent") ?? (isMask == true ? 1 : 8)
    guard width > 0, height > 0, width <= maximumPixels / height, [1, 2, 4, 8, 16].contains(bits)
    else { return nil }

    let space: Space
    if isMask == true {
      space = Space(space: CGColorSpaceCreateDeviceGray(), components: 1, isIndexed: false)
    } else if let found = colourSpace(in: dictionary, spaces: colourSpaces) {
      space = found
    } else {
      return nil
    }

    let bitsPerPixel = bits * space.components
    let bytesPerRow = (width * bitsPerPixel + 7) / 8
    guard data.count >= bytesPerRow * height, let provider = CGDataProvider(data: data as CFData)
    else { return nil }
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    if bits == 16 { info.insert(.byteOrder16Big) }

    guard
      let picture = CGImage(
        width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bitsPerPixel,
        bytesPerRow: bytesPerRow, space: space.space, bitmapInfo: info, provider: provider,
        decode: decodeArray(dictionary, components: space.components, isIndexed: space.isIndexed),
        shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }

    if let maskStream = PDFObjects.stream(dictionary, "SMask") {
      return applying(softMask: maskStream, to: picture, maximumPixels: maximumPixels) ?? picture
    }
    return picture
  }

  // MARK: - Soft mask

  /// The picture with the soft mask as its alpha. The mask may have another size than the picture.
  private static func applying(
    softMask stream: CGPDFStreamRef, to picture: CGImage, maximumPixels: Int
  ) -> CGImage? {
    guard let maskDictionary = CGPDFStreamGetDictionary(stream) else { return nil }
    var format = CGPDFDataFormat.raw
    guard let copy = CGPDFStreamCopyData(stream, &format) else { return nil }
    let maskData = copy as Data
    let mask: CGImage?
    switch format {
    case .raw:
      mask = make(
        data: maskData, dictionary: maskDictionary, colourSpaces: nil, maximumPixels: maximumPixels)
    default:
      mask = ImageCodec.decode(maskData)
    }
    guard let mask,
      let colour = ImageGeometry.makeContext(width: picture.width, height: picture.height),
      let alpha = CGContext(
        data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8,
        bytesPerRow: picture.width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
    colour.draw(picture, in: bounds)
    alpha.interpolationQuality = .high
    alpha.draw(mask, in: bounds)
    guard let colourBytes = colour.data?.assumingMemoryBound(to: UInt8.self),
      let alphaBytes = alpha.data?.assumingMemoryBound(to: UInt8.self)
    else { return nil }
    for pixel in 0..<(picture.width * picture.height) {
      let opacity = Int(alphaBytes[pixel])
      // The colour context is premultiplied, and the picture was opaque.
      for channel in 0..<3 {
        let offset = pixel * 4 + channel
        colourBytes[offset] = UInt8(Int(colourBytes[offset]) * opacity / 255)
      }
      colourBytes[pixel * 4 + 3] = UInt8(opacity)
    }
    return colour.makeImage()
  }

  // MARK: - Colour spaces

  /// `Decode` as Core Graphics takes it. Nil for the default, which Core Graphics assumes.
  private static func decodeArray(
    _ dictionary: CGPDFDictionaryRef, components: Int, isIndexed: Bool
  ) -> [CGFloat]? {
    let values = PDFObjects.numbers(dictionary, "Decode")
    guard !isIndexed, values.count == components * 2 else { return nil }
    let standard = (0..<components).flatMap { _ in [0.0, 1.0] }
    return values == standard ? nil : values.map { CGFloat($0) }
  }

  private static func colourSpace(
    in dictionary: CGPDFDictionaryRef, spaces: CGPDFDictionaryRef?
  ) -> Space? {
    var object: CGPDFObjectRef?
    guard
      CGPDFDictionaryGetObject(dictionary, "ColorSpace", &object)
        || CGPDFDictionaryGetObject(dictionary, "CS", &object), let object
    else { return nil }
    return colourSpace(from: object, spaces: spaces, depth: 0)
  }

  private static func colourSpace(
    from object: CGPDFObjectRef, spaces: CGPDFDictionaryRef?, depth: Int
  ) -> Space? {
    guard depth < maximumSpaceDepth else { return nil }
    var name: UnsafePointer<CChar>?
    if CGPDFObjectGetValue(object, .name, &name), let name {
      return named(String(cString: name), spaces: spaces, depth: depth)
    }
    var list: CGPDFArrayRef?
    guard CGPDFObjectGetValue(object, .array, &list), let list, CGPDFArrayGetCount(list) > 0
    else { return nil }
    var family: UnsafePointer<CChar>?
    guard CGPDFArrayGetName(list, 0, &family), let family else { return nil }
    switch String(cString: family) {
    case "ICCBased": return iccBased(list)
    case "Indexed", "I": return indexed(list, spaces: spaces, depth: depth)
    case "CalGray": return device(1)
    case "CalRGB": return device(3)
    default: return named(String(cString: family), spaces: spaces, depth: depth)
    }
  }

  private static func named(
    _ name: String, spaces: CGPDFDictionaryRef?, depth: Int
  ) -> Space? {
    switch name {
    case "DeviceGray", "G": return device(1)
    case "DeviceRGB", "RGB": return device(3)
    case "DeviceCMYK", "CMYK": return device(4)
    default:
      var object: CGPDFObjectRef?
      guard let spaces, CGPDFDictionaryGetObject(spaces, name, &object), let object else {
        return nil
      }
      return colourSpace(from: object, spaces: spaces, depth: depth + 1)
    }
  }

  private static func device(_ components: Int) -> Space? {
    let space: CGColorSpace
    switch components {
    case 1: space = CGColorSpaceCreateDeviceGray()
    case 3: space = CGColorSpaceCreateDeviceRGB()
    case 4: space = CGColorSpaceCreateDeviceCMYK()
    default: return nil
    }
    return Space(space: space, components: components, isIndexed: false)
  }

  private static func iccBased(_ list: CGPDFArrayRef) -> Space? {
    var stream: CGPDFStreamRef?
    guard CGPDFArrayGetStream(list, 1, &stream), let stream,
      let dictionary = CGPDFStreamGetDictionary(stream),
      let components = PDFObjects.integer(dictionary, "N")
    else { return nil }
    var format = CGPDFDataFormat.raw
    if let profile = CGPDFStreamCopyData(stream, &format),
      let space = CGColorSpace(iccData: profile),
      space.numberOfComponents == components
    {
      return Space(space: space, components: components, isIndexed: false)
    }
    return device(components)
  }

  private static func indexed(
    _ list: CGPDFArrayRef, spaces: CGPDFDictionaryRef?, depth: Int
  ) -> Space? {
    var base: CGPDFObjectRef?
    var highest: CGPDFInteger = 0
    guard CGPDFArrayGetCount(list) == 4, CGPDFArrayGetObject(list, 1, &base), let base,
      CGPDFArrayGetInteger(list, 2, &highest), (0...255).contains(highest),
      let baseSpace = colourSpace(from: base, spaces: spaces, depth: depth + 1),
      !baseSpace.isIndexed, let table = lookupTable(list)
    else { return nil }
    guard table.count >= (highest + 1) * baseSpace.components else { return nil }
    guard
      let space = CGColorSpace(
        indexedBaseSpace: baseSpace.space, last: Int(highest), colorTable: table)
    else { return nil }
    return Space(space: space, components: 1, isIndexed: true)
  }

  /// The colour table of an indexed space, which a file stores as a string or as a stream.
  private static func lookupTable(_ list: CGPDFArrayRef) -> [UInt8]? {
    var text: CGPDFStringRef?
    if CGPDFArrayGetString(list, 3, &text), let text, let pointer = CGPDFStringGetBytePtr(text) {
      return Array(UnsafeBufferPointer(start: pointer, count: CGPDFStringGetLength(text)))
    }
    var stream: CGPDFStreamRef?
    var format = CGPDFDataFormat.raw
    if CGPDFArrayGetStream(list, 3, &stream), let stream,
      let copy = CGPDFStreamCopyData(stream, &format)
    {
      return [UInt8](copy as Data)
    }
    return nil
  }
}
