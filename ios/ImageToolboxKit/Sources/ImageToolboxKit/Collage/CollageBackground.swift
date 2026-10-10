import CoreGraphics
import Foundation

/// What is drawn behind the cells of a collage and in the gaps between them. A solid colour keeps its alpha,
/// so a transparent background gives a collage with transparent gaps.
public enum CollageBackground: Equatable, Sendable {
  /// One colour over the whole canvas.
  case solid(RGBA)
  /// A linear gradient. `angle` is in degrees: 0 runs from left to right and 90 from top to bottom. The
  /// gradient line is as long as the canvas along that direction, so the first and last stop touch corners.
  case linearGradient(stops: [GradientStop], angle: Double)
  /// A radial gradient centred in the canvas. The first stop is the centre and the last stop is at the corners.
  case radialGradient(stops: [GradientStop])

  /// Opaque white, the default of the Android collage.
  public static let white = CollageBackground.solid(RGBA(red: 255, green: 255, blue: 255))

  /// A linear gradient between two colours.
  public static func linearGradient(from start: RGBA, to end: RGBA, angle: Double)
    -> CollageBackground
  {
    .linearGradient(
      stops: [GradientStop(color: start, location: 0), GradientStop(color: end, location: 1)],
      angle: angle)
  }

  /// A radial gradient between two colours.
  public static func radialGradient(from start: RGBA, to end: RGBA) -> CollageBackground {
    .radialGradient(stops: [
      GradientStop(color: start, location: 0), GradientStop(color: end, location: 1),
    ])
  }

  /// Whether any part of the background is not fully opaque, so the collage should be saved with alpha.
  public var hasTransparency: Bool {
    switch self {
    case .solid(let color):
      return color.alpha < 255
    case .linearGradient(let stops, _), .radialGradient(let stops):
      return stops.contains { $0.color.alpha < 255 }
    }
  }

  /// Fills `width` by `height` pixels of `context`, whose origin is at the bottom left.
  public func draw(in context: CGContext, width: Int, height: Int) {
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    switch self {
    case .solid(let color):
      context.setFillColor(Self.cgColor(color))
      context.fill(canvas)
    case .linearGradient(let stops, let angle):
      guard let gradient = Self.gradient(stops) else {
        return drawFallback(stops, in: context, canvas: canvas)
      }
      let line = Self.linearLine(angle: angle, width: Double(width), height: Double(height))
      // The line is in top-left coordinates and the context is not.
      context.drawLinearGradient(
        gradient,
        start: CGPoint(x: line.start.x, y: Double(height) - line.start.y),
        end: CGPoint(x: line.end.x, y: Double(height) - line.end.y),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    case .radialGradient(let stops):
      guard let gradient = Self.gradient(stops) else {
        return drawFallback(stops, in: context, canvas: canvas)
      }
      let centre = CGPoint(x: canvas.midX, y: canvas.midY)
      context.drawRadialGradient(
        gradient, startCenter: centre, startRadius: 0, endCenter: centre,
        endRadius: hypot(canvas.width, canvas.height) / 2,
        options: [.drawsAfterEndLocation])
    }
  }

  /// The start and end of a linear gradient over a canvas, in top-left coordinates. The line passes through the
  /// centre of the canvas and is as long as the canvas is along the direction of `angle`, as in the Android
  /// gradient fill.
  static func linearLine(angle: Double, width: Double, height: Double)
    -> (start: CGPoint, end: CGPoint)
  {
    let radians = (angle.isFinite ? angle : 0) * Double.pi / 180
    let dx = cos(radians)
    let dy = sin(radians)
    let half = max(abs(dx) * width + abs(dy) * height, 1) / 2
    let centre = CGPoint(x: width / 2, y: height / 2)
    return (
      CGPoint(x: centre.x - dx * half, y: centre.y - dy * half),
      CGPoint(x: centre.x + dx * half, y: centre.y + dy * half)
    )
  }

  // MARK: - Helpers

  /// A gradient needs two stops. With one stop the canvas is filled with that colour instead.
  private func drawFallback(_ stops: [GradientStop], in context: CGContext, canvas: CGRect) {
    guard let only = stops.first else { return }
    context.setFillColor(Self.cgColor(only.color))
    context.fill(canvas)
  }

  private static func gradient(_ stops: [GradientStop]) -> CGGradient? {
    guard stops.count >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let sorted = stops.sorted { $0.location < $1.location }
    return CGGradient(
      colorsSpace: space,
      colors: sorted.map { cgColor($0.color) } as CFArray,
      locations: sorted.map { CGFloat(min(max($0.location, 0), 1)) })
  }

  private static func cgColor(_ color: RGBA) -> CGColor {
    ImageStitcher.cgColor(color)
  }
}
