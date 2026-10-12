import CoreImage
import Foundation

/// Яркость, контраст, цвет и светотень. Android: пакет `data/model`, классы `*Filter`.
///
/// Статус каждого фильтра и источник формулы записаны рядом с его структурой. Aire, GPUImage и
/// Jh Labs в репозитории нет, формулы взяты из их публичных исходников; фильтры без пометки
/// «проверено по эталону» остаются приближениями на встроенных фильтрах Core Image.
enum LightColourFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "BrightnessFilter",
      titleKey: "brightness",
      category: .lightAndColour,
      engine: .coreImage,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "brightness",
          kind: .number(range: -1...1, step: 0.01, defaultValue: 0.5))
      ],
      make: { BrightnessFilter(bias: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "ContrastFilter",
      titleKey: "contrast",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "contrast",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 2))
      ],
      make: { ContrastFilter(gain: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "NegativeFilter",
      titleKey: "negative",
      category: .lightAndColour,
      engine: .coreImage,
      make: { _ in NegativeFilter() }
    ),
    FilterDescriptor(
      id: "GammaFilter",
      titleKey: "gamma",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "gamma",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 1))
      ],
      keywords: ["power"],
      make: { GammaFilter(power: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "ExposureFilter",
      titleKey: "exposure",
      category: .lightAndColour,
      engine: .coreImage,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "exposure",
          kind: .number(range: -4...4, step: 0.01, defaultValue: 1))
      ],
      keywords: ["EV", "stops"],
      make: { ExposureFilter(stops: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "HueFilter",
      titleKey: "hue",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "hue",
          kind: .number(range: 0...255, step: 0.01, defaultValue: 90))
      ],
      keywords: ["rotation", "angle"],
      make: { HueFilter(degrees: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "SaturationFilter",
      titleKey: "saturation",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "strength", titleKey: "strength",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 2)),
        FilterParameter(
          key: "enableTonemapping", titleKey: "enable_tonemapping",
          kind: .flag(defaultValue: true)),
      ],
      keywords: ["colour intensity"],
      make: {
        SaturationFilter(strength: $0.number("strength"), tonemapping: $0.flag("enableTonemapping"))
      }
    ),
    FilterDescriptor(
      id: "VibranceFilter",
      titleKey: "vibrance",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "vibrance",
          kind: .number(range: -5...5, step: 0.01, defaultValue: 3))
      ],
      make: { VibranceFilter(amount: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "WhiteBalanceFilter",
      titleKey: "white_balance",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "temperature", titleKey: "temperature",
          kind: .number(range: 1000...10000, step: 1, defaultValue: 7000)),
        FilterParameter(
          key: "tint", titleKey: "tint",
          kind: .number(range: -100...100, step: 0.01, defaultValue: 100)),
      ],
      keywords: ["temperature", "tint", "colour temperature"],
      make: {
        WhiteBalanceFilter(temperature: $0.number("temperature"), tint: $0.number("tint"))
      }
    ),
    FilterDescriptor(
      id: "LevelsFilter",
      titleKey: "levels",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "lowInput", titleKey: "low_input",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0)),
        FilterParameter(
          key: "highInput", titleKey: "high_input",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 1)),
        FilterParameter(
          key: "lowOutput", titleKey: "low_output",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0)),
        FilterParameter(
          key: "highOutput", titleKey: "high_output",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 1)),
      ],
      make: {
        LevelsFilter(
          lowInput: $0.number("lowInput"), highInput: $0.number("highInput"),
          lowOutput: $0.number("lowOutput"), highOutput: $0.number("highOutput"))
      }
    ),
    FilterDescriptor(
      id: "HighlightsAndShadowsFilter",
      titleKey: "highlights_shadows",
      category: .lightAndColour,
      engine: .coreImage,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "highlights_shadows",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 0.25))
      ],
      keywords: ["shadows", "highlights"],
      make: { HighlightsAndShadowsFilter(shadows: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "BlackAndWhiteFilter",
      titleKey: "black_and_white",
      category: .lightAndColour,
      engine: .coreImage,
      keywords: ["grayscale", "greyscale", "monochrome", "luminance"],
      make: { _ in BlackAndWhiteFilter() }
    ),
    FilterDescriptor(
      id: "SepiaFilter",
      titleKey: "sepia",
      category: .lightAndColour,
      engine: .cpu,
      keywords: ["vintage", "brown"],
      make: { _ in SepiaFilter() }
    ),
    FilterDescriptor(
      id: "PosterizeFilter",
      titleKey: "posterize",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "posterize",
          kind: .number(range: 1...40, step: 1, defaultValue: 5))
      ],
      keywords: ["levels", "quantize"],
      make: { PosterizeFilter(levels: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "SolarizeFilter",
      titleKey: "solarize",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "solarize",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5))
      ],
      keywords: ["threshold", "invert"],
      make: { SolarizeFilter(threshold: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "SimpleSolarizeFilter",
      titleKey: "simple_solarize",
      category: .lightAndColour,
      engine: .cpu,
      make: { _ in SimpleSolarizeFilter() }
    ),
    FilterDescriptor(
      id: "VignetteFilter",
      titleKey: "vignette",
      category: .lightAndColour,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "start", titleKey: "start",
          kind: .number(range: -2...2, step: 0.01, defaultValue: 0.3)),
        FilterParameter(
          key: "end", titleKey: "end",
          kind: .number(range: -2...2, step: 0.01, defaultValue: 0.75)),
        FilterParameter(
          key: "color", titleKey: "color", kind: .color(defaultValue: .black)),
      ],
      keywords: ["corners", "dark edges"],
      make: {
        VignetteFilter(start: $0.number("start"), end: $0.number("end"), color: $0.color("color"))
      }
    ),
  ]
}

