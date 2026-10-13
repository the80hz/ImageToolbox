import CoreGraphics
import Foundation

/// Reading and changing the parts of a layer that depend on its content.
extension MarkupLayer {
  /// Whether the layer is text. Only text has a style and a visible line count.
  public var isText: Bool { textStyle != nil }

  /// Whether the corner radius applies: pictures and text backgrounds.
  public var supportsCornerRadius: Bool {
    switch content {
    case .text, .sticker, .image: true
    case .shape, .stroke: false
    }
  }

  /// The text style, or nil for layers that are not text.
  public var textStyle: MarkupTextStyle? {
    guard case .text(_, _, _, _, _, _, _, let style) = content else { return nil }
    return style
  }

  /// Number of lines of a text layer, ignoring `visibleLineCount`. Nil for layers that are not text.
  public var textLineCount: Int? {
    var unlimited = self
    unlimited.visibleLineCount = nil
    return unlimited.textLayout(colour: CGColor(gray: 0, alpha: 1))?.lines.count
  }

  /// Whether the layer is a closed shape with a fill. Only these show a gradient.
  public var isFilledShape: Bool {
    guard case .shape(let kind, _, _, _, let fill, _) = content else { return false }
    return kind.isClosed && fill != nil
  }

  /// The kind of a shape, or nil for layers that are not shapes.
  public var shapeKind: Content.ShapeKind? {
    guard case .shape(let kind, _, _, _, _, _) = content else { return nil }
    return kind
  }

  /// The style of a shape, or nil for layers that are not shapes.
  public var shapeStyle: MarkupShapeStyle? {
    guard case .shape(_, _, _, _, _, let style) = content else { return nil }
    return style
  }

  /// The stroke width of a shape in pixels, or nil for layers that are not shapes.
  public var shapeStrokeWidth: Double? {
    guard case .shape(_, _, let strokeWidth, _, _, _) = content else { return nil }
    return strokeWidth
  }

  /// The turn of a text layer in radians, clockwise on screen, or nil for layers that are not text.
  public var textRotation: Double? {
    guard case .text(_, _, _, _, _, let rotation, _, _) = content else { return nil }
    return rotation
  }

  /// Changes the text style of a text layer. Other layers are left as they are.
  public mutating func updateTextStyle(_ change: (inout MarkupTextStyle) -> Void) {
    guard
      case .text(
        let string, let fontName, let fontSize, let colour, let origin, let rotation,
        let wrapWidth, var style) = content
    else { return }
    change(&style)
    content = .text(
      string: string, fontName: fontName, fontSize: fontSize, colour: colour, origin: origin,
      rotation: rotation, wrapWidth: wrapWidth, style: style)
  }

  /// Changes the style of a shape. Other layers are left as they are.
  public mutating func updateShapeStyle(_ change: (inout MarkupShapeStyle) -> Void) {
    guard
      case .shape(
        let kind, let frame, let strokeWidth, let strokeColour, let fillColour,
        var style) = content
    else { return }
    change(&style)
    content = .shape(
      kind: kind, frame: frame, strokeWidth: strokeWidth, strokeColour: strokeColour,
      fillColour: fillColour, style: style)
  }

  /// Sets the stroke width of a shape in pixels. Zero removes the outline of a closed shape, and
  /// negative values become zero. Other layers are left as they are.
  public mutating func updateShapeStrokeWidth(_ width: Double) {
    guard
      case .shape(
        let kind, let frame, _, let strokeColour, let fillColour, let style) = content
    else { return }
    content = .shape(
      kind: kind, frame: frame, strokeWidth: max(width, 0), strokeColour: strokeColour,
      fillColour: fillColour, style: style)
  }

  /// Sets the turn of a text layer in radians, clockwise on screen around its origin. Other layers
  /// are left as they are.
  public mutating func updateTextRotation(_ radians: Double) {
    guard
      case .text(
        let string, let fontName, let fontSize, let colour, let origin, _,
        let wrapWidth, let style) = content
    else { return }
    content = .text(
      string: string, fontName: fontName, fontSize: fontSize, colour: colour, origin: origin,
      rotation: radians, wrapWidth: wrapWidth, style: style)
  }

  /// The laid-out lines of a text layer, as the renderer and hit testing both build them, so they
  /// agree on the size of the block. Nil for layers that are not text.
  func textLayout(colour: CGColor) -> MarkupTextLayout? {
    guard
      case .text(let string, let fontName, let fontSize, _, _, _, let wrapWidth, let style) =
        content
    else { return nil }
    return MarkupTextLayout(
      string: string, fontName: fontName, fontSize: CGFloat(fontSize), colour: colour,
      wrapWidth: wrapWidth.map { CGFloat($0) }, style: style, maxLines: visibleLineCount)
  }

  /// The point that the layer mirrors around, in top-left pixel coordinates. For text it is the
  /// centre of the rotated block. Nil when there is nothing to mirror, such as a stroke with no points.
  func flipCentre() -> CGPoint? {
    switch content {
    case .text(_, _, _, _, let origin, let rotation, _, _):
      guard let layout = textLayout(colour: CGColor(gray: 0, alpha: 1)) else { return nil }
      let halfWidth = layout.blockWidth / 2
      let halfHeight = layout.height / 2
      let cosine = CGFloat(cos(rotation))
      let sine = CGFloat(sin(rotation))
      return CGPoint(
        x: origin.x + halfWidth * cosine - halfHeight * sine,
        y: origin.y + halfWidth * sine + halfHeight * cosine)
    case .sticker(_, let frame), .image(_, let frame), .shape(_, let frame, _, _, _, _):
      // The raw size is used, so that a line runs from its origin to the far end of its size.
      return CGPoint(
        x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
    case .stroke(let points, _, _):
      guard let first = points.first else { return nil }
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      let minX = xs.min() ?? first.x
      let maxX = xs.max() ?? first.x
      let minY = ys.min() ?? first.y
      let maxY = ys.max() ?? first.y
      return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
  }

  /// Maps a point on the drawn layer back to the unflipped layer. A flip is its own inverse, so
  /// the same mapping also takes unflipped geometry to the drawn position.
  func unflipped(_ point: CGPoint) -> CGPoint {
    guard isFlippedHorizontally || isFlippedVertically, let centre = flipCentre() else {
      return point
    }
    return CGPoint(
      x: isFlippedHorizontally ? 2 * centre.x - point.x : point.x,
      y: isFlippedVertically ? 2 * centre.y - point.y : point.y)
  }
}
