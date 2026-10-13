import CoreGraphics
import Foundation

/// How the pixels under a warp brush move.
public enum WarpMode: Hashable, Sendable, CaseIterable {
  /// Pushes the pixels along the direction of the stroke.
  case push
  /// Pulls the pixels outwards from the centre, so the content under the brush grows.
  case grow
  /// Pulls the pixels inwards towards the centre, so the content under the brush shrinks.
  case shrink
  /// Turns the pixels clockwise around the centre.
  case swirlClockwise
  /// Turns the pixels counter-clockwise around the centre.
  case swirlCounterclockwise
}

/// A warp brush: the pixels under the brush move, as if dragged or squeezed.
///
/// The result is computed backwards. For a pixel `p` inside the circle, the output takes the source
/// colour at a point `s` that depends on the mode, and the source is read with bilinear
/// interpolation. The falloff is `1` in a solid core of radius `radius * hardness` and falls
/// linearly to `0` at the edge; the weight is its square. Pixels outside the circle are copied
/// unchanged.
///
/// Grow, shrink and swirl are this kit's own mappings. Android's warp engine is a library
/// (Trickle), and its exact curves are not reproduced here.
public enum WarpBrush {

  /// Pushes the pixels under the brush: a `WarpMode.push` with a hard-edged zero core.
  ///
  /// - Parameters:
  ///   - direction: how far the pointer moved since the previous event, in pixels. Pixels at the
  ///     centre move by `direction * strength`.
  ///   - strength: from 0 to 1. Values outside that range are clamped.
  public static func push(
    _ raster: RasterImage, at centre: CGPoint, direction: CGPoint, radius: Double, strength: Double
  ) -> RasterImage {
    warp(
      raster, at: centre, direction: direction, radius: radius, strength: strength, hardness: 0,
      mode: .push)
  }

  /// Warps the pixels under the brush with `mode`.
  ///
  /// - Parameters:
  ///   - direction: the pointer movement since the previous event. Only `push` moves pixels along
  ///     it, and a zero movement leaves `push` unchanged. The other modes ignore it.
  ///   - strength: from 0 to 1, clamped. Zero changes nothing.
  ///   - hardness: from 0 (soft edge) to 1 (hard edge), the share of the radius that is fully
  ///     affected.
  public static func warp(
    _ raster: RasterImage, at centre: CGPoint, direction: CGPoint, radius: Double,
    strength: Double, hardness: Double = 0, mode: WarpMode = .push
  ) -> RasterImage {
    let centreX = Double(centre.x)
    let centreY = Double(centre.y)
    let amount = min(max(strength, 0), 1)
    let dx = Double(direction.x) * amount
    let dy = Double(direction.y) * amount
    let softness = min(max(hardness, 0), 1)
    guard
      radius > 0, radius.isFinite, centreX.isFinite, centreY.isFinite, dx.isFinite, dy.isFinite,
      amount > 0, mode != .push || dx != 0 || dy != 0
    else { return raster }

    let width = raster.width
    let height = raster.height
    guard
      let columns = pixelIndices(from: centreX - radius, to: centreX + radius, limit: width),
      let rows = pixelIndices(from: centreY - radius, to: centreY + radius, limit: height)
    else { return raster }

    let source = raster.pixels
    var pixels = source
    for y in rows {
      for x in columns {
        let pointX = Double(x) + 0.5
        let pointY = Double(y) + 0.5
        let distance = hypot(pointX - centreX, pointY - centreY)
        guard distance < radius else { continue }
        let fall = falloff(distance: distance, radius: radius, hardness: softness)
        let weight = fall * fall
        let from = sourcePoint(
          mode: mode, pointX: pointX, pointY: pointY, centreX: centreX, centreY: centreY,
          weight: weight, amount: amount, dx: dx, dy: dy)
        sample(
          source, width: width, height: height, x: from.x, y: from.y,
          into: &pixels, at: (y * width + x) * 4)
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  // MARK: - Helpers

  /// The point of the source that lands on (`pointX`, `pointY`) for `mode`.
  private static func sourcePoint(
    mode: WarpMode, pointX: Double, pointY: Double, centreX: Double, centreY: Double,
    weight: Double, amount: Double, dx: Double, dy: Double
  ) -> (x: Double, y: Double) {
    let offsetX = pointX - centreX
    let offsetY = pointY - centreY
    switch mode {
    case .push:
      return (pointX - weight * dx, pointY - weight * dy)
    case .grow:
      let factor = 1 - weight * amount
      return (centreX + offsetX * factor, centreY + offsetY * factor)
    case .shrink:
      let factor = 1 + weight * amount
      return (centreX + offsetX * factor, centreY + offsetY * factor)
    case .swirlClockwise, .swirlCounterclockwise:
      // At full strength the centre turns by a quarter turn, and the turn fades to none at the edge.
      let turn = weight * amount * Double.pi / 2
      let angle = mode == .swirlClockwise ? turn : -turn
      // The source is the point rotated back by `angle`.
      return (
        centreX + cos(angle) * offsetX + sin(angle) * offsetY,
        centreY - sin(angle) * offsetX + cos(angle) * offsetY
      )
    }
  }

  /// 1 inside the solid core, then linear to 0 at the edge of the circle.
  private static func falloff(distance: Double, radius: Double, hardness: Double) -> Double {
    let solid = radius * hardness
    if distance <= solid { return 1 }
    guard radius > solid else { return 0 }
    return 1 - (distance - solid) / (radius - solid)
  }

  /// Writes the bilinear blend of the four source pixels around (x, y) into `pixels` at `index`.
  /// Pixel centres sit at half-integers, and positions outside the image clamp to its edge.
  private static func sample(
    _ source: [UInt8], width: Int, height: Int, x: Double, y: Double,
    into pixels: inout [UInt8], at index: Int
  ) {
    let fx = min(max(x - 0.5, 0), Double(width - 1))
    let fy = min(max(y - 0.5, 0), Double(height - 1))
    let x0 = Int(fx)
    let y0 = Int(fy)
    let x1 = min(x0 + 1, width - 1)
    let y1 = min(y0 + 1, height - 1)
    let tx = fx - Double(x0)
    let ty = fy - Double(y0)

    let topLeft = (y0 * width + x0) * 4
    let topRight = (y0 * width + x1) * 4
    let bottomLeft = (y1 * width + x0) * 4
    let bottomRight = (y1 * width + x1) * 4
    for channel in 0..<4 {
      let top =
        Double(source[topLeft + channel]) * (1 - tx)
        + Double(source[topRight + channel]) * tx
      let bottom =
        Double(source[bottomLeft + channel]) * (1 - tx)
        + Double(source[bottomRight + channel]) * tx
      let value = top * (1 - ty) + bottom * ty
      pixels[index + channel] = UInt8(min(max(value.rounded(), 0), 255))
    }
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
