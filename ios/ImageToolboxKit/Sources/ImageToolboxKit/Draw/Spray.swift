import CoreGraphics
import Foundation

/// A SplitMix64 generator. An edit replayed with the same seed scatters the same dots, so the
/// picture does not change between renders.
public struct DrawRandom: Sendable {
  private var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  /// The next number in `0 ..< 1`.
  public mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value >> 11) / Double(UInt64(1) << 53)
  }
}

/// Spray paint: dots scattered at random inside a circle around each point of a drag.
public enum Spray {

  /// Adds `density` dots around each point. The dots fall inside `radius` of their point, uniformly
  /// over the area of the circle. Each dot is a disc, or a square when `square` is set, and
  /// `dotSize` is its diameter or side in drawing units.
  public static func draw(
    points: [CGPoint], radius: Double, density: Int, dotSize: Double, square: Bool, seed: UInt64,
    onto canvas: inout BrushCanvas
  ) {
    guard radius > 0, radius.isFinite, dotSize > 0, density > 0 else { return }
    var random = DrawRandom(seed: seed)
    let disc = Brush(radius: max(dotSize / 2, 0.5), hardness: 1, opacity: 1, spacing: 1)
    for point in points where point.x.isFinite && point.y.isFinite {
      for _ in 0..<density {
        let angle = 2 * Double.pi * random.next()
        let distance = radius * random.next().squareRoot()
        let centre = CGPoint(
          x: point.x + CGFloat(distance * cos(angle)),
          y: point.y + CGFloat(distance * sin(angle)))
        if square {
          canvas.paintSquare(at: centre, side: dotSize)
        } else {
          canvas.stroke(from: centre, to: centre, brush: disc)
        }
      }
    }
  }
}
