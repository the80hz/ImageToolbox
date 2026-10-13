import Foundation

/// Дизеринг без распространения ошибки: Bayer, Clustered, случайный и простой порог.
///
/// Bayer и Clustered портированы из `Dithering.cpp` Trickle 1.9.3 (com.github.T8RIN:Trickle,
/// trickle/src/main/cpp) вместе с его матрицами и особенностями (решение 16 в FILTERS.md).
/// `SimpleThresholdDitheringFilter` проверен по эталону. `RandomDitheringFilter` остаётся
/// приближением: Android берёт системный генератор, эталон снять нельзя.
/// Постеризация (G'MIC) и Yililoma (нативный алгоритм с палитрой) не перенесены.
///
/// Каждый фильтр задаёт порог на канал: пиксель становится 255, если значение не меньше порога,
/// иначе 0. Пиксели premultiplied: «включённое» значение равно альфе, поэтому цвет не выходит
/// за альфу. Для непрозрачного изображения это 255.
enum OrderedDitheringFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "BayerTwoDitheringFilter",
      titleKey: "bayer_two_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        BayerTwoDitheringFilter(threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "BayerThreeDitheringFilter",
      titleKey: "bayer_three_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        BayerThreeDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "BayerFourDitheringFilter",
      titleKey: "bayer_four_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        BayerFourDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "BayerEightDitheringFilter",
      titleKey: "bayer_eight_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        BayerEightDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "Clustered2x2DitheringFilter",
      titleKey: "clustered_2x2_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: grayScaleOnly,
      make: { Clustered2x2DitheringFilter(grayScale: $0.flag("grayScale")) }
    ),
    FilterDescriptor(
      id: "Clustered4x4DitheringFilter",
      titleKey: "clustered_4x4_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: grayScaleOnly,
      make: { Clustered4x4DitheringFilter(grayScale: $0.flag("grayScale")) }
    ),
    FilterDescriptor(
      id: "Clustered8x8DitheringFilter",
      titleKey: "clustered_8x8_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: grayScaleOnly,
      make: { Clustered8x8DitheringFilter(grayScale: $0.flag("grayScale")) }
    ),
    FilterDescriptor(
      id: "RandomDitheringFilter",
      titleKey: "random_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        RandomDitheringFilter(threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "SimpleThresholdDitheringFilter",
      titleKey: "simple_threshold_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdAndGrayScale,
      make: {
        SimpleThresholdDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
  ]

  /// Android `Pair<Float, Boolean>`: порог 1...255 (шаг 1, по умолчанию 200) и серые тона.
  private static let thresholdAndGrayScale: [FilterParameter] = [
    FilterParameter(
      key: "threshold", titleKey: "threshold",
      kind: .number(range: 1...255, step: 1, defaultValue: 200)),
    FilterParameter(
      key: "grayScale", titleKey: "gray_scale", kind: .flag(defaultValue: false)),
  ]

  /// Android `Boolean`: только серые тона.
  private static let grayScaleOnly: [FilterParameter] = [
    FilterParameter(key: "grayScale", titleKey: "gray_scale", kind: .flag(defaultValue: false))
  ]
}

/// Общий проход для всех фильтров с порогом. `cut` даёт порог канала (0...255) в клетке (x, y).
enum OrderedDitherKernel {
  static func apply(
    _ image: RasterImage,
    grayScale: Bool,
    cut: (_ x: Int, _ y: Int, _ channel: Int) -> Double
  ) -> RasterImage {
    var output = image.pixels
    let width = image.width
    for y in 0..<image.height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        let alpha = image.pixels[index + 3]
        let on = alpha
        if grayScale {
          let luma =
            0.299 * Double(image.pixels[index]) + 0.587 * Double(image.pixels[index + 1])
            + 0.114 * Double(image.pixels[index + 2])
          let value: UInt8 = luma >= cut(x, y, 0) ? on : 0
          output[index] = value
          output[index + 1] = value
          output[index + 2] = value
        } else {
          for channel in 0..<3 {
            let level = Double(image.pixels[index + channel])
            output[index + channel] = level >= cut(x, y, channel) ? on : 0
          }
        }
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: output)
  }
}

