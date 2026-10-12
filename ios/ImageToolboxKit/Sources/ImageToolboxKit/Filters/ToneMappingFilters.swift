import Foundation

/// Тональная компрессия: ACES (Narkowicz), Hable, Hejl–Burgess, логарифмическая, Uchimura и Drago.
///
/// Android вызывает нативный Aire 0.18.1 (исходники открыты: github.com/awxkee/aire). Uchimura сверен
/// с эталоном Android. Остальные операторы — приближения по опубликованным описаниям, с эталоном
/// расходятся (FILTERS.md, раздел 10). ACES Hill не перенесён.
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

  /// Один параметр `value`, который задаёт экспозицию в ступенях EV (2^value).
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

/// Преобразования между sRGB и линейными значениями, общие для операторов.
private enum ToneColour {
  static func linear(_ encoded: Double) -> Double {
    encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
  }

  static func encoded(_ linear: Double) -> Double {
    let clamped = min(max(linear, 0), 1)
    return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
  }

  /// Применяет оператор к каждому каналу в линейных значениях и возвращает sRGB-байты.
  /// Альфа сохраняется, цвет остаётся premultiplied, как в `RasterImage`.
  static func apply(
    _ image: RasterImage,
    encodeOutput: Bool = true,
    rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero,
    _ operatorCurve: (Double) -> Double
  ) -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Double(pixels[index + 3]) / 255
      guard alpha > 0 else { continue }
      for channel in 0..<3 {
        let straight = min(1, Double(pixels[index + channel]) / 255 / alpha)
        let mapped = operatorCurve(linear(straight))
        let output = encodeOutput ? encoded(mapped) : min(max(mapped, 0), 1)
        pixels[index + channel] = UInt8((min(1, max(0, output)) * alpha * 255).rounded(rounding))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// ACES filmic curve, approximation by Krzysztof Narkowicz (2015).
struct AcesFilmicFilter: Filter {
  let exposure: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = pow(2, exposure)
    return ToneColour.apply(image) { x in
      let v = x * scale
      return (v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14)
    }
  }
}

/// Hable's filmic curve (Uncharted 2, GDC 2010), normalised to the white point 11.2.
struct HableFilmicFilter: Filter {
  let exposure: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = pow(2, exposure)
    return ToneColour.apply(image) { x in
      let white = Self.curve(11.2)
      return Self.curve(x * scale * 2) / white
    }
  }

  private static func curve(_ x: Double) -> Double {
    let a = 0.15
    let b = 0.50
    let c = 0.10
    let d = 0.20
    let e = 0.02
    let f = 0.30
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f
  }
}

/// Hejl–Burgess curve (2015). The output is already display-encoded, so it is not converted to sRGB again.
struct HejlBurgessFilter: Filter {
  let exposure: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = pow(2, exposure)
    return ToneColour.apply(image, encodeOutput: false) { x in
      let v = max(0, x * scale - 0.004)
      return (v * (6.2 * v + 0.5)) / (v * (6.2 * v + 1.7) + 0.06)
    }
  }
}

/// Logarithmic compression: log(1 + x) / log(2), so the white point 1 maps to 1.
struct LogarithmicFilter: Filter {
  let exposure: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = pow(2, exposure)
    return ToneColour.apply(image) { x in
      log(1 + x * scale) / log(2)
    }
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
    return ToneColour.apply(image, rounding: .towardZero) { x in
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

/// Drago's logarithmic mapping (Eurographics 2003) with bias 0.85. The white point is `whitePoint / 250`
/// in linear units; the mapping of that threshold to Android's `threshold` is not verified.
struct DragoFilter: Filter {
  let scale: Double
  let whitePoint: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let bias = 0.85
    let maxLuminance = max(whitePoint / 250, 1e-6)
    let power = log(bias) / log(0.5)
    let normaliser = log(10) / log(1 + maxLuminance)
    return ToneColour.apply(image) { x in
      let v = x * scale
      let denominator = log(2 + 8 * pow(v / maxLuminance, power))
      return log(1 + v) / denominator * normaliser
    }
  }
}
