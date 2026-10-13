import CoreGraphics
import Foundation

extension MarkupDocument {
  /// Index of the topmost visible layer under `point`, or nil. Hidden layers are skipped. Locked
  /// layers can still be picked, so that they can be unlocked.
  ///
  /// `tolerance` widens every layer by that many pixels, so thin lines and small stickers can be
  /// picked with a finger. Pass the touch slop divided by the zoom scale.
  public func layerIndex(at point: CGPoint, tolerance: Double = 0) -> Int? {
    layers.indices.last { index in
      layers[index].isVisible && layers[index].contains(point, tolerance: tolerance)
    }
  }
}

extension MarkupLayer {
  /// Whether `point` lies on the layer, within `tolerance` pixels. Opacity does not matter here.
  func contains(_ drawnPoint: CGPoint, tolerance: Double) -> Bool {
    let slop = CGFloat(max(tolerance, 0))
    // Geometry is stored unflipped, so the point is mapped back into that space first.
    let point = unflipped(drawnPoint)
    switch content {
    case .text(_, _, _, _, let origin, let rotation, _, _):
      guard let layout = textLayout(colour: CGColor(gray: 0, alpha: 1)) else { return false }
      // Rotate the point back by the text's angle, into the text's own top-left coordinates.
      let dx = point.x - origin.x
      let dy = point.y - origin.y
      let cosine = CGFloat(cos(rotation))
      let sine = CGFloat(sin(rotation))
      let localX = dx * cosine + dy * sine
      let localY = -dx * sine + dy * cosine
      return localX >= -slop && localX <= layout.blockWidth + slop && localY >= -slop
        && localY <= layout.height + slop

    case .sticker(_, let frame), .image(_, let frame):
      return frame.standardized.insetBy(dx: -slop, dy: -slop).contains(point)

    case .shape(let kind, let frame, let strokeWidth, _, _, let style):
      let path = MarkupShapeGeometry.path(
        kind: kind, frame: frame, strokeWidth: strokeWidth, style: style)
      let reach = slop + CGFloat(max(strokeWidth, 0)) / 2
      return HitGeometry.path(path, contains: point, reach: reach, closed: kind.isClosed)

    case .stroke(let points, let brush, _):
      guard let nearest = HitGeometry.distance(from: point, toPolyline: points) else {
        return false
      }
      return nearest <= CGFloat(brush.radius) + slop
    }
  }
}

/// Distance and area helpers for hit testing. Private to this file.
private enum HitGeometry {
  /// Whether `point` lies inside `path`, or within `reach` of its outline. The inside counts
  /// whether or not the shape is filled, as it does for rectangles. The outline is tested by
  /// stroking the path with a width of twice the reach, so it follows any curve or corner.
  /// An open path has no inside. CoreGraphics closes its subpaths when it fills them, which would
  /// make the area between line heads count as inside, so only the band is tested.
  static func path(_ path: CGPath, contains point: CGPoint, reach: CGFloat, closed: Bool) -> Bool {
    if closed, path.contains(point, using: .winding) { return true }
    guard reach > 0 else { return false }
    let band = path.copy(
      strokingWithWidth: reach * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return band.contains(point, using: .winding)
  }

  static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
    // Project onto the segment and clamp, so the end caps are round.
    let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
    return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
  }

  /// Distance to the nearest segment of the polyline. A single point is measured directly.
  /// Returns nil when there are no points.
  static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat? {
    guard let first = points.first else { return nil }
    guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
    return zip(points, points.dropFirst()).map { start, end in
      distance(from: point, toSegment: start, end)
    }.min()
  }
}
