import CoreGraphics
import Foundation

/// How the outline of a stroke or shape is broken up.
///
/// The lengths are ratios of the brush diameter `d`, which is Android's stroke width. A dash is
/// `2d` long with `5d` between dashes, which matches Android's defaults at a width of 5 pt (dash
/// 10 pt, gap 20 pt plus the width). A dot-dash repeats a `4d` dash, a `2d` gap, a `d / 4` dot and
/// a `2d` gap. A zigzag has a period of `d` and a height of `d / 2`.
public enum LineStyle: Hashable, Sendable, CaseIterable {
  case solid
  case dashed
  case dotDashed
  case zigZag

  /// The pieces to stroke for a polyline, in drawing units, for a brush of `diameter`.
  public func pieces(of points: [CGPoint], diameter: Double) -> [[CGPoint]] {
    guard points.count >= 2 else { return [points] }
    let d = max(diameter, 0.5)
    switch self {
    case .solid:
      return [points]
    case .dashed:
      return Self.dashes(points, pattern: [2 * d, 5 * d])
    case .dotDashed:
      return Self.dashes(points, pattern: [4 * d, 2 * d, d / 4, 2 * d])
    case .zigZag:
      return [Self.zigzag(points, diameter: d)]
    }
  }

  /// Walks along the polyline and keeps the parts that fall on the "on" steps of `pattern`.
  /// Pattern entries alternate between on and off, starting with on.
  private static func dashes(_ points: [CGPoint], pattern: [Double]) -> [[CGPoint]] {
    var pieces: [[CGPoint]] = []
    var current: [CGPoint] = [points[0]]
    var on = true
    var phase = 0
    var remaining = pattern[0]

    for (start, end) in zip(points, points.dropFirst()) {
      let total = distance(start, end)
      guard total > 0 else { continue }
      var travelled = 0.0
      while total - travelled >= remaining {
        travelled += remaining
        let boundary = point(from: start, to: end, fraction: travelled / total)
        if on {
          current.append(boundary)
          pieces.append(current)
          current = []
        } else {
          current = [boundary]
        }
        on.toggle()
        phase = (phase + 1) % pattern.count
        remaining = pattern[phase]
      }
      remaining -= total - travelled
      if on {
        current.append(end)
      }
    }
    if on, current.count >= 2 {
      pieces.append(current)
    }
    return pieces
  }

  /// A triangle wave along the polyline: the offset alternates between the line and a peak one
  /// half period away, on the left of the direction of travel.
  private static func zigzag(_ points: [CGPoint], diameter: Double) -> [CGPoint] {
    let step = diameter / 2
    var result: [CGPoint] = [points[0]]
    var samples = 0
    // Distance from the last sample to the start of the current segment is `carry`, so the next
    // sample falls `step - carry` into the segment.
    var carry = 0.0

    for (start, end) in zip(points, points.dropFirst()) {
      let total = distance(start, end)
      guard total > 0 else { continue }
      let ux = Double(end.x - start.x) / total
      let uy = Double(end.y - start.y) / total
      let normal = (x: -uy, y: ux)
      var t = step - carry
      while t <= total {
        samples += 1
        let offset = samples.isMultiple(of: 2) ? 0 : step
        let base = point(from: start, to: end, fraction: t / total)
        result.append(
          CGPoint(
            x: base.x + CGFloat(normal.x * offset), y: base.y + CGFloat(normal.y * offset)))
        t += step
      }
      carry = total - (t - step)
    }
    if let last = points.last {
      result.append(last)
    }
    return result
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    Double(hypot(b.x - a.x, b.y - a.y))
  }

  private static func point(from start: CGPoint, to end: CGPoint, fraction: Double) -> CGPoint {
    CGPoint(
      x: start.x + (end.x - start.x) * CGFloat(fraction),
      y: start.y + (end.y - start.y) * CGFloat(fraction))
  }
}

extension BrushCanvas {
  /// Strokes a polyline with the brush, broken up by `style`.
  public mutating func stroke(through points: [CGPoint], brush: Brush, style: LineStyle) {
    guard style != .solid else {
      stroke(through: points, brush: brush)
      return
    }
    for piece in style.pieces(of: points, diameter: brush.radius * 2) {
      stroke(through: piece, brush: brush)
    }
  }
}
