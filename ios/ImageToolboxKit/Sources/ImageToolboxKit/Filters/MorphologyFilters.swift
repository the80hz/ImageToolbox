import Foundation

/// Морфология из Android: дилатация, эрозия, открытие, закрытие, top-hat, black-hat и морфологический градиент.
///
/// Android вызывает `Aire.morphology` с ядром `MorphKernels.box(size)` или `MorphKernels.circle(size)`,
/// границей `REFLECT_101` и размером `size × size`. Здесь ядро — квадрат `size × size` (или диск в нём),
/// якорь в центре, индекс `size / 2`. Реализация Aire в репозитории не видна, поэтому:
/// - форма круга — диск, вписанный в квадрат, с центром пикселя; точная форма Aire не проверена (приближение);
/// - для top-hat, black-hat и градиента альфа-канал сохраняется, чтобы непрозрачная картинка не стала
///   прозрачной (поведение Aire для RGBA здесь не видно, приближение).
enum MorphologyFilters {
  static let descriptors: [FilterDescriptor] = [
    descriptor(id: "DilationFilter", titleKey: "dilation") { size, circle in
      DilationFilter(size: size, circle: circle)
    },
    descriptor(id: "ErodeFilter", titleKey: "erode") { size, circle in
      ErodeFilter(size: size, circle: circle)
    },
    descriptor(id: "OpeningFilter", titleKey: "opening") { size, circle in
      OpeningFilter(size: size, circle: circle)
    },
    descriptor(id: "ClosingFilter", titleKey: "closing") { size, circle in
      ClosingFilter(size: size, circle: circle)
    },
    descriptor(id: "TopHatFilter", titleKey: "top_hat") { size, circle in
      TopHatFilter(size: size, circle: circle)
    },
    descriptor(id: "BlackHatFilter", titleKey: "black_hat") { size, circle in
      BlackHatFilter(size: size, circle: circle)
    },
    descriptor(
      id: "MorphologicalGradientFilter", titleKey: "morphological_gradient"
    ) { size, circle in
      MorphologicalGradientFilter(size: size, circle: circle)
    },
  ]

  /// Все семь фильтров одинаковы по параметрам: размер ядра 1...150 и флаг формы круга.
  private static func descriptor(
    id: String,
    titleKey: String,
    make: @escaping @Sendable (_ size: Int, _ circle: Bool) -> any Filter
  ) -> FilterDescriptor {
    FilterDescriptor(
      id: id,
      titleKey: titleKey,
      category: .morphology,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "size", titleKey: "just_size",
          kind: .number(range: 1...150, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "useCircleKernel", titleKey: "use_circle_kernel",
          kind: .flag(defaultValue: true)),
      ],
      make: { values in
        make(Int(values.number("size").rounded()), values.flag("useCircleKernel"))
      }
    )
  }
}

/// Дилатация: максимум по окрестности каждого канала.
struct DilationFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.dilate, on: image, size: size, circle: circle)
  }
}

/// Эрозия: минимум по окрестности каждого канала.
struct ErodeFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.erode, on: image, size: size, circle: circle)
  }
}

/// Открытие: эрозия, затем дилатация. Убирает светлые детали меньше ядра.
struct OpeningFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.opening, on: image, size: size, circle: circle)
  }
}

/// Закрытие: дилатация, затем эрозия. Заполняет тёмные детали меньше ядра.
struct ClosingFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.closing, on: image, size: size, circle: circle)
  }
}

/// Top-hat: исходное изображение минус открытие. Выделяет светлые детали меньше ядра.
struct TopHatFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.topHat, on: image, size: size, circle: circle)
  }
}

/// Black-hat: закрытие минус исходное изображение. Выделяет тёмные детали меньше ядра.
struct BlackHatFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.blackHat, on: image, size: size, circle: circle)
  }
}

/// Морфологический градиент: дилатация минус эрозия. Подсвечивает границы.
struct MorphologicalGradientFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.gradient, on: image, size: size, circle: circle)
  }
}

