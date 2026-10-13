import Foundation

/// Дизеринг с распространением ошибки: Floyd–Steinberg, Atkinson, Sierra, Stucki, Burkes, Jarvis и другие.
///
/// Порт `Dithering.cpp` из Trickle 1.9.3 (com.github.T8RIN:Trickle, trickle/src/main/cpp), который
/// Android вызывает через `Trickle.dithering`. Повторены и особенности нативного кода, иначе
/// результат расходится с Android (решение 16 в FILTERS.md):
/// - порог целый (`toInt()`), сравнение `значение + ошибка < порог`, ошибка делится целочисленно
///   с отбрасыванием дроби к нулю, отдельно на каждый вес ядра;
/// - серые тона берут красный канал, а не яркость;
/// - цикл идёт не по всему кадру, а с отступами у краёв, причём указатель источника не сдвигается
///   на левый отступ: результат смещён влево, а крайние строки и столбцы остаются
///   прозрачными чёрными;
/// - SierraLite считает по ядру двухстрочного Sierra.
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

/// Одно слагаемое ядра: сосед `(dx, dy)` получает `numerator * ошибка / divisor`.
struct ErrorTap: Sendable {
  let dx: Int
  let dy: Int
  let numerator: Int32
}

/// Ядро распространения ошибки Trickle: веса, делитель и отступы цикла от краёв кадра.
///
/// Цикл Trickle идёт по `x` от `leadingInset` до `width - trailingInset`, по `y` до
/// `height - bottomInset`. Читается при этом пиксель с номером `x - leadingInset`, а запись идёт туда
/// же, поэтому результат сдвинут влево на `leadingInset`. Вне цикла пиксели остаются нулевыми.
struct ErrorKernel: Sendable {
  let taps: [ErrorTap]
  let divisor: Int32
  let leadingInset: Int
  let trailingInset: Int
  let bottomInset: Int

  init(
    divisor: Int, leadingInset: Int, trailingInset: Int, bottomInset: Int,
    _ weights: [(dx: Int, dy: Int, weight: Int)]
  ) {
    precondition(weights.allSatisfy { $0.dy >= 0 && $0.dy <= 2 }, "ring of three rows")
    taps = weights.map { ErrorTap(dx: $0.dx, dy: $0.dy, numerator: Int32($0.weight)) }
    self.divisor = Int32(divisor)
    self.leadingInset = leadingInset
    self.trailingInset = trailingInset
    self.bottomInset = bottomInset
  }

  static let floydSteinberg = ErrorKernel(
    divisor: 16, leadingInset: 1, trailingInset: 1, bottomInset: 1,
    [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)])

  static let falseFloydSteinberg = ErrorKernel(
    divisor: 8, leadingInset: 1, trailingInset: 1, bottomInset: 1,
    [(1, 0, 3), (0, 1, 3), (1, 1, 2)])

  static let jarvisJudiceNinke = ErrorKernel(
    divisor: 48, leadingInset: 2, trailingInset: 2, bottomInset: 2,
    [
      (1, 0, 7), (2, 0, 5),
      (-2, 1, 3), (-1, 1, 5), (0, 1, 7), (1, 1, 5), (2, 1, 3),
      (-2, 2, 1), (-1, 2, 3), (0, 2, 5), (1, 2, 3), (2, 2, 1),
    ])

  static let sierra = ErrorKernel(
    divisor: 32, leadingInset: 2, trailingInset: 2, bottomInset: 2,
    [
      (1, 0, 5), (2, 0, 3),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 5), (1, 1, 4), (2, 1, 2),
      (-1, 2, 2), (0, 2, 3), (1, 2, 2),
    ])

  static let twoRowSierra = ErrorKernel(
    divisor: 16, leadingInset: 2, trailingInset: 2, bottomInset: 1,
    [
      (1, 0, 4), (2, 0, 3),
      (-2, 1, 1), (-1, 1, 2), (0, 1, 3), (1, 1, 2), (2, 1, 1),
    ])

  /// В Trickle совпадает с `twoRowSierra`: легковесного ядра 2/1/1 в нём нет.
  static let sierraLite = twoRowSierra

  /// Передаёт 6/8 ошибки, остальное теряется. Отступы несимметричны: слева 1, справа 2.
  static let atkinson = ErrorKernel(
    divisor: 8, leadingInset: 1, trailingInset: 2, bottomInset: 2,
    [(1, 0, 1), (2, 0, 1), (-1, 1, 1), (0, 1, 1), (1, 1, 1), (0, 2, 1)])

  static let stucki = ErrorKernel(
    divisor: 42, leadingInset: 2, trailingInset: 2, bottomInset: 2,
    [
      (1, 0, 8), (2, 0, 4),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
      (-2, 2, 1), (-1, 2, 2), (0, 2, 4), (1, 2, 2), (2, 2, 1),
    ])

  static let burkes = ErrorKernel(
    divisor: 32, leadingInset: 2, trailingInset: 2, bottomInset: 1,
    [
      (1, 0, 8), (2, 0, 4),
      (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
    ])
}

