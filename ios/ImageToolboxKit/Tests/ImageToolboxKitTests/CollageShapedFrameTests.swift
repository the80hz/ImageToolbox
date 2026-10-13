import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage shaped frame layouts")
struct CollageShapedFrameTests {

  /// The eight layouts of the Android library that cut a figure out of their cells, with the pictures they take.
  private static let layouts: [(id: String, count: Int)] = [
    ("collage_2_7", 2), ("collage_3_1", 3), ("collage_3_4", 3), ("collage_3_6", 3),
    ("collage_3_8", 3), ("collage_3_13", 3), ("collage_5_5", 5), ("collage_5_7", 5),
  ]

  /// One colour for each picture of a layout.
  private static let colours: [RGBA] = [
    RGBA(red: 255, green: 0, blue: 0), RGBA(red: 0, green: 255, blue: 0),
    RGBA(red: 0, green: 0, blue: 255), RGBA(red: 255, green: 255, blue: 0),
    RGBA(red: 255, green: 0, blue: 255),
  ]

  private static let plain = CollageLayout.Settings(gap: 0, margin: 0, background: (0, 0, 0))
  private static let spaced = CollageLayout.Settings(gap: 4, margin: 8, background: (0, 0, 0))

  /// Points of the 128 pixel canvas, as column, row and the index of the picture that must show there, for each
  /// layout. The points lie well away from the cell edges, so the test does not depend on pixel rounding.
  private static let probes: [(id: String, points: [(x: Int, y: Int, picture: Int)])] = [
    ("collage_2_7", [(10, 10, 0), (100, 100, 1), (70, 100, 0), (64, 64, 0)]),
    (
      "collage_3_1",
      [(20, 20, 0), (20, 108, 1), (64, 20, 0), (64, 108, 1), (64, 64, 2), (64, 40, 2)]
    ),
    ("collage_3_4", [(64, 64, 2), (64, 40, 0), (64, 110, 1), (20, 20, 0), (20, 108, 1)]),
    ("collage_3_6", [(30, 64, 0), (100, 64, 1), (50, 64, 2), (64, 50, 2)]),
    ("collage_3_8", [(20, 64, 0), (100, 64, 1), (64, 64, 2), (50, 64, 2)]),
    ("collage_3_13", [(20, 64, 0), (108, 64, 1), (64, 64, 2), (40, 40, 2), (20, 40, 0)]),
    (
      "collage_5_5",
      [
        (10, 10, 0), (118, 10, 1), (118, 118, 2), (10, 118, 3), (64, 64, 4),
        (48, 30, 0),
      ]
    ),
    (
      "collage_5_7",
      [
        (10, 10, 0), (118, 10, 1), (118, 118, 2), (10, 118, 3), (64, 64, 4),
        (50, 50, 4), (30, 30, 0),
      ]
    ),
  ]

  private static func pictures(_ count: Int) -> [CGImage] {
    colours.prefix(count).map { TestImages.solid($0, width: 10, height: 10) }
  }

  /// Shoelace area of a polygon, signed by the direction it runs.
  private func signedArea(_ points: [CGPoint]) -> Double {
    var sum = 0.0
    for index in points.indices {
      let current = points[index]
      let next = points[(index + 1) % points.count]
      sum += Double(current.x * next.y - next.x * current.y)
    }
    return sum / 2
  }

  /// The area of a path with its closed subpaths: the signed areas are summed, so a cut-out that runs the other way
  /// round is taken away from the outline.
  private func area(of path: CGPath) -> Double {
    var subpaths: [[CGPoint]] = []
    path.applyWithBlock { element in
      switch element.pointee.type {
      case .moveToPoint:
        subpaths.append([element.pointee.points[0]])
      case .addLineToPoint:
        subpaths[subpaths.count - 1].append(element.pointee.points[0])
      default:
        break
      }
    }
    return abs(subpaths.reduce(0) { $0 + signedArea($1) })
  }

  /// How many of the paths cover each pixel of a `size` by `size` canvas, by the nonzero rule, with each pixel
  /// tested at an off-centre point. Pixel centres lie exactly on the heart's 45-degree tip edges, where the
  /// containment test is ambiguous, so the sample point is shifted off that grid, as in CollageFrameLibraryTests.
  private func coverage(_ paths: [CGPath], size: Int) -> [Int] {
    var counts = [Int](repeating: 0, count: size * size)
    for y in 0..<size {
      for x in 0..<size {
        let sample = CGPoint(x: Double(x) + 0.37, y: Double(y) + 0.61)
        counts[y * size + x] = paths.filter { $0.contains(sample, using: .winding) }.count
      }
    }
    return counts
  }

