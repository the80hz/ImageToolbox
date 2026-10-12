import Foundation

/// Дизеринг без распространения ошибки: Bayer, Clustered, случайный и простой порог.
///
/// Android отдаёт эти фильтры нативной библиотеке Trickle, и её код в репозитории не лежит. Здесь
/// все матрицы и пороги собраны по стандартным формулам, поэтому статус у фильтров «приближение»,
/// кроме Bayer 2, 4, 8 (матрицы Байера строятся рекурсивно и совпадают с классическими).
/// Сверка с Android 2026-10-13: Bayer, Clustered совпали не с классическими матрицами (среднее 85...118 из 255),
/// совпал только простой порог; числа в FILTERS.md, раздел 10.
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

/// Матрицы порогов. Ранг клетки от 0 до N*N-1, порог клетки строится из ранга.
enum DitherMatrix {
  /// Классическая матрица Байера для N = 2, 4, 8. Каждое удвоение размера:
  /// четыре копии предыдущей матрицы, умноженные на 4, со смещениями 0, 2, 3, 1 по квадрантам.
  static func bayer(_ size: Int) -> [Int] {
    var matrix = [0, 2, 3, 1]
    var current = 2
    while current < size {
      let next = current * 2
      var grown = [Int](repeating: 0, count: next * next)
      for y in 0..<next {
        for x in 0..<next {
          let quadrant: Int
          switch (y < current, x < current) {
          case (true, true): quadrant = 0
          case (true, false): quadrant = 2
          case (false, true): quadrant = 3
          case (false, false): quadrant = 1
          }
          grown[y * next + x] = 4 * matrix[(y % current) * current + x % current] + quadrant
        }
      }
      matrix = grown
      current = next
    }
    return matrix
  }

  /// Матрица 3x3 для Bayer Three. Классической матрицы Байера для нечётного размера нет, поэтому
  /// клетки упорядочены по дробной части `i * a + j * b` (последовательность R2, распределяет точки
  /// равномерно). Это приближение.
  static func dispersed(_ size: Int) -> [Int] {
    let a = 0.7548776662466927
    let b = 0.5698402909980532
    var keys: [Double] = []
    for y in 0..<size {
      for x in 0..<size {
        let value = Double(y) * a + Double(x) * b
        keys.append(value - value.rounded(.down))
      }
    }
    return rank(keys)
  }

  /// Кластерная матрица: клетки упорядочены по расстоянию от центра, чтобы точки росли группами.
  /// Ничья решается по строке. Точная матрица Trickle неизвестна, это приближение.
  static func clustered(_ size: Int) -> [Int] {
    let centre = Double(size - 1) / 2
    var keys: [Double] = []
    for y in 0..<size {
      for x in 0..<size {
        let dy = Double(y) - centre
        let dx = Double(x) - centre
        keys.append(dx * dx + dy * dy)
      }
    }
    return rank(keys)
  }

  /// Ранг каждого ключа: 0 у самого маленького. Ничьи идут в порядке индекса.
  private static func rank(_ keys: [Double]) -> [Int] {
    let order = keys.indices.sorted { lhs, rhs in
      keys[lhs] != keys[rhs] ? keys[lhs] < keys[rhs] : lhs < rhs
    }
    var ranks = [Int](repeating: 0, count: keys.count)
    for (position, index) in order.enumerated() {
      ranks[index] = position
    }
    return ranks
  }
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

  /// Порог клетки матрицы: `base` плюс сдвиг ранга в пределах 0...255 со средним 0.
  static func matrixCut(rank: Int, size: Int, base: Double) -> Double {
    let cells = Double(size * size)
    return base + 255 * ((Double(rank) + 0.5) / cells - 0.5)
  }

  /// Порог из матрицы, повторённой по изображению.
  static func tiled(_ matrix: [Int], size: Int, base: Double) -> (Int, Int, Int) -> Double {
    { x, y, _ in
      matrixCut(rank: matrix[(y % size) * size + x % size], size: size, base: base)
    }
  }
}

/// Bayer 2x2 с порогом и серыми тонами.
struct BayerTwoDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.bayer(2), size: 2, base: threshold))
  }
}

/// Bayer 3x3 с порогом и серыми тонами. Приближение: см. `DitherMatrix.dispersed`.
struct BayerThreeDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.dispersed(3), size: 3, base: threshold))
  }
}

/// Bayer 4x4 с порогом и серыми тонами.
struct BayerFourDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.bayer(4), size: 4, base: threshold))
  }
}

/// Bayer 8x8 с порогом и серыми тонами.
struct BayerEightDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.bayer(8), size: 8, base: threshold))
  }
}

/// Кластерный дизеринг 2x2 без порога: базовый порог 127.5. Приближение.
struct Clustered2x2DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.clustered(2), size: 2, base: 127.5))
  }
}

/// Кластерный дизеринг 4x4 без порога: базовый порог 127.5. Приближение.
struct Clustered4x4DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.clustered(4), size: 4, base: 127.5))
  }
}

/// Кластерный дизеринг 8x8 без порога: базовый порог 127.5. Приближение.
struct Clustered8x8DitheringFilter: Filter {
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    OrderedDitherKernel.apply(
      image, grayScale: grayScale,
      cut: OrderedDitherKernel.tiled(DitherMatrix.clustered(8), size: 8, base: 127.5))
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
    OrderedDitherKernel.apply(image, grayScale: grayScale) { _, _, _ in threshold }
  }
}
