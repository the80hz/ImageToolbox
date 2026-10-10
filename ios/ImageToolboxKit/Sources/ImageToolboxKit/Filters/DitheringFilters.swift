import Foundation

/// Дизеринг с распространением ошибки: Floyd–Steinberg, Atkinson, Sierra, Stucki, Burkes, Jarvis и другие.
///
/// Android вызывает нативный `Trickle.dithering`, его кода в репозитории нет. Поэтому ядра распространения
/// взяты из опубликованных описаний алгоритмов, а не из Android. Все фильтры помечены как приближение.
/// Пиксели обрабатываются построчно слева направо, без «змейки». Порог бинарный: значение канала
/// не меньше порога даёт 255, иначе 0. Ошибка каждого канала распространяется отдельно, если не включены
/// серые тона: тогда сначала берётся яркость по весам 0.299, 0.587, 0.114.
enum DitheringFilters {
  /// Порог и серые тона одинаковы у всех фильтров группы, как в Ui-файлах Android.
  private static let thresholdParameters: [FilterParameter] = [
    FilterParameter(
      key: "threshold", titleKey: "threshold",
      kind: .number(range: 1...255, step: 1, defaultValue: 200)),
    FilterParameter(key: "grayScale", titleKey: "gray_scale", kind: .flag(defaultValue: false)),
  ]

  private static let keywords = ["dithering", "error diffusion"]

  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "FloydSteinbergDitheringFilter",
      titleKey: "floyd_steinberg_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        FloydSteinbergDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "FalseFloydSteinbergDitheringFilter",
      titleKey: "false_floyd_steinberg_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        FalseFloydSteinbergDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "JarvisJudiceNinkeDitheringFilter",
      titleKey: "jarvis_judice_ninke_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        JarvisJudiceNinkeDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "SierraDitheringFilter",
      titleKey: "sierra_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        SierraDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "TwoRowSierraDitheringFilter",
      titleKey: "two_row_sierra_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        TwoRowSierraDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "SierraLiteDitheringFilter",
      titleKey: "sierra_lite_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        SierraLiteDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "AtkinsonDitheringFilter",
      titleKey: "atkinson_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        AtkinsonDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "StuckiDitheringFilter",
      titleKey: "stucki_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        StuckiDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "BurkesDitheringFilter",
      titleKey: "burkes_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        BurkesDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
    FilterDescriptor(
      id: "LeftToRightDitheringFilter",
      titleKey: "left_to_right_dithering",
      category: .dithering,
      engine: .cpu,
      parameters: thresholdParameters,
      keywords: keywords,
      make: {
        LeftToRightDitheringFilter(
          threshold: $0.number("threshold"), grayScale: $0.flag("grayScale"))
      }
    ),
  ]
}

/// Один сосед, которому передаётся часть ошибки. `weight` уже разделён на делитель ядра.
struct ErrorTap: Sendable {
  let dx: Int
  let dy: Int
  let weight: Float
}

/// Ядро распространения ошибки. Записано целыми весами и делителем, как в опубликованных таблицах.
struct ErrorKernel: Sendable {
  let taps: [ErrorTap]

  init(divisor: Int, _ weights: [(dx: Int, dy: Int, weight: Int)]) {
    taps = weights.map {
      ErrorTap(dx: $0.dx, dy: $0.dy, weight: Float($0.weight) / Float(divisor))
    }
  }

  static let floydSteinberg = ErrorKernel(
    divisor: 16, [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)])

  static let falseFloydSteinberg = ErrorKernel(
    divisor: 8, [(1, 0, 3), (0, 1, 3), (1, 1, 2)])

  static let jarvisJudiceNinke = ErrorKernel(
    divisor: 48,
    [
      (1, 0, 7), (2, 0, 5),
      (-2, 1, 3), (-1, 1, 5), (0, 1, 7), (1, 1, 5), (2, 1, 3),
      (-2, 2, 1), (-1, 2, 3), (0, 2, 5), (1, 2, 3), (2, 2, 1),
    ])

  static let sierra = ErrorKernel(
    divisor: 32,
    [
      (1, 0, 5), (2, 0, 3),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 5), (1, 1, 4), (2, 1, 2),
      (-1, 2, 2), (0, 2, 3), (1, 2, 2),
    ])

  static let twoRowSierra = ErrorKernel(
    divisor: 16,
    [
      (1, 0, 4), (2, 0, 3),
      (-2, 1, 1), (-1, 1, 2), (0, 1, 3), (1, 1, 2), (2, 1, 1),
    ])

  static let sierraLite = ErrorKernel(divisor: 4, [(1, 0, 2), (-1, 1, 1), (0, 1, 1)])

  /// Передаёт только 6/8 ошибки, остальное теряется. Так задано в Atkinson.
  static let atkinson = ErrorKernel(
    divisor: 8, [(1, 0, 1), (2, 0, 1), (-1, 1, 1), (0, 1, 1), (1, 1, 1), (0, 2, 1)])

  static let stucki = ErrorKernel(
    divisor: 42,
    [
      (1, 0, 8), (2, 0, 4),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
      (-2, 2, 1), (-1, 2, 2), (0, 2, 4), (1, 2, 2), (2, 2, 1),
    ])

  static let burkes = ErrorKernel(
    divisor: 32,
    [
      (1, 0, 8), (2, 0, 4),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
    ])

  /// Ошибка уходит только в соседний справа пиксель той же строки.
  static let leftToRight = ErrorKernel(divisor: 1, [(1, 0, 1)])
}

