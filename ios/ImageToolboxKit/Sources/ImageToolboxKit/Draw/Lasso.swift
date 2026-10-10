import CoreGraphics
import Foundation

/// A closed polygon used as a lasso selection. A pixel is inside when its centre is inside.
public struct LassoMask: Sendable {
  /// Corners in drawing order. The last corner connects back to the first.
  public let polygon: [CGPoint]

  public init(polygon: [CGPoint]) {
    self.polygon = polygon
  }

  /// One flag per pixel, row-major from the top, true where the pixel centre is inside.
  ///
  /// Uses the even-odd rule, so where the outline crosses itself the overlap is outside.
  /// A polygon with fewer than three corners selects nothing.
  public func mask(width: Int, height: Int) -> [Bool] {
    guard width > 0, height > 0 else { return [] }
    var inside = [Bool](repeating: false, count: width * height)
    guard polygon.count >= 3 else { return inside }

    let vertices = polygon.map { (x: Double($0.x), y: Double($0.y)) }
    var crossings: [Double] = []
    for y in 0..<height {
      let centreY = Double(y) + 0.5
      crossings.removeAll(keepingCapacity: true)
      for index in vertices.indices {
        let start = vertices[index]
        let end = vertices[(index + 1) % vertices.count]
        // Half-open on y, so a corner shared by two edges is counted once.
        guard (start.y > centreY) != (end.y > centreY) else { continue }
        crossings.append(start.x + (centreY - start.y) * (end.x - start.x) / (end.y - start.y))
      }
      crossings.sort()

      // Crossings come in pairs: the span between each pair is inside.
      for pair in stride(from: 0, to: crossings.count - 1, by: 2) {
        // Columns whose centres fall in [left, right).
        let first = max((crossings[pair] - 0.5).rounded(.up), 0)
        let last = min((crossings[pair + 1] - 0.5).rounded(.up), Double(width))
        guard first < last else { continue }
        for x in Int(first)..<Int(last) {
          inside[y * width + x] = true
        }
      }
    }
    return inside
  }

  /// Keeps the pixels inside the polygon and makes everything outside transparent.
  public static func cut(_ raster: RasterImage, polygon: [CGPoint]) -> RasterImage {
    let inside = LassoMask(polygon: polygon).mask(width: raster.width, height: raster.height)
    var pixels = raster.pixels
    for index in inside.indices where !inside[index] {
      let base = index * 4
      pixels[base] = 0
      pixels[base + 1] = 0
      pixels[base + 2] = 0
      pixels[base + 3] = 0
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: pixels)
  }

  /// Recolours the pixels inside the polygon. Their alpha is kept, so transparent areas stay
  /// transparent. Colour components are 0...255.
  public static func fill(
    _ raster: RasterImage, polygon: [CGPoint], with colour: (UInt8, UInt8, UInt8)
  ) -> RasterImage {
    let inside = LassoMask(polygon: polygon).mask(width: raster.width, height: raster.height)
    let (red, green, blue) = colour
    var pixels = raster.pixels
    for index in inside.indices where inside[index] {
      let base = index * 4
      let alpha = pixels[base + 3]
      // Pixels are premultiplied, so the colour is scaled by the alpha that stays.
      pixels[base] = premultiplied(red, alpha: alpha)
      pixels[base + 1] = premultiplied(green, alpha: alpha)
      pixels[base + 2] = premultiplied(blue, alpha: alpha)
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: pixels)
  }

  private static func premultiplied(_ value: UInt8, alpha: UInt8) -> UInt8 {
    UInt8((Int(value) * Int(alpha) + 127) / 255)
  }
}
