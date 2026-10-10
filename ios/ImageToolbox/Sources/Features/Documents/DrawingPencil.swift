import CoreGraphics
import PencilKit

/// Turns PencilKit strokes into the alpha coverage that the drawing tool keeps.
enum DrawingPencil {

  /// Rasterises PencilKit strokes in drawing units into the alpha coverage of their bounding box.
  /// Returns nil when the strokes leave no ink on the canvas.
  static func patch(from drawing: PKDrawing) -> DrawingToolModel.PencilPatch? {
    let side = DrawingToolModel.canvasSide
    guard
      !drawing.strokes.isEmpty,
      let image = drawing.image(
        from: CGRect(x: 0, y: 0, width: side, height: side), scale: 1
      ).cgImage
    else { return nil }

    // Draw into a bitmap of exactly the canvas size, so that the pixel layout does not depend on
    // the size of the image that PencilKit returns.
    let rowBytes = side * 4
    var pixels = [UInt8](repeating: 0, count: rowBytes * side)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
          bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard drawn else { return nil }

    var left = side
    var top = side
    var right = -1
    var bottom = -1
    for y in 0..<side {
      for x in 0..<side where pixels[(y * side + x) * 4 + 3] != 0 {
        left = min(left, x)
        right = max(right, x)
        top = min(top, y)
        bottom = max(bottom, y)
      }
    }
    guard right >= left, bottom >= top else { return nil }

    let width = right - left + 1
    let height = bottom - top + 1
    var coverage: [UInt8] = []
    coverage.reserveCapacity(width * height)
    for y in top...bottom {
      for x in left...right {
        coverage.append(pixels[(y * side + x) * 4 + 3])
      }
    }
    return DrawingToolModel.PencilPatch(
      x: left, y: top, width: width, height: height, coverage: coverage)
  }
}
