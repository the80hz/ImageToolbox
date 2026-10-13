import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Blur filters")
struct BlurFilterTests {

  /// Чередующиеся столбцы разной яркости: видно и размытие, и дилатацию.
  private func stripes(width: Int, height: Int, low: UInt8, high: UInt8) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        let value = x % 2 == 0 ? low : high
        pixels[index] = value
        pixels[index + 1] = value
        pixels[index + 2] = value
        pixels[index + 3] = 255
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Каждый фильтр с крайними значениями диапазона, на 1x1 и 5x3: размер сохраняется.
  private func runsOnExtremes(_ filter: any Filter) async throws {
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      let output = try await filter.apply(to: picture)
      #expect(output.width == width)
      #expect(output.height == height)
      #expect(output.pixels.count == picture.pixels.count)
    }
  }

  /// Однородная картинка остаётся однородной: усреднение и выбор медианы её не меняют.
  private func keepsSolid(_ filter: any Filter) async throws {
    let picture = FilterTestImages.solid(width: 5, height: 3, red: 90, green: 140, blue: 200)
    let output = try await filter.apply(to: picture)
    for index in stride(from: 0, to: output.pixels.count, by: 4) {
      #expect(abs(Int(output.pixels[index]) - 90) <= 1)
      #expect(abs(Int(output.pixels[index + 1]) - 140) <= 1)
      #expect(abs(Int(output.pixels[index + 2]) - 200) <= 1)
      #expect(output.pixels[index + 3] == 255)
    }
  }

  @Test("box blur changes stripes; radius 0 changes nothing")
  func boxBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await BoxBlurFilter(radius: 2).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    let same = try await BoxBlurFilter(radius: 0).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(BoxBlurFilter(radius: 0))
    try await runsOnExtremes(BoxBlurFilter(radius: 100))
    try await keepsSolid(BoxBlurFilter(radius: 3))
  }

  @Test("gaussian blur changes stripes; radius 0 changes nothing")
  func gaussianBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await GaussianBlurFilter(radius: 2, sigma: 2, edge: .reflect101).apply(
      to: picture)
    #expect(blurred.pixels != picture.pixels)
    let same = try await GaussianBlurFilter(radius: 0, sigma: 10, edge: .clamp).apply(
      to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(GaussianBlurFilter(radius: 0, sigma: 1, edge: .clamp))
    try await runsOnExtremes(GaussianBlurFilter(radius: 100, sigma: 100, edge: .wrap))
    try await keepsSolid(GaussianBlurFilter(radius: 4, sigma: 3, edge: .reflect))
  }

  @Test("motion blur changes stripes; length 1 changes nothing")
  func motionBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await MotionBlurFilter(size: 5, degrees: 0, edge: .reflect101).apply(
      to: picture)
    #expect(blurred.pixels != picture.pixels)
    let same = try await MotionBlurFilter(size: 0, degrees: 45, edge: .clamp).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(MotionBlurFilter(size: 0, degrees: 0, edge: .clamp))
    try await runsOnExtremes(MotionBlurFilter(size: 201, degrees: 360, edge: .reflect))
    try await keepsSolid(MotionBlurFilter(size: 7, degrees: 30, edge: .reflect101))
  }

  @Test("zoom blur changes stripes; zero size changes nothing")
  func zoomBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await ZoomBlurFilter(centerX: 0.5, centerY: 0.5, size: 5).apply(
      to: picture)
    #expect(blurred.pixels != picture.pixels)
    let same = try await ZoomBlurFilter(centerX: 0.2, centerY: 0.8, size: 0).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(ZoomBlurFilter(centerX: 0, centerY: 1, size: 0))
    try await runsOnExtremes(ZoomBlurFilter(centerX: 1, centerY: 0, size: 10))
    try await keepsSolid(ZoomBlurFilter(centerX: 0.5, centerY: 0.5, size: 10))
  }

  @Test("bokeh spreads bright stripes; size 1 changes nothing")
  func bokeh() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let spread = try await BokehFilter(size: 3, sides: 6).apply(to: picture)
    #expect(spread.pixels != picture.pixels)
    let same = try await BokehFilter(size: 1, sides: 3).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(BokehFilter(size: 1, sides: 3))
    try await runsOnExtremes(BokehFilter(size: 150, sides: 40))
    try await keepsSolid(BokehFilter(size: 4, sides: 5))
  }

  @Test("linear tilt shift changes stripes away from the focus line")
  func linearTiltShift() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await LinearTiltShiftFilter(
      blurRadius: 2, sigma: 2, anchorX: 0.5, anchorY: 0.5, hole: 0, degrees: 0
    ).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    try await runsOnExtremes(
      LinearTiltShiftFilter(
        blurRadius: 1, sigma: 1, anchorX: 0, anchorY: 1, hole: 0, degrees: 360))
    try await runsOnExtremes(
      LinearTiltShiftFilter(
        blurRadius: 100, sigma: 50, anchorX: 1, anchorY: 0, hole: 1, degrees: 0))
    try await keepsSolid(
      LinearTiltShiftFilter(
        blurRadius: 3, sigma: 5, anchorX: 0.5, anchorY: 0.5, hole: 0.2, degrees: 45))
  }

  @Test("radial tilt shift changes stripes away from the focus circle")
  func radialTiltShift() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await RadialTiltShiftFilter(
      blurRadius: 2, sigma: 2, anchorX: 0.5, anchorY: 0.5, hole: 0
    ).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    try await runsOnExtremes(
      RadialTiltShiftFilter(blurRadius: 1, sigma: 1, anchorX: 0, anchorY: 0, hole: 0))
    try await runsOnExtremes(
      RadialTiltShiftFilter(blurRadius: 100, sigma: 50, anchorX: 1, anchorY: 1, hole: 1))
    try await keepsSolid(
      RadialTiltShiftFilter(blurRadius: 3, sigma: 5, anchorX: 0.5, anchorY: 0.5, hole: 0.2))
  }

  @Test("fast blur changes stripes; full scale and zero radius change nothing")
  func fastBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await FastBlurFilter(scale: 0.5, radius: 1).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    let same = try await FastBlurFilter(scale: 1, radius: 0).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(FastBlurFilter(scale: 0.1, radius: 0))
    try await runsOnExtremes(FastBlurFilter(scale: 1, radius: 100))
    try await keepsSolid(FastBlurFilter(scale: 0.5, radius: 3))
  }

  @Test("native stack blur changes stripes at its minimum radius")
  func nativeStackBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await NativeStackBlurFilter(radius: 1).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    try await runsOnExtremes(NativeStackBlurFilter(radius: 0))
    try await runsOnExtremes(NativeStackBlurFilter(radius: 250))
    try await keepsSolid(NativeStackBlurFilter(radius: 3))
  }

  @Test("median blur removes a single bright pixel; radius 0 is window radius 1, as in Aire")
  func medianBlur() async throws {
    var picture = FilterTestImages.solid(width: 5, height: 3, red: 10, green: 10, blue: 10)
    picture = RasterImage(
      width: 5, height: 3,
      pixels: picture.pixels.enumerated().map { index, value in
        // Одна яркая точка в центре: медиана 3x3 её убирает.
        index == (1 * 5 + 2) * 4 ? 250 : (index % 4 == 3 ? 255 : value)
      })
    let filtered = try await MedianBlurFilter(radius: 1).apply(to: picture)
    #expect(filtered.pixels[(1 * 5 + 2) * 4] == 10)
    // Aire передаёт в libblur радиус 2 * round(value) + 1, поэтому радиус 0 — окно радиуса 1.
    let smallest = try await MedianBlurFilter(radius: 0).apply(to: picture)
    #expect(smallest.pixels[(1 * 5 + 2) * 4] == 10)
    try await runsOnExtremes(MedianBlurFilter(radius: 0))
    try await runsOnExtremes(MedianBlurFilter(radius: 100))
    try await keepsSolid(MedianBlurFilter(radius: 2))
  }

  @Test("tent blur changes stripes; size 1 still blurs, as in Aire")
  func tentBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 0, high: 255)
    let blurred = try await TentBlurFilter(size: 5).apply(to: picture)
    #expect(blurred.pixels != picture.pixels)
    // Sigma 1 даёт у libblur два прохода box с ядром 3, это не тождество.
    let smallest = try await TentBlurFilter(size: 1).apply(to: picture)
    #expect(smallest.pixels != picture.pixels)
    try await runsOnExtremes(TentBlurFilter(size: 1))
    try await runsOnExtremes(TentBlurFilter(size: 300))
    try await keepsSolid(TentBlurFilter(size: 7))
  }

  @Test("bilateral blur smooths a faint difference; radius 0 changes nothing")
  func bilateralBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 100, high: 110)
    let smoothed = try await BilaterialBlurFilter(
      radius: 2, spatialSigma: 3, rangeSigma: 50, edge: .reflect101
    ).apply(to: picture)
    #expect(smoothed.pixels != picture.pixels)
    let same = try await BilaterialBlurFilter(
      radius: 0, spatialSigma: 10, rangeSigma: 3, edge: .clamp
    ).apply(to: picture)
    #expect(same.pixels == picture.pixels)
    try await runsOnExtremes(
      BilaterialBlurFilter(radius: 1, spatialSigma: 1, rangeSigma: 1, edge: .wrap))
    try await runsOnExtremes(
      BilaterialBlurFilter(radius: 50, spatialSigma: 100, rangeSigma: 100, edge: .reflect))
    try await keepsSolid(
      BilaterialBlurFilter(radius: 2, spatialSigma: 10, rangeSigma: 3, edge: .clamp))
  }

  @Test("fast bilateral blur smooths a faint difference; size 1 stays inside the value range")
  func fastBilateralBlur() async throws {
    let picture = stripes(width: 6, height: 4, low: 100, high: 110)
    let smoothed = try await FastBilaterialBlurFilter(
      size: 5, spatialSigma: 3, rangeSigma: 50
    ).apply(to: picture)
    #expect(smoothed.pixels != picture.pixels)
    // Ядро 1 не размывает сетку, но сама сетка огрубляет картинку, так что тождества нет.
    let smallest = try await FastBilaterialBlurFilter(size: 1, spatialSigma: 10, rangeSigma: 3)
      .apply(to: picture)
    #expect(
      smallest.pixels.enumerated().allSatisfy {
        $0.offset % 4 == 3 || (100...110).contains($0.element)
      })
    try await runsOnExtremes(FastBilaterialBlurFilter(size: 1, spatialSigma: 1, rangeSigma: 1))
    try await runsOnExtremes(
      FastBilaterialBlurFilter(size: 200, spatialSigma: 100, rangeSigma: 100))
    try await keepsSolid(FastBilaterialBlurFilter(size: 5, spatialSigma: 10, rangeSigma: 3))
  }

  @Test("edge modes map out-of-range indices inside the picture")
  func edgeModes() {
    #expect(BlurBorderMode.clamp.index(-2, count: 5) == 0)
    #expect(BlurBorderMode.clamp.index(7, count: 5) == 4)
    #expect(BlurBorderMode.wrap.index(-1, count: 5) == 4)
    #expect(BlurBorderMode.reflect.index(-1, count: 5) == 0)
    #expect(BlurBorderMode.reflect101.index(-1, count: 5) == 1)
    #expect(BlurBorderMode.reflect101.index(5, count: 5) == 3)
    #expect(BlurBorderMode.reflect101.index(3, count: 1) == 0)
  }
}
