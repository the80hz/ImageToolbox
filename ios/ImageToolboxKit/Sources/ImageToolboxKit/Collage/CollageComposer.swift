import CoreGraphics
import Foundation

/// Draws a collage: the background, then each picture clipped to its cell with the cell's own mask, then the border.
/// It works on cells from any source: a grid, a template or a free layout.
public enum CollageComposer {

  /// Draws `pictures` into `cells` on a canvas of `width` by `height` pixels. `cells` are paths in top-left
  /// coordinates and `cells[index]` takes `pictures[index]`. Each picture fills the picture box of its cell (see
  /// `pictureBox(in:mask:)`), is turned and moved by `placements[index]` and is clipped to the outline of
  /// `masks[index]`. Nil for a placement or mask means the aspect fill with no mask. `drawOrder` lists the picture
  /// indices from the back to the front; the default is the order of the pictures. Nil when the pictures, the cells or
  /// the placements or masks do not match, or the canvas is empty.
  public static func render(
    _ pictures: [CGImage], cells: [CGPath], drawOrder: [Int]? = nil,
    placements: [CollagePhotoPlacement]? = nil, masks: [CollageMask]? = nil,
    style: CollageStyle, width: Int, height: Int
  ) -> CGImage? {
    let order = drawOrder ?? Array(pictures.indices)
    guard !pictures.isEmpty, pictures.count == cells.count,
      order.sorted() == Array(pictures.indices),
      placements == nil || placements?.count == pictures.count,
      masks == nil || masks?.count == pictures.count,
      let context = ImageGeometry.makeContext(width: width, height: height)
    else { return nil }

    context.interpolationQuality = .high
    style.background.draw(in: context, width: width, height: height)

    // The cells are laid out from the top, while the context origin is at the bottom left.
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
    for index in order {
      let cell = cells[index]
      let picture = pictures[index]
      let placement = placements?[index] ?? .identity
      let mask = masks?[index] ?? .none
      let drawn = placement.drawn(
        of: CGSize(width: picture.width, height: picture.height),
        into: pictureBox(in: cell, mask: mask))
      guard let outline = mask.outline(in: cell).copy(using: &flip) else { return nil }

      context.saveGState()
      context.addPath(outline)
      context.clip()
      // The context is upside down compared with the cells, so a turn on the screen is a turn the other way here.
      context.translateBy(x: drawn.centre.x, y: CGFloat(height) - drawn.centre.y)
      context.rotate(by: -drawn.rotation)
      context.draw(
        picture,
        in: CGRect(
          x: -drawn.size.width / 2, y: -drawn.size.height / 2,
          width: drawn.size.width, height: drawn.size.height))
      context.restoreGState()

      if style.border.isVisible {
        // A stroke is centred on the edge. Clipped to the outline, twice the width leaves the inner half.
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.addPath(outline)
        context.setStrokeColor(ImageStitcher.cgColor(style.border.color))
        context.setLineWidth(style.border.width * 2)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
      }
    }
    return context.makeImage()
  }

  /// Draws `pictures` into the cells of `template`. Nil when the template does not take that many pictures.
  public static func render(
    _ pictures: [CGImage], template: CollageTemplate, settings: CollageLayout.Settings,
    placements: [CollagePhotoPlacement]? = nil, masks: [CollageMask]? = nil,
    style: CollageStyle, width: Int, height: Int
  ) -> CGImage? {
    guard
      let cells = CollageTemplates.cells(
        template, count: pictures.count, width: Double(width), height: Double(height),
        settings: settings)
    else { return nil }
    return render(
      pictures, cells: cells, placements: placements, masks: masks, style: style, width: width,
      height: height)
  }

  /// Draws `pictures` into the cells of a free layout. Nil when the layout has a different number of cells.
  public static func render(
    _ pictures: [CGImage], layout: FreeCollageLayout, settings: CollageLayout.Settings,
    placements: [CollagePhotoPlacement]? = nil, masks: [CollageMask]? = nil,
    style: CollageStyle, width: Int, height: Int
  ) -> CGImage? {
    guard pictures.count == layout.count,
      let cells = layout.cellPaths(
        width: Double(width), height: Double(height), settings: settings)
    else { return nil }
    return render(
      pictures, cells: cells, drawOrder: layout.drawOrder, placements: placements, masks: masks,
      style: style, width: width, height: height)
  }

  /// The rectangle, in top-left coordinates, that a picture fills in `cell` under `mask`: the bounding box of the mask
  /// shape. A `CollagePhotoPlacement` is relative to this rectangle.
  public static func pictureBox(in cell: CGPath, mask: CollageMask) -> CGRect {
    mask.path(in: cell).boundingBox
  }
}
