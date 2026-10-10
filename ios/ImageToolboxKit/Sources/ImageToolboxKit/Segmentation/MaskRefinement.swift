import CoreGraphics
import Foundation

/// Opacity of a subject, touched up by hand after `BackgroundRemover`. `erase` removes the subject under a
/// brush, `restore` brings back the opacity of the original picture. Pixels are row-major, row 0 at the top,
/// as in `RasterImage`.
public struct SubjectMask: Equatable, Sendable {

  public let width: Int
  public let height: Int
  /// Opacity per pixel, 0...1.
  public private(set) var alpha: [Double]

  /// `alpha` is clamped to 0...1. It must hold `width * height` values.
  public init(width: Int, height: Int, alpha: [Double]) {
    precondition(alpha.count == width * height, "mask size mismatch")
    self.width = width
    self.height = height
    self.alpha = alpha.map { min(max($0, 0), 1) }
  }

  /// The alpha channel of `raster`, so any picture can start a mask.
  public init(raster: RasterImage) {
    width = raster.width
    height = raster.height
    alpha = stride(from: 3, to: raster.pixels.count, by: 4).map { Double(raster.pixels[$0]) / 255 }
  }

  /// The alpha channel of a cut-out, such as the output of `BackgroundRemover`. Nil if it cannot be read.
  public init?(cutout: CGImage) {
    guard let raster = RasterImage(cutout) else { return nil }
    self.init(raster: raster)
  }

  /// Makes the pixels under the brush transparent. The opacity falls off towards the rim as (1 - d/r) squared,
  /// so the edge of the stroke is soft. Pixels outside the circle are not touched.
  public mutating func erase(at centre: CGPoint, radius: Double) {
    paint(centre: centre, radius: radius) { current, weight, _ in current * (1 - weight) }
  }

  /// Brings back the opacity of `source` inside the circle, so an opaque photo gives alpha 1 there.
  /// The edge is hard. `source` must have the same size as the mask.
  public mutating func restore(at centre: CGPoint, radius: Double, source: RasterImage) {
    precondition(source.width == width && source.height == height, "source size mismatch")
    paint(centre: centre, radius: radius) { _, _, index in
      Double(source.pixels[index * 4 + 3]) / 255
    }
  }

  /// The pixels of `source` with this mask as their opacity. The alpha is the mask times the source alpha.
  /// Premultiplied channels are scaled by the mask: straight colour times alpha, without a division.
  public func applied(to source: RasterImage) -> RasterImage {
    precondition(source.width == width && source.height == height, "source size mismatch")
    var pixels = source.pixels
    for index in 0..<(width * height) {
      let opacity = alpha[index]
      for channel in index * 4..<index * 4 + 4 {
        pixels[channel] = UInt8((Double(source.pixels[channel]) * opacity).rounded())
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Replaces the opacity of every pixel whose centre lies inside the circle. `update` receives the current
  /// opacity, the brush weight (1 at the centre, 0 at the rim) and the pixel index.
  private mutating func paint(
    centre: CGPoint,
    radius: Double,
    update: (_ current: Double, _ weight: Double, _ index: Int) -> Double
  ) {
    let cx = Double(centre.x)
    let cy = Double(centre.y)
    guard radius > 0, radius.isFinite, cx.isFinite, cy.isFinite else { return }

    // The bounding box of the circle, clamped to the mask. Empty when the circle misses the mask.
    let left = max((cx - radius).rounded(.down), 0)
    let right = min((cx + radius).rounded(.up), Double(width - 1))
    let top = max((cy - radius).rounded(.down), 0)
    let bottom = min((cy + radius).rounded(.up), Double(height - 1))
    guard left <= right, top <= bottom else { return }

    for y in Int(top)...Int(bottom) {
      for x in Int(left)...Int(right) {
        let dx = Double(x) + 0.5 - cx
        let dy = Double(y) + 0.5 - cy
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= radius else { continue }
        let index = y * width + x
        let falloff = 1 - distance / radius
        alpha[index] = update(alpha[index], falloff * falloff, index)
      }
    }
  }
}
