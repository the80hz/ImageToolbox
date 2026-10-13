import Foundation
import Testing

@testable import ImageToolboxKit

// The Android coder writes the swatches with Bitmap.compress(PNG), which uses the platform PNG
// encoder, so the PNG bytes cannot be reproduced here. The writer is therefore checked for the PNG
// structure, the swatch colours and the names line after the IEND chunk, which is written exactly.
// The reader is checked on a PNG that the test builds byte by byte with a stored zlib stream, the
// way any encoder may write it.

@Suite("Android layout: Image palette (PNG with names)")
struct PaletteAndroidLayoutTestsImage {

  private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

  /// The IEND chunk: a zero length, the type and its CRC. Every PNG file ends with it.
  private static let iend: [UInt8] = [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]

  private static let colours: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
  ]

  @Test("Image writer starts with the PNG signature and a 32 pixel high IHDR per colour")
  func imageStructure() {
    let data = [UInt8](ImagePaletteCoder.encode(Self.colours))
    #expect(Array(data.prefix(8)) == Self.signature)
    // IHDR: a 13 byte chunk, then the width, the height and the bit depth of 8.
    #expect(Array(data[8..<16]) == [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
    #expect(Array(data[16..<20]) == [0, 0, 0, 96])
    #expect(Array(data[20..<24]) == [0, 0, 0, 32])
    #expect(data[24] == 8)
  }

  @Test("Image writer ends the PNG with IEND, then the names line the Android coder writes")
  func imageTrailer() {
    let data = [UInt8](ImagePaletteCoder.encode(Self.colours))
    let trailer = Array("\n; IMAGE_NAMES: Red||Blue\n".utf8)
    #expect(Array(data.suffix(trailer.count)) == trailer)
    let end = data.count - trailer.count
    #expect(Array(data[(end - Self.iend.count)..<end]) == Self.iend)
  }

  @Test("Image writer keeps names as they are, and a line break becomes a space")
  func imageNames() {
    let data = [UInt8](
      ImagePaletteCoder.encode([
        PaletteColour(name: "Two\tor\nthree", red: 1, green: 2, blue: 3),
        PaletteColour(red: 4, green: 5, blue: 6),
        PaletteColour(name: "Last ", red: 7, green: 8, blue: 9),
      ]))
    let trailer = Array("\n; IMAGE_NAMES: Two\tor three||Last \n".utf8)
    #expect(Array(data.suffix(trailer.count)) == trailer)
  }

  @Test("Image writer paints each colour over its swatch, with the same colour at the edges")
  func imageSwatches() throws {
    let image = try #require(ImageCodec.decode(ImagePaletteCoder.encode(Self.colours)))
    let raster = try #require(RasterImage(image))
    #expect(raster.width == 96)
    #expect(raster.height == 32)
    for (index, colour) in Self.colours.enumerated() {
      let expected = RGBA(red: colour.red, green: colour.green, blue: colour.blue)
      for x in [index * 32, index * 32 + 16, index * 32 + 31] {
        #expect(raster.pixel(x: x, y: 0) == expected)
        #expect(raster.pixel(x: x, y: 31) == expected)
      }
    }
  }

  @Test("Image reader takes the centre pixel of each swatch from a PNG the test builds")
  func imageReaderOnStoredPNG() throws {
    // Two 32 pixel swatches. The centre column has the colour, and the other columns are black.
    let swatches: [[UInt8]] = [[255, 0, 0], [0, 0, 255]]
    let png = Self.pngRGB(width: 64, height: 32) { x, _ in
      x % 32 == 16 ? swatches[x / 32] : [0, 0, 0]
    }
    let file = png + Array("\n; IMAGE_NAMES: Red|\n".utf8)
    let colours = try ImagePaletteCoder.decode(Data(file))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 0, blue: 255),
      ])
  }

  /// A PNG of 8-bit RGB pixels, with no filter, in one stored deflate block.
  private static func pngRGB(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) -> [UInt8] {
    var scanlines: [UInt8] = []
    for y in 0..<height {
      scanlines.append(0)  // Filter type 0, which is no filter.
      for x in 0..<width {
        scanlines += pixel(x, y)
      }
    }
    let length = scanlines.count
    let complement = 0xFFFF - length
    // The zlib header, then a final stored block with its length and the one's complement.
    var zlib: [UInt8] = [
      0x78, 0x01, 0x01,
      UInt8(length & 0xFF), UInt8(length >> 8),
      UInt8(complement & 0xFF), UInt8(complement >> 8),
    ]
    zlib += scanlines
    zlib += bigEndian(adler32(scanlines))
    let header = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 2, 0, 0, 0]
    return signature + chunk("IHDR", header) + chunk("IDAT", zlib) + iend
  }

  /// A PNG chunk: the length, the type, the data and the CRC of the type and data.
  private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
    let body = Array(type.utf8) + data
    return bigEndian(UInt32(data.count)) + body + bigEndian(crc32(body))
  }

  private static func bigEndian(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  /// The CRC-32 of PNG chunks, with the polynomial 0xEDB88320.
  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
      }
    }
    return ~crc
  }

  /// The Adler-32 checksum that ends a zlib stream.
  private static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in bytes {
      a = (a + UInt32(byte)) % 65521
      b = (b + a) % 65521
    }
    return (b << 16) | a
  }
}