/// Порог Trickle: Kotlin `Float.toInt()` (дробь отбрасывается, значение зажато в диапазон Int).
func androidThreshold(_ value: Double) -> Int32 {
  guard value.isFinite else { return value > 0 ? Int32.max : (value < 0 ? Int32.min : 0) }
  return Int32(max(Double(Int32.min), min(Double(Int32.max), value.rounded(.towardZero))))
}

/// Бинарный дизеринг с распространением ошибки по `kernel`. Общая часть для всех фильтров группы.
enum ErrorDiffusion {
  /// Результат того же размера. Пиксели вне цикла Trickle остаются прозрачными чёрными. Цвет не
  /// больше альфы (premultiplied), поэтому полупрозрачные пиксели не получают лишней яркости.
  ///
  /// Каналы независимы, поэтому цветной режим считает R, G, B параллельно. Выделения памяти
  /// только на плоскость: три строки ошибок на канал.
  static func dither(
    _ image: RasterImage, kernel: ErrorKernel, threshold: Double, grayScale: Bool
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    let columns = width - kernel.leadingInset - kernel.trailingInset
    let rows = height - kernel.bottomInset
    var output = [UInt8](repeating: 0, count: width * height * 4)
    guard columns > 0, rows > 0 else {
      return RasterImage(width: width, height: height, pixels: output)
    }
    let level = androidThreshold(threshold)
    image.pixels.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { target in
        let input = source
        let destination = target
        DispatchQueue.concurrentPerform(iterations: grayScale ? 1 : 3) { channel in
          diffuse(
            input, into: destination, channel: channel, grayScale: grayScale, kernel: kernel,
            width: width, columns: columns, rows: rows, level: level)
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Одна плоскость. Запись канала `channel` (или всех трёх в серых тонах) в `destination`.
  private static func diffuse(
    _ source: UnsafeBufferPointer<UInt8>, into destination: UnsafeMutableBufferPointer<UInt8>,
    channel: Int, grayScale: Bool, kernel: ErrorKernel, width: Int, columns: Int, rows: Int,
    level: Int32
  ) {
    var errors = [Int32](repeating: 0, count: 3 * width)
    let inset = kernel.leadingInset
    let divisor = kernel.divisor
    errors.withUnsafeMutableBufferPointer { ring in
      kernel.taps.withUnsafeBufferPointer { taps in
        for y in 0..<rows {
          let slots = SIMD3<Int>(
            (y % 3) * width, ((y + 1) % 3) * width, ((y + 2) % 3) * width)
          for k in 0..<columns {
            let x = k + inset
            let offset = (y * width + k) * 4
            let current = Int32(source[offset + channel]) + ring[slots[0] + x]
            let isOn = current >= level
            let error = isOn ? current - 255 : current
            for tap in taps {
              ring[slots[tap.dy] + x + tap.dx] += tap.numerator * error / divisor
            }
            let alpha = source[offset + 3]
            let value: UInt8 = isOn ? alpha : 0
            if grayScale {
              destination[offset] = value
              destination[offset + 1] = value
              destination[offset + 2] = value
              destination[offset + 3] = alpha
            } else {
              destination[offset + channel] = value
              if channel == 0 { destination[offset + 3] = alpha }
            }
          }
          for x in 0..<width { ring[slots[0] + x] = 0 }
        }
      }
    }
  }

  /// Ошибка копится вдоль строки и сбрасывается на её начале. Разница меньше 10 по модулю
  /// отбрасывается, поэтому слабый градиент не накапливает ошибку (как в Trickle).
  static func leftToRight(
    _ image: RasterImage, threshold: Double, grayScale: Bool
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    let level = androidThreshold(threshold)
    var output = [UInt8](repeating: 0, count: width * height * 4)
    image.pixels.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        for y in 0..<height {
          var accumulated: (Int32, Int32, Int32) = (0, 0, 0)
          for x in 0..<width {
            let offset = (y * width + x) * 4
            let alpha = source[offset + 3]
            if grayScale {
              let value = step(Int32(source[offset]), &accumulated.0, level) ? alpha : 0
              destination[offset] = value
              destination[offset + 1] = value
              destination[offset + 2] = value
            } else {
              destination[offset] =
                step(Int32(source[offset]), &accumulated.0, level) ? alpha : 0
              destination[offset + 1] =
                step(Int32(source[offset + 1]), &accumulated.1, level) ? alpha : 0
              destination[offset + 2] =
                step(Int32(source[offset + 2]), &accumulated.2, level) ? alpha : 0
            }
            destination[offset + 3] = alpha
          }
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Один пиксель одного канала: включён ли он, и новая накопленная ошибка.
  private static func step(_ value: Int32, _ accumulated: inout Int32, _ level: Int32) -> Bool {
    let isOn = value + accumulated >= level
    var delta = isOn ? value - 255 : value
    if abs(delta) < 10 { delta = 0 }
    accumulated += delta
    return isOn
  }
}

/// Floyd–Steinberg: 7/16, 3/16, 5/16, 1/16.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `floydSteinbergImpl`.
/// Статус: проверено по эталону.
struct FloydSteinbergDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .floydSteinberg, threshold: threshold, grayScale: grayScale)
  }
}

/// False Floyd–Steinberg: 3/8, 3/8, 2/8 без диагонального соседа слева.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `falseFloydSteinbergImpl`.
/// Статус: проверено по эталону.
struct FalseFloydSteinbergDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .falseFloydSteinberg, threshold: threshold, grayScale: grayScale)
  }
}