/// Считает морфологические операции по плоскостям каналов RGBA.
///
/// Минимум и максимум прямоугольного ядра разделяются на проход по строкам и по столбцам.
/// Для ядра-диска каждая строка ядра даёт свой отрезок, и результат берётся по строкам ядра.
/// Вне картинки значения берутся отражением без повтора края (`REFLECT_101`).
enum MorphologyEngine {
  enum Operation: Sendable {
    case erode
    case dilate
    case opening
    case closing
    case topHat
    case blackHat
    case gradient

    /// Top-hat, black-hat и градиент не трогают альфа-канал (см. комментарий в файле).
    var preservesAlpha: Bool {
      switch self {
      case .topHat, .blackHat, .gradient: true
      case .erode, .dilate, .opening, .closing: false
      }
    }
  }

  /// Отрезок по горизонтали относительно якоря: от `lo` до `hi` включительно.
  struct Span: Hashable {
    let lo: Int
    let hi: Int
  }

  /// Строки ядра сверху вниз. Строка `i` имеет смещение `i - anchor` по вертикали.
  struct Kernel {
    let anchor: Int
    let rows: [Span]

    /// Квадрат `size × size` или диск в нём. Центр диска — центр пикселя ядра.
    static func make(size: Int, circle: Bool) -> Kernel {
      let anchor = size / 2
      let centre = Double(size - 1) / 2
      let radius2 = Double(size * size) / 4
      let rows: [Span] = (0..<size).map { row in
        let dy = Double(row) - centre
        var first = 0
        var last = size - 1
        if circle {
          let inside = (0..<size).filter { column in
            let dx = Double(column) - centre
            return dx * dx + dy * dy <= radius2
          }
          first = inside.first ?? anchor
          last = inside.last ?? anchor
        }
        return Span(lo: first - anchor, hi: last - anchor)
      }
      return Kernel(anchor: anchor, rows: rows)
    }
  }

