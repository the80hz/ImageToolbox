import Foundation

/// Тональная компрессия: ACES (Narkowicz), Hable, Hejl–Burgess, логарифмическая, Uchimura и Drago.
///
/// Android вызывает нативный Aire 0.18.1 (исходники открыты: github.com/awxkee/aire). Все шесть
/// операторов совпадают с эталоном Android (FILTERS.md, раздел 10). ACES Hill не перенесён.
enum ToneMappingFilters {
  static let descriptors: [FilterDescriptor] = [
    descriptor(
      id: "AcesFilmicToneMappingFilter", titleKey: "aces_filmic_tone_mapping",
      range: -4...4, defaultValue: 1
    ) { AcesFilmicFilter(exposure: $0) },
    descriptor(
      id: "HableFilmicToneMappingFilter", titleKey: "hable_filmic_tone_mapping",
      range: -4...4, defaultValue: 1
    ) { HableFilmicFilter(exposure: $0) },
    descriptor(
      id: "HejlBurgessToneMappingFilter", titleKey: "heji_burgess_tone_mapping",
      range: 0...4, defaultValue: 1
    ) { HejlBurgessFilter(exposure: $0) },
    descriptor(
      id: "LogarithmicToneMappingFilter", titleKey: "logarithmic_tone_mapping",
      range: 0...4, defaultValue: 1
    ) { LogarithmicFilter(exposure: $0) },
    descriptor(
      id: "UchimuraFilter", titleKey: "uchimura",
      range: 0...2, defaultValue: 1
    ) { UchimuraFilter(scale: $0) },
    FilterDescriptor(
      id: "DragoFilter",
      titleKey: "drago",
      category: .toneMapping,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "exposure", titleKey: "exposure",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 1)),
        FilterParameter(
          key: "threshold", titleKey: "threshold",
          kind: .number(range: 0...500, step: 1, defaultValue: 250)),
      ],
      make: { DragoFilter(scale: $0.number("exposure"), whitePoint: $0.number("threshold")) }
    ),
  ]

  /// Один параметр `value`, множитель линейного значения (`exposure` в Aire).
  private static func descriptor(
    id: String,
    titleKey: String,
    range: ClosedRange<Double>,
    defaultValue: Double,
    make: @escaping @Sendable (Double) -> any Filter
  ) -> FilterDescriptor {
    FilterDescriptor(
      id: id,
      titleKey: titleKey,
      category: .toneMapping,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: titleKey,
          kind: .number(range: range, step: 0.01, defaultValue: defaultValue))
      ],
      make: { make($0.number("value")) }
    )
  }
}

/// Преобразования между sRGB и линейными значениями для Uchimura (в `Double`).
private enum ToneColour {
  static func linear(_ encoded: Double) -> Double {
    encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
  }

  static func encoded(_ linear: Double) -> Double {
    let clamped = min(max(linear, 0), 1)
    return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
  }

  /// Применяет оператор к каждому каналу в линейных значениях и возвращает sRGB-байты (усечением).
  /// Альфа сохраняется, цвет остаётся premultiplied, как в `RasterImage`.
  static func apply(_ image: RasterImage, _ operatorCurve: (Double) -> Double) -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Double(pixels[index + 3]) / 255
      guard alpha > 0 else { continue }
      for channel in 0..<3 {
        let straight = min(1, Double(pixels[index + channel]) / 255 / alpha)
        let output = encoded(operatorCurve(linear(straight)))
        pixels[index + channel] = UInt8((min(1, max(0, output)) * alpha * 255).rounded(.towardZero))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Оператор Aire, заданный в линейных значениях sRGB. Aire обрабатывает строку блоками по 4 пикселя
/// (SIMD) и добивает хвост скалярным кодом; у некоторых операторов эти два пути считают по-разному.
private protocol AireToneOperator {
  /// Путь блоков по 4 пикселя.
  func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float)
  /// Путь хвоста строки: последние 1...4 пикселя.
  func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float)
}

