import Foundation
import Testing

@testable import ImageToolboxKit

/// Особенности Aire 0.18.1 и libblur 0.19.4, которые перенесены как есть (раздел 9, решение 16).
/// Побитовое совпадение с Android проверяет `AndroidReferenceParityTests`; здесь то, что эталон
/// на картинке 64 x 64 не показывает.
@Suite("Aire and libblur quirks kept from Android")
struct AireBlurQuirkTests {

  @Test("the border function mirrors indices inside the picture for reflect modes only")
  func arenaIndexMirrorsInterior() {
    // reflect101: (n - 1) - i mod (n - 1); внутри картинки это зеркальный индекс, 0 не встречается.
    #expect(AireArena.index(1, count: 5, mode: .reflect101) == 3)
    #expect(AireArena.index(0, count: 5, mode: .reflect101) == 4)
    #expect(AireArena.index(-1, count: 5, mode: .reflect101) == 1)
    #expect(AireArena.index(5, count: 5, mode: .reflect101) == 3)
    #expect(AireArena.index(2, count: 5, mode: .reflect) == 2)
    #expect(AireArena.index(1, count: 5, mode: .reflect) == 3)
    #expect(AireArena.index(-1, count: 5, mode: .reflect) == 0)
    // clamp и wrap внутри картинки возвращают тот же индекс.
    #expect(AireArena.index(3, count: 5, mode: .clamp) == 3)
    #expect(AireArena.index(3, count: 5, mode: .wrap) == 3)
    #expect(AireArena.index(-1, count: 5, mode: .wrap) == 4)
    #expect(AireArena.index(7, count: 1, mode: .reflect101) == 0)
  }

  @Test(
    "a gaussian kernel above 61 repeats the first rows at the bottom when the height is not a multiple of 3"
  )
  func largeGaussianRepeatsFirstRows() async throws {
    let picture = FilterTestImages.gradient(width: 7, height: 8)
    let output = try await GaussianBlurFilter(radius: 40, sigma: 15, edge: .reflect101).apply(
      to: picture)
    let stride = 7 * 4
    // 8 строк: считаются 6, строки 6 и 7 повторяют строки 0 и 1.
    #expect(Array(output.pixels[(6 * stride)..<(7 * stride)]) == Array(output.pixels[0..<stride]))
    #expect(
      Array(output.pixels[(7 * stride)..<(8 * stride)])
        == Array(output.pixels[stride..<(2 * stride)]))
    // Ядро до 61 так не делает.
    let ordinary = try await GaussianBlurFilter(radius: 25, sigma: 10, edge: .reflect101).apply(
      to: picture)
    #expect(
      Array(ordinary.pixels[(6 * stride)..<(7 * stride)]) != Array(ordinary.pixels[0..<stride]))
  }

  @Test("median takes the lower middle value; a window of one sample gives 0, as in libblur")
  func medianTakesLowerMiddle() async throws {
    // Столбец из пяти значений, радиус 1 у фильтра — окно 3 у libblur: для середины n = 5,
    // n / 2 = 2, берётся второе по возрастанию значение (20), а не третье (30).
    var pixels = [UInt8](repeating: 255, count: 5 * 4)
    for (y, value) in [10, 20, 30, 40, 50].enumerated() {
      for channel in 0..<3 { pixels[y * 4 + channel] = UInt8(value) }
    }
    let column = RasterImage(width: 1, height: 5, pixels: pixels)
    let output = try await MedianBlurFilter(radius: 1).apply(to: column)
    #expect(output.pixels[2 * 4] == 20)
    #expect(output.pixels[2 * 4 + 3] == 255)
    // В окне один отсчёт: n / 2 = 0, первый же бин 0 «доходит до порога».
    let single = RasterImage(width: 1, height: 1, pixels: [77, 88, 99, 255])
    let lone = try await MedianBlurFilter(radius: 0).apply(to: single)
    #expect(Array(lone.pixels[0..<3]) == [0, 0, 0])
  }

  @Test("fast blur turns transparency into opaque pixels and keeps the size")
  func fastBlurIsOpaque() async throws {
    var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) { pixels[index + 3] = 128 }
    let picture = RasterImage(width: 8, height: 8, pixels: pixels)
    let output = try await FastBlurFilter(scale: 0.5, radius: 2).apply(to: picture)
    #expect(output.width == 8 && output.height == 8)
    #expect(stride(from: 3, to: output.pixels.count, by: 4).allSatisfy { output.pixels[$0] == 255 })
    let untouched = try await FastBlurFilter(scale: 0.5, radius: 0).apply(to: picture)
    #expect(untouched.pixels == picture.pixels)
  }

  @Test("tilt shift with a zero focus radius blackens the anchor pixel, as Aire does")
  func tiltShiftNaNPixel() async throws {
    let picture = FilterTestImages.solid(width: 9, height: 9, red: 200, green: 100, blue: 50)
    let output = try await RadialTiltShiftFilter(
      blurRadius: 3, sigma: 2, anchorX: 0.5, anchorY: 0.5, hole: 0
    ).apply(to: picture)
    let centre = (4 * 9 + 4) * 4
    #expect(Array(output.pixels[centre..<(centre + 3)]) == [0, 0, 0])
    #expect(output.pixels[centre + 3] == 255)
  }

  @Test("the bokeh kernel of size 6 with 6 sides is the filled hexagon of Aire")
  func bokehKernelShape() {
    let kernel = bokehMorphologyKernel(size: 6, sides: 6)
    var mask = [Bool](repeating: false, count: 36)
    for run in kernel.runs {
      for column in run.lo...run.hi { mask[run.row * 6 + column] = true }
    }
    let expected: [[Int]] = [
      [0, 1, 1, 1, 1, 0], [0, 1, 1, 1, 1, 0], [1, 1, 1, 1, 1, 1],
      [1, 1, 1, 1, 1, 1], [0, 1, 1, 1, 1, 0], [0, 1, 1, 1, 1, 0],
    ]
    for row in 0..<6 {
      for column in 0..<6 {
        #expect(mask[row * 6 + column] == (expected[row][column] == 1), "\(row),\(column)")
      }
    }
  }
}
