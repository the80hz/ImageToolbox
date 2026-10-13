import CoreGraphics
import Foundation

/// The EXIF block in the form WebP stores it: a raw TIFF structure. ImageIO writes EXIF only inside
/// an image file, so the block is cut out of a JPEG that was written with the metadata.
enum ExifBlock {

  /// The TIFF block for `metadata`, or nil when the metadata holds no EXIF. The JPEG is written
  /// from `image` itself, because ImageIO takes the EXIF pixel size from the picture it encodes.
  static func tiff(from metadata: [String: Any], of image: CGImage) -> Data? {
    // Quality 0 is the cheapest encode. Only the EXIF block of the JPEG is kept, not its pixels.
    guard let jpeg = ImageCodec.encode(image, as: .jpeg, quality: 0, metadata: metadata)
    else { return nil }
    return exifPayload(ofJPEG: jpeg)
  }

  /// The payload of the first APP1 segment that starts with `Exif\0\0`, without that prefix.
  static func exifPayload(ofJPEG data: Data) -> Data? {
    let prefix: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]
    let bytes = [UInt8](data)
    guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }

    var offset = 2
    while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
      let marker = bytes[offset + 1]
      // Start of scan: the entropy-coded pixels follow, so no header segment comes after it.
      if marker == 0xDA { break }

      let length = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
      let end = offset + 2 + length
      guard length >= 2, end <= bytes.count else { return nil }

      let payload = bytes[(offset + 4)..<end]
      if marker == 0xE1, payload.starts(with: prefix) {
        return Data(payload.dropFirst(prefix.count))
      }
      offset = end
    }
    return nil
  }
}