/// Матрицы Trickle для Bayer и Clustered, записанные как в `Dithering.cpp`.
///
/// У Bayer значение `matrix[x % n][y % n]` берётся с индексами в порядке (столбец, строка), то есть
/// матрица как бы транспонирована. У Clustered `thresholdMatrix[y % n][x % n]` с обычным порядком.
enum TrickleMatrix {
  /// Bayer 2x2, делитель 5.
  static let bayer2: [Int32] = [1, 3, 4, 2]

  /// Bayer 3x3, делитель 10. Не классическая матрица Байера.
  static let bayer3: [Int32] = [3, 7, 4, 6, 1, 9, 2, 8, 5]

  /// Bayer 4x4, делитель 17.
  static let bayer4: [Int32] = [
    1, 9, 3, 11,
    13, 5, 15, 7,
    4, 12, 2, 10,
    16, 8, 14, 6,
  ]

  /// Bayer 8x8, делитель 65.
  static let bayer8: [Int32] = [
    1, 49, 13, 61, 4, 52, 16, 64,
    33, 17, 45, 29, 36, 20, 48, 32,
    9, 57, 5, 53, 12, 60, 8, 56,
    41, 25, 37, 21, 44, 28, 40, 24,
    3, 51, 15, 63, 2, 50, 14, 62,
    35, 19, 47, 31, 34, 18, 46, 30,
    11, 59, 7, 55, 10, 58, 6, 54,
    43, 27, 39, 23, 42, 26, 38, 22,
  ]

  /// Clustered 2x2, множитель порога 64.
  static let clustered2: [Int32] = [0, 2, 3, 1]

  /// Clustered 4x4, множитель порога 16.
  static let clustered4: [Int32] = [
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5,
  ]

  /// Clustered 8x8, множитель порога 4.
  static let clustered8: [Int32] = [
    0, 48, 12, 60, 3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
    8, 56, 4, 52, 11, 59, 7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
    2, 50, 14, 62, 1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58, 6, 54, 9, 57, 5, 53,
    42, 26, 38, 22, 41, 25, 37, 21,
  ]
}

/// Проходы Bayer и Clustered. Цикл идёт по всему кадру, без отступов. Серые тона, как и в Trickle,
/// берут красный канал, а не яркость.
enum TrickleOrderedKernel {
  /// Bayer: канал `v` растёт на `v * m / divisor` (целочисленно), затем сравнение `< порог`.
  /// `matrix` задан строками как в C++, индекс (столбец, строка) = `(x % n) * n + y % n`.
  static func bayer(
    _ image: RasterImage, matrix: [Int32], size: Int, divisor: Int32, threshold: Double,
    grayScale: Bool
  ) -> RasterImage {
    let level = androidThreshold(threshold)
    return run(image, grayScale: grayScale) { x, y, value in
      let cell = matrix[(x % size) * size + y % size]
      return value + value * cell / divisor >= level
    }
  }

  /// Clustered: порог клетки `cell * scale`, строгое сравнение `> порог`.
  static func clustered(
    _ image: RasterImage, matrix: [Int32], size: Int, scale: Int32, grayScale: Bool
  ) -> RasterImage {
    run(image, grayScale: grayScale) { x, y, value in
      value > matrix[(y % size) * size + x % size] * scale
    }
  }

  /// Общий цикл. `isOn(x, y, value)` решает по значению канала 0...255. Цвет не больше альфы.
  private static func run(
    _ image: RasterImage, grayScale: Bool,
    isOn: (_ x: Int, _ y: Int, _ value: Int32) -> Bool
  ) -> RasterImage {
    let width = image.width
    var output = image.pixels
    image.pixels.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        for y in 0..<image.height {
          for x in 0..<width {
            let offset = (y * width + x) * 4
            let alpha = source[offset + 3]
            if grayScale {
              let value: UInt8 = isOn(x, y, Int32(source[offset])) ? alpha : 0
              destination[offset] = value
              destination[offset + 1] = value
              destination[offset + 2] = value
            } else {
              for channel in 0..<3 {
                destination[offset + channel] =
                  isOn(x, y, Int32(source[offset + channel])) ? alpha : 0
              }
            }
          }
        }
      }
    }
    return RasterImage(width: width, height: image.height, pixels: output)
  }
}

/// Bayer 2x2 с порогом и серыми тонами.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `ordered2By2BayerImpl`.
/// Статус: проверено по эталону.
struct BayerTwoDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.bayer(
      image, matrix: TrickleMatrix.bayer2, size: 2, divisor: 5, threshold: threshold,
      grayScale: grayScale)
  }
}

