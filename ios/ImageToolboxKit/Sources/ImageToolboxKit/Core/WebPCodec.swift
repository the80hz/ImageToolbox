import CoreGraphics
import Foundation
import libwebp

/// WebP encoding through libwebp. ImageIO on iOS and macOS can decode WebP but cannot write it.
public enum WebPCodec {

  /// - Parameters:
  ///   - quality: 0...100 for lossy output. Ignored when `lossless` is true.
  ///   - lossless: when true, encodes losslessly and keeps every pixel.
  ///   - exif: a raw TIFF block. When present it is stored in the file's `EXIF` chunk.
  public static func encode(
    _ image: CGImage, quality: Float = 80, lossless: Bool = false, exif: Data? = nil
  ) -> Data? {
    guard let raster = RasterImage(image) else { return nil }
    let straight = raster.straightRGBA()
    let stride = Int32(raster.width * 4)
    var output: UnsafeMutablePointer<UInt8>?

    let size: Int = straight.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return 0 }
      if lossless {
        return WebPEncodeLosslessRGBA(
          base, Int32(raster.width), Int32(raster.height), stride, &output)
      }
      let clamped = min(max(quality, 0), 100)
      return WebPEncodeRGBA(
        base, Int32(raster.width), Int32(raster.height), stride, clamped, &output)
    }

    guard size > 0, let output else { return nil }
    let data = Data(bytes: output, count: size)
    WebPFree(output)
    guard let exif else { return data }
    return attachEXIF(exif, to: data)
  }

  /// Adds an `EXIF` chunk with libwebp's mux. The mux rewrites the file in the extended layout
  /// (VP8X), which is the layout that can carry metadata. The pixels are not re-encoded.
  private static func attachEXIF(_ exif: Data, to bitstream: Data) -> Data? {
    bitstream.withUnsafeBytes { raw -> Data? in
      var input = WebPData(
        bytes: raw.baseAddress?.assumingMemoryBound(to: UInt8.self), size: bitstream.count)
      guard let mux = WebPMuxCreate(&input, 1) else { return nil }
      defer { WebPMuxDelete(mux) }

      let status = exif.withUnsafeBytes { exifRaw -> WebPMuxError in
        var chunk = WebPData(
          bytes: exifRaw.baseAddress?.assumingMemoryBound(to: UInt8.self), size: exif.count)
        return WebPMuxSetChunk(mux, "EXIF", &chunk, 1)
      }
      guard status == WEBP_MUX_OK else { return nil }

      var assembled = WebPData()
      defer { WebPDataClear(&assembled) }
      guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes
      else { return nil }
      return Data(bytes: bytes, count: assembled.size)
    }
  }
}