/// `aire::convolveToneMapper` (Aire 0.18.1, `color/ConvolveToneMapper.cpp`): sRGB в линейный вид,
/// оператор, обратно в sRGB, умножение на 255 и запись в байт усечением.
///
/// Работает с сохранёнными (premultiplied) байтами, как Aire с `Bitmap` Android; альфа не меняется.
/// Блоки по 4 пикселя покрывают `4 * ((width - 1) / 4)` первых пикселей строки, остальные идут
/// скалярным путём (цикл `for (; x + 4 < width; x += 4)`).
///
/// Деление на 255 в Aire — `ApproximateReciprocal` (NEON `FRECPE`), а не точное деление; так же
/// считаются `1 / 12.92` и `1 / 1.055` в `SRGBToLinear` (`color/eotf-inl.h`), порог линейного
/// участка там 0.045. Степени и логарифмы SIMD-кода Aire (Sleef, многочлен `Lognf`) отличаются от
/// libm на единицы последнего разряда `Float`, это не меняет байт.
private enum AireToneMapper {
  static let reciprocal255 = NEONEmulation.reciprocalEstimate(255)
  static let reciprocalOfLinearDivisor = NEONEmulation.reciprocalEstimate(12.92)
  static let reciprocalOfGammaScale = NEONEmulation.reciprocalEstimate(1.055)
  static let inverseGamma = 1 / Float(2.4)

  static func linear(_ encoded: Float) -> Float {
    if encoded <= 0.045 { return encoded * reciprocalOfLinearDivisor }
    return powf((encoded + 0.055) * reciprocalOfGammaScale, 2.4)
  }

  /// Векторная и скалярная ветки отличаются только слиянием умножения со сложением.
  static func encoded(_ linear: Float, fused: Bool) -> Float {
    if linear <= 0.0031308 { return linear * 12.92 }
    let power = powf(linear, inverseGamma)
    return fused ? fmaf(power, 1.055, -0.055) : 1.055 * power - 0.055
  }

  /// Float -> байт, как `std::clamp(x * 255, 0, 255)` и приведение к `uint8_t`; `NaN` даёт 0.
  static func byte(_ value: Float) -> UInt8 {
    let scaled = value * 255
    guard scaled > 0 else { return 0 }
    return scaled >= 255 ? 255 : UInt8(scaled)
  }

  static func apply<Operator: AireToneOperator>(
    _ image: RasterImage, _ toneOperator: Operator
  ) -> RasterImage {
    let width = image.width
    let vectorEnd = width > 0 ? (width - 1) / 4 * 4 : 0
    var pixels = image.pixels
    pixels.withUnsafeMutableBufferPointer { buffer in
      for row in 0..<image.height {
        for column in 0..<width {
          let index = (row * width + column) * 4
          let isVector = column < vectorEnd
          var red = linear(Float(buffer[index]) * reciprocal255)
          var green = linear(Float(buffer[index + 1]) * reciprocal255)
          var blue = linear(Float(buffer[index + 2]) * reciprocal255)
          if isVector {
            toneOperator.vector(&red, &green, &blue)
          } else {
            toneOperator.tail(&red, &green, &blue)
          }
          buffer[index] = byte(encoded(red, fused: isVector))
          buffer[index + 1] = byte(encoded(green, fused: isVector))
          buffer[index + 2] = byte(encoded(blue, fused: isVector))
        }
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// ACES filmic, приближение Narkowicz: `x (2.51 x + 0.03) / (x (2.43 x + 0.59) + 0.14)`, результат
/// ограничен 0...1. `exposure` умножает линейное значение (не `2^exposure`).
///
/// Aire 0.18.1: `color/tone/AcesFilmicToneMapper.hpp`, `ConvolveToneMapper.cpp` (`aire::acesFilm`).
/// Статус: проверено по эталону.
struct AcesFilmicFilter: Filter {
  let exposure: Double

  private struct Operator: AireToneOperator {
    let exposure: Float

    func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red = curve(red * exposure)
      green = curve(green * exposure)
      blue = curve(blue * exposure)
    }

    func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      vector(&red, &green, &blue)
    }

    private func curve(_ x: Float) -> Float {
      let numerator = fmaf(2.51, x, 0.03) * x
      let denominator = fmaf(x, fmaf(2.43, x, 0.59), 0.14)
      return min(max(numerator / denominator, 0), 1)
    }
  }

  func apply(to image: RasterImage) async throws -> RasterImage {
    AireToneMapper.apply(image, Operator(exposure: Float(exposure)))
  }
}

/// Кривая Hable (Uncharted 2): `(x (0.15 x + 0.05) + 0.004) / (x (0.15 x + 0.5) + 0.06) - 1/15`,
/// без нормировки на белую точку. `exposure` умножает линейное значение (не `2^exposure`).
///
/// Aire 0.18.1: `color/tone/HableFilmicToneMapper.hpp`, `ConvolveToneMapper.cpp`
/// (`aire::hableFilmic`).
/// Статус: проверено по эталону.
struct HableFilmicFilter: Filter {
  let exposure: Double

  private struct Operator: AireToneOperator {
    let exposure: Float

    func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red = curve(red * exposure)
      green = curve(green * exposure)
      blue = curve(blue * exposure)
    }

    func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      vector(&red, &green, &blue)
    }

    private func curve(_ x: Float) -> Float {
      let shoulder: Float = 0.15
      let linear: Float = 0.50
      let angle: Float = 0.10
      let toeStrength: Float = 0.20
      let toeNumerator: Float = 0.02
      let toeDenominator: Float = 0.30
      let numerator = fmaf(x, fmaf(shoulder, x, angle * linear), toeStrength * toeNumerator)
      let denominator = fmaf(x, fmaf(x, shoulder, linear), toeStrength * toeDenominator)
      return numerator / denominator - toeNumerator / toeDenominator
    }
  }

