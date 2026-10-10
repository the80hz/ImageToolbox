import CoreImage
import Foundation

/// Резкость, зерно и пикселизация из групп резкости и шума.
///
/// Перенесено: SharpenFilter, UnsharpFilter, GrainFilter (приближение), PixelationFilter,
/// CirclePixelationFilter, DiamondPixelationFilter (приближение).
/// Не перенесено: ConstrainedSharpenFilter и AlphaSharpenFilter (G'MIC), NoiseFilter (Trickle),
/// ReduceNoiseFilter и DespeckleFilter (Jh Labs). Их алгоритмы есть только в нативных или
/// внешних библиотеках, которых нет в репозитории.
enum SharpenNoiseFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "SharpenFilter",
      titleKey: "sharpen",
      category: .sharpenAndNoise,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "sharpen",
          kind: .number(range: -1...1, step: 0.01, defaultValue: 1))
      ],
      make: { SharpenFilter(amount: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "UnsharpFilter",
      titleKey: "unsharp",
      category: .sharpenAndNoise,
      engine: .coreImage,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "unsharp",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5))
      ],
      make: { UnsharpFilter(intensity: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "GrainFilter",
      titleKey: "grain",
      category: .sharpenAndNoise,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "grain",
          kind: .number(range: 0...2, step: 0.01, defaultValue: 0.75))
      ],
      make: { GrainFilter(intensity: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "PixelationFilter",
      titleKey: "pixelation",
      category: .sharpenAndNoise,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "pixelation",
          kind: .number(range: 5...200, step: 0.01, defaultValue: 25))
      ],
      make: { PixelationFilter(size: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "CirclePixelationFilter",
      titleKey: "circle_pixelation",
      category: .sharpenAndNoise,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "circle_pixelation",
          kind: .number(range: 5...200, step: 0.01, defaultValue: 24))
      ],
      make: { CirclePixelationFilter(size: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "DiamondPixelationFilter",
      titleKey: "diamond_pixelation",
      category: .sharpenAndNoise,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "diamond_pixelation",
          kind: .number(range: 10...200, step: 0.01, defaultValue: 24))
      ],
      make: { DiamondPixelationFilter(size: $0.number("value")) }
    ),
  ]
}

/// Резкость по ядру 3x3 из GPUImage: центр `1 + 4s`, четыре соседа `-s`. Края берутся с повтором.
///
/// Приближение: исходник GPUImage не в репозитории, формула по публичному шейдеру без сверки.
/// Значение 0 не меняет картинку. Для изображения 1x1 результат всегда совпадает со входом.
struct SharpenFilter: Filter {
  let amount: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let width = image.width
    let height = image.height
    let source = image.pixels
    var output = source
    let weight = amount
    for y in 0..<height {
      let up = max(y - 1, 0)
      let down = min(y + 1, height - 1)
      for x in 0..<width {
        let left = max(x - 1, 0)
        let right = min(x + 1, width - 1)
        let index = (y * width + x) * 4
        let alpha = Double(source[index + 3])
        let neighbours = [
          (up * width + x) * 4,
          (down * width + x) * 4,
          (y * width + left) * 4,
          (y * width + right) * 4,
        ]
        for channel in 0..<3 {
          let centre = Double(source[index + channel])
          let sum = neighbours.reduce(0.0) { $0 + Double(source[$1 + channel]) }
          let value = centre * (1 + 4 * weight) - sum * weight
          // Значения premultiplied, поэтому цвет не выше альфы.
          output[index + channel] = UInt8(min(max(value.rounded(), 0), alpha))
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }
}

/// Нерезкая маска из Core Image.
///
/// Приближение: Aire недоступен в репозитории, радиус размытия Aire неизвестен.
/// Взят радиус `CIUnsharpMask` по умолчанию, интенсивность равна значению настройки.
struct UnsharpFilter: Filter {
  /// Радиус размытия, который Aire не раскрывает. Задан условно.
  static let assumedRadius = 2.5

  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    try CoreImageBridge.render(image, filterID: "UnsharpFilter") { input in
      input.applyingFilter(
        "CIUnsharpMask",
        parameters: [
          "inputRadius": Self.assumedRadius,
          "inputIntensity": intensity,
        ])
    }
  }
}

/// Монохромное зерно. Приближение: Aire недоступен, поэтому амплитуда выбрана условно.
///
/// Шум детерминированный: один и тот же пиксель всегда получает одно и то же значение.
/// Значение 0 не меняет картинку.
struct GrainFilter: Filter {
  /// Наибольшее отклонение канала при интенсивности 1, в шкале 0...255. Задано условно.
  static let assumedAmplitude = 64.0

  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let width = image.width
    var output = image.pixels
    for y in 0..<image.height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        let alpha = Double(image.pixels[index + 3])
        let delta = Self.noise(x: x, y: y) * intensity * Self.assumedAmplitude * alpha / 255
        for channel in 0..<3 {
          let value = Double(image.pixels[index + channel]) + delta
          output[index + channel] = UInt8(min(max(value.rounded(), 0), alpha))
        }
      }
    }
    return RasterImage(width: width, height: image.height, pixels: output)
  }

  /// Хеш координат в диапазоне -1...1.
  static func noise(x: Int, y: Int) -> Double {
    var hash = UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1
    hash ^= UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77
    hash ^= hash >> 15
    hash = hash &* 0x2C1B_3C6D
    hash ^= hash >> 12
    hash = hash &* 0x297A_2D39
    hash ^= hash >> 15
    return Double(hash) / Double(UInt32.max) * 2 - 1
  }
}

