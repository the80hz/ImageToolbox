import CoreGraphics
import Foundation

/// Sizes and places of new layers. Lengths scale with the shorter side of the picture, so a new
/// layer looks the same on a small picture and on a large one.
public enum MarkupLayerDefaults {
  /// Radius of a brush stroke: 0.8 % of the shorter side, and at least 2 pixels.
  public static func brushRadius(for canvas: CGSize) -> Double {
    max(2, Double(min(canvas.width, canvas.height)) * 0.008)
  }

  /// Width of outlines of shapes and text: 0.6 % of the shorter side, and at least 2 pixels.
  public static func outlineWidth(for canvas: CGSize) -> Double {
    max(2, Double(min(canvas.width, canvas.height)) * 0.006)
  }

  /// Text at the top-left area of the picture. The font is 6 % of the shorter side, at least 12
  /// pixels, and the block starts at 10 % of each side.
  public static func text(
    _ string: String, canvas: CGSize, colour: MarkupColour
  ) -> MarkupLayer.Content {
    let fontSize = max(12, Double(min(canvas.width, canvas.height)) * 0.06)
    return .text(
      string: string,
      fontName: "Helvetica-Bold",
      fontSize: fontSize,
      colour: colour,
      origin: CGPoint(x: canvas.width * 0.1, y: canvas.height * 0.1),
      rotation: 0)
  }

  /// A shape in the middle of the picture. A filled closed shape has a fill and no stroke. Any
  /// other shape is stroked, and a line is always stroked.
  public static func shape(
    _ kind: MarkupLayer.Content.ShapeKind, canvas: CGSize, colour: MarkupColour, filled: Bool
  ) -> MarkupLayer.Content {
    let filledShape = filled && kind.isClosed
    let size = presetSize(for: kind)
    let frame = CGRect(
      x: canvas.width * (1 - size.width) / 2, y: canvas.height * (1 - size.height) / 2,
      width: canvas.width * size.width, height: canvas.height * size.height)
    return .shape(
      kind: kind,
      frame: frame,
      strokeWidth: filledShape ? 0 : outlineWidth(for: canvas),
      strokeColour: colour,
      fillColour: filledShape ? colour : nil)
  }

  /// A sticker in the middle of the picture. It is scaled to at most 40 % of the shorter side and
  /// is never enlarged.
  public static func stickerFrame(for size: CGSize, canvas: CGSize) -> CGRect {
    centred(size, in: canvas, limit: min(canvas.width, canvas.height) * 0.4)
  }

  /// A picture in the middle of the picture. It is scaled to at most 60 % of each side and is
  /// never enlarged.
  public static func imageFrame(for size: CGSize, canvas: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
    let scale = min(1, 0.6 * canvas.width / size.width, 0.6 * canvas.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    return CGRect(
      x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
  }

  /// Decodes a picture for a layer. The longest side is limited to `maxSide` pixels, so that a
  /// large photo does not keep its full size in memory.
  public static func raster(from image: CGImage, maxSide: Int) -> RasterImage? {
    let longest = max(image.width, image.height)
    guard longest > maxSide else { return RasterImage(image) }
    let scale = Double(maxSide) / Double(longest)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard let scaled = ImageGeometry.resize(image, width: width, height: height) else {
      return RasterImage(image)
    }
    return RasterImage(scaled)
  }

  // MARK: - Helpers

  /// Fraction of the canvas that a new shape of this kind covers, as width and height. Lines have
  /// no height, so they run across the middle of the picture.
  private static func presetSize(for kind: MarkupLayer.Content.ShapeKind) -> CGSize {
    switch kind {
    case .line, .lineArrow, .doubleLineArrow: CGSize(width: 0.5, height: 0)
    case .arrow, .doubleArrow: CGSize(width: 0.5, height: 0.2)
    case .rectangle, .ellipse: CGSize(width: 0.4, height: 0.25)
    case .triangle: CGSize(width: 0.36, height: 0.32)
    case .polygon: CGSize(width: 0.36, height: 0.36)
    case .star: CGSize(width: 0.38, height: 0.38)
    }
  }

  /// `size` centred in `canvas`, scaled down to fit `limit` on its longest side, never enlarged.
  private static func centred(_ size: CGSize, in canvas: CGSize, limit: CGFloat) -> CGRect {
    guard size.width > 0, size.height > 0 else { return .zero }
    let scale = min(1, limit / max(size.width, size.height))
    let width = size.width * scale
    let height = size.height * scale
    return CGRect(
      x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
  }
}
