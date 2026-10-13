import CoreGraphics
import Foundation

/// How one picture sits in its cell: how far it is zoomed in, where its centre is and how it is turned. The identity
/// placement is the aspect fill of the Android collage. A zoom of at least 1 keeps the picture covering its cell, and
/// the offset moves the picture only within the travel that leaves no gap at the edges, so a cell is never empty.
///
/// The offset is stored as a fraction of the travel along the picture's own axes, not in pixels, so a placement keeps
/// its meaning when the canvas changes size. A turned picture is zoomed in just enough to cover its cell as well.
public struct CollagePhotoPlacement: Equatable, Sendable {

  /// The largest zoom. Android has no limit; four times is enough to pick out a detail.
  public static let maximumZoom: CGFloat = 4

  /// The zoom relative to the cover size of the cell, from 1 to `maximumZoom`.
  public private(set) var zoom: CGFloat
  /// The centre of the picture as a fraction of its travel along each of its own axes, from -1 to 1. Minus one puts
  /// the left or top edge of the picture on the edge of the cell, one puts the right or bottom edge there. An axis with
  /// no travel ignores the offset.
  public private(set) var offset: CGVector
  /// The turn of the picture in radians, clockwise on the screen, from -pi to pi.
  public private(set) var rotation: CGFloat

  /// Makes a placement. The zoom is kept within 1...`maximumZoom` and each offset component within -1...1. A value
  /// that is not a finite number becomes the default. The rotation is wrapped into -pi...pi.
  public init(zoom: CGFloat = 1, offset: CGVector = .zero, rotation: CGFloat = 0) {
    self.zoom = zoom.isFinite ? min(max(zoom, 1), Self.maximumZoom) : 1
    self.offset = CGVector(dx: Self.unit(offset.dx), dy: Self.unit(offset.dy))
    self.rotation = rotation.isFinite ? Self.wrapped(rotation) : 0
  }

  /// The aspect fill, centred and unturned.
  public static let identity = CollagePhotoPlacement()

  /// The same placement with another zoom, limited as in `init`.
  public func zoomed(to zoom: CGFloat) -> CollagePhotoPlacement {
    CollagePhotoPlacement(zoom: zoom, offset: offset, rotation: rotation)
  }

  /// The same placement with another offset, limited as in `init`.
  public func positioned(at offset: CGVector) -> CollagePhotoPlacement {
    CollagePhotoPlacement(zoom: zoom, offset: offset, rotation: rotation)
  }

  /// The same placement turned to `radians`, wrapped as in `init`.
  public func rotated(to radians: CGFloat) -> CollagePhotoPlacement {
    CollagePhotoPlacement(zoom: zoom, offset: offset, rotation: radians)
  }

  /// A picture as it is drawn into a box: its centre, its size before the turn and the turn.
  public struct Drawn: Equatable, Sendable {
    /// The centre of the picture, in the coordinates of the box.
    public let centre: CGPoint
    /// The size of the picture before the turn, in the units of the box.
    public let size: CGSize
    /// The turn in radians, as in the placement.
    public let rotation: CGFloat
  }

  /// The picture of `picture` pixels drawn into `box`: it covers the box at this zoom, is moved by the offset and
  /// turned by the rotation. Without a usable picture or box it is the box itself, unturned.
  public func drawn(of picture: CGSize, into box: CGRect) -> Drawn {
    guard Self.isUsable(picture, box) else {
      return Drawn(centre: CGPoint(x: box.midX, y: box.midY), size: box.size, rotation: 0)
    }
    let fit = fitted(picture, into: box)
    let axes = Axes(rotation: rotation)
    let shift = CGVector(dx: offset.dx * fit.travel.dx, dy: offset.dy * fit.travel.dy)
    return Drawn(
      centre: CGPoint(
        x: box.midX + axes.u.dx * shift.dx + axes.v.dx * shift.dy,
        y: box.midY + axes.u.dy * shift.dx + axes.v.dy * shift.dy),
      size: fit.size, rotation: rotation)
  }