/// Adds `bias` to every colour channel, clamped to the range of the picture.
///
/// Статус: проверено по эталону (`BrightnessFilter`, раздел 10: среднее 0.010, наибольшее 1).
struct BrightnessFilter: Filter {
  let bias: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let offset = CGFloat(bias)
    return try CoreImageBridge.render(image, filterID: "BrightnessFilter") { input in
      input.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: offset, y: offset, z: offset, w: 0),
        ])
    }
  }
}

/// Scales each channel around the middle grey 0.5 by `gain`. A gain of 1 may still lower some
/// channels by one level, because Aire truncates the `Float` result.
///
/// As Aire 0.18.1 `aire::adjustment` (`color/Adjustments.cpp`, bias 0): `gain * (c / 255 - 0.5) + 0.5`
/// in `Float`, clamped, written to the byte by truncation. Applied to the stored (premultiplied)
/// channels, alpha is kept.
/// Статус: проверено по эталону.
struct ContrastFilter: Filter {
  let gain: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let factor = Float(gain)
    var pixels = image.pixels
    for index in pixels.indices where index % 4 != 3 {
      let value = factor * (Float(pixels[index]) / 255 - 0.5) + 0.5
      pixels[index] = UInt8(min(max(value * 255, 0), 255))
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Inverts every colour channel and keeps alpha.
struct NegativeFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try CoreImageBridge.render(image, filterID: "NegativeFilter") { input in
      input.applyingFilter("CIColorInvert")
    }
  }
}