  func apply(to image: RasterImage) async throws -> RasterImage {
    AireToneMapper.apply(image, Operator(exposure: Float(exposure)))
  }
}

/// Кривая Hejl–Burgess: `x = max(0, c e - offset)`, `x (6.2 x + 0.5) / (x (6.2 x + 1.7) + 0.06)`,
/// затем степень 2.4 (после неё общий путь Aire снова кодирует в sRGB). `exposure` умножает
/// линейное значение (не `2^exposure`).
///
/// В Aire смещение `offset` разное: 0.0004 в блоках по 4 пикселя и 0.004 в скалярном хвосте строки
/// (`color/tone/HejlBurgessToneMapper.hpp`), поэтому последние пиксели строки считаются иначе.
/// Aire 0.18.1, `ConvolveToneMapper.cpp` (`aire::hejlBurgess`).
/// Статус: проверено по эталону.
struct HejlBurgessFilter: Filter {
  let exposure: Double

  private struct Operator: AireToneOperator {
    let exposure: Float

    func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red = curve(red, offset: 0.0004)
      green = curve(green, offset: 0.0004)
      blue = curve(blue, offset: 0.0004)
    }

    func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red = curve(red, offset: 0.004)
      green = curve(green, offset: 0.004)
      blue = curve(blue, offset: 0.004)
    }

    private func curve(_ value: Float, offset: Float) -> Float {
      let x = max(0, value * exposure - offset)
      let numerator = x * fmaf(x, 6.2, 0.5)
      let denominator = fmaf(x, fmaf(x, 6.2, 1.7), 0.06)
      return powf(numerator / denominator, 2.4)
    }
  }

  func apply(to image: RasterImage) async throws -> RasterImage {
    AireToneMapper.apply(image, Operator(exposure: Float(exposure)))
  }
}

/// Логарифмическая компрессия яркости: `L' = ln(1 + L e) / ln(1 + e)` для яркости
/// `L = 0.299 r + 0.587 g + 0.114 b`, каналы умножаются на `L' / L`. `exposure` — множитель
/// линейного значения (не `2^exposure`).
///
/// Aire 0.18.1: `color/tone/LogarithmicToneMapper.hpp`, `ConvolveToneMapper.cpp`
/// (`aire::logarithmic`).
/// Статус: проверено по эталону.
struct LogarithmicFilter: Filter {
  let exposure: Double

  private struct Operator: AireToneOperator {
    let exposure: Float
    /// `1 / ln(1 + Lmax e)` при `Lmax = 1`.
    let denominator: Float

    init(exposure: Float) {
      self.exposure = exposure
      denominator = 1 / logf(1 + exposure)
    }

    func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red *= exposure
      green *= exposure
      blue *= exposure
      let luma = red * 0.299 + green * 0.587 + blue * 0.114
      let mapped = logf(abs(luma + 1)) * denominator
      let scale = mapped / (luma == 0 ? 1 : luma)
      red *= scale
      green *= scale
      blue *= scale
    }

    func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red *= exposure
      green *= exposure
      blue *= exposure
      let luma = red * 0.299 + green * 0.587 + blue * 0.114
      guard luma != 0 else { return }
      let scale = logf(abs(1 + luma)) * denominator / luma
      red *= scale
      green *= scale
      blue *= scale
    }
  }

  func apply(to image: RasterImage) async throws -> RasterImage {
    AireToneMapper.apply(image, Operator(exposure: Float(exposure)))
  }
}

