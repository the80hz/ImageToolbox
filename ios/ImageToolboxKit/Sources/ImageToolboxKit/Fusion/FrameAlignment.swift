import CoreGraphics
import Foundation
import Vision
import simd

/// Aligns frames to the first one with a transform from Vision (a homography for frames of at least
/// 256 px, a translation below that), then crops them to the area that every aligned frame covers.
/// Vision replaces the feature matching of the Android app.
public enum FrameAlignment {

  /// A frame whose valid area after warping is smaller than this fraction is rejected.
  static let minimumValidFraction = 0.45
  /// The largest common rectangle must be at least this fraction of the frame, and this many pixels
  /// on each side.
  static let minimumCropFraction = 0.25
  static let minimumCropSide = 64

  /// Aligned frames of one size, or nil when a frame cannot be aligned, the frames differ in size,
  /// or the frames have no common area large enough to keep.
  public static func align(_ images: [CGImage], cropToOverlap: Bool) -> [RasterImage]? {
    guard let reference = images.first else { return nil }
    guard images.allSatisfy({ $0.width == reference.width && $0.height == reference.height })
    else { return nil }

    var warped: [(raster: RasterImage, valid: [Bool])] = []
    for image in images {
      guard let homography = transform(of: image, to: reference) else { return nil }
      let source = RasterImage(image)
      guard let source,
        let result = warp(
          source, by: homography, width: reference.width,
          height: reference.height)
      else { return nil }
      let validCount = result.valid.lazy.filter { $0 }.count
      guard Double(validCount) >= minimumValidFraction * Double(result.valid.count) else {
        return nil
      }
      warped.append(result)
    }

    guard cropToOverlap else { return warped.map(\.raster) }
    var common = [Bool](repeating: true, count: reference.width * reference.height)
    for frame in warped {
      for index in common.indices where !frame.valid[index] {
        common[index] = false
      }
    }
    guard
      let rectangle = largestRectangle(
        in: common, width: reference.width, height: reference.height),
      rectangle.width >= minimumCropSide, rectangle.height >= minimumCropSide,
      Double(rectangle.width * rectangle.height)
        >= minimumCropFraction * Double(reference.width * reference.height)
    else { return nil }
    return warped.compactMap { crop($0.raster, to: rectangle) }
  }

  // MARK: - Homography

  /// Vision's homography estimate is reliable only from this side length. On smaller frames it
  /// returns the identity with full confidence even when the frames differ, so those frames get a
  /// translation instead.
  static let homographyMinimumSide = 256

  /// The transform that maps `image` onto `reference`, in top-left pixel coordinates. A full
  /// homography is used for frames of at least `homographyMinimumSide`. Smaller frames are aligned by
  /// a translation only, which is what Vision estimates reliably at any size.
  static func transform(of image: CGImage, to reference: CGImage) -> simd_double3x3? {
    if image === reference { return matrix_identity_double3x3 }
    if min(reference.width, reference.height) >= homographyMinimumSide {
      return homography(of: image, to: reference)
    }
    return translation(of: image, to: reference)
  }

  /// The full homography from Vision. Vision works with the origin at the bottom left, so the matrix
  /// is converted to top-left coordinates here.
  static func homography(of image: CGImage, to reference: CGImage) -> simd_double3x3? {
    let request = VNHomographicImageRegistrationRequest(targetedCGImage: image, options: [:])
    guard perform(request, on: reference),
      let observation = request.results?.first as? VNImageHomographicAlignmentObservation
    else { return nil }
    let columns = observation.warpTransform.columns
    let vision = simd_double3x3(
      simd_double3(Double(columns.0.x), Double(columns.0.y), Double(columns.0.z)),
      simd_double3(Double(columns.1.x), Double(columns.1.y), Double(columns.1.z)),
      simd_double3(Double(columns.2.x), Double(columns.2.y), Double(columns.2.z)))
    return flipToTopLeft(vision, height: reference.height)
  }

