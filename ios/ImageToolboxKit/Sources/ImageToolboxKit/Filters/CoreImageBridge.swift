import CoreGraphics
import CoreImage
import Foundation

/// Runs Core Image filters on a `RasterImage` and reads the result back into one.
///
/// Colours stay in the values the picture is stored in: there is no linear working space. The
/// arithmetic then matches the per-channel formulas of the Android filters.
enum CoreImageBridge {
  /// One context serves every filter. Core Image contexts may be used from several threads.
  private static let context = CIContext(
    options: [.workingColorSpace: NSNull()])

  /// Applies `transform` to the picture and returns the rendered result at the same size.
  static func render(
    _ image: RasterImage,
    filterID: String,
    _ transform: (CIImage) -> CIImage
  ) throws -> RasterImage {
    guard let cgImage = image.toCGImage() else {
      throw FilterError.renderFailed(filterID)
    }
    let output = transform(CIImage(cgImage: cgImage))
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard
      let rendered = context.createCGImage(
        output, from: bounds, format: .RGBA8, colorSpace: nil),
      let raster = RasterImage(rendered),
      raster.width == image.width, raster.height == image.height
    else {
      throw FilterError.renderFailed(filterID)
    }
    return raster
  }
}