/// Uchimura's GT curve (CEDEC 2017) with the constants P = 1, a = 1, m = 0.22, l = 0.4, c = 1.33,
/// b = 0, as in Aire 0.18.1 (`UchimuraToneMapper.hpp`, `ConvolveToneMapper.cpp`, `aire::uchimura`).
/// `scale` is Android `exposure` and multiplies the linear input before the curve (no 2^x).
///
/// Aire writes the byte by truncation, not rounding; that is what makes the result match.
/// Статус: проверено по эталону.
struct UchimuraFilter: Filter {
  let scale: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let peak = 1.0
    let contrast = 1.0
    let start = 0.22
    let length = 0.4
    let toe = 1.33
    let pedestal = 0.0
    let l0 = (peak - start) * length / contrast
    let s0 = start + l0
    let s1 = start + contrast * l0
    let c2 = contrast * peak / (peak - s1)
    let cp = -c2 / peak
    return ToneColour.apply(image) { x in
      let v = x * scale
      let w0 = 1 - Self.smoothstep(0, start, v)
      let w2 = v >= start + l0 ? 1.0 : 0.0
      let w1 = 1 - w0 - w2
      let toeValue = start * pow(v / start, toe) + pedestal
      let linearValue = start + contrast * (v - start)
      let shoulder = peak - (peak - s1) * exp(cp * (v - s0))
      return toeValue * w0 + linearValue * w1 + shoulder * w2
    }
  }

  private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
  }
}

/// Логарифмическое отображение Drago (Eurographics 2003) по яркости
/// `L = 0.299 r + 0.587 g + 0.114 b` с bias 0.85 и средней яркостью 1: `L' = c1 c2`,
/// `c1 = 0.01 w / log10(1 + w / Lwa')`,
/// `c2 = ln(1 + L / Lwa') / ln(2 + 8 (L / w)^(ln 0.85 / ln 0.5))`, где `w` — белая точка SDR
/// (`threshold` на Android), `Lwa' = 1 / (1 + 0.85 - 0.85)^5`. Каналы умножаются на `L' / L`.
///
/// В хвосте строки Aire берёт `w · exposure`, в блоках по 4 пикселя просто `w`
/// (`color/tone/DragoToneMapper.hpp`); в хвосте цвет без изменения, если масштаб ровно 1. Aire
/// 0.18.1, `ConvolveToneMapper.cpp` (`aire::drago`).
/// Статус: проверено по эталону.
struct DragoFilter: Filter {
  let scale: Double
  let whitePoint: Double

  private struct Operator: AireToneOperator {
    let exposure: Float
    let whitePoint: Float
    let averageLuminance: Float
    let exponent: Float

    init(exposure: Float, whitePoint: Float) {
      self.exposure = exposure
      self.whitePoint = whitePoint
      let bias: Float = 0.85
      averageLuminance = 1 / powf(1 + bias - 0.85, 5)
      exponent = logf(bias) / logf(0.5)
    }

    func vector(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red *= exposure
      green *= exposure
      blue *= exposure
      let luma = red * 0.299 + green * 0.587 + blue * 0.114
      let scale = outputScale(luma: luma, maximum: whitePoint) / (luma == 0 ? 1 : luma)
      red *= scale
      green *= scale
      blue *= scale
    }

    func tail(_ red: inout Float, _ green: inout Float, _ blue: inout Float) {
      red *= exposure
      green *= exposure
      blue *= exposure
      let luma = red * 0.299 + green * 0.587 + blue * 0.114
      let scale = outputScale(luma: luma, maximum: whitePoint * exposure) / luma
      if scale == 1 { return }
      red *= scale
      green *= scale
      blue *= scale
    }

    /// `L'` для яркости `luma` и максимума `maximum`.
    private func outputScale(luma: Float, maximum: Float) -> Float {
      let scaledMaximum = maximum / averageLuminance
      let scaledLuma = luma / averageLuminance
      let first = (0.01 * whitePoint) / log10f(1 + scaledMaximum)
      let second =
        logf(1 + scaledLuma) / logf(fmaf(8, powf(scaledLuma / scaledMaximum, exponent), 2))
      return first * second
    }
  }

  func apply(to image: RasterImage) async throws -> RasterImage {
    AireToneMapper.apply(image, Operator(exposure: Float(scale), whitePoint: Float(whitePoint)))
  }
}