/// Bayer 3x3 с порогом и серыми тонами.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `ordered3By3BayerImpl`.
/// Статус: проверено по эталону.
struct BayerThreeDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.bayer(
      image, matrix: TrickleMatrix.bayer3, size: 3, divisor: 10, threshold: threshold,
      grayScale: grayScale)
  }
}

/// Bayer 4x4 с порогом и серыми тонами.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `ordered4By4BayerImpl`.
/// Статус: проверено по эталону.
struct BayerFourDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.bayer(
      image, matrix: TrickleMatrix.bayer4, size: 4, divisor: 17, threshold: threshold,
      grayScale: grayScale)
  }
}

/// Bayer 8x8 с порогом и серыми тонами.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `ordered8By8BayerImpl`.
/// Статус: проверено по эталону.
struct BayerEightDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.bayer(
      image, matrix: TrickleMatrix.bayer8, size: 8, divisor: 65, threshold: threshold,
      grayScale: grayScale)
  }
}

/// Кластерный дизеринг 2x2: порог клетки равен значению матрицы (0...3), умноженному на 64.
/// Параметра порога нет.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `clustered2x2DitheringImpl`.
/// Статус: проверено по эталону.
struct Clustered2x2DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.clustered(
      image, matrix: TrickleMatrix.clustered2, size: 2, scale: 64, grayScale: grayScale)
  }
}

/// Кластерный дизеринг 4x4: порог клетки равен значению матрицы (0...15), умноженному на 16.
/// Параметра порога нет.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `clustered4x4DitheringImpl`.
/// Статус: проверено по эталону.
struct Clustered4x4DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.clustered(
      image, matrix: TrickleMatrix.clustered4, size: 4, scale: 16, grayScale: grayScale)
  }
}

/// Кластерный дизеринг 8x8: порог клетки равен значению матрицы (0...63), умноженному на 4.
/// Параметра порога нет.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `clustered8x8DitheringImpl`.
/// Статус: проверено по эталону.
struct Clustered8x8DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleOrderedKernel.clustered(
      image, matrix: TrickleMatrix.clustered8, size: 8, scale: 4, grayScale: grayScale)
  }
}

/// Случайный порог: на каждый канал пикселя сдвиг от -127.5 до 127.5 вокруг порога. Шум задан
/// фиксированным зерном, поэтому результат повторяется. Приближение: Android берёт системный
/// генератор.
struct RandomDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  /// Зерно шума. Одно и то же для всех запусков.
  static let seed: UInt64 = 0x44_4954_4852

  func apply(to image: RasterImage) async throws -> RasterImage {
    var generator = SeededGenerator(seed: Self.seed)
    let count = image.width * image.height * 3
    var noise = [Double](repeating: 0, count: count)
    for index in 0..<count {
      let unit = Double(generator.next() >> 11) / Double(UInt64(1) << 53)
      noise[index] = (unit - 0.5) * 255
    }
    let width = image.width
    return OrderedDitherKernel.apply(image, grayScale: grayScale) { x, y, channel in
      threshold + noise[((y * width + x) * 3) + channel]
    }
  }
}

/// Простой порог без матрицы: значение не меньше порога становится 255, иначе 0.
///
/// Статус: проверено по эталону (`SimpleThresholdDitheringFilter`, раздел 10, порог 200: точное совпадение).
struct SimpleThresholdDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    // Trickle `simpleThresholdImpl`: порог усекается до целого, в оттенках серого берётся красный
    // канал (`gray = r`), а не яркость.
    let level = Double(androidThreshold(threshold))
    if grayScale {
      return OrderedDitherKernel.apply(image, grayScale: false) { _, _, _ in level }
        .replacingColourWithRed()
    }
    return OrderedDitherKernel.apply(image, grayScale: false) { _, _, _ in level }
  }
}

extension RasterImage {
  /// Копирует красный канал в зелёный и синий.
  fileprivate func replacingColourWithRed() -> RasterImage {
    var output = pixels
    for index in stride(from: 0, to: output.count, by: 4) {
      output[index + 1] = output[index]
      output[index + 2] = output[index]
    }
    return RasterImage(width: width, height: height, pixels: output)
  }
}
