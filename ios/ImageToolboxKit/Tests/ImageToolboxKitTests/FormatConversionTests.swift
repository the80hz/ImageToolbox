import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import ImageToolboxKit

@Suite("Format conversion and the QOI codec")
struct FormatConversionTests {

  @Test("a single opaque black pixel encodes to the reference QOI bytes")
  func referenceBytes() throws {
    let data = try QOICodec.encode(width: 1, height: 1, rgba: [0, 0, 0, 255])
    let expected: [UInt8] = [
      0x71, 0x6F, 0x69, 0x66,  // "qoif"
      0x00, 0x00, 0x00, 0x01,  // width
      0x00, 0x00, 0x00, 0x01,  // height
      0x04, 0x00,  // 4 channels, sRGB
      0xC0,  // run of one pixel equal to the start pixel
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,  // end marker
    ]
    #expect([UInt8](data) == expected)
  }

  @Test("a QOI file round-trips every pixel, including transparent ones")
  func qoiRoundTrip() throws {
    var generator = SeededGenerator(seed: 7)
    let width = 40
    let height = 25
    var pixels: [UInt8] = []
    for index in 0..<(width * height) {
      if index % 9 < 3 {
        // Runs and repeats exercise the run and index operations.
        pixels += [200, 40, 90, 255]
      } else {
        pixels += (0..<4).map { _ in UInt8.random(in: 0...255, using: &generator) }
      }
    }
    let data = try QOICodec.encode(width: width, height: height, rgba: pixels)
    let decoded = try QOICodec.decode(data)
    #expect(decoded.width == width && decoded.height == height)
    #expect(decoded.rgba == pixels)
  }

  @Test("a file without the qoif signature is rejected")
  func badSignature() {
    #expect(throws: QOICodec.Failure.malformed) {
      try QOICodec.decode(Data(repeating: 0, count: 40))
    }
  }

  @Test("the engines show which targets this build can write")
  func availability() {
    #expect(ConversionTarget.png.isAvailable)
    #expect(ConversionTarget.webp.isAvailable)
    #expect(ConversionTarget.qoi.isAvailable)
    #expect(ConversionTarget.telegramSticker.isAvailable)
    #expect(ConversionTarget.jpegXL.isAvailable)
    #expect(ConversionTarget.jpegXL.engine == .jxl)
    #expect(ConversionTarget.jpegXL.fileExtension == "jxl")
    // The JPEG XL writer is lossless, so quality is not a setting for it.
    #expect(!ConversionTarget.jpegXL.isLossy)
  }

  @Test("every target that this device cannot write is refused")
  func unavailableRefused() {
    // Which targets are missing depends on the system (AVIF and HEIC come from ImageIO).
    let image = TestImages.solid(RGBA(red: 1, green: 2, blue: 3), width: 4, height: 4)
    for target in ConversionTarget.allCases where !target.isAvailable {
      #expect(throws: FormatConverter.Failure.unavailable) {
        try FormatConverter.convert(image, to: target)
      }
    }
  }

  @Test("JPEG XL conversion is lossless and ignores quality")
  func jpegXLConversion() throws {
    let image = TestImages.image(width: 70, height: 33) { x, y in
      // Premultiplied colour never exceeds its alpha.
      let alpha = 255 - (x + y) % 120
      return RGBA(
        red: UInt8(min(alpha, (x * 3) % 256)), green: UInt8(min(alpha, (y * 7) % 256)),
        blue: UInt8(min(alpha, (x * y) % 256)), alpha: UInt8(alpha))
    }
    let data = try FormatConverter.convert(image, to: .jpegXL)
    #expect(data.prefix(2) == Data([0xFF, 0x0A]))
    #expect(try FormatConverter.convert(image, to: .jpegXL, quality: 0.05) == data)

    // ImageIO is the reference decoder; it hands back straight (not premultiplied) RGBA.
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 70 && decoded.height == 33)
    let original = try #require(RasterImage(image))
    let provider = try #require(decoded.dataProvider?.data)
    let bytes = [UInt8](provider as Data)
    #expect(decoded.alphaInfo == .last && decoded.bitsPerPixel == 32)
    var straight = [UInt8](repeating: 0, count: 70 * 33 * 4)
    for y in 0..<33 {
      for x in 0..<70 {
        for channel in 0..<4 {
          straight[(y * 70 + x) * 4 + channel] = bytes[y * decoded.bytesPerRow + x * 4 + channel]
        }
      }
    }
    #expect(straight == original.straightRGBA())
  }

  @Test("QOI conversion keeps the pixels exactly")
  func qoiConversion() throws {
    let image = TestImages.image(width: 6, height: 4) { x, y in
      RGBA(red: UInt8(x * 40), green: UInt8(y * 60), blue: 120)
    }
    let data = try FormatConverter.convert(image, to: .qoi)
    let decoded = try QOICodec.decode(data)
    let original = try #require(RasterImage(image))
    #expect(decoded.rgba == original.straightRGBA())
  }

  @Test("a Telegram sticker has 512 pixels on its longer side")
  func stickerSize() throws {
    let image = TestImages.solid(RGBA(red: 90, green: 90, blue: 200), width: 100, height: 50)
    let data = try FormatConverter.convert(image, to: .telegramSticker)
    let decoded = try #require(ImageCodec.decode(data))
    #expect(decoded.width == 512)
    #expect(decoded.height == 256)
  }

  @Test("an icon is a square of at most 256 pixels, with the picture centred")
  func iconSize() throws {
    let wide = TestImages.solid(RGBA(red: 10, green: 20, blue: 30), width: 600, height: 300)
    let data = try FormatConverter.convert(wide, to: .ico)
    let decoded = try #require(ImageCodec.decode(data))
    #expect(decoded.width == 256 && decoded.height == 256)

    let small = TestImages.solid(RGBA(red: 10, green: 20, blue: 30), width: 64, height: 64)
    let square = try #require(FormatConverter.iconSquare(small))
    #expect(square.width == 64)
  }

  @Test("the picture keeps its place on the icon square and the margins stay transparent")
  func iconCentring() throws {
    let wide = TestImages.solid(RGBA(red: 200, green: 30, blue: 30), width: 200, height: 100)
    let square = try #require(FormatConverter.iconSquare(wide))
    let raster = try #require(RasterImage(square))
    #expect(square.width == 200)
    // The picture fills the middle band, and the top row is outside it.
    #expect(raster.pixel(x: 100, y: 100).alpha == 255)
    #expect(raster.pixel(x: 100, y: 5).alpha == 0)
  }
}
