import CoreGraphics
import Foundation

/// A format the converter can write. The engine says how the file is written on this platform.
public enum ConversionTarget: CaseIterable, Sendable {
  case png
  case jpeg
  case heic
  case avif
  case tiff
  case bmp
  case gif
  case jpeg2000
  case ico
  case tga
  case webp
  case qoi
  case telegramSticker
  case jpegXL

  public enum Engine: Equatable, Sendable {
    /// ImageIO writes the container with this type identifier.
    case imageIO(typeIdentifier: String)
    /// libwebp writes WebP.
    case libwebp
    /// The QOI codec in this package writes the file.
    case qoi
    /// The lossless JPEG XL encoder in this package writes the file. There is no lossy mode, so
    /// quality has no effect, and no metadata is carried.
    case jxl
    /// PNG within the limits of a Telegram static sticker.
    case stickerPNG
    /// No encoder is available in this build.
    case none
  }

  public var engine: Engine {
    switch self {
    case .png: .imageIO(typeIdentifier: "public.png")
    case .jpeg: .imageIO(typeIdentifier: "public.jpeg")
    case .heic: .imageIO(typeIdentifier: "public.heic")
    case .avif: .imageIO(typeIdentifier: "public.avif")
    case .tiff: .imageIO(typeIdentifier: "public.tiff")
    case .bmp: .imageIO(typeIdentifier: "com.microsoft.bmp")
    case .gif: .imageIO(typeIdentifier: "com.compuserve.gif")
    case .jpeg2000: .imageIO(typeIdentifier: "public.jpeg-2000")
    case .ico: .imageIO(typeIdentifier: "com.microsoft.ico")
    case .tga: .imageIO(typeIdentifier: "com.truevision.tga-image")
    case .webp: .libwebp
    case .qoi: .qoi
    case .telegramSticker: .stickerPNG
    case .jpegXL: .jxl
    }
  }

  public var fileExtension: String {
    switch self {
    case .png, .telegramSticker: "png"
    case .jpeg: "jpg"
    case .heic: "heic"
    case .avif: "avif"
    case .tiff: "tiff"
    case .bmp: "bmp"
    case .gif: "gif"
    case .jpeg2000: "jp2"
    case .ico: "ico"
    case .tga: "tga"
    case .webp: "webp"
    case .qoi: "qoi"
    case .jpegXL: "jxl"
    }
  }

  /// Whether `quality` changes the output.
  public var isLossy: Bool {
    switch self {
    case .jpeg, .heic, .avif, .jpeg2000, .webp: true
    default: false
    }
  }

  /// Whether this device can write the target now. ImageIO containers are checked against the
  /// types it reports, because the list depends on the system version.
  public var isAvailable: Bool {
    switch engine {
    case .imageIO(let typeIdentifier):
      ImageCodec.encodableTypeIdentifiers.contains(typeIdentifier)
    case .libwebp, .qoi, .jxl, .stickerPNG:
      true
    case .none:
      false
    }
  }
}

/// Converts a picture to a conversion target, with the size rules of the target's container.
public enum FormatConverter {

  public enum Failure: Error, Equatable {
    /// The target has no encoder on this device.
    case unavailable
    /// The encoder rejected the picture.
    case encodingFailed
    /// The file is larger than the target allows.
    case tooLarge
  }

  /// A Telegram static sticker has one side of exactly 512 pixels and a file of at most 512 KB.
  public static let stickerSide = 512
  public static let stickerByteLimit = 512 * 1024
  /// An ICO entry holds at most 256 pixels per side.
  public static let iconSide = 256

  public static func convert(
    _ image: CGImage,
    to target: ConversionTarget,
    quality: Double = 0.9,
    metadata: [String: Any] = [:]
  ) throws -> Data {
    guard target.isAvailable else { throw Failure.unavailable }

    switch target.engine {
    case .imageIO(let typeIdentifier):
      // ImageIO writes ICO only for square pictures, so a non-square picture is centred on
      // a square.
      let picture = target == .ico ? iconSquare(image) : image
      guard let picture,
        let data = ImageCodec.encode(
          picture, typeIdentifier: typeIdentifier, lossy: target.isLossy, quality: quality,
          metadata: metadata)
      else { throw Failure.encodingFailed }
      return data

    case .libwebp:
      guard
        let data = ImageCodec.encode(
          image, as: .webp, quality: quality, metadata: metadata)
      else { throw Failure.encodingFailed }
      return data

    case .qoi:
      guard let raster = RasterImage(image),
        let data = try? QOICodec.encode(
          width: raster.width, height: raster.height, rgba: raster.straightRGBA())
      else { throw Failure.encodingFailed }
      return data

    case .jxl:
      // Lossless only: `quality` is ignored, and ImageIO metadata is not written into the file.
      guard let raster = RasterImage(image),
        let data = try? JXLEncoder.encode(raster)
      else { throw Failure.encodingFailed }
      return data

    case .stickerPNG:
      guard let picture = scaled(image, longestSide: stickerSide, onlyDown: false),
        let data = ImageCodec.encode(picture, typeIdentifier: "public.png", lossy: false)
      else { throw Failure.encodingFailed }
      guard data.count <= stickerByteLimit else { throw Failure.tooLarge }
      return data

    case .none:
      throw Failure.unavailable
    }
  }

  /// A square, at most `iconSide` pixels across, with the picture fitted and centred. The space
  /// around a non-square picture is transparent.
  public static func iconSquare(_ image: CGImage) -> CGImage? {
    let side = min(iconSide, max(image.width, image.height))
    let scale = Double(side) / Double(max(image.width, image.height))
    let width = Double(image.width) * scale
    let height = Double(image.height) * scale
    guard
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    let origin = CGPoint(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2)
    context.draw(image, in: CGRect(origin: origin, size: CGSize(width: width, height: height)))
    return context.makeImage()
  }

  /// The picture scaled so its longer side is `longestSide`. With `onlyDown` a smaller picture is
  /// returned as it is.
  public static func scaled(_ image: CGImage, longestSide: Int, onlyDown: Bool) -> CGImage? {
    let current = max(image.width, image.height)
    if onlyDown && current <= longestSide { return image }
    let scale = Double(longestSide) / Double(current)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    return ImageGeometry.resize(image, width: width, height: height)
  }
}