  /// The placement after the picture has been dragged by `delta` pixels, in a cell whose picture box is `box`.
  /// `picture` is the size of the picture in pixels. The drag is measured along the picture's own axes, so it follows
  /// a turned picture. A drag along an axis with no travel changes nothing there.
  public func panned(by delta: CGVector, picture: CGSize, into box: CGRect)
    -> CollagePhotoPlacement
  {
    guard delta.dx.isFinite, delta.dy.isFinite, Self.isUsable(picture, box) else { return self }
    let travel = fitted(picture, into: box).travel
    let axes = Axes(rotation: rotation)
    let along = CGVector(
      dx: delta.dx * axes.u.dx + delta.dy * axes.u.dy,
      dy: delta.dx * axes.v.dx + delta.dy * axes.v.dy)
    return CollagePhotoPlacement(
      zoom: zoom,
      offset: CGVector(
        dx: travel.dx > 0 ? offset.dx + along.dx / travel.dx : offset.dx,
        dy: travel.dy > 0 ? offset.dy + along.dy / travel.dy : offset.dy),
      rotation: rotation)
  }

  /// The rectangle that encloses the picture as drawn, which is the picture itself without a turn. Use `drawn(of:into:)`
  /// to draw a turned picture. Without a picture or a box it is `box`.
  public func drawRect(of picture: CGSize, into box: CGRect) -> CGRect {
    let drawn = drawn(of: picture, into: box)
    let reach = Axes.extent(
      halfWidth: drawn.size.width / 2, halfHeight: drawn.size.height / 2, rotation: drawn.rotation)
    return CGRect(
      x: drawn.centre.x - reach.dx, y: drawn.centre.y - reach.dy,
      width: 2 * reach.dx, height: 2 * reach.dy)
  }

  // MARK: - Helpers

  /// The size the picture is drawn at to cover `box` at this zoom, and how far its centre can travel from the centre
  /// of the box along the picture's axes while it still covers the box.
  private func fitted(_ picture: CGSize, into box: CGRect) -> (size: CGSize, travel: CGVector) {
    let reach = Axes.extent(
      halfWidth: box.width / 2, halfHeight: box.height / 2, rotation: rotation)
    // The smallest scale at which the picture covers every corner of the box, times the zoom.
    let cover = max(2 * reach.dx / picture.width, 2 * reach.dy / picture.height)
    let size = CGSize(width: picture.width * cover * zoom, height: picture.height * cover * zoom)
    let travel = CGVector(
      dx: max(size.width / 2 - reach.dx, 0), dy: max(size.height / 2 - reach.dy, 0))
    return (size, travel)
  }

  /// The unit vectors along the picture's width and height, for a turn by `rotation` on the screen.
  private struct Axes {
    let u: CGVector
    let v: CGVector

    init(rotation: CGFloat) {
      u = CGVector(dx: cos(rotation), dy: sin(rotation))
      v = CGVector(dx: -sin(rotation), dy: cos(rotation))
    }

    /// The half extents of a rectangle with these half sizes, turned by `rotation`, along the screen axes.
    static func extent(halfWidth: CGFloat, halfHeight: CGFloat, rotation: CGFloat) -> CGVector {
      let c = abs(cos(rotation))
      let s = abs(sin(rotation))
      return CGVector(dx: halfWidth * c + halfHeight * s, dy: halfWidth * s + halfHeight * c)
    }
  }

  private static func isUsable(_ picture: CGSize, _ box: CGRect) -> Bool {
    picture.width > 0 && picture.height > 0 && box.width > 0 && box.height > 0
      && picture.width.isFinite && picture.height.isFinite
  }

  private static func unit(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(max(value, -1), 1) : 0
  }

  /// The angle in -pi...pi that a turn of `radians` stands for.
  private static func wrapped(_ radians: CGFloat) -> CGFloat {
    let turn = 2 * CGFloat.pi
    var value = radians.truncatingRemainder(dividingBy: turn)
    if value > .pi { value -= turn }
    if value <= -.pi { value += turn }
    return value
  }
}
