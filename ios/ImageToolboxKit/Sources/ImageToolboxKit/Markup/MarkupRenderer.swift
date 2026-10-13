import CoreGraphics
import CoreText
import Foundation

/// Draws a `MarkupDocument` over a base picture with Core Graphics.
///
/// All layer geometry is in top-left pixel coordinates (see `MarkupDocument`). Every drawing call
/// converts it to Core Graphics coordinates, where y grows upwards, so no context flip is needed.
public enum MarkupRenderer {

  /// Draws `base`, then each visible layer from bottom to top. A layer's `opacity` multiplies the
  /// alpha of its content, and its blend mode combines it with what is below. The result has the
  /// size of `base`. It is nil when the bitmap context or the final image cannot be created.
  public static func render(base: CGImage, document: MarkupDocument) -> CGImage? {
    let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
    guard let context = ImageGeometry.makeContext(width: base.width, height: base.height) else {
      return nil
    }
    context.draw(base, in: bounds)

    for layer in document.layers where layer.isVisible {
      let opacity = min(max(layer.opacity, 0), 1)
      guard opacity > 0 else { continue }
      context.saveGState()
      context.setAlpha(CGFloat(opacity))
      context.setBlendMode(layer.blendMode.cgBlendMode)
      applyFlips(of: layer, in: context, canvasHeight: bounds.height)
      applyShadow(of: layer, in: context)
      drawContent(of: layer, in: context, bounds: bounds)
      context.restoreGState()
    }
    return context.makeImage()
  }

  // MARK: - Content

  private static func drawContent(of layer: MarkupLayer, in context: CGContext, bounds: CGRect) {
    let height = bounds.height
    switch layer.content {
    case .text(_, _, _, let colour, let origin, let rotation, _, let style):
      guard let layout = layer.textLayout(colour: colour.cgColor) else { return }
      drawText(
        layout, origin: origin, rotation: CGFloat(rotation), style: style,
        cornerRadius: cornerRadius(for: layer, width: layout.blockWidth, height: layout.height),
        in: context, canvasHeight: height)

    case .sticker(let raster, let frame), .image(let raster, let frame):
      guard let image = raster.toCGImage() else { return }
      let rect = flipped(frame.standardized, canvasHeight: height)
      context.saveGState()
      let radius = cornerRadius(for: layer, width: rect.width, height: rect.height)
      if radius > 0 {
        context.addPath(
          CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
      }
      context.draw(image, in: rect)
      context.restoreGState()

    case .shape(let kind, let frame, let strokeWidth, let strokeColour, let fillColour, let style):
      drawShape(
        kind: kind, frame: frame, strokeWidth: strokeWidth, strokeColour: strokeColour,
        fillColour: fillColour, style: style, in: context, canvasHeight: height)

    case .stroke(let points, let brush, let colour):
      drawStroke(points, brush: brush, colour: colour, bounds: bounds, in: context)
    }
  }

  /// Draws the lines of a text layer, and its background behind them. The text is drawn in a space
  /// whose origin is the top-left corner of the block, with y growing upwards, so lines go down at
  /// negative y.
  private static func drawText(
    _ layout: MarkupTextLayout, origin: CGPoint, rotation: CGFloat, style: MarkupTextStyle,
    cornerRadius: CGFloat, in context: CGContext, canvasHeight: CGFloat
  ) {
    let anchor = flipped(origin, canvasHeight: canvasHeight)

    context.saveGState()
    // The anchor is the top-left corner of the text block. A clockwise turn on screen is a
    // negative angle in Core Graphics, because y is flipped.
    context.translateBy(x: anchor.x, y: anchor.y)
    context.rotate(by: -rotation)
    context.textMatrix = .identity
    if let background = style.backgroundColour {
      let block = CGRect(x: 0, y: -layout.height, width: layout.blockWidth, height: layout.height)
      context.setFillColor(background.cgColor)
      context.addPath(
        CGPath(
          roundedRect: block, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
          transform: nil))
      context.fillPath()
    }
    for (index, line) in layout.lines.enumerated() {
      // Lines go down the screen, which is negative y in this space.
      context.textPosition = CGPoint(
        x: layout.offset(ofLine: index),
        y: -(layout.ascent + CGFloat(index) * layout.lineHeight))
      CTLineDraw(line, context)
    }
    context.restoreGState()
  }

  private static func drawShape(
    kind: MarkupLayer.Content.ShapeKind,
    frame: CGRect,
    strokeWidth: Double,
    strokeColour: MarkupColour,
    fillColour: MarkupColour?,
    style: MarkupShapeStyle,
    in context: CGContext,
    canvasHeight: CGFloat
  ) {
    let path = MarkupShapeGeometry.path(
      kind: kind, frame: frame, strokeWidth: strokeWidth, style: style)
    // The shape is built in top-left coordinates, so it is flipped to Core Graphics space here.
    var toCoreGraphics = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight)
    guard let drawn = path.copy(using: &toCoreGraphics) else { return }

    if let fillColour, kind.isClosed {
      if let gradient = style.fillGradient {
        fillGradient(gradient, path: drawn, frame: frame, in: context, canvasHeight: canvasHeight)
      } else {
        context.setFillColor(fillColour.cgColor)
        context.addPath(drawn)
        context.fillPath()
      }
    }
    if strokeWidth > 0 {
      context.setStrokeColor(strokeColour.cgColor)
      context.setLineWidth(CGFloat(strokeWidth))
      context.setLineJoin(.round)
      context.addPath(drawn)
      context.strokePath()
    }
  }

