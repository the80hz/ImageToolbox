import CoreGraphics
import Foundation

/// Removes a small blemish by replacing the pixels inside a circle with the average of a ring of
/// pixels around it.
///
/// The ring is the band just outside the circle, `max(2, radius / 2)` pixels wide. A ring pixel
/// weighs `1 - t`, where `t` is its distance from the circle's edge as a fraction of the band, so
/// the pixels nearest the edge count most. Every pixel inside the circle then takes the same
/// weighted mean, premultiplied RGBA included.
///
/// This is a deliberately simple and deterministic filter, not PatchMatch and not texture
/// synthesis. It works on smooth backgrounds. On textured ones it leaves a flat patch.
public enum SpotHealing {

  /// Returns a copy of `raster` with the circle at `centre` healed. Returns `raster` unchanged when
  /// the radius is not positive or the ring has no pixels inside the image.
  public static func heal(_ raster: RasterImage, at centre: CGPoint, radius: Double) -> RasterImage
  {
    let centreX = Double(centre.x)
    let centreY = Double(centre.y)
    guard radius > 0, radius.isFinite, centreX.isFinite, centreY.isFinite else { return raster }

    let band = max(2, radius / 2)
    let outer = radius + band
    let width = raster.width
    let height = raster.height
    guard
      let columns = pixelIndices(from: centreX - outer, to: centreX + outer, limit: width),
      let rows = pixelIndices(from: centreY - outer, to: centreY + outer, limit: height)
    else { return raster }

    var sums = [Double](repeating: 0, count: 4)
    var weightSum = 0.0
    for y in rows {
      for x in columns {
        let distance = hypot(Double(x) + 0.5 - centreX, Double(y) + 0.5 - centreY)
        guard distance >= radius, distance < outer else { continue }
        let weight = 1 - (distance - radius) / band
        let index = (y * width + x) * 4
        for channel in 0..<4 {
          sums[channel] += weight * Double(raster.pixels[index + channel])
        }
        weightSum += weight
      }
    }
    guard weightSum > 0 else { return raster }
    let mean = sums.map { UInt8(min(max(($0 / weightSum).rounded(), 0), 255)) }

    var pixels = raster.pixels
    for y in rows {
      for x in columns {
        let distance = hypot(Double(x) + 0.5 - centreX, Double(y) + 0.5 - centreY)
        guard distance < radius else { continue }
        let index = (y * width + x) * 4
        for channel in 0..<4 {
          pixels[index + channel] = mean[channel]
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Indices of the pixels whose centres lie in `lower...upper`, clipped to `0..<limit`.
  /// Returns nil when no pixel qualifies.
  private static func pixelIndices(
    from lower: Double, to upper: Double, limit: Int
  ) -> ClosedRange<Int>? {
    let first = max((lower - 0.5).rounded(.up), 0)
    let last = min((upper - 0.5).rounded(.down), Double(limit - 1))
    guard first <= last else { return nil }
    return Int(first)...Int(last)
  }
}
