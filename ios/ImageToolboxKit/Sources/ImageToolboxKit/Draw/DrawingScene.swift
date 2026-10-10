import CoreGraphics
import Foundation

/// Replays drawing edits, in order, onto a transparent square picture.
///
/// Pen strokes, shapes and spray are painted into one coverage canvas, which is put over the
/// picture before the next edit that needs the pixels as they are. Every other kind of edit flushes
/// that canvas first, then works on the picture itself. So an eraser removes only what was drawn
/// before it, and a later pen stroke is not removed by it.
public enum DrawingScene {
  /// A colour with 0 to 255 channels.
  public typealias Colour = (red: UInt8, green: UInt8, blue: UInt8)

  /// The picture after every edit, as a premultiplied `side` by `side` raster.
  public static func render(_ edits: [DrawingEdit], side: Int, colour: Colour) -> RasterImage {
    var picture = RasterImage(
      width: side, height: side, pixels: [UInt8](repeating: 0, count: side * side * 4))
    var paint = BrushCanvas(width: side, height: side)
    var hasPaint = false

    func flushPaint() {
      guard hasPaint else { return }
      let painted = paint.raster(red: colour.red, green: colour.green, blue: colour.blue)
      picture = composite(painted, over: picture)
      paint = BrushCanvas(width: side, height: side)
      hasPaint = false
    }

    for edit in edits {
      switch edit {
      case .stroke(let stroke):
        if stroke.kind == .pen {
          paint.stroke(through: stroke.points, brush: stroke.brush, style: stroke.style)
          hasPaint = true
        } else {
          flushPaint()
          var layer = BrushCanvas(width: side, height: side)
          layer.stroke(through: stroke.points, brush: stroke.brush, style: stroke.style)
          picture = apply(stroke.kind, coverage: layer.coverage, to: picture, colour: colour)
        }

      case .shape(let shape):
        ShapeRenderer.draw(
          shape.kind, from: shape.start, to: shape.end, filled: shape.filled, brush: shape.brush,
          options: shape.options, onto: &paint)
        hasPaint = true

      case .spray(let spray):
        Spray.draw(
          points: spray.points, radius: spray.radius, density: spray.density,
          dotSize: spray.dotSize, square: spray.square, seed: spray.seed, onto: &paint)
        hasPaint = true

      case .flood(let point, let tolerance):
        flushPaint()
        picture = FloodFill.fill(picture, at: point, tolerance: tolerance, colour: colour)

      case .lasso(let polygon, let action):
        flushPaint()
        picture = applyLasso(polygon, action: action, to: picture, colour: colour)

      case .heal(let centres, let radius):
        flushPaint()
        for centre in centres {
          picture = SpotHealing.heal(picture, at: centre, radius: radius)
        }

      case .warp(let warp):
        flushPaint()
        for sample in warp.samples {
          picture = WarpBrush.warp(
            picture, at: sample.centre, direction: sample.direction, radius: warp.radius,
            strength: warp.strength, hardness: warp.hardness, mode: warp.mode)
        }

      case .pencil(let patch):
        flushPaint()
        picture = composite(patch.raster(colour: colour), at: patch.x, y: patch.y, over: picture)
      }
    }
    flushPaint()
    return picture
  }

  // MARK: - Helpers

  /// Applies a non-pen stroke to the picture under its coverage.
  private static func apply(
    _ kind: DrawingPaintKind, coverage: [Double], to picture: RasterImage, colour: Colour
  ) -> RasterImage {
    switch kind {
    case .pen:
      return RegionEffects.paint(picture, coverage: coverage, colour: colour, opacity: 1)
    case .highlighter:
      return RegionEffects.paint(
        picture, coverage: coverage, colour: colour, opacity: RegionEffects.highlighterOpacity)
    case .neon:
      return RegionEffects.neon(picture, coverage: coverage, colour: colour)
    case .eraser:
      return RegionEffects.erase(picture, coverage: coverage)
    case .blur:
      return RegionEffects.blur(
        picture, coverage: coverage, radius: RegionEffects.privacyBlurRadius)
    case .pixelate:
      return RegionEffects.pixelate(
        picture, coverage: coverage, block: RegionEffects.pixelBlock,
        preBlur: RegionEffects.privacyBlurRadius)
    }
  }

  /// Puts `top` over `bottom` with the top-left corner of `top` at (`x`, `y`). Both hold
  /// premultiplied RGBA, so the "over" rule is `top + bottom * (1 - alpha)` for each channel. The
  /// whole of `top` must lie inside `bottom`.
  private static func composite(
    _ top: RasterImage, at x: Int = 0, y: Int = 0, over bottom: RasterImage
  ) -> RasterImage {
    var pixels = bottom.pixels
    for row in 0..<top.height {
      for column in 0..<top.width {
        let source = (row * top.width + column) * 4
        let target = ((y + row) * bottom.width + x + column) * 4
        let keep = 255 - Int(top.pixels[source + 3])
        for channel in 0..<4 {
          let value =
            Int(top.pixels[source + channel]) + (Int(pixels[target + channel]) * keep + 127) / 255
          pixels[target + channel] = UInt8(min(value, 255))
        }
      }
    }
    return RasterImage(width: bottom.width, height: bottom.height, pixels: pixels)
  }

  /// Clears or fills the pixels inside the polygon. The fill is solid: unlike `LassoMask.fill`, it
  /// also paints the transparent pixels.
  private static func applyLasso(
    _ polygon: [CGPoint], action: DrawingLassoAction, to picture: RasterImage, colour: Colour
  ) -> RasterImage {
    let inside = LassoMask(polygon: polygon).mask(width: picture.width, height: picture.height)
    let replacement: [UInt8] =
      switch action {
      case .clear: [0, 0, 0, 0]
      case .fill: [colour.red, colour.green, colour.blue, 255]
      }
    var pixels = picture.pixels
    for index in inside.indices where inside[index] {
      let base = index * 4
      for channel in 0..<4 {
        pixels[base + channel] = replacement[channel]
      }
    }
    return RasterImage(width: picture.width, height: picture.height, pixels: pixels)
  }
}
