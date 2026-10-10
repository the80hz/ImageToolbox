import CoreImage
import Foundation

/// Яркость, контраст, цвет и светотень. Android: пакет `data/model`, классы `*Filter`.
///
/// Статус каждого фильтра и причина отличий от Android записаны рядом с его структурой.
/// Алгоритмы Aire, GPUImage и Jh Labs в репозитории отсутствуют, поэтому везде, кроме сепии,
/// это приближение на основе встроенных фильтров Core Image или стандартной формулы.
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
      engine: .coreImage,
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
      engine: .coreImage,
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
      engine: .coreImage,
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
      engine: .coreImage,
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
      engine: .coreImage,
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

/// Scales each channel around the middle grey 0.5 by `gain`. A gain of 1 changes nothing.
struct ContrastFilter: Filter {
  let gain: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scale = CGFloat(gain)
    let offset = CGFloat(0.5 - 0.5 * gain)
    return try CoreImageBridge.render(image, filterID: "ContrastFilter") { input in
      input.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: offset, y: offset, z: offset, w: 0),
        ])
    }
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

/// Приближение. Android: `Aire.gamma`. Формула Aire в репозитории отсутствует. Принята
/// `out = in ^ power` через `CIGammaAdjust`, направление параметра не сверено с Android.
struct GammaFilter: Filter {
  let power: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let exponent = Float(power)
    return try CoreImageBridge.render(image, filterID: "GammaFilter") { input in
      input.applyingFilter("CIGammaAdjust", parameters: ["inputPower": exponent])
    }
  }
}

/// Приближение. Android: `GPUImageExposureFilter`, по формуле GPUImage `out = in * 2^EV`.
/// Формула GPUImage в репозитории отсутствует, поэтому она взята как стандартная.
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

/// Приближение. Android: `GPUImageHueFilter`, угол в градусах. Поворот оттенка в HSV на CPU
/// (раньше был `CIHueAdjust`). Единица шкалы Android 0...255 не подтверждена: значение принято
/// как градусы, как и раньше.
struct HueFilter: Filter {
  let degrees: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Double(pixels[index + 3]) / 255
      guard alpha > 0 else { continue }
      let red = min(1, Double(pixels[index]) / 255 / alpha)
      let green = min(1, Double(pixels[index + 1]) / 255 / alpha)
      let blue = min(1, Double(pixels[index + 2]) / 255 / alpha)
      let (hue, saturation, value) = Self.hsv(red: red, green: green, blue: blue)
      let turned = (hue + degrees).truncatingRemainder(dividingBy: 360) + 360
      let rgb = Self.rgb(
        hue: turned.truncatingRemainder(dividingBy: 360), saturation: saturation, value: value)
      pixels[index] = UInt8((rgb.0 * alpha * 255).rounded())
      pixels[index + 1] = UInt8((rgb.1 * alpha * 255).rounded())
      pixels[index + 2] = UInt8((rgb.2 * alpha * 255).rounded())
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }

  /// Hue in degrees 0..<360, saturation and value in 0...1.
  private static func hsv(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    var hue = 0.0
    if delta > 0 {
      if maximum == red {
        hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
      } else if maximum == green {
        hue = 60 * ((blue - red) / delta + 2)
      } else {
        hue = 60 * ((red - green) / delta + 4)
      }
    }
    if hue < 0 { hue += 360 }
    let saturation = maximum == 0 ? 0 : delta / maximum
    return (hue, saturation, maximum)
  }

  private static func rgb(hue: Double, saturation: Double, value: Double) -> (
    Double, Double, Double
  ) {
    let chroma = value * saturation
    let sector = hue / 60
    let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
    let match = value - chroma
    let (r, g, b): (Double, Double, Double)
    switch sector {
    case 0..<1: (r, g, b) = (chroma, second, 0)
    case 1..<2: (r, g, b) = (second, chroma, 0)
    case 2..<3: (r, g, b) = (0, chroma, second)
    case 3..<4: (r, g, b) = (0, second, chroma)
    case 4..<5: (r, g, b) = (second, 0, chroma)
    default: (r, g, b) = (chroma, 0, second)
    }
    return (r + match, g + match, b + match)
  }
}

/// Приближение. Android: `Aire.saturation` (нативный код, в репозитории его нет). Флаг `tonemapping`
/// сохраняется в настройках, но не применяется. Сверка с эталоном (насыщенность 2, tonemap включён):
/// среднее отличие 35.5, максимум 111. Известное расхождение, см. `AndroidReferenceParityTests`.
struct SaturationFilter: Filter {
  let strength: Double
  let tonemapping: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    let saturation = Float(strength)
    return try CoreImageBridge.render(image, filterID: "SaturationFilter") { input in
      input.applyingFilter("CIColorControls", parameters: ["inputSaturation": saturation])
    }
  }
}

/// Приближение. Android: `Aire.vibrance`. Масштаб значения Android неизвестен: принят
/// `amount = value / 5`, чтобы диапазон -5...5 совпал с диапазоном `CIVibrance` -1...1.
struct VibranceFilter: Filter {
  let amount: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let scaled = Float(amount / 5)
    return try CoreImageBridge.render(image, filterID: "VibranceFilter") { input in
      input.applyingFilter("CIVibrance", parameters: ["inputAmount": scaled])
    }
  }
}

/// Приближение. Android: `GPUImageWhiteBalanceFilter(temperature, tint)`. Core Image сдвигает
/// баланс от заданной точки белого (`inputNeutral`) к 6500 K, поэтому шкала отличается от Android.
/// Значение 6500 K и тон 0 дают исходную картинку.
struct WhiteBalanceFilter: Filter {
  let temperature: Double
  let tint: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    return try CoreImageBridge.render(image, filterID: "WhiteBalanceFilter") { input in
      input.applyingFilter(
        "CITemperatureAndTint",
        parameters: [
          "inputNeutral": CIVector(x: CGFloat(temperature), y: CGFloat(tint))
        ])
    }
  }
}

/// Приближение. Android: `Jh Labs LevelsFilter`, четыре значения (вход и выход, низ и верх).
/// Формула Jh Labs в репозитории отсутствует. Принята стандартная линейная растяжка каналов:
/// `out = lowOutput + (highOutput - lowOutput) * clamp((in - lowInput) / (highInput - lowInput))`.
struct LevelsFilter: Filter {
  let lowInput: Double
  let highInput: Double
  let lowOutput: Double
  let highOutput: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let span = highInput - lowInput
    return mapChannels(image) { value in
      let position: Double
      if span > 0 {
        position = min(max((value - lowInput) / span, 0), 1)
      } else {
        position = value < lowInput ? 0 : 1
      }
      return lowOutput + (highOutput - lowOutput) * position
    }
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
