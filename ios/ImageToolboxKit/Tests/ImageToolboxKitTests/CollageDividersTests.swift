import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage dividers")
struct CollageDividersTests {

  /// Two cells side by side, divided at x = 0.5.
  private static let halves: [[CGPoint]] = [
    [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 1)],
    [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 1)],
  ]

  /// Columns between the given boundaries, each a rectangle the height of the square.
  private static func columns(_ boundaries: [Double]) -> [[CGPoint]] {
    zip(boundaries, boundaries.dropFirst()).map { left, right in
      [
        CGPoint(x: left, y: 0), CGPoint(x: right, y: 0), CGPoint(x: right, y: 1),
        CGPoint(x: left, y: 1),
      ]
    }
  }

  /// The area of a polygon, which is positive for both windings.
  private static func area(_ polygon: [CGPoint]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      sum += Double(a.x * b.y - b.x * a.y)
    }
    return abs(sum) / 2
  }

  @Test("two cells side by side share one vertical divider across the whole square")
  func oneVerticalDivider() {
    #expect(
      CollageDividers.dividers(of: Self.halves)
        == [CollageDivider(orientation: .vertical, position: 0.5, span: 0...1)])
  }

  @Test("a grid of four cells has one vertical and one horizontal divider")
  func gridDividers() {
    let cells: [[CGPoint]] = [
      [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0.5)],
      [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 0.5)],
      [CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 1)],
      [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0.5), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 1)],
    ]
    #expect(
      CollageDividers.dividers(of: cells)
        == [
          CollageDivider(orientation: .vertical, position: 0.5, span: 0...1),
          CollageDivider(orientation: .horizontal, position: 0.5, span: 0...1),
        ])
  }

  @Test("a single cell has no dividers, because its sides are all on the edge")
  func singleCell() {
    let square = [
      CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
    ]
    #expect(CollageDividers.dividers(of: [square]).isEmpty)
  }

  @Test("moving a divider moves the sides of both cells that it divides")
  func movingKeepsCellsTogether() throws {
    let divider = try #require(CollageDividers.dividers(of: Self.halves).first)
    let moved = try #require(
      CollageDividers.moving(divider, to: 0.3, in: Self.halves, minimumSize: 0.05))
    #expect(moved[0].map(\.x) == [0, 0.3, 0.3, 0])
    #expect(moved[1].map(\.x) == [0.3, 1, 1, 0.3])
    #expect(moved[0].map(\.y) == [0, 0, 1, 1])
  }

  @Test("a divider cannot move past the edge of the square or make a cell too narrow")
  func movingIsClamped() throws {
    let divider = try #require(CollageDividers.dividers(of: Self.halves).first)
    let left = try #require(
      CollageDividers.moving(divider, to: -5, in: Self.halves, minimumSize: 0.05))
    #expect(abs(left[0][1].x - 0.05) < 1e-9)
    let right = try #require(
      CollageDividers.moving(divider, to: 5, in: Self.halves, minimumSize: 0.05))
    #expect(abs(right[1][0].x - 0.95) < 1e-9)
  }

  @Test("a divider stops at the next divider beside it")
  func movingStopsAtNeighbour() throws {
    let cells = Self.columns([0, 1.0 / 3, 2.0 / 3, 1])
    let first = try #require(CollageDividers.dividers(of: cells).first)
    #expect(abs(first.position - 1.0 / 3) < 1e-9)
    let moved = try #require(CollageDividers.moving(first, to: 0.9, in: cells, minimumSize: 0.05))
    #expect(abs(moved[0][1].x - (2.0 / 3 - 0.05)) < 1e-9)
    #expect(abs(moved[1][0].x - (2.0 / 3 - 0.05)) < 1e-9)
    #expect(abs(moved[2][0].x - 2.0 / 3) < 1e-9)
  }

  @Test("a divider that is not in the cells does not move")
  func missingDividerDoesNotMove() {
    let stray = CollageDivider(orientation: .vertical, position: 0.2, span: 0...1)
    #expect(CollageDividers.moving(stray, to: 0.3, in: Self.halves) == nil)
  }

  @Test("every divider of every template moves without changing the area of the cells")
  func templatesStayWhole() throws {
    var checked = 0
    for count in 2...9 {
      for template in CollageTemplate.allCases {
        guard let cells = CollageTemplates.unitCells(template, count: count) else { continue }
        let total = cells.reduce(0) { $0 + Self.area($1) }
        for divider in CollageDividers.dividers(of: cells) {
          for target in [divider.position - 0.1, divider.position + 0.1] {
            guard let moved = CollageDividers.moving(divider, to: target, in: cells) else {
              continue
            }
            checked += 1
            let movedTotal = moved.reduce(0) { $0 + Self.area($1) }
            #expect(abs(movedTotal - total) < 1e-6, "\(template) with \(count) pictures")
            #expect(moved.allSatisfy { Self.area($0) > 1e-4 })
          }
        }
      }
    }
    #expect(checked > 0)
  }
}