  @Test("the library holds exactly the eight layouts, each taking the pictures in its id")
  func holdsEightLayouts() {
    #expect(CollageShapedFrameLibrary.all.map(\.id) == Self.layouts.map(\.id))
    for (id, count) in Self.layouts {
      #expect(CollageShapedFrameLibrary.frame(id: id)?.count == count, "\(id)")
      #expect(CollageFrameLibrary.frame(id: id) == nil, "\(id)")
      let settings = Self.spaced
      #expect(
        CollageTemplates.cells(
          .frame(id), count: count, width: 600, height: 400, settings: settings)?.count == count,
        "\(id)")
      #expect(
        CollageTemplates.cells(
          .frame(id), count: count + 1, width: 600, height: 400, settings: settings) == nil, "\(id)"
      )
    }
    #expect(CollageShapedFrameLibrary.frame(id: "collage_99_0") == nil)
  }

  @Test("every cell lies inside the canvas, on a landscape and on a portrait canvas")
  func cellsLieInCanvas() throws {
    for (id, count) in Self.layouts {
      for (width, height) in [(600.0, 400.0), (400.0, 600.0)] {
        let paths = try #require(
          CollageTemplates.cells(
            .frame(id), count: count, width: width, height: height, settings: Self.spaced),
          "\(id)")
        for path in paths {
          let box = path.boundingBoxOfPath
          #expect(box.minX >= 0 && box.minY >= 0, "\(id)")
          #expect(box.maxX <= width && box.maxY <= height, "\(id)")
        }
      }
    }
  }

  @Test("every cell has a positive area, and so does its cut-out")
  func cellAreasArePositive() throws {
    for (id, count) in Self.layouts {
      let paths = try #require(
        CollageTemplates.cells(
          .frame(id), count: count, width: 128, height: 128, settings: Self.plain),
        "\(id)")
      for path in paths {
        #expect(area(of: path) > 0, "\(id)")
      }
    }
  }

  @Test("without a gap every pixel of the canvas belongs to exactly one cell")
  func cellsTileTheCanvas() throws {
    for (id, count) in Self.layouts {
      let paths = try #require(
        CollageTemplates.cells(
          .frame(id), count: count, width: 128, height: 128, settings: Self.plain),
        "\(id)")
      let wrong = coverage(paths, size: 128).filter { $0 != 1 }.count
      #expect(wrong == 0, "\(id): \(wrong) pixels")
    }
  }

  @Test("with a gap no pixel belongs to two cells, and the gap leaves some pixels empty")
  func gapSeparatesCells() throws {
    let gapped = CollageLayout.Settings(gap: 6, margin: 0, background: (0, 0, 0))
    for (id, count) in Self.layouts {
      let paths = try #require(
        CollageTemplates.cells(.frame(id), count: count, width: 128, height: 128, settings: gapped),
        "\(id)")
      let counts = coverage(paths, size: 128)
      #expect(!counts.contains { $0 > 1 }, "\(id)")
      #expect(counts.contains(0), "\(id)")
    }
  }

  @Test("each cut-out shows the picture of its own cell in a render at 128 pixels")
  func rendersCutOuts() throws {
    for (id, points) in Self.probes {
      let count = try #require(Self.layouts.first { $0.id == id }?.count, "\(id)")
      let collage = try #require(
        CollageTemplates.render(
          Self.pictures(count), template: .frame(id), width: 128, height: 128, settings: Self.plain),
        "\(id)")
      let raster = try #require(RasterImage(collage), "\(id)")
      for point in points {
        #expect(
          raster.pixel(x: point.x, y: point.y) == Self.colours[point.picture],
          "\(id) at (\(point.x), \(point.y))")
      }
    }
  }

  @Test("every picture is visible in a render at 128 pixels, with no gap")
  func rendersEveryPicture() throws {
    for (id, count) in Self.layouts {
      let collage = try #require(
        CollageTemplates.render(
          Self.pictures(count), template: .frame(id), width: 128, height: 128, settings: Self.plain),
        "\(id)")
      let raster = try #require(RasterImage(collage), "\(id)")
      for index in 0..<count {
        let seen = (0..<128).reduce(0) { total, y in
          total + (0..<128).filter { raster.pixel(x: $0, y: y) == Self.colours[index] }.count
        }
        #expect(seen > 0, "\(id) picture \(index)")
      }
    }
  }

  @Test("a disc stays round on a landscape canvas")
  func discStaysRound() throws {
    // On a 240 by 135 canvas the disc of 3_8 has a diameter of 120 pixels, so it is round, not an ellipse.
    let collage = try #require(
      CollageTemplates.render(
        Self.pictures(3), template: .frame("collage_3_8"), width: 240, height: 135,
        settings: Self.plain))
    let raster = try #require(RasterImage(collage))
    #expect(raster.pixel(x: 120, y: 117) == Self.colours[2])
    #expect(raster.pixel(x: 161, y: 108) == Self.colours[2])
    #expect(raster.pixel(x: 60, y: 5) == Self.colours[0])
    #expect(raster.pixel(x: 200, y: 10) == Self.colours[1])
  }
}
