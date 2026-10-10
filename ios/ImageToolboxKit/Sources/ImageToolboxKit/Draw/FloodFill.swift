import CoreGraphics
import Foundation

/// A paint bucket: fills the connected area around a point whose colour matches the point's.
public enum FloodFill {

  /// Replaces with `colour`, at full opacity, every pixel that can be reached from `point` through
  /// pixels sharing an edge, as long as each one differs from the seed pixel by at most
  /// `tolerance` in every premultiplied channel.
  ///
  /// `tolerance` is a fraction of the full channel range, from 0 (only identical pixels) to 1 (all
  /// pixels). Returns `raster` unchanged when `point` lies outside the image.
  public static func fill(
    _ raster: RasterImage, at point: CGPoint, tolerance: Double,
    colour: (red: UInt8, green: UInt8, blue: UInt8)
  ) -> RasterImage {
    guard point.x.isFinite, point.y.isFinite else { return raster }
    let seedX = Int(Double(point.x).rounded(.down))
    let seedY = Int(Double(point.y).rounded(.down))
    let width = raster.width
    let height = raster.height
    guard (0..<width).contains(seedX), (0..<height).contains(seedY) else { return raster }

    let source = raster.pixels
    var pixels = source
    let seed = seedY * width + seedX
    let limit = min(max(tolerance, 0), 1) * 255
    var visited = [Bool](repeating: false, count: width * height)
    var stack = [seed]
    visited[seed] = true

    // A pixel joins the stack only when it matches, so each one is painted at most once.
    func consider(_ neighbour: Int) {
      guard !visited[neighbour] else { return }
      visited[neighbour] = true
      if matches(source, neighbour, seed: seed, limit: limit) {
        stack.append(neighbour)
      }
    }

    while let index = stack.popLast() {
      let base = index * 4
      pixels[base] = colour.red
      pixels[base + 1] = colour.green
      pixels[base + 2] = colour.blue
      pixels[base + 3] = 255

      let x = index % width
      let y = index / width
      if x > 0 { consider(index - 1) }
      if x < width - 1 { consider(index + 1) }
      if y > 0 { consider(index - width) }
      if y < height - 1 { consider(index + width) }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func matches(_ source: [UInt8], _ index: Int, seed: Int, limit: Double) -> Bool {
    (0..<4).allSatisfy { channel in
      let difference =
        Double(source[index * 4 + channel]) - Double(source[seed * 4 + channel])
      return abs(difference) <= limit
    }
  }
}