  /// Применяет операцию ко всем каналам. Альфа сохраняется, если операция этого требует.
  static func run(
    _ operation: Operation, on image: RasterImage, size: Int, circle: Bool
  ) -> RasterImage {
    let kernel = Kernel.make(size: max(1, size), circle: circle)
    let width = image.width
    let height = image.height
    var pixels = image.pixels
    let channels = operation.preservesAlpha ? 3 : 4
    for channel in 0..<channels {
      var plane = [UInt8](repeating: 0, count: width * height)
      for index in 0..<(width * height) {
        plane[index] = image.pixels[index * 4 + channel]
      }
      let result = transform(operation, plane, width: width, height: height, kernel: kernel)
      for index in 0..<(width * height) {
        pixels[index * 4 + channel] = result[index]
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func transform(
    _ operation: Operation, _ plane: [UInt8], width: Int, height: Int, kernel: Kernel
  ) -> [UInt8] {
    func erode(_ values: [UInt8]) -> [UInt8] {
      extreme(values, width: width, height: height, kernel: kernel, isMax: false)
    }
    func dilate(_ values: [UInt8]) -> [UInt8] {
      extreme(values, width: width, height: height, kernel: kernel, isMax: true)
    }
    switch operation {
    case .erode:
      return erode(plane)
    case .dilate:
      return dilate(plane)
    case .opening:
      return dilate(erode(plane))
    case .closing:
      return erode(dilate(plane))
    case .topHat:
      let opened = dilate(erode(plane))
      return zip(plane, opened).map { UInt8(clamping: Int($0.0) - Int($0.1)) }
    case .blackHat:
      let closed = erode(dilate(plane))
      return zip(closed, plane).map { UInt8(clamping: Int($0.0) - Int($0.1)) }
    case .gradient:
      let grown = dilate(plane)
      let shrunk = erode(plane)
      return zip(grown, shrunk).map { UInt8(clamping: Int($0.0) - Int($0.1)) }
    }
  }

  /// Максимум (или минимум) плоскости по ядру. Размер плоскости `width × height`, строки сверху.
  private static func extreme(
    _ plane: [UInt8], width: Int, height: Int, kernel: Kernel, isMax: Bool
  ) -> [UInt8] {
    if Set(kernel.rows).count == 1, let span = kernel.rows.first {
      // Прямоугольное ядро: сначала по строкам, потом по столбцам.
      let verticalSpan = Span(lo: -kernel.anchor, hi: kernel.rows.count - 1 - kernel.anchor)
      var rowPass = [UInt8](repeating: 0, count: width * height)
      for y in 0..<height {
        let row = Array(plane[(y * width)..<(y * width + width)])
        rowPass.replaceSubrange(
          (y * width)..<(y * width + width),
          with: slidingExtreme(row, span: span, isMax: isMax))
      }
      var output = [UInt8](repeating: 0, count: width * height)
      for x in 0..<width {
        var column = [UInt8](repeating: 0, count: height)
        for y in 0..<height {
          column[y] = rowPass[y * width + x]
        }
        let result = slidingExtreme(column, span: verticalSpan, isMax: isMax)
        for y in 0..<height {
          output[y * width + x] = result[y]
        }
      }
      return output
    }

    // Ядро-диск: горизонтальный проход для каждого отрезка, затем сбор по строкам ядра.
    var cache: [Span: [UInt8]] = [:]
    var rowPlanes: [[UInt8]] = []
    for span in kernel.rows {
      if let cached = cache[span] {
        rowPlanes.append(cached)
        continue
      }
      var pass = [UInt8](repeating: 0, count: width * height)
      for y in 0..<height {
        let row = Array(plane[(y * width)..<(y * width + width)])
        pass.replaceSubrange(
          (y * width)..<(y * width + width),
          with: slidingExtreme(row, span: span, isMax: isMax))
      }
      cache[span] = pass
      rowPlanes.append(pass)
    }

    var output = [UInt8](repeating: isMax ? 0 : 255, count: width * height)
    for y in 0..<height {
      for (index, pass) in rowPlanes.enumerated() {
        let source = reflect101(y + index - kernel.anchor, height) * width
        for x in 0..<width {
          output[y * width + x] = pick(output[y * width + x], pass[source + x], isMax: isMax)
        }
      }
    }
    return output
  }

  /// Для каждой позиции `i` возвращает экстремум значений `values[i + k]` при `k` из `span`.
  /// Граница — `REFLECT_101`. Алгоритм van Herk / Gil-Werman, время линейно от длины.
  private static func slidingExtreme(_ values: [UInt8], span: Span, isMax: Bool) -> [UInt8] {
    let count = values.count
    let length = span.hi - span.lo + 1
    let leftPad = max(0, -span.lo)
    let rightPad = max(0, span.hi)
    let total = count + leftPad + rightPad

    var padded = [UInt8](repeating: 0, count: total)
    for index in 0..<total {
      padded[index] = values[reflect101(index - leftPad, count)]
    }

    // Префиксы и суффиксы внутри блоков длины `length`.
    var prefix = padded
    var suffix = padded
    for index in 0..<total where index % length != 0 {
      prefix[index] = pick(prefix[index - 1], padded[index], isMax: isMax)
    }
    for index in stride(from: total - 2, through: 0, by: -1) where (index + 1) % length != 0 {
      suffix[index] = pick(suffix[index + 1], padded[index], isMax: isMax)
    }

    var output = [UInt8](repeating: 0, count: count)
    for x in 0..<count {
      let start = x + span.lo + leftPad
      output[x] = pick(suffix[start], prefix[start + length - 1], isMax: isMax)
    }
    return output
  }

  @inline(__always)
  private static func pick(_ a: UInt8, _ b: UInt8, isMax: Bool) -> UInt8 {
    isMax ? max(a, b) : min(a, b)
  }

  /// Индекс отражения без повтора края: -1 даёт 1, `count` даёт `count - 2`.
  private static func reflect101(_ index: Int, _ count: Int) -> Int {
    guard count > 1 else { return 0 }
    let period = 2 * (count - 1)
    var wrapped = index % period
    if wrapped < 0 { wrapped += period }
    return wrapped < count ? wrapped : period - wrapped
  }
}
