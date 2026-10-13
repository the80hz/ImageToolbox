import CoreGraphics
import Foundation

/// A round brush. Its hardness sets where the soft edge starts, its spacing how far apart the stamps are
/// along a stroke, and its opacity the strength of each stamp.
public struct Brush: Equatable, Sendable {
  /// Radius in pixels, from 0.5 to 500.
  public var radius: Double
  /// 0 is fully soft, 1 is fully hard. The solid core ends at `radius * hardness`.
  public var hardness: Double
  /// Strength of one stamp, from 0 to 1.
  public var opacity: Double
  /// Distance between stamps as a fraction of the radius, from 0.05 to 1.
  public var spacing: Double

  public init(
    radius: Double = 8, hardness: Double = 0.8, opacity: Double = 1, spacing: Double = 0.25
  ) {
    self.radius = min(max(radius, 0.5), 500)
    self.hardness = min(max(hardness, 0), 1)
    self.opacity = min(max(opacity, 0), 1)
    self.spacing = min(max(spacing, 0.05), 1)
  }

  /// Coverage of one stamp at distance `distance` from its centre, from 0 to 1.
  func coverage(atDistance distance: Double) -> Double {
    if distance >= radius { return 0 }
    let solid = radius * hardness
    if distance <= solid { return 1 }
    return 1 - (distance - solid) / (radius - solid)
  }
}

/// A canvas of alpha coverage. Strokes add coverage with the "over" rule, and the result can be
/// turned into a coloured picture.
public struct BrushCanvas: Sendable {
  public let width: Int
  public let height: Int
  /// Coverage per pixel, from 0 to 1, row by row from the top.
  public private(set) var coverage: [Double]

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    coverage = [Double](repeating: 0, count: self.width * self.height)
  }

  /// Draws a straight stroke from `start` to `end`.
  public mutating func stroke(from start: CGPoint, to end: CGPoint, brush: Brush) {
    let length = hypot(end.x - start.x, end.y - start.y)
    let step = max(brush.radius * brush.spacing, 0.5)
    let count = max(Int((length / step).rounded(.up)), 1)
    for index in 0...count {
      let fraction = Double(index) / Double(count)
      stamp(
        at: CGPoint(
          x: start.x + (end.x - start.x) * fraction,
          y: start.y + (end.y - start.y) * fraction),
        brush: brush)
    }
  }

  /// Draws a stroke through a list of points, one straight segment at a time.
  public mutating func stroke(through points: [CGPoint], brush: Brush) {
    guard let first = points.first else { return }
    if points.count == 1 {
      stamp(at: first, brush: brush)
      return
    }
    for (start, end) in zip(points, points.dropFirst()) {
      stroke(from: start, to: end, brush: brush)
    }
  }

  /// A picture in one colour with the coverage as its alpha. Colour components are 0...255.
  public func raster(red: UInt8, green: UInt8, blue: UInt8) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in coverage.indices {
      let alpha = UInt8((min(max(coverage[index], 0), 1) * 255).rounded())
      let premultiplied = { (value: UInt8) -> UInt8 in
        UInt8((Int(value) * Int(alpha) + 127) / 255)
      }
      pixels[index * 4] = premultiplied(red)
      pixels[index * 4 + 1] = premultiplied(green)
      pixels[index * 4 + 2] = premultiplied(blue)
      pixels[index * 4 + 3] = alpha
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Erases the coverage under one stamp, with the brush's shape and opacity.
  public mutating func erase(at point: CGPoint, brush: Brush) {
    for (index, distance) in pixels(near: point, radius: brush.radius) {
      let strength = brush.coverage(atDistance: distance) * brush.opacity
      coverage[index] *= 1 - strength
    }
  }

  /// Adds `opacity` of coverage to each pixel whose flag in `mask` is true, with the "over" rule.
  /// The mask holds one flag per pixel, row by row from the top, as `LassoMask` returns it.
  public mutating func paint(_ mask: [Bool], opacity: Double) {
    guard mask.count == coverage.count else { return }
    let strength = min(max(opacity, 0), 1)
    for index in mask.indices where mask[index] {
      coverage[index] = coverage[index] + strength * (1 - coverage[index])
    }
  }

  /// Sets full coverage on the pixels whose centres lie in a square of `side` drawing units,
  /// centred on `centre`.
  public mutating func paintSquare(at centre: CGPoint, side: Double) {
    let half = side / 2
    let minX = max(Int((Double(centre.x) - half - 0.5).rounded(.up)), 0)
    let maxX = min(Int((Double(centre.x) + half - 0.5).rounded(.down)), width - 1)
    let minY = max(Int((Double(centre.y) - half - 0.5).rounded(.up)), 0)
    let maxY = min(Int((Double(centre.y) + half - 0.5).rounded(.down)), height - 1)
    guard minX <= maxX, minY <= maxY else { return }
    for y in minY...maxY {
      for x in minX...maxX {
        coverage[y * width + x] = 1
      }
    }
  }

  // MARK: - Helpers

  private mutating func stamp(at point: CGPoint, brush: Brush) {
    for (index, distance) in pixels(near: point, radius: brush.radius) {
      let strength = brush.coverage(atDistance: distance) * brush.opacity
      coverage[index] = coverage[index] + strength * (1 - coverage[index])
    }
  }

  /// The index and distance of each pixel centre within `radius` of `point`.
  private func pixels(near point: CGPoint, radius: Double) -> [(index: Int, distance: Double)] {
    let minX = max(Int((point.x - radius).rounded(.down)), 0)
    let maxX = min(Int((point.x + radius).rounded(.up)), width - 1)
    let minY = max(Int((point.y - radius).rounded(.down)), 0)
    let maxY = min(Int((point.y + radius).rounded(.up)), height - 1)
    guard minX <= maxX, minY <= maxY else { return [] }
    var result: [(index: Int, distance: Double)] = []
    for y in minY...maxY {
      for x in minX...maxX {
        let distance = hypot(Double(x) + 0.5 - point.x, Double(y) + 0.5 - point.y)
        if distance < radius {
          result.append((y * width + x, distance))
        }
      }
    }
    return result
  }
}
