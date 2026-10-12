import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import ImageToolboxKit

/// Сверка фильтров с эталонами Android по пикселям (`Fixtures/AndroidReference`).
///
/// Эталоны сняты `ReferenceFilterExportTest` на эмуляторе Android: каждый фильтр из списка ниже
/// применён с параметрами по умолчанию Android к `input.png` (64x64, градиент) через `transform`.
/// Размер не меняется.
@Suite("Android reference parity with default parameters")
struct AndroidReferenceParityTests {

  /// Допуск: среднее отличие по каналам RGB не больше 0.25 и наибольшее отличие канала не больше 1.
  /// Значения строгие. Android округляет или отбрасывает дробную часть при записи в байт, поэтому
  /// точное совпадение или отличие на один уровень. Ослаблять допуск можно только с причиной здесь же.
  static let maximumMeanDifference = 0.25
  static let maximumChannelDifference = 1

  @Test("each filter matches its Android reference output", arguments: AndroidReferenceCase.all)
  func matchesAndroidReference(_ testCase: AndroidReferenceCase) async throws {
    let input = try loadReference("input")
    let expected = try loadReference(testCase.name)
    let output = try await testCase.filter.apply(to: input)
    let difference = channelDifference(output, expected)
    let check = {
      #expect(
        difference.mean <= AndroidReferenceParityTests.maximumMeanDifference,
        "среднее отличие \(difference.mean), допуск \(AndroidReferenceParityTests.maximumMeanDifference)"
      )
      #expect(
        difference.maximum <= AndroidReferenceParityTests.maximumChannelDifference,
        "наибольшее отличие \(difference.maximum), допуск \(AndroidReferenceParityTests.maximumChannelDifference)"
      )
    }
    if let knownIssue = testCase.knownIssue {
      withKnownIssue(Comment(rawValue: knownIssue)) { check() }
    } else {
      check()
    }
  }
}

/// Один фильтр с параметрами по умолчанию и имя его эталона (совпадает с именем класса Android).
struct AndroidReferenceCase: Sendable, CustomTestStringConvertible {
  let name: String
  let filter: any Filter
  /// Расхождение, которое пока не устранено, с числами. Пусто, если фильтр должен совпасть с эталоном.
  let knownIssue: String?

  var testDescription: String { name }

  static let all: [AndroidReferenceCase] = [
    AndroidReferenceCase(name: "SepiaFilter", filter: SepiaFilter(), knownIssue: nil),
    AndroidReferenceCase(name: "NegativeFilter", filter: NegativeFilter(), knownIssue: nil),
    AndroidReferenceCase(
      name: "BlackAndWhiteFilter", filter: BlackAndWhiteFilter(), knownIssue: nil),
    AndroidReferenceCase(
      name: "SolarizeFilter", filter: SolarizeFilter(threshold: 0.5), knownIssue: nil),
    AndroidReferenceCase(
      name: "PosterizeFilter", filter: PosterizeFilter(levels: 5), knownIssue: nil),
    AndroidReferenceCase(
      name: "GaussianBlurFilter",
      filter: GaussianBlurFilter(radius: 25, sigma: 10, edge: .reflect101),
      knownIssue:
        "GaussianBlurFilter: Android вызывает Aire.gaussianBlur (нативный код, формул в репозитории нет); "
        + "среднее отличие 1.63, наибольшее 19"),
    AndroidReferenceCase(
      name: "PixelationFilter", filter: PixelationFilter(size: 25), knownIssue: nil),
    AndroidReferenceCase(
      name: "VignetteFilter",
      filter: VignetteFilter(start: 0.3, end: 0.75, color: .black), knownIssue: nil),
    AndroidReferenceCase(name: "SharpenFilter", filter: SharpenFilter(amount: 1), knownIssue: nil),
    AndroidReferenceCase(
      name: "SaturationFilter",
      filter: SaturationFilter(strength: 2, tonemapping: true),
      knownIssue:
        "SaturationFilter: Android вызывает Aire.saturation с tonemap (нативный код, формул в репозитории нет); "
        + "среднее отличие 35.5, наибольшее 111"),
    AndroidReferenceCase(
      name: "SimpleSolarizeFilter", filter: SimpleSolarizeFilter(), knownIssue: nil),
    AndroidReferenceCase(name: "ExposureFilter", filter: ExposureFilter(stops: 1), knownIssue: nil),
    AndroidReferenceCase(name: "HueFilter", filter: HueFilter(degrees: 90), knownIssue: nil),
    AndroidReferenceCase(
      name: "WhiteBalanceFilter",
      filter: WhiteBalanceFilter(temperature: 7000, tint: 100),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BulgeDistortionFilter",
      filter: BulgeDistortionFilter(radius: 0.25, scale: 0.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SwirlDistortionFilter",
      filter: SwirlDistortionFilter(radius: 0.5, angle: 1, centreX: 0.5, centreY: 0.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SphereRefractionFilter",
      filter: SphereRefractionFilter(radius: 0.25, refractiveIndex: 0.71),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GlassSphereRefractionFilter",
      filter: GlassSphereRefractionFilter(radius: 0.25, refractiveIndex: 0.71),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ZoomBlurFilter",
      filter: ZoomBlurFilter(centerX: 0.5, centerY: 0.5, size: 5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GlassHexTilesFilter",
      filter: GlassHexTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GlassRectTilesFilter",
      filter: GlassRectTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GlassTriangleTilesFilter",
      filter: GlassTriangleTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "LogarithmicSpiralFilter",
      filter: LogarithmicSpiralFilter(count: 2, intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SpiralDrosteFilter",
      filter: SpiralDrosteFilter(intensity: 2, distortion: 0.2),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GradientMapFilter",
      filter: GradientMapFilter(palette: "Spectral"),
      knownIssue: nil),
    // Нестандартные матрицы из `ReferenceFilterExportTest`, те же коэффициенты.
    AndroidReferenceCase(
      name: "ColorMatrix3x3Filter_custom",
      filter: ColorMatrix3x3Filter(matrix: [
        1.2, -0.1, 0.0,
        0.1, 0.9, 0.05,
        -0.2, 0.3, 1.1,
      ]),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ColorMatrix4x4Filter_custom",
      filter: ColorMatrix4x4Filter(matrix: [
        1.1, 0.0, 0.2, 0.0,
        -0.1, 0.9, 0.0, 0.05,
        0.0, 0.1, 0.8, 0.0,
        0.0, 0.0, 0.0, 1.0,
      ]),
      knownIssue: nil),
  ]
}

/// Разница между двумя картинками по каналам RGB (альфа не сравнивается).
struct ChannelDifference {
  /// Средняя абсолютная разница по всем каналам 0...255.
  let mean: Double
  /// Наибольшая разница одного канала 0...255.
  let maximum: Int
}

func channelDifference(_ output: RasterImage, _ reference: RasterImage) -> ChannelDifference {
  var total = 0
  var maximum = 0
  for index in stride(from: 0, to: output.pixels.count, by: 4) {
    for channel in 0..<3 {
      let delta = abs(Int(output.pixels[index + channel]) - Int(reference.pixels[index + channel]))
      total += delta
      maximum = max(maximum, delta)
    }
  }
  let count = output.width * output.height * 3
  return ChannelDifference(mean: Double(total) / Double(count), maximum: maximum)
}

private func loadReference(_ name: String) throws -> RasterImage {
  let url = try #require(
    Bundle.module.url(
      forResource: name, withExtension: "png", subdirectory: "Fixtures/AndroidReference"))
  let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
  let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  return try #require(RasterImage(image))
}