/// Jarvis, Judice и Ninke: делитель 48, три строки.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `jarvisJudiceNinkeImpl`.
/// Статус: проверено по эталону.
struct JarvisJudiceNinkeDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .jarvisJudiceNinke, threshold: threshold, grayScale: grayScale)
  }
}

/// Sierra (трёхстрочная): делитель 32.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `sierraImpl`.
/// Статус: проверено по эталону.
struct SierraDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .sierra, threshold: threshold, grayScale: grayScale)
  }
}

/// Двухстрочный Sierra: делитель 16.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `twoRowSierraImpl`.
/// Статус: проверено по эталону.
struct TwoRowSierraDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .twoRowSierra, threshold: threshold, grayScale: grayScale)
  }
}

/// Sierra Lite: в Trickle считается по ядру двухстрочного Sierra (делитель 16).
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `sierraLiteImpl`.
/// Статус: проверено по эталону.
struct SierraLiteDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .sierraLite, threshold: threshold, grayScale: grayScale)
  }
}

/// Atkinson: 1/8 шести соседям, четверть ошибки теряется.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `atkinsonImpl`.
/// Статус: проверено по эталону.
struct AtkinsonDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .atkinson, threshold: threshold, grayScale: grayScale)
  }
}

/// Stucki: делитель 42, пять соседей в двух строках ниже.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `stuckiImpl`.
/// Статус: проверено по эталону.
struct StuckiDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .stucki, threshold: threshold, grayScale: grayScale)
  }
}

/// Burkes: делитель 32, две строки.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `burkesImpl`.
/// Статус: проверено по эталону.
struct BurkesDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.dither(
      image, kernel: .burkes, threshold: threshold, grayScale: grayScale)
  }
}

/// Дизеринг слева направо: ошибка копится вдоль строки и не передаётся вниз.
///
/// Источник: Trickle 1.9.3, `Dithering.cpp`, `simpleLeftToRightErrorDiffusionImpl`.
/// Статус: проверено по эталону.
struct LeftToRightDitheringFilter: Filter {
  let threshold: Double
  let grayScale: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    ErrorDiffusion.leftToRight(image, threshold: threshold, grayScale: grayScale)
  }
}