  /// A translation from Vision, as a homography in top-left coordinates.
  static func translation(of image: CGImage, to reference: CGImage) -> simd_double3x3? {
    let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image, options: [:])
    guard perform(request, on: reference),
      let observation = request.results?.first as? VNImageTranslationAlignmentObservation
    else { return nil }
    let shift = observation.alignmentTransform
    let vision = simd_double3x3(
      simd_double3(1, 0, 0),
      simd_double3(0, 1, 0),
      simd_double3(Double(shift.tx), Double(shift.ty), 1))
    return flipToTopLeft(vision, height: reference.height)
  }

  private static func perform(_ request: VNImageRegistrationRequest, on reference: CGImage) -> Bool
  {
    let handler = VNImageRequestHandler(cgImage: reference, options: [:])
    do {
      try handler.perform([request])
      return true
    } catch {
      return false
    }
  }

  /// Flipping y on both sides turns a bottom-left matrix into a top-left one. A flip is its own
  /// inverse, so the same flip converts back.
  private static func flipToTopLeft(_ matrix: simd_double3x3, height: Int) -> simd_double3x3 {
    let flip = simd_double3x3(
      simd_double3(1, 0, 0),
      simd_double3(0, -1, 0),
      simd_double3(0, Double(height), 1))
    return flip * matrix * flip
  }

  // MARK: - Warping

  /// Resamples `source` into the reference frame: each reference pixel reads the source pixel that
  /// the homography maps onto it, with bilinear interpolation. Pixels with no source are black, and
  /// `valid` marks the ones that have one.
  static func warp(
    _ source: RasterImage, by homography: simd_double3x3, width: Int, height: Int
  ) -> (raster: RasterImage, valid: [Bool])? {
    let inverse = homography.inverse
    let straight = source.straightRGBA()
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    var valid = [Bool](repeating: false, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        let target = inverse * simd_double3(Double(x) + 0.5, Double(y) + 0.5, 1)
        guard target.z != 0 else { continue }
        let sourceX = target.x / target.z - 0.5
        let sourceY = target.y / target.z - 0.5
        guard sourceX >= 0, sourceY >= 0,
          sourceX <= Double(source.width - 1), sourceY <= Double(source.height - 1)
        else { continue }
        let index = y * width + x
        valid[index] = true
        let x0 = Int(sourceX)
        let y0 = Int(sourceY)
        let x1 = min(x0 + 1, source.width - 1)
        let y1 = min(y0 + 1, source.height - 1)
        let fractionX = sourceX - Double(x0)
        let fractionY = sourceY - Double(y0)
        for channel in 0..<3 {
          let top =
            Double(straight[(y0 * source.width + x0) * 4 + channel]) * (1 - fractionX)
            + Double(straight[(y0 * source.width + x1) * 4 + channel]) * fractionX
          let bottom =
            Double(straight[(y1 * source.width + x0) * 4 + channel]) * (1 - fractionX)
            + Double(straight[(y1 * source.width + x1) * 4 + channel]) * fractionX
          pixels[index * 4 + channel] = UInt8(
            (top * (1 - fractionY) + bottom * fractionY).rounded())
        }
      }
    }
    return (RasterImage(width: width, height: height, pixels: pixels), valid)
  }

  // MARK: - Common area

  struct Rectangle: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
  }

  /// The largest rectangle made only of `true` cells, by the histogram method: each row is scanned
  /// with a stack of column heights.
  static func largestRectangle(in valid: [Bool], width: Int, height: Int) -> Rectangle? {
    var heights = [Int](repeating: 0, count: width)
    var best: (area: Int, rectangle: Rectangle)?
    for row in 0..<height {
      for column in 0..<width {
        heights[column] = valid[row * width + column] ? heights[column] + 1 : 0
      }
      var stack: [Int] = []
      for column in 0...width {
        let current = column == width ? 0 : heights[column]
        while let top = stack.last, heights[top] >= current {
          stack.removeLast()
          let barHeight = heights[top]
          let left = stack.last.map { $0 + 1 } ?? 0
          let barWidth = column - left
          let area = barHeight * barWidth
          if barHeight > 0, area > (best?.area ?? 0) {
            best = (
              area, Rectangle(x: left, y: row - barHeight + 1, width: barWidth, height: barHeight)
            )
          }
        }
        stack.append(column)
      }
    }
    return best?.rectangle
  }

  private static func crop(_ raster: RasterImage, to rectangle: Rectangle) -> RasterImage? {
    var pixels: [UInt8] = []
    pixels.reserveCapacity(rectangle.width * rectangle.height * 4)
    for y in rectangle.y..<(rectangle.y + rectangle.height) {
      let start = (y * raster.width + rectangle.x) * 4
      pixels += raster.pixels[start..<(start + rectangle.width * 4)]
    }
    return RasterImage(width: rectangle.width, height: rectangle.height, pixels: pixels)
  }
}
