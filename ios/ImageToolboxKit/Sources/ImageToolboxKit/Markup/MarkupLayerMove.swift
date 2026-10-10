import CoreGraphics

extension MarkupLayer {

  /// The layer moved by `offset` picture pixels. Every point of the content moves by the same amount, so
  /// the size, rotation and style of the layer stay as they are.
  public func translated(by offset: CGPoint) -> MarkupLayer {
    var layer = self
    layer.content = content.translated(by: offset)
    return layer
  }
}

extension MarkupLayer.Content {

  func translated(by offset: CGPoint) -> MarkupLayer.Content {
    func shifted(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }
    switch self {
    case .text(
      let string, let fontName, let fontSize, let colour, let origin, let rotation, let wrapWidth,
      let style):
      return .text(
        string: string, fontName: fontName, fontSize: fontSize, colour: colour,
        origin: shifted(origin), rotation: rotation, wrapWidth: wrapWidth, style: style)
    case .sticker(let raster, let frame):
      return .sticker(raster: raster, frame: frame.offsetBy(dx: offset.x, dy: offset.y))
    case .image(let raster, let frame):
      return .image(raster: raster, frame: frame.offsetBy(dx: offset.x, dy: offset.y))
    case .shape(let kind, let frame, let strokeWidth, let strokeColour, let fillColour, let style):
      return .shape(
        kind: kind, frame: frame.offsetBy(dx: offset.x, dy: offset.y), strokeWidth: strokeWidth,
        strokeColour: strokeColour, fillColour: fillColour, style: style)
    case .stroke(let points, let brush, let colour):
      return .stroke(points: points.map(shifted), brush: brush, colour: colour)
    }
  }
}
