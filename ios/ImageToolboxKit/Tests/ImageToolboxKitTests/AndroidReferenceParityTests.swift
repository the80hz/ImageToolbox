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
      knownIssue: nil),
    AndroidReferenceCase(
      name: "PixelationFilter", filter: PixelationFilter(size: 25), knownIssue: nil),
    AndroidReferenceCase(
      name: "VignetteFilter",
      filter: VignetteFilter(start: 0.3, end: 0.75, color: .black), knownIssue: nil),
    AndroidReferenceCase(name: "SharpenFilter", filter: SharpenFilter(amount: 1), knownIssue: nil),
    AndroidReferenceCase(
      name: "SaturationFilter",
      filter: SaturationFilter(strength: 2, tonemapping: true),
      knownIssue: nil),
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
    AndroidReferenceCase(
      name: "BrightnessFilter",
      filter: BrightnessFilter(bias: 0.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ContrastFilter",
      filter: ContrastFilter(gain: 2),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GammaFilter",
      filter: GammaFilter(power: 1.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "VibranceFilter",
      filter: VibranceFilter(amount: 3),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "HighlightsAndShadowsFilter",
      filter: HighlightsAndShadowsFilter(shadows: 0.25),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 21.75, наибольшее 110."),
    AndroidReferenceCase(
      name: "BoxBlurFilter",
      filter: BoxBlurFilter(radius: 10),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "MotionBlurFilter",
      filter: MotionBlurFilter(size: 25, degrees: 45, edge: .reflect101),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BokehFilter",
      filter: BokehFilter(size: 6, sides: 6),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "LinearTiltShiftFilter",
      filter: LinearTiltShiftFilter(
        blurRadius: 25, sigma: 10, anchorX: 0.5, anchorY: 0.5, hole: 0.2, degrees: 45),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "RadialTiltShiftFilter",
      filter: RadialTiltShiftFilter(
        blurRadius: 25, sigma: 10, anchorX: 0.5, anchorY: 0.5, hole: 0.2),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FastBlurFilter",
      filter: FastBlurFilter(scale: 0.5, radius: 5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "NativeStackBlurFilter",
      filter: NativeStackBlurFilter(radius: 25),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "MedianBlurFilter",
      filter: MedianBlurFilter(radius: 10),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "TentBlurFilter",
      filter: TentBlurFilter(size: 15),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BilaterialBlurFilter",
      filter: BilaterialBlurFilter(radius: 12, spatialSigma: 10, rangeSigma: 3, edge: .reflect101),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FastBilaterialBlurFilter",
      filter: FastBilaterialBlurFilter(size: 11, spatialSigma: 10, rangeSigma: 3),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "UnsharpFilter",
      filter: UnsharpFilter(intensity: 0.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "CirclePixelationFilter",
      filter: CirclePixelationFilter(size: 24),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 4.513, наибольшее 120."),
    AndroidReferenceCase(
      name: "DiamondPixelationFilter",
      filter: DiamondPixelationFilter(size: 24),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 0.708, наибольшее 15."),
    AndroidReferenceCase(
      name: "ProtanopiaFilter",
      filter: ProtanopiaFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "DeuteranopiaFilter",
      filter: DeuteranopiaFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "TritanopiaFilter",
      filter: TritanopiaFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "AchromatopsiaFilter",
      filter: AchromatopsiaFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ProtonomalyFilter",
      filter: ProtonomalyFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "DeutaromalyFilter",
      filter: DeutaromalyFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "TritonomalyFilter",
      filter: TritonomalyFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "AchromatomalyFilter",
      filter: AchromatomalyFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "AmatorkaFilter",
      filter: LUTPresetFilter(table: "lookup_amatorka", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "KodakFilter",
      filter: LUTPresetFilter(table: "lookup_kodak", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BleachBypassFilter",
      filter: LUTPresetFilter(table: "lookup_bleach_bypass", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "CandlelightFilter",
      filter: LUTPresetFilter(table: "lookup_candlelight", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "CelluloidFilter",
      filter: LUTPresetFilter(table: "lookup_celluloid", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "CoffeeFilter",
      filter: LUTPresetFilter(table: "lookup_coffee", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "DropBluesFilter",
      filter: LUTPresetFilter(table: "lookup_drop_blues", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EdgyAmberFilter",
      filter: LUTPresetFilter(table: "lookup_edgy_amber", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FallColorsFilter",
      filter: LUTPresetFilter(table: "lookup_fall_colors", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FilmStock50Filter",
      filter: LUTPresetFilter(table: "lookup_filmstock_50", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FoggyNightFilter",
      filter: LUTPresetFilter(table: "lookup_foggy_night", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GoldenForestFilter",
      filter: LUTPresetFilter(table: "lookup_golden_forest", intensity: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FloydSteinbergDitheringFilter",
      filter: FloydSteinbergDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FalseFloydSteinbergDitheringFilter",
      filter: FalseFloydSteinbergDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "JarvisJudiceNinkeDitheringFilter",
      filter: JarvisJudiceNinkeDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SierraDitheringFilter",
      filter: SierraDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "TwoRowSierraDitheringFilter",
      filter: TwoRowSierraDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SierraLiteDitheringFilter",
      filter: SierraLiteDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "AtkinsonDitheringFilter",
      filter: AtkinsonDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "StuckiDitheringFilter",
      filter: StuckiDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BurkesDitheringFilter",
      filter: BurkesDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "LeftToRightDitheringFilter",
      filter: LeftToRightDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BayerTwoDitheringFilter",
      filter: BayerTwoDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BayerThreeDitheringFilter",
      filter: BayerThreeDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BayerFourDitheringFilter",
      filter: BayerFourDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BayerEightDitheringFilter",
      filter: BayerEightDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "Clustered2x2DitheringFilter",
      filter: Clustered2x2DitheringFilter(grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "Clustered4x4DitheringFilter",
      filter: Clustered4x4DitheringFilter(grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "Clustered8x8DitheringFilter",
      filter: Clustered8x8DitheringFilter(grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "SimpleThresholdDitheringFilter",
      filter: SimpleThresholdDitheringFilter(threshold: 200, grayScale: false),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "DilationFilter",
      filter: DilationFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ErodeFilter",
      filter: ErodeFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "OpeningFilter",
      filter: OpeningFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ClosingFilter",
      filter: ClosingFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "TopHatFilter",
      filter: TopHatFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "BlackHatFilter",
      filter: BlackHatFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "MorphologicalGradientFilter",
      filter: MorphologicalGradientFilter(size: 25, circle: true),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "AcesFilmicToneMappingFilter",
      filter: AcesFilmicFilter(exposure: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "HableFilmicToneMappingFilter",
      filter: HableFilmicFilter(exposure: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "HejlBurgessToneMappingFilter",
      filter: HejlBurgessFilter(exposure: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "LogarithmicToneMappingFilter",
      filter: LogarithmicFilter(exposure: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "UchimuraFilter",
      filter: UchimuraFilter(scale: 1),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "DragoFilter",
      filter: DragoFilter(scale: 1, whitePoint: 250),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EqualizeFilter",
      filter: EqualizeFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EqualizeHistogramFilter",
      filter: EqualizeHistogramFilter(),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EqualizeHistogramHSVFilter",
      filter: EqualizeHistogramHSVFilter(bins: 128),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EqualizeHistogramPixelationFilter",
      filter: EqualizeHistogramPixelationFilter(gridX: 50, gridY: 50),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "ClaheFilter",
      filter: ClaheFilter(threshold: 0.5, gridX: 8, gridY: 8),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "EqualizeHistogramAdaptiveFilter",
      filter: EqualizeHistogramAdaptiveFilter(gridX: 3, gridY: 3),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "FishEyeFilter",
      filter: FishEyeFilter(radius: 70, amplitude: 1),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 8.189, наибольшее 62."),
    AndroidReferenceCase(
      name: "TwirlFilter",
      filter: TwirlFilter(angle: 45, centreX: 0.5, centreY: 0.5, radius: 0.5),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "PinchFilter",
      filter: PinchFilter(angle: 15, centreX: 0.5, centreY: 0.5, radius: 1, amount: 0.5),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 6.573, наибольшее 37."),
    AndroidReferenceCase(
      name: "KaleidoscopeFilter",
      filter: KaleidoscopeFilter(
        angle: 0, secondaryAngle: 0, centreX: 0.5, centreY: 0.5, sides: 5, radius: 0),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 8.054, наибольшее 41."),
    AndroidReferenceCase(
      name: "RippleFilter",
      filter: RippleFilter(xAmplitude: 5, xWavelength: 16, yAmplitude: 5, yWavelength: 16),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 22.00, наибольшее 252."),
    AndroidReferenceCase(
      name: "GlitchFilter",
      filter: GlitchFilter(amount: 20, seed: 15, iterations: 9),
      knownIssue: "Приближение, расхождение с эталоном Android: среднее 81.18, наибольшее 255."),
    AndroidReferenceCase(
      name: "GaussianBlurFilter_r5",
      filter: GaussianBlurFilter(radius: 5, sigma: 2, edge: .reflect101),
      knownIssue: nil),
    AndroidReferenceCase(
      name: "GaussianBlurFilter_r40",
      filter: GaussianBlurFilter(radius: 40, sigma: 15, edge: .reflect101),
      knownIssue: nil
    ),
    AndroidReferenceCase(
      name: "LevelsFilter_custom",
      filter: LevelsFilter(lowInput: 0.1, highInput: 0.9, lowOutput: 0.2, highOutput: 0.8),
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
