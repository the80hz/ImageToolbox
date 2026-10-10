import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Draw line styles: dashes, dot-dashes and zigzags")
struct DrawLineStyleTests {

  private let straight = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]

  @Test("solid keeps the polyline whole")
  func solidIsWhole() {
    #expect(LineStyle.solid.pieces(of: straight, diameter: 4) == [straight])
  }

  @Test("dashes are twice the width long with five widths between them")
  func dashesFollowRatios() throws {
    // Diameter 4: on 8, off 20, so the dashes start at 0, 28, 56 and 84.
    let pieces = LineStyle.dashed.pieces(of: straight, diameter: 4)
    #expect(pieces.count == 4)
    let second = try #require(pieces.dropFirst().first)
    #expect(abs(second.first!.x - 28) < 1e-9)
    #expect(abs(second.last!.x - 36) < 1e-9)
    #expect(abs(pieces[3].first!.x - 84) < 1e-9)
  }

  @Test("a dot-dash alternates a long dash, a gap, a dot and a gap")
  func dotDashPattern() throws {
    // Diameter 4: dash 16, gap 8, dot 1, gap 8, so the period is 33.
    let pieces = LineStyle.dotDashed.pieces(of: straight, diameter: 4)
    #expect(pieces.count == 7)
    #expect(abs(pieces[0].last!.x - 16) < 1e-9)
    let dot = try #require(pieces.dropFirst().first)
    #expect(abs(dot.first!.x - 24) < 1e-9)
    #expect(abs(dot.last!.x - 25) < 1e-9)
  }

  @Test("a zigzag offsets its samples by half a width, alternating with the line")
  func zigzagOffsets() throws {
    // Diameter 4: a sample every 2 units, alternately on the line and 2 units off it.
    let line = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)]
    let pieces = LineStyle.zigZag.pieces(of: line, diameter: 4)
    let zig = try #require(pieces.first)
    #expect(abs(zig[1].x - 2) < 1e-9)
    #expect(abs(zig[1].y - 2) < 1e-9)
    #expect(abs(zig[2].x - 4) < 1e-9)
    #expect(abs(zig[2].y) < 1e-9)
    #expect(zig.last == CGPoint(x: 20, y: 0))
  }

  @Test("pieces follow a bent polyline around its corner")
  func dashesFollowCorner() {
    let bent = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
    let pieces = LineStyle.dashed.pieces(of: bent, diameter: 1)
    // On 2 and off 5, so the period is 7. The second dash starts 7 units along the first leg. The
    // third starts 4 units up the second leg, because the gap bends round the corner.
    let second = pieces[1]
    #expect(abs(second.first!.x - 7) < 1e-9)
    #expect(abs(second.first!.y) < 1e-9)
    #expect(abs(second.last!.x - 9) < 1e-9)
    let third = pieces[2]
    #expect(abs(third.first!.x - 10) < 1e-9)
    #expect(abs(third.first!.y - 4) < 1e-9)
  }

  @Test("a stroke with a dashed style covers fewer pixels than a solid one")
  func dashedStrokeCoversLess() {
    var solid = BrushCanvas(width: 60, height: 8)
    var dashed = BrushCanvas(width: 60, height: 8)
    let brush = Brush(radius: 1, hardness: 1)
    solid.stroke(through: straight, brush: brush)
    dashed.stroke(through: straight, brush: brush, style: .dashed)
    #expect(dashed.coverage.reduce(0, +) < solid.coverage.reduce(0, +))
  }
}