/// Бинарный дизеринг с распространением ошибки по `kernel`. Общая часть для всех фильтров группы.
enum ErrorDiffusion {
  /// Возвращает картинку того же размера. Альфа сохраняется, а цвет не больше альфы
  /// (premultiplied), поэтому полупрозрачные пиксели не получают лишней яркости.
  static func dither(
    _ image: RasterImage, kernel: ErrorKernel, threshold: Double, grayScale: Bool
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    let count = width * height
    let level = Float(threshold)
    let source = image.pixels
    var pixels = source

    if grayScale {
      var luma = [Float](repeating: 0, count: count)
      for index in 0..<count {
        let offset = index * 4
        luma[index] =
          0.299 * Float(source[offset]) + 0.587 * Float(source[offset + 1])
          + 0.114 * Float(source[offset + 2])
      }
      let bits = binarize(luma, width: width, height: height, kernel: kernel, level: level)
      for index in 0..<count {
        let offset = index * 4
        let value = min(bits[index], source[offset + 3])
        pixels[offset] = value
        pixels[offset + 1] = value
        pixels[offset + 2] = value
      }
    } else {
      for channel in 0..<3 {
        var plane = [Float](repeating: 0, count: count)
        for index in 0..<count {
          plane[index] = Float(source[index * 4 + channel])
        }
        let bits = binarize(plane, width: width, height: height, kernel: kernel, level: level)
        for index in 0..<count {
          let offset = index * 4 + channel
          pixels[offset] = min(bits[index], source[index * 4 + 3])
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Одна плоскость: каждое значение сравнивается с порогом, ошибка уходит соседям по ядру.
  private static func binarize(
    _ values: [Float], width: Int, height: Int, kernel: ErrorKernel, level: Float
  ) -> [UInt8] {
    var work = values
    var output = [UInt8](repeating: 0, count: values.count)
    for y in 0..<height {
      for x in 0..<width {
        let index = y * width + x
        let old = work[index]
        let new: Float = old >= level ? 255 : 0
        output[index] = UInt8(new)
        let error = old - new
        for tap in kernel.taps {
          let nx = x + tap.dx
          let ny = y + tap.dy
          guard nx >= 0, nx < width, ny < height else { continue }
          work[ny * width + nx] += error * tap.weight
        }
      }
    }
    return output
  }
}

/// Floyd–Steinberg: 7/16, 3/16, 5/16, 1/16. Приближение к Android.
struct FloydSteinbergDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .floydSteinberg, threshold: threshold, grayScale: grayScale)
  }
}

/// False Floyd–Steinberg: 3/8, 3/8, 2/8 без диагонального соседа слева. Приближение к Android.
struct FalseFloydSteinbergDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .falseFloydSteinberg, threshold: threshold, grayScale: grayScale)
  }
}

/// Jarvis, Judice и Ninke: 48-й делитель, три строки. Приближение к Android.
struct JarvisJudiceNinkeDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .jarvisJudiceNinke, threshold: threshold, grayScale: grayScale)
  }
}

/// Sierra (трёхстрочная): делитель 32. Приближение к Android.
struct SierraDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .sierra, threshold: threshold, grayScale: grayScale)
  }
}

/// Двухстрочный Sierra: делитель 16. Приближение к Android.
struct TwoRowSierraDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .twoRowSierra, threshold: threshold, grayScale: grayScale)
  }
}

/// Упрощённый Sierra (Sierra Lite): делитель 4. Приближение к Android.
struct SierraLiteDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .sierraLite, threshold: threshold, grayScale: grayScale)
  }
}

/// Atkinson: 1/8 шести соседям, четверть ошибки теряется. Приближение к Android.
struct AtkinsonDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .atkinson, threshold: threshold, grayScale: grayScale)
  }
}

/// Stucki: делитель 42, пять соседей в двух строках ниже. Приближение к Android.
struct StuckiDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .stucki, threshold: threshold, grayScale: grayScale)
  }
}

/// Burkes: делитель 32, две строки. Приближение к Android.
struct BurkesDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .burkes, threshold: threshold, grayScale: grayScale)
  }
}

/// Дизеринг слева направо: ошибка уходит только соседу справа. Приближение к Android.
struct LeftToRightDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .leftToRight, threshold: threshold, grayScale: grayScale)
  }
}