  /// Stamps the brush on a canvas that covers only the stroke's area, then draws that canvas.
  /// A canvas for the whole picture would cost width * height * 8 bytes for every stroke.
  private static func drawStroke(
    _ points: [CGPoint], brush: Brush, colour: MarkupColour, bounds: CGRect,
    in context: CGContext
  ) {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
    else { return }

    // Stamps reach `radius` past the path. The extra pixel covers rounding at the edges.
    let margin = CGFloat(brush.radius) + 1
    let area = CGRect(
      x: minX - margin, y: minY - margin,
      width: maxX - minX + 2 * margin, height: maxY - minY + 2 * margin
    )
    .integral.intersection(bounds)
    guard !area.isNull, area.width >= 1, area.height >= 1 else { return }

    // Whole-pixel origin, so canvas pixels line up with image pixels. Points outside the area
    // are still stamped, and the canvas only keeps the pixels inside it.
    var canvas = BrushCanvas(width: Int(area.width), height: Int(area.height))
    let local = points.map { CGPoint(x: $0.x - area.minX, y: $0.y - area.minY) }
    canvas.stroke(through: local, brush: brush)

    let bytes = colour.bytes
    let raster = canvas.raster(red: bytes.red, green: bytes.green, blue: bytes.blue)
    guard let image = raster.toCGImage() else { return }
    context.draw(image, in: flipped(area, canvasHeight: bounds.height))
  }

  // MARK: - Flips and corners

  /// Mirrors the layer around its flip centre. Core Graphics has y growing upwards, so the centre
  /// is converted to that space before the mirror is applied.
  private static func applyFlips(
    of layer: MarkupLayer, in context: CGContext, canvasHeight: CGFloat
  ) {
    guard layer.isFlippedHorizontally || layer.isFlippedVertically,
      let centre = layer.flipCentre()
    else { return }
    let mirror = flipped(centre, canvasHeight: canvasHeight)
    context.translateBy(x: mirror.x, y: mirror.y)
    context.scaleBy(
      x: layer.isFlippedHorizontally ? -1 : 1, y: layer.isFlippedVertically ? -1 : 1)
    context.translateBy(x: -mirror.x, y: -mirror.y)
  }

  /// Sets the drop shadow of the layer on the context. Core Graphics measures the offset on the
  /// screen, so the flips above do not mirror it. Its y is negated, because Core Graphics has y
  /// growing upwards. The values are clamped to the ranges that `MarkupShadow` documents. The
  /// alpha of the shadow colour is its own opacity; the layer's opacity is applied on top of it.
  private static func applyShadow(of layer: MarkupLayer, in context: CGContext) {
    guard let shadow = layer.shadow else { return }
    let alpha = CGFloat(min(max(shadow.alpha, 0), 1))
    context.setShadow(
      offset: CGSize(
        width: min(max(shadow.offsetX, -64), 64), height: -min(max(shadow.offsetY, -64), 64)),
      blur: CGFloat(min(max(shadow.blurRadius, 0), 100)),
      color: shadow.colour.cgColor.copy(alpha: alpha) ?? shadow.colour.cgColor)
  }

  /// Fills `path` with the gradient. The gradient spans `frame` along its angle, and the colours
  /// continue past both ends of the span. The fill is clipped to the path, so only the shape shows.
  private static func fillGradient(
    _ gradient: MarkupGradient, path: CGPath, frame: CGRect, in context: CGContext,
    canvasHeight: CGFloat
  ) {
    let colours = [gradient.startColour.cgColor, gradient.endColour.cgColor] as CFArray
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let shading = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1])
    else { return }

    let rect = frame.standardized
    let radians = CGFloat(gradient.angleDegrees * .pi / 180)
    // A unit vector in top-left coordinates, where a positive angle turns clockwise on screen.
    let dx = cos(radians)
    let dy = sin(radians)
    // Half the length of the frame's projection onto the direction, so the span covers the frame.
    let half = (abs(dx) * rect.width + abs(dy) * rect.height) / 2
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let start = flipped(
      CGPoint(x: centre.x - dx * half, y: centre.y - dy * half), canvasHeight: canvasHeight)
    let end = flipped(
      CGPoint(x: centre.x + dx * half, y: centre.y + dy * half), canvasHeight: canvasHeight)

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
      shading, start: start, end: end,
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
  }

  /// The corner radius of a picture or text background: the layer's percentage of the shorter
  /// side. Zero for layers that do not round their corners.
  private static func cornerRadius(for layer: MarkupLayer, width: CGFloat, height: CGFloat)
    -> CGFloat
  {
    guard layer.supportsCornerRadius else { return 0 }
    return min(width, height) * CGFloat(layer.cornerRadiusPercent) / 100
  }

  // MARK: - Coordinates

  /// Converts a top-left point to Core Graphics coordinates.
  private static func flipped(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: canvasHeight - point.y)
  }

  /// Converts a top-left rectangle to Core Graphics coordinates. The rectangle must be standardized.
  private static func flipped(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
  }
}
