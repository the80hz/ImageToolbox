import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Histogram equalize filters")
struct HistogramFilterTests {

  /// Low contrast: red 100...(100 + width - 1), green 100...(100 + height - 1), blue 96.
  /// The full gradient already uses evenly spaced levels, so equalize leaves it unchanged;
  /// this picture has room to stretch.
  static func narrowRamp(width: Int, height: Int) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        pixels[index] = UInt8(100 + x)
        pixels[index + 1] = UInt8(100 + y)
        pixels[index + 2] = 96
        pixels[index + 3] = 255
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  @Test("equalize stretches a low-contrast picture, so the picture changes")
  func equalizeChangesRamp() async throws {
    let picture = Self.narrowRamp(width: 6, height: 4)
    let output = try await EqualizeFilter().apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  // Jh Labs не вычитает минимум накопленной гистограммы, поэтому один цвет переходит в 255.
  @Test("equalize maps a single-colour picture to 255, as Jh Labs does without a minimum")
  func equalizeSolidGoesWhite() async throws {
    let picture = FilterTestImages.solid(width: 4, height: 3, red: 100, green: 100, blue: 100)
    let output = try await EqualizeFilter().apply(to: picture)
    let white = FilterTestImages.solid(width: 4, height: 3, red: 255, green: 255, blue: 255)
    #expect(output.pixels == white.pixels)
  }

  // Aire (YCgCo): у однотонной картинки cdf - cdfMin = N для всех пикселей, яркость Y становится 255,
  // а Cg и Co остаются. Для (30, 60, 90): Y = 60, Cg = 128, Co = 48 (Co - 128 = -80), итог (225, 255, 255).
  @Test("equalize histogram lifts a single colour to full luma and keeps its chroma")
  func equalizeHistogramProperties() async throws {
    let ramp = Self.narrowRamp(width: 6, height: 4)
    let changed = try await EqualizeHistogramFilter().apply(to: ramp)
    #expect(changed.pixels != ramp.pixels)

    let solid = FilterTestImages.solid(width: 4, height: 3, red: 30, green: 60, blue: 90)
    let lifted = try await EqualizeHistogramFilter().apply(to: solid)
    #expect(Array(lifted.pixels.prefix(4)) == [225, 255, 255, 255])
  }

  @Test("equalize keeps alpha")
  func equalizeKeepsAlpha() async throws {
    var pixels = FilterTestImages.gradient(width: 5, height: 3).pixels
    for index in stride(from: 3, to: pixels.count, by: 4) {
      pixels[index] = 128
    }
    let picture = RasterImage(width: 5, height: 3, pixels: pixels)
    let output = try await EqualizeHistogramFilter().apply(to: picture)
    #expect(stride(from: 3, to: output.pixels.count, by: 4).allSatisfy { output.pixels[$0] == 128 })
  }

  @Test("HSV equalize changes a gradient at 256 bins")
  func hsvChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await EqualizeHistogramHSVFilter(bins: 256).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  // Все V одинаковы: cdf - cdfMin = N, V уходит в максимум, H и S остаются (100, 60, 20 -> 255, 152, 50).
  @Test("HSV equalize at 256 bins lifts a single colour to full value and keeps hue")
  func hsvSolidGoesToFullValue() async throws {
    let picture = FilterTestImages.solid(width: 4, height: 3, red: 100, green: 60, blue: 20)
    let output = try await EqualizeHistogramHSVFilter(bins: 256).apply(to: picture)
    #expect(Array(output.pixels.prefix(4)) == [255, 152, 50, 255])
  }

  // Rust: все пиксели в корзине 0 дают 0 * inf = NaN, а `f64::min` отдаёт тогда верхнюю границу.
  // Так выходит по исходнику Aire, эталона для чёрной картинки нет.
  @Test("HSV equalize turns an all-black picture white, as the Rust NaN rule gives")
  func hsvBlackGoesWhite() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 2, red: 0, green: 0, blue: 0)
    let output = try await EqualizeHistogramHSVFilter(bins: 2).apply(to: picture)
    let white = FilterTestImages.solid(width: 3, height: 2, red: 255, green: 255, blue: 255)
    #expect(output.pixels == white.pixels)
  }

  // В клетке из одного пикселя cdf - cdfMin = 1, поэтому V всегда 1 (наибольший канал 255).
  @Test("pixelation with one-pixel cells lifts every pixel to full value")
  func pixelationOnePixelCells() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await EqualizeHistogramPixelationFilter(gridX: 6, gridY: 4).apply(to: picture)
    for index in stride(from: 0, to: output.pixels.count, by: 4) {
      #expect(max(output.pixels[index], output.pixels[index + 1], output.pixels[index + 2]) == 255)
      #expect(output.pixels[index + 3] == 255)
    }
  }

  @Test("pixelation with a 2x2 grid changes a gradient")
  func pixelationChangesGradient() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await EqualizeHistogramPixelationFilter(gridX: 2, gridY: 2).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("every equalize filter survives its extremes on a 1x1 and a 5x3 picture")
  func extremesKeepSize() async throws {
    let filters: [any Filter] = [
      EqualizeFilter(),
      EqualizeHistogramFilter(),
      EqualizeHistogramHSVFilter(bins: 2),
      EqualizeHistogramHSVFilter(bins: 256),
      EqualizeHistogramPixelationFilter(gridX: 1, gridY: 1),
      EqualizeHistogramPixelationFilter(gridX: 200, gridY: 200),
    ]
    for (width, height) in [(1, 1), (5, 3)] {
      let picture = FilterTestImages.gradient(width: width, height: height)
      for filter in filters {
        let output = try await filter.apply(to: picture)
        #expect(output.width == width && output.height == height)
        #expect(output.pixels.count == picture.pixels.count)
      }
    }
  }

  @Test("the NEON part of the HSV pipeline covers 4 * 16 + 8 pixels of a 64-pixel row")
  func hsvVectorPixelCount() {
    #expect(AireHSV.vectorPixelCount(width: 64) == 56)
    #expect(AireHSV.vectorPixelCount(width: 17) == 16)
    #expect(AireHSV.vectorPixelCount(width: 8) == 0)
    #expect(AireHSV.vectorPixelCount(width: 9) == 8)
  }

  @Test("YCgCo round trip keeps grey exactly and colours within one level")
  func ycgcoRoundTrip() {
    for value in stride(from: 0, through: 255, by: 15) {
      let grey = AireYCgCo.components(value, value, value)
      #expect(grey.luma == value && grey.cg == 128 && grey.co == 128)
    }
    for (red, green, blue) in [(200, 30, 90), (10, 250, 40), (0, 0, 255)] {
      let parts = AireYCgCo.components(red, green, blue)
      let back = AireYCgCo.rgb(luma: parts.luma, cg: parts.cg, co: parts.co)
      let worst = max(abs(back.red - red), abs(back.green - green), abs(back.blue - blue))
      #expect(worst <= 2)
    }
  }
}