/// Android: `Aire.gamma` (Aire 0.18.1, `jni/Base.cpp`, `gammaImpl`). Таблица на 256 значений:
/// `powf(i, power)` от самого байта `i` (0...255, не от доли 0...1), ограничение 0...255 и запись в
/// байт усечением. Поэтому `power` = 1 тождество, больше 1 почти белая картинка (все значения от 41
/// и выше дают 255), меньше 1 тёмная. Таблица применяется к сохранённым (premultiplied) R, G, B,
/// альфа не меняется.
/// Статус: проверено по эталону.
struct GammaFilter: Filter {
  let power: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let exponent = Float(power)
    let table = (0..<256).map { byte -> UInt8 in
      let value = powf(Float(byte), exponent)
      return value.isNaN ? 0 : UInt8(min(max(value, 0), 255))
    }
    var pixels = image.pixels
    for index in pixels.indices where index % 4 != 3 {
      pixels[index] = table[Int(pixels[index])]
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `GPUImageExposureFilter`, по формуле GPUImage `out = in * 2^EV`.
/// Проверено по эталону (`ExposureFilter`, раздел 10): совпадение точное.
struct ExposureFilter: Filter {
  /// Exposure in stops (EV). Each stop doubles or halves the brightness.
  let stops: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = CGFloat(pow(2, stops))
    return try CoreImageBridge.render(image, filterID: "ExposureFilter") { input in
      input.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }
  }
}

/// Поворот оттенка по шейдеру GPUImage `HUE_FRAGMENT_SHADER`: цвет переводится в YIQ, фаза
/// поворачивается на `-hueAdjust`, затем результат возвращается в RGB. `setHue` в Java берёт остаток
/// от деления угла на 360 и переводит его в радианы во float32.
///
/// Статус: проверено по эталону (`HueFilter`, раздел 10).
struct HueFilter: Filter {
  let degrees: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let adjust = Float(degrees).truncatingRemainder(dividingBy: 360) * 3.1415927 / 180
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Float(pixels[index]) / 255
      let green = Float(pixels[index + 1]) / 255
      let blue = Float(pixels[index + 2]) / 255
      let luma = 0.299 * red + 0.587 * green + 0.114 * blue
      let inphase = 0.595716 * red - 0.274453 * green - 0.321263 * blue
      let quadrature = 0.211456 * red - 0.522591 * green + 0.31135 * blue
      let hue = atan2(quadrature, inphase) - adjust
      let chroma = (inphase * inphase + quadrature * quadrature).squareRoot()
      let rotatedInphase = chroma * cos(hue)
      let rotatedQuadrature = chroma * sin(hue)
      let channels: [Float] = [
        luma + 0.9563 * rotatedInphase + 0.6210 * rotatedQuadrature,
        luma - 0.2721 * rotatedInphase - 0.6474 * rotatedQuadrature,
        luma - 1.1070 * rotatedInphase + 1.7046 * rotatedQuadrature,
      ]
      for channel in 0..<3 {
        pixels[index + channel] = UInt8(min(max(channels[channel] * 255, 0), 255).rounded())
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Повторяет `Aire.saturation` (Rust, `aire-filters/src/palette.rs`): sRGB переводится в линейный
/// RGB и в Oklab, компоненты `a` и `b` умножаются на `strength`, затем обратно в линейный RGB.
/// При включённом `tonemapping` линейный RGB дополнительно проходит через кривую ACES (Hill), после
/// чего значения ограничиваются диапазоном 0...1. В sRGB результат записывается с отбрасыванием
/// дробной части (не округлением): с округлением эталон Android не совпадает. Альфа не меняется.
///
/// Статус: проверено по эталону (`SaturationFilter`, разделы 7 и 10).
struct SaturationFilter: Filter {
  let strength: Double
  let tonemapping: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    let decode = (0...255).map { srgbToLinear(Double($0) / 255) }
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = decode[Int(pixels[index])]
      let green = decode[Int(pixels[index + 1])]
      let blue = decode[Int(pixels[index + 2])]
      let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
      let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
      let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
      let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
      let a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) * strength
      let b = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) * strength
      let l3 = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
      let m3 = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
      let s3 = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
      var linear = [
        4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
        -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
        -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
      ]
      if tonemapping {
        linear = acesHill(linear)
      }
      for channel in 0..<3 {
        let encoded = linearToSRGB(min(max(linear[channel], 0), 1))
        pixels[index + channel] = UInt8(min(max(encoded * 255, 0), 255))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }

  /// Аппроксимация ACES по Hill: входная матрица, рациональная кривая, выходная матрица.
  private func acesHill(_ c: [Double]) -> [Double] {
    let input = [
      0.59719 * c[0] + 0.35458 * c[1] + 0.04823 * c[2],
      0.07600 * c[0] + 0.90834 * c[1] + 0.01566 * c[2],
      0.02840 * c[0] + 0.13383 * c[1] + 0.83777 * c[2],
    ]
    let v = input.map { x in
      (x * (x + 0.0245786) - 0.000090537) / (x * (0.983729 * x + 0.4329510) + 0.238081)
    }
    return [
      1.60475 * v[0] - 0.53108 * v[1] - 0.07367 * v[2],
      -0.10208 * v[0] + 1.10813 * v[1] - 0.00605 * v[2],
      -0.00327 * v[0] - 0.07276 * v[1] + 1.07602 * v[2],
    ]
  }

  private func srgbToLinear(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  private func linearToSRGB(_ value: Double) -> Double {
    value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
  }
}

/// Android: `Aire.vibrance` (Aire 0.18.1, `base/Vibrance.cpp`). Не насыщенность, а сдвиг яркости:
/// `boost = trunc(clamp((max(R, G, B) - (R + G + B) / 3) * amount, -255, 255))`, где среднее
/// целочисленное, и `boost` прибавляется к R, G и B с ограничением 0...255. Считается по
/// сохранённым (premultiplied) байтам, альфа не меняется.
/// Статус: проверено по эталону.
struct VibranceFilter: Filter {
  let amount: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let factor = Float(amount)
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Int(pixels[index])
      let green = Int(pixels[index + 1])
      let blue = Int(pixels[index + 2])
      let average = (red + green + blue) / 3
      let spread = Float(max(red, green, blue) - average) * factor
      let boost = Int(min(max(spread, -255), 255))
      pixels[index] = UInt8(min(max(red + boost, 0), 255))
      pixels[index + 1] = UInt8(min(max(green + boost, 0), 255))
      pixels[index + 2] = UInt8(min(max(blue + boost, 0), 255))
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Баланс белого по шейдеру GPUImage `WHITE_BALANCE_FRAGMENT_SHADER`: сдвиг тона в YIQ и
/// смешивание с тёплым фильтром. Параметры переводятся как `setTemperature` и `setTint` в Java:
/// температура ниже 5000 K — `0.0004 * (T - 5000)`, иначе `0.00006 * (T - 5000)`; тон делится на 100.
///
/// Статус: проверено по эталону (`WhiteBalanceFilter`, раздел 10). Матрицы в GLSL заданы по
/// столбцам, поэтому коэффициенты ниже записаны по строкам результата.
struct WhiteBalanceFilter: Filter {
  let temperature: Double
  let tint: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let warmth = Float(
      temperature < 5000 ? 0.0004 * (temperature - 5000) : 0.00006 * (temperature - 5000))
    let tintUniform = Float(tint / 100)
    let warm: [Float] = [0.93, 0.54, 0]
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Float(pixels[index]) / 255
      let green = Float(pixels[index + 1]) / 255
      let blue = Float(pixels[index + 2]) / 255
      let luma = 0.299 * red + 0.596 * green + 0.212 * blue
      let inphase = 0.587 * red - 0.274 * green - 0.523 * blue
      let quadrature = min(
        max(0.114 * red - 0.322 * green + 0.311 * blue + tintUniform * 0.5226 * 0.1, -0.5226),
        0.5226)
      let rgb: [Float] = [
        luma + inphase + quadrature,
        0.956 * luma - 0.272 * inphase - 1.105 * quadrature,
        0.621 * luma - 0.647 * inphase + 1.702 * quadrature,
      ]
      for channel in 0..<3 {
        let value = rgb[channel]
        let processed =
          value < 0.5
          ? 2 * value * warm[channel] : 1 - 2 * (1 - value) * (1 - warm[channel])
        let mixed = value * (1 - warmth) + processed * warmth
        pixels[index + channel] = UInt8(min(max(mixed * 255, 0), 255).rounded())
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: Jh Labs `LevelsFilter` (T8RIN/ImageToolboxLibs 8.1.0, `libs/jhlabs/src/main/rust/jhlabs/src/lib.rs`,
/// ветка `"LevelsFilter"` и `transfer`). Таблица на 256 значений в `Float`:
/// `lowOutput + (highOutput - lowOutput) * (v - lowInput) / (highInput - lowInput)`, `v` = байт / 255.
/// Без ограничения позиции: результат `255 * f(v)` отбрасывает дробную часть и только потом ограничивается
/// 0...255. Если `lowInput == highInput`, к `highInput` прибавляется 1/255.
/// Статус: проверено по эталону.
struct LevelsFilter: Filter {
  let lowInput: Double
  let highInput: Double
  let lowOutput: Double
  let highOutput: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let low = Float(lowInput)
    let high = lowInput == highInput ? Float(highInput) + 1 / 255 : Float(highInput)
    let outputLow = Float(lowOutput)
    let outputHigh = Float(highOutput)
    let table = (0..<256).map { byte -> UInt8 in
      let value = Float(byte) / 255
      let mapped = outputLow + (outputHigh - outputLow) * (value - low) / (high - low)
      // Rust `as i32` truncates toward zero and saturates; NaN becomes 0.
      let scaled = mapped.isNaN ? 0 : max(min(255 * mapped, 1000), -1000)
      return UInt8(min(max(Int(scaled), 0), 255))
    }
    var pixels = image.pixels
    for index in pixels.indices where index % 4 != 3 {
      pixels[index] = table[Int(pixels[index])]
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Приближение. Android: `GPUImageHighlightShadowWideRangeFilter(value, 1)`, где `value` задаёт
/// тени. Алгоритм GPUImage в репозитории отсутствует. Используется `CIHighlightShadowAdjust` с
/// тенями `value` и светами 1 (без изменения). Ноль не меняет картинку.
struct HighlightsAndShadowsFilter: Filter {
  let shadows: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let shadowAmount = Float(shadows)
    return try CoreImageBridge.render(image, filterID: "HighlightsAndShadowsFilter") { input in
      input.applyingFilter(
        "CIHighlightShadowAdjust",
        parameters: [
          "inputShadowAmount": shadowAmount,
          "inputHighlightAmount": Float(1),
        ])
    }
  }
}

/// Android: `GPUImageLuminanceFilter`, шейдер GPUImage 8.1.0: яркость по весам 0.2125, 0.7154,
/// 0.0721, каждый канал получает её. Сверка с эталоном: отличие не больше 1 уровня (среднее 0.006).
struct BlackAndWhiteFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try CoreImageBridge.render(image, filterID: "BlackAndWhiteFilter") { input in
      input.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 0.2125, y: 0.7154, z: 0.0721, w: 0),
          "inputGVector": CIVector(x: 0.2125, y: 0.7154, z: 0.0721, w: 0),
          "inputBVector": CIVector(x: 0.2125, y: 0.7154, z: 0.0721, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }
  }
}

/// Android: `ColorMatrix3x3Filter(ColorMatrices.SEPIA)`. Матрица взята из AAR Aire 0.18.1
/// (`ColorMatrices.SEPIA`, строки по каналам R, G, B), расчёт общий с `ColorMatrix3x3Filter`.
/// Сверка с эталоном: из 12288 значений 12279 совпали точно, остальные 9 отличаются на 1 уровень.
struct SepiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(
      image, rows: [0.393, 0.769, 0.189, 0.349, 0.686, 0.168, 0.272, 0.534, 0.131])
  }
}

/// Android: `GPUImagePosterizeFilter(levels)`, шейдер GPUImage 8.1.0: каждый канал считается как
/// `floor(c * L + 0.5) / L`, где `L` — число уровней (на Android `value.toInt()`). При `L = 1`
/// канал становится 0 или 1 по порогу 0.5. Сверка с эталоном: точное совпадение.
struct PosterizeFilter: Filter {
  let levels: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let steps = Double(max(Int(levels), 1))
    return mapChannels(image) { value in
      (value * steps + 0.5).rounded(.down) / steps
    }
  }
}

/// Android: `SimpleSolarizeFilter` через `com.jhlabs.SolarizeFilter` (Jh Labs, нативный JNI-код).
/// Формула из Java-метода `transferFunction` в AAR: при `v > 0.5` это `2 * (v - 0.5)`, иначе
/// `2 * (0.5 - v)`, где `v` — канал / 255 во Float. Результат записывается усечением `(int)(f * 255)`.
/// Сверка с эталоном: точное совпадение. Альфа не меняется.
struct SimpleSolarizeFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      for channel in 0..<3 {
        let value = Float(image.pixels[index + channel]) / 255
        let folded: Float = value > 0.5 ? 2 * (value - 0.5) : 2 * (0.5 - value)
        pixels[index + channel] = UInt8(min(max(folded * 255, 0), 255))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `GPUImageSolarizeFilter(threshold)`, шейдер GPUImage 8.1.0. Яркость считается по весам
/// 0.2125, 0.7154, 0.0721. Если она не больше порога, каждый канал инвертируется, иначе пиксель
/// не меняется. Порог 1 инвертирует всё, порог 0 трогает только чёрный. Сверка с эталоном:
/// точное совпадение.
struct SolarizeFilter: Filter {
  let threshold: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Double(image.pixels[index]) / 255
      let green = Double(image.pixels[index + 1]) / 255
      let blue = Double(image.pixels[index + 2]) / 255
      let luminance = 0.2125 * red + 0.7154 * green + 0.0721 * blue
      guard luminance <= threshold else { continue }
      for channel in 0..<3 {
        pixels[index + channel] = 255 - pixels[index + channel]
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `GPUImageVignetteFilter(center, color, start, end)`, шейдер GPUImage 8.1.0:
/// `smoothstep(start, end, distance)` от центра в координатах текстуры (0...1, без поправки на
/// пропорции), края смешиваются с `color`. Сверка с эталоном: отличие не больше 1 уровня
/// (среднее 0.001). Шейдер Android работает в `lowp`, поэтому допуск на 1 уровень сохранён.
struct VignetteFilter: Filter {
  let start: Double
  let end: Double
  let color: FilterColor

  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    let width = image.width
    let tint = [color.red, color.green, color.blue].map { $0 * 255 }
    for y in 0..<image.height {
      for x in 0..<width {
        let dx = (Double(x) + 0.5) / Double(width) - 0.5
        let dy = (Double(y) + 0.5) / Double(image.height) - 0.5
        let distance = (dx * dx + dy * dy).squareRoot()
        let percent = vignetteWeight(distance: distance, start: start, end: end)
        let index = (y * width + x) * 4
        for channel in 0..<3 {
          let source = Double(pixels[index + channel])
          pixels[index + channel] = byte(source * (1 - percent) + tint[channel] * percent)
        }
      }
    }
    return RasterImage(width: width, height: image.height, pixels: pixels)
  }

  /// 0 в центре, 1 у края. Переход сглажен. Если `start` равен `end`, это резкая граница.
  private func vignetteWeight(distance: Double, start: Double, end: Double) -> Double {
    guard end != start else { return distance >= start ? 1 : 0 }
    let t = min(max((distance - start) / (end - start), 0), 1)
    return t * t * (3 - 2 * t)
  }
}

/// Переводит значение 0...1 в байт с округлением и ограничением.
private func byte(_ value: Double) -> UInt8 {
  UInt8(min(max(value.rounded(), 0), 255))
}

/// Применяет `transform` к каждому цветовому каналу через таблицу из 256 значений. Альфа не меняется.
/// Для непрозрачных картинок вход и выход — обычные значения RGB.
private func mapChannels(_ image: RasterImage, _ transform: (Double) -> Double) -> RasterImage {
  let table = (0...255).map { level in
    byte(min(max(transform(Double(level) / 255), 0), 1) * 255)
  }
  var pixels = image.pixels
  for index in stride(from: 0, to: pixels.count, by: 4) {
    for channel in 0..<3 {
      pixels[index + channel] = table[Int(pixels[index + channel])]
    }
  }
  return RasterImage(width: image.width, height: image.height, pixels: pixels)
}
