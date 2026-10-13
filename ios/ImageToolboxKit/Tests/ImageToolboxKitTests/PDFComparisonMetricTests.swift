import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("PDF comparison metrics")
struct PDFComparisonMetricTests {

  private static let black = RGBA(red: 0, green: 0, blue: 0)

  /// A page of 200 x 100 points, drawn at 2 pixels to a point by `PDFComparison`: 400 x 200 pixels.
  private static let pixelsPerPage = 400 * 200

  @Test("identical pages differ in no pixel, by any metric")
  func identicalPagesMatch() throws {
    let pdf = try PDFFixtures.make([
      PDFFixtures.Page(colour: PDFFixtures.white, rightColour: Self.black)
    ])
    for metric in PDFComparisonMetric.allCases {
      let result = try PDFComparison.compare(pdf, with: pdf, metric: metric)
      #expect(result.differingPixels == [0], "\(metric.rawValue)")
    }
  }

  @Test("a changed half of the page is marked by every metric")
  func changedHalfIsMarked() throws {
    let first = try PDFFixtures.make([PDFFixtures.Page(colour: PDFFixtures.white)])
    let second = try PDFFixtures.make([
      PDFFixtures.Page(colour: PDFFixtures.white, rightColour: Self.black)
    ])
    for metric in PDFComparisonMetric.allCases {
      let result = try PDFComparison.compare(first, with: second, metric: metric)
      #expect(result.differingPixels[0] >= 30_000, "\(metric.rawValue)")
      #expect(result.differingPixels[0] <= Self.pixelsPerPage, "\(metric.rawValue)")
    }
    let absolute = try PDFComparison.compare(first, with: second, metric: .absoluteError)
    let canvas = try PDFFixtures.pageSize(of: absolute.data)
    #expect(canvas == CGSize(width: 400, height: 200))
    #expect(absolute.differingPixels == [Self.pixelsPerPage / 2])
  }

  @Test("a page drawn at twice its size covers the whole picture, as PDFKit draws it")
  func pageStretchesToLargerPicture() throws {
    let pdf = try PDFFixtures.make([
      PDFFixtures.Page(colour: PDFFixtures.white, rightColour: Self.black)
    ])
    let source = try PDFSourcePages(pdf)
    #expect(source.displayedSize(of: 0) == CGSize(width: 200, height: 100))
    let picture = try #require(source.render(0, scale: 2, maximumSide: 8_192))
    #expect(picture.width == 400)
    #expect(picture.height == 200)
    let raster = try #require(RasterImage(picture))
    let dark = (0..<(raster.width * raster.height)).filter { raster.pixels[$0 * 4] < 64 }.count
    #expect(dark == 40_000)

    let viaKit = try #require(RasterImage(try PDFTools.render(pdf, page: 0, width: 400)))
    let kitDark = (0..<(viaKit.width * viaKit.height)).filter { viaKit.pixels[$0 * 4] < 64 }.count
    #expect(kitDark == dark)
  }

  @Test("a change of 5 levels is below the default tolerance, so no metric marks it")
  func smallChangeIsNotMarked() throws {
    let first = try PDFFixtures.make([
      PDFFixtures.Page(colour: RGBA(red: 128, green: 128, blue: 128))
    ])
    let second = try PDFFixtures.make([
      PDFFixtures.Page(colour: RGBA(red: 133, green: 133, blue: 133))
    ])
    for metric in PDFComparisonMetric.allCases {
      let result = try PDFComparison.compare(first, with: second, metric: metric)
      #expect(result.differingPixels == [0], "\(metric.rawValue)")
    }
  }

  @Test("a tighter tolerance marks the same small change everywhere")
  func toleranceIsTheThreshold() throws {
    let first = try PDFFixtures.make([
      PDFFixtures.Page(colour: RGBA(red: 128, green: 128, blue: 128))
    ])
    let second = try PDFFixtures.make([
      PDFFixtures.Page(colour: RGBA(red: 133, green: 133, blue: 133))
    ])
    let result = try PDFComparison.compare(
      first, with: second, tolerance: 0.01, metric: .absoluteError)
    #expect(result.differingPixels == [Self.pixelsPerPage])
  }

  @Test("the Gaussian window sums to one and is symmetric, with its peak in the middle")
  func gaussianKernel() {
    let kernel = PDFPixelMetric.gaussianKernel(size: 11)
    #expect(kernel.count == 11)
    #expect(abs(kernel.reduce(0, +) - 1) < 0.00001)
    #expect(abs(kernel[0] - kernel[10]) < 0.00001)
    #expect(kernel[5] == kernel.max())
  }

  @Test("the window is 11 pixels, shrunk to an odd size for a small picture")
  func windowSize() {
    #expect(PDFPixelMetric.oddWindow(50) == 11)
    #expect(PDFPixelMetric.oddWindow(12) == 11)
    #expect(PDFPixelMetric.oddWindow(4) == 3)
    #expect(PDFPixelMetric.oddWindow(1) == 1)
    #expect(PDFPixelMetric.oddWindow(0) == 1)
  }

  @Test("the Android metrics are all offered")
  func allMetrics() {
    #expect(
      PDFComparisonMetric.allCases.map(\.rawValue) == [
        "absoluteError", "meanAbsoluteError", "rootMeanSquaredError",
        "peakSignalToNoiseRatio", "structuralSimilarity", "normalizedCrossCorrelation",
      ])
  }
}
