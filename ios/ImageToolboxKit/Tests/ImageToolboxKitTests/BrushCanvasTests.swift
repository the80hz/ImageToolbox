import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Brush strokes on a coverage canvas")
struct BrushCanvasTests {

  @Test("a stroke covers the pixels on its line and not the ones far away")
  func straightStroke() {
    var canvas = BrushCanvas(width: 40, height: 20)
    canvas.stroke(
      from: CGPoint(x: 5, y: 10), to: CGPoint(x: 35, y: 10), brush: Brush(radius: 2, hardness: 1))
    let onLine = canvas.coverage[10 * 40 + 20]
    let far = canvas.coverage[2 * 40 + 20]
    #expect(onLine > 0.99)
    #expect(far == 0)
  }

  @Test("a soft brush has partial coverage at its edge, and a hard brush does not")
  func hardnessEdge() {
    let soft = Brush(radius: 10, hardness: 0, opacity: 1)
    let hard = Brush(radius: 10, hardness: 1, opacity: 1)
    #expect(soft.coverage(atDistance: 5) > 0 && soft.coverage(atDistance: 5) < 1)
    #expect(hard.coverage(atDistance: 9.9) == 1)
    #expect(hard.coverage(atDistance: 10) == 0)
  }

  @Test("repeated stamps build up to full coverage and never exceed 1")
  func overCompositing() {
    var canvas = BrushCanvas(width: 10, height: 10)
    for _ in 0..<20 {
      canvas.stroke(
        from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5),
        brush: Brush(radius: 3, hardness: 1, opacity: 0.5))
    }
    let centre = canvas.coverage[5 * 10 + 5]
    #expect(centre > 0.99 && centre <= 1)
  }

  @Test("the coloured picture carries the coverage as alpha")
  func colouredRaster() {
    var canvas = BrushCanvas(width: 4, height: 4)
    canvas.stroke(
      from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 0), brush: Brush(radius: 2, hardness: 1))
    let raster = canvas.raster(red: 200, green: 100, blue: 50)
    #expect(raster.pixel(x: 0, y: 0).alpha == 255)
    #expect(raster.pixel(x: 3, y: 3).alpha == 0)
  }

  @Test("erasing removes the coverage under the brush")
  func erasing() {
    var canvas = BrushCanvas(width: 20, height: 20)
    canvas.stroke(
      from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10), brush: Brush(radius: 4, hardness: 1))
    canvas.erase(at: CGPoint(x: 10, y: 10), brush: Brush(radius: 4, hardness: 1))
    #expect(canvas.coverage[10 * 20 + 10] < 0.01)
  }
}