/// Форма ячейки пикселизации, как в `PixelationLayer.Shape` на Android.
private enum PixelShape {
  case square
  case circle
  case diamond
}

/// Один слой пикселизации: сетка с шагом `resolution`, фигуры размером `size` (по умолчанию `resolution`).
private struct PixelLayer {
  let shape: PixelShape
  let resolution: Double
  var size: Double?
  var alpha: Double = 1
  var offset: Double = 0
}

/// Рисует слои по порядку, как `PixelationTool` на Android. Каждая ячейка берёт цвет пикселя в своём центре.
///
/// Приближение: Canvas на Android рисует фигуры со сглаживанием, здесь края жёсткие.
private enum Pixelation {
  static func render(_ image: RasterImage, layers: [PixelLayer]) -> RasterImage {
    let width = image.width
    let height = image.height
    // Начинаем с прозрачного холста, как createBitmap на Android.
    var output = [UInt8](repeating: 0, count: width * height * 4)

    for layer in layers {
      let size = layer.size ?? layer.resolution
      let half = size / 2
      let columns = Int(Double(width) / layer.resolution + 1)
      let rows = Int(Double(height) / layer.resolution + 1)

      for row in 0...rows {
        let y = (Double(row) - 0.5) * layer.resolution + layer.offset
        let sampleY = Int(min(max(y, 0), Double(height - 1)))
        for column in 0...columns {
          let x = (Double(column) - 0.5) * layer.resolution + layer.offset
          let sampleX = Int(min(max(x, 0), Double(width - 1)))
          let source = image.pixel(x: sampleX, y: sampleY)
          // Как Color.argb на Android: альфа обрезается до целого.
          let alpha = (layer.alpha * Double(source.alpha)).rounded(.down)
          guard alpha > 0 else { continue }
          paint(
            into: &output, width: width, height: height,
            shape: layer.shape, centreX: x, centreY: y, half: half,
            colour: source, alpha: alpha)
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Накладывает фигуру цвета `colour` с альфой `alpha` (0...255) методом source-over.
  private static func paint(
    into output: inout [UInt8], width: Int, height: Int,
    shape: PixelShape, centreX: Double, centreY: Double, half: Double,
    colour: RGBA, alpha: Double
  ) {
    let minX = max(0, Int((centreX - half).rounded(.down)) - 1)
    let maxX = min(width - 1, Int((centreX + half).rounded(.up)) + 1)
    let minY = max(0, Int((centreY - half).rounded(.down)) - 1)
    let maxY = min(height - 1, Int((centreY + half).rounded(.up)) + 1)
    guard minX <= maxX, minY <= maxY else { return }

    let coverage = alpha / 255
    let source = [Double(colour.red), Double(colour.green), Double(colour.blue)]
    for y in minY...maxY {
      for x in minX...maxX {
        let dx = Double(x) + 0.5 - centreX
        let dy = Double(y) + 0.5 - centreY
        let inside: Bool
        switch shape {
        case .square: inside = abs(dx) <= half && abs(dy) <= half
        case .circle: inside = dx * dx + dy * dy <= half * half
        case .diamond: inside = abs(dx) + abs(dy) <= half
        }
        guard inside else { continue }

        let index = (y * width + x) * 4
        for channel in 0..<3 {
          let value = source[channel] * coverage + Double(output[index + channel]) * (1 - coverage)
          output[index + channel] = UInt8(min(value.rounded(), 255))
        }
        let alphaValue = alpha + Double(output[index + 3]) * (1 - coverage)
        output[index + 3] = UInt8(min(alphaValue.rounded(), 255))
      }
    }
  }
}

/// Квадратная пикселизация. Слой: квадрат со стороной `size`, шаг сетки `size - 4`.
///
/// Приближение: края без сглаживания, см. `Pixelation`.
struct PixelationFilter: Filter {
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    Pixelation.render(
      image,
      layers: [PixelLayer(shape: .square, resolution: size - 4, size: size)])
  }
}

/// Круглая пикселизация: два слоя кругов, второй смещён на половину шага.
///
/// Приближение: края без сглаживания, см. `Pixelation`.
struct CirclePixelationFilter: Filter {
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    Pixelation.render(
      image,
      layers: [
        PixelLayer(shape: .circle, resolution: size),
        PixelLayer(shape: .circle, resolution: size, size: size / 3, offset: size / 2),
      ])
  }
}

/// Ромбовидная пикселизация: два слоя ромбов и квадратный слой с альфой 0.6, как `PixelationCommands.diamond`.
///
/// Приближение: края без сглаживания, см. `Pixelation`.
struct DiamondPixelationFilter: Filter {
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    Pixelation.render(
      image,
      layers: [
        PixelLayer(shape: .diamond, resolution: size, size: size + 1),
        PixelLayer(shape: .diamond, resolution: size, offset: size / 2),
        PixelLayer(shape: .square, resolution: size, alpha: 0.6),
      ])
  }
}
