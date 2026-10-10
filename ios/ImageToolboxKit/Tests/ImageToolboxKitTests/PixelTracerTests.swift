import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Pixel tracing to SVG")
struct PixelTracerTests {

  /// Signed area of a loop by the shoelace formula.
  private static func signedArea(_ loop: PixelTracer.Loop) -> Int {
    var sum = 0
    for index in loop.indices {
      let a = loop[index]
      let b = loop[(index + 1) % loop.count]
      sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
  }

  @Test("a filled square traces to one loop of four corners")
  func square() {
    let loops = PixelTracer.contours(of: [true, true, true, true], width: 2, height: 2)
    #expect(loops.count == 1)
    #expect(loops[0].count == 4)
    #expect(abs(Self.signedArea(loops[0])) == 4)
  }

  @Test("a frame with a hole traces to two loops of opposite orientation")
  func frameWithHole() {
    var mask = [Bool](repeating: true, count: 16)
    for y in 1...2 {
      for x in 1...2 {
        mask[y * 4 + x] = false
      }
    }
    let loops = PixelTracer.contours(of: mask, width: 4, height: 4)
    #expect(loops.count == 2)
    // Outer area 16 minus hole area 4. Opposite orientations make the signed sum 12.
    #expect(abs(loops.map(Self.signedArea).reduce(0, +)) == 12)
  }

  @Test("a solid picture becomes one red path in the SVG")
  func solidSVG() {
    let raster = TestImages.solid(RGBA(red: 255, green: 0, blue: 0), width: 4, height: 4)
    let svg = PixelTracer.svg(for: try! #require(RasterImage(raster)), colours: 1)
    #expect(svg.contains("fill=\"#ff0000\""))
    #expect(svg.contains("fill-rule=\"evenodd\""))
    #expect(svg.contains("viewBox=\"0 0 4 4\""))
  }

  @Test("two colours give two paths, one for each colour")
  func twoColours() throws {
    let halves = TestImages.image(width: 8, height: 4) { x, _ in
      x < 4 ? RGBA(red: 255, green: 0, blue: 0) : RGBA(red: 0, green: 0, blue: 255)
    }
    let svg = PixelTracer.svg(for: try #require(RasterImage(halves)), colours: 2)
    #expect(svg.contains("#ff0000"))
    #expect(svg.contains("#0000ff"))
    #expect(svg.components(separatedBy: "<path").count == 3)
  }
}
