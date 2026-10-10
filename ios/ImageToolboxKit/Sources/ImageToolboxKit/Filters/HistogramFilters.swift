import Foundation

/// Гистограммные фильтры: выравнивание по накопленной гистограмме (Equalize).
/// CLAHE сюда не входит, он в `ClaheFilters.swift`.
///
/// Все фильтры работают на процессоре по таблицам гистограммы. Нативный код Aire и JhLabs в репозитории
/// отсутствует, поэтому выравнивание сделано стандартной накопленной формулой; отличия от Android
/// возможны, см. статусы в отчёте.
enum HistogramFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "EqualizeFilter",
      titleKey: "equalize",
      category: .histogram,
      engine: .cpu,
      make: { _ in EqualizeFilter() }
    ),
    FilterDescriptor(
      id: "EqualizeHistogramFilter",
      titleKey: "equalize_histogram",
      category: .histogram,
      engine: .cpu,
      make: { _ in EqualizeHistogramFilter() }
    ),
    FilterDescriptor(
      id: "EqualizeHistogramHSVFilter",
      titleKey: "equalize_histogram_hsv",
      category: .histogram,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "bins_count",
          kind: .number(range: 2...256, step: 1, defaultValue: 128))
      ],
      make: { EqualizeHistogramHSVFilter(bins: Int($0.number("value").rounded())) }
    ),
    FilterDescriptor(
      id: "EqualizeHistogramPixelationFilter",
      titleKey: "equalize_histogram_pixelation",
      category: .histogram,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "gridSizeX", titleKey: "grid_size_x",
          kind: .number(range: 1...200, step: 1, defaultValue: 50)),
        FilterParameter(
          key: "gridSizeY", titleKey: "grid_size_y",
          kind: .number(range: 1...200, step: 1, defaultValue: 50)),
      ],
      make: {
        EqualizeHistogramPixelationFilter(
          gridX: Int($0.number("gridSizeX").rounded()),
          gridY: Int($0.number("gridSizeY").rounded()))
      }
    ),
  ]
}

/// Выравнивает каждый канал R, G, B своей гистограммой на всей картинке. Альфа не меняется.
///
/// Статус: приближение. Android-вызов `JhFilterTransformation` (JhLabs `EqualizeFilter`) в репозитории
/// не лежит, поэтому реализована стандартная поканальная эквализация.
struct EqualizeFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    HistogramMath.equalize(&pixels, width: image.width, rect: (0, image.width, 0, image.height))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Та же поканальная эквализация, что у `EqualizeFilter`, но вызов Android идёт через Aire
/// (`Aire.equalizeHist`), нативного кода Aire в репозитории нет.
///
/// Статус: приближение. Порядок каналов и обработка почти одинаковы, но числа могут отличаться.
struct EqualizeHistogramFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    HistogramMath.equalize(&pixels, width: image.width, rect: (0, image.width, 0, image.height))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Выравнивает яркость (V = max(R, G, B)) по `bins` корзинам и сохраняет цветовой тон и насыщенность.
///
/// Статус: приближение. Android вызывает `Aire.equalizeHistHSV` (нативный код), здесь та же идея:
/// V квантуется в `bins` корзин, накопленная гистограмма задаёт новую V, RGB масштабируется на
/// `newV / oldV`. Это эквивалентно замене V в HSV без перевода цвета. Чёрные пиксели остаются чёрными,
/// потому что тон у них не определён.
struct EqualizeHistogramHSVFilter: Filter {
  /// Number of value buckets, 2...256.
  let bins: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let count = image.width * image.height
    guard count > 0 else { return image }
    var pixels = image.pixels
    var binOf = [Int](repeating: 0, count: count)
    var histogram = [Int](repeating: 0, count: bins)

    for pixel in 0..<count {
      let index = pixel * 4
      let value = Double(max(pixels[index], pixels[index + 1], pixels[index + 2])) / 255
      let bin = min(bins - 1, Int(value * Double(bins)))
      binOf[pixel] = bin
      histogram[bin] += 1
    }

    let levels = HistogramMath.equalizedLevels(histogram)
    for pixel in 0..<count {
      let index = pixel * 4
      let oldMax = max(pixels[index], pixels[index + 1], pixels[index + 2])
      guard oldMax > 0 else { continue }
      let scale = levels[binOf[pixel]] * 255 / Double(oldMax)
      for channel in 0..<3 {
        pixels[index + channel] = UInt8(
          min(255, (Double(pixels[index + channel]) * scale).rounded()))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Делит картинку на `gridX` × `gridY` прямоугольников и выравнивает каждый своей гистограммой.
/// Границы между ячейками резкие, без сглаживания, как у пикселизации.
///
/// Статус: приближение. Android вызывает `Aire.equalizeHistSquares` (нативный код).
struct EqualizeHistogramPixelationFilter: Filter {
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    var pixels = image.pixels
    for row in 0..<gridY {
      let top = row * image.height / gridY
      let bottom = (row + 1) * image.height / gridY
      for column in 0..<gridX {
        let left = column * image.width / gridX
        let right = (column + 1) * image.width / gridX
        HistogramMath.equalize(
          &pixels, width: image.width, rect: (left, right, top, bottom))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Общая арифметика гистограмм. Видна только этому файлу.
private enum HistogramMath {
  /// Накопленная эквализация одной гистограммы.
  /// Для каждого уровня возвращает новое значение в 0...1: (cdf(уровень) - cdfMin) / (N - cdfMin).
  /// Если в гистограмме один уровень, растягивать нечего, и таблица тождественна: i / (count - 1).
  static func equalizedLevels(_ histogram: [Int]) -> [Double] {
    let count = histogram.count
    let total = histogram.reduce(0, +)
    let identity = (0..<count).map { Double($0) / Double(count - 1) }
    guard let first = histogram.firstIndex(where: { $0 > 0 }) else { return identity }
    let base = histogram[first]
    guard total > base else { return identity }

    let span = Double(total - base)
    var running = 0
    return histogram.map { level in
      running += level
      return Double(max(0, running - base)) / span
    }
  }

  /// Выравнивает каналы R, G, B внутри прямоугольника. Альфа не меняется.
  /// Прямоугольник задаётся как (left, right, top, bottom), правая и нижняя границы не входят.
  static func equalize(_ pixels: inout [UInt8], width: Int, rect: (Int, Int, Int, Int)) {
    let (left, right, top, bottom) = rect
    guard right > left, bottom > top else { return }

    var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
    for y in top..<bottom {
      for x in left..<right {
        let index = (y * width + x) * 4
        for channel in 0..<3 {
          histograms[channel][Int(pixels[index + channel])] += 1
        }
      }
    }

    let tables = histograms.map { histogram in
      equalizedLevels(histogram).map { UInt8(($0 * 255).rounded()) }
    }
    for y in top..<bottom {
      for x in left..<right {
        let index = (y * width + x) * 4
        for channel in 0..<3 {
          pixels[index + channel] = tables[channel][Int(pixels[index + channel])]
        }
      }
    }
  }
}
