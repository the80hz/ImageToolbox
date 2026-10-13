import CoreGraphics
import Foundation

/// Grid collage layouts: the pictures fill the cells of a grid in reading order, each cell filled with its
/// picture cropped to the cell (aspect fill), with a gap between cells and the outer margin.
public enum CollageLayout {

  public struct Settings: Equatable, Sendable {
    /// Pixels between neighbouring cells.
    public var gap: Double
    /// Pixels between the outer cells and the edge of the collage.
    public var margin: Double
    /// Background colour, components 0...1.
    public var background: (red: Double, green: Double, blue: Double)

    public init(
      gap: Double = 8, margin: Double = 8, background: (Double, Double, Double) = (1, 1, 1)
    ) {
      self.gap = max(gap, 0)
      self.margin = max(margin, 0)
      self.background = (background.0, background.1, background.2)
    }

    public static func == (lhs: Settings, rhs: Settings) -> Bool {
      lhs.gap == rhs.gap && lhs.margin == rhs.margin && lhs.background.0 == rhs.background.0
        && lhs.background.1 == rhs.background.1 && lhs.background.2 == rhs.background.2
    }
  }

  /// The number of columns and rows that hold `count` pictures: as square as possible, with the extra
  /// cells in the last row. Nil for no pictures or more than 36.
  public static func grid(for count: Int) -> (columns: Int, rows: Int)? {
    guard count >= 1, count <= 36 else { return nil }
    let columns = Int(Double(count).squareRoot().rounded(.up))
    let rows = (count + columns - 1) / columns
    return (columns, rows)
  }

  /// The rectangle of each cell for `count` pictures in a collage of the given size, in reading order.
  public static func cells(count: Int, width: Double, height: Double, settings: Settings)
    -> [CGRect]?
  {
    guard let (columns, rows) = grid(for: count) else { return nil }
    let usableWidth = width - 2 * settings.margin - Double(columns - 1) * settings.gap
    let usableHeight = height - 2 * settings.margin - Double(rows - 1) * settings.gap
    guard usableWidth > 0, usableHeight > 0 else { return nil }
    let cellWidth = usableWidth / Double(columns)
    let cellHeight = usableHeight / Double(rows)
    var result: [CGRect] = []
    for index in 0..<count {
      let column = index % columns
      let row = index / columns
      result.append(
        CGRect(
          x: settings.margin + Double(column) * (cellWidth + settings.gap),
          y: settings.margin + Double(row) * (cellHeight + settings.gap),
          width: cellWidth, height: cellHeight))
    }
    return result
  }

  /// Draws the pictures into a collage of `width` by `height` pixels. Each picture is cropped to fill its cell.
  public static func render(
    _ pictures: [CGImage], width: Int, height: Int, settings: Settings
  ) -> CGImage? {
    guard
      let cells = cells(
        count: pictures.count, width: Double(width), height: Double(height), settings: settings),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(
      red: settings.background.red, green: settings.background.green,
      blue: settings.background.blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (picture, cell) in zip(pictures, cells) {
      // The context origin is at the bottom left, while the cells are laid out from the top.
      let target = CGRect(
        x: cell.minX, y: Double(height) - cell.maxY, width: cell.width, height: cell.height)
      context.saveGState()
      context.clip(to: target)
      context.draw(
        picture,
        in: aspectFill(
          width: Double(picture.width), height: Double(picture.height), into: target))
      context.restoreGState()
    }
    return context.makeImage()
  }

  /// The rectangle that makes a picture of `width` by `height` cover `target`, centred on it.
  static func aspectFill(width: Double, height: Double, into target: CGRect) -> CGRect {
    let scale = max(target.width / width, target.height / height)
    let drawWidth = width * scale
    let drawHeight = height * scale
    return CGRect(
      x: target.midX - drawWidth / 2, y: target.midY - drawHeight / 2,
      width: drawWidth, height: drawHeight)
  }
}
