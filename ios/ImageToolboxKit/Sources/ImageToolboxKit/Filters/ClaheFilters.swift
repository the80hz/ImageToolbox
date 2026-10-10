import Foundation

/// CLAHE и адаптивная эквализация гистограммы по RGB.
///
/// Статус: приближение. В Android эти фильтры вызывают нативный Aire, а формулы в Kotlin-коде нет.
/// Здесь алгоритм собран по стандартной схеме: изображение делится на плитки, для каждой плитки
/// строится гистограмма канала, у CLAHE она обрезается по пределу, затем по CDF строится таблица
/// замены, а значения пикселя интерполируются между четырьмя ближайшими плитками. Семантика
/// `threshold` в Aire неизвестна: здесь предел обрезки равен `2^threshold` от средней высоты столбца.
/// Альфа-канал не меняется. Фильтры работают с премультиплицированными значениями, как и `RasterImage`.
///
/// Перевод в Lab, Luv, HSL, HSV, Oklab, Oklch и Jzazbz не перенесён: в репозитории нет формул
/// этих преобразований, только вызовы Aire.
enum ClaheFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "ClaheFilter",
      titleKey: "clahe",
      category: .histogram,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "threshold", titleKey: "threshold",
          kind: .number(range: -10...10, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "gridSizeX", titleKey: "grid_size_x",
          kind: .number(range: 1...100, step: 1, defaultValue: 8)),
        FilterParameter(
          key: "gridSizeY", titleKey: "grid_size_y",
          kind: .number(range: 1...100, step: 1, defaultValue: 8)),
      ],
      make: {
        ClaheFilter(
          threshold: $0.number("threshold"),
          gridX: Int($0.number("gridSizeX").rounded()),
          gridY: Int($0.number("gridSizeY").rounded()))
      }),
    FilterDescriptor(
      id: "EqualizeHistogramAdaptiveFilter",
      titleKey: "equalize_histogram_adaptive",
      category: .histogram,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "gridSizeX", titleKey: "grid_size_x",
          kind: .number(range: 1...100, step: 1, defaultValue: 3)),
        FilterParameter(
          key: "gridSizeY", titleKey: "grid_size_y",
          kind: .number(range: 1...100, step: 1, defaultValue: 3)),
      ],
      make: {
        EqualizeHistogramAdaptiveFilter(
          gridX: Int($0.number("gridSizeX").rounded()),
          gridY: Int($0.number("gridSizeY").rounded()))
      }),
  ]
}

/// CLAHE по каналам R, G и B. Предел обрезки равен `2^threshold`, поэтому 0 даёт предел 1.
struct ClaheFilter: Filter {
  let threshold: Double
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    TileHistogramEqualizer.apply(
      image, gridX: gridX, gridY: gridY, clipLimit: pow(2, threshold))
  }
}

/// Адаптивная эквализация гистограммы по RGB без обрезки. Однотонное изображение не меняется.
struct EqualizeHistogramAdaptiveFilter: Filter {
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    TileHistogramEqualizer.apply(image, gridX: gridX, gridY: gridY, clipLimit: nil)
  }
}

/// Общий расчёт для CLAHE и адаптивной эквализации. Работает с 8-битными каналами.
enum TileHistogramEqualizer {
  /// `clipLimit` задаёт предел высоты столбца относительно средней высоты; `nil` отключает обрезку.
  static func apply(
    _ image: RasterImage, gridX: Int, gridY: Int, clipLimit: Double?
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    let columns = tileRanges(length: width, count: gridX)
    let rows = tileRanges(length: height, count: gridY)
    let columnCenters = centers(of: columns)
    let rowCenters = centers(of: rows)
    let columnWeights = interpolation(length: width, centers: columnCenters)
    let rowWeights = interpolation(length: height, centers: rowCenters)

    var output = image.pixels
    for channel in 0..<3 {
      let tables = lookupTables(
        image, channel: channel, columns: columns, rows: rows, clipLimit: clipLimit)
      for y in 0..<height {
        let (top, bottom, wy) = rowWeights[y]
        for x in 0..<width {
          let (left, right, wx) = columnWeights[x]
          let value = Int(image.pixels[(y * width + x) * 4 + channel])
          let topLeft = tables[(top * gridX + left) * 256 + value]
          let topRight = tables[(top * gridX + right) * 256 + value]
          let bottomLeft = tables[(bottom * gridX + left) * 256 + value]
          let bottomRight = tables[(bottom * gridX + right) * 256 + value]
          let upper = topLeft + (topRight - topLeft) * wx
          let lower = bottomLeft + (bottomRight - bottomLeft) * wx
          let result = upper + (lower - upper) * wy
          output[(y * width + x) * 4 + channel] = UInt8(min(255, max(0, result.rounded())))
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Делит длину на `count` частей без пересечений. Части могут быть пустыми, если `count` больше длины.
  private static func tileRanges(length: Int, count: Int) -> [Range<Int>] {
    (0..<count).map { index in
      (index * length / count)..<((index + 1) * length / count)
    }
  }

  private static func centers(of ranges: [Range<Int>]) -> [Double] {
    ranges.map { Double($0.lowerBound + $0.upperBound) / 2 }
  }

  /// Для каждой координаты пикселя: номера двух плиток по сторонам и доля второй из них.
  private static func interpolation(length: Int, centers: [Double]) -> [(Int, Int, Double)] {
    (0..<length).map { index in
      let position = Double(index) + 0.5
      var low = 0
      while low + 1 < centers.count, centers[low + 1] <= position {
        low += 1
      }
      guard low + 1 < centers.count, position > centers[low] else {
        return (low, low, 0)
      }
      let high = low + 1
      let share = (position - centers[low]) / (centers[high] - centers[low])
      return (low, high, share)
    }
  }

  /// Таблицы замены для одного канала: по 256 значений на каждую плитку, плитка за плиткой.
  private static func lookupTables(
    _ image: RasterImage, channel: Int, columns: [Range<Int>], rows: [Range<Int>],
    clipLimit: Double?
  ) -> [Double] {
    let width = image.width
    var tables = [Double](repeating: 0, count: columns.count * rows.count * 256)
    for (row, rowRange) in rows.enumerated() {
      for (column, columnRange) in columns.enumerated() {
        var histogram = [Int](repeating: 0, count: 256)
        for y in rowRange {
          for x in columnRange {
            histogram[Int(image.pixels[(y * width + x) * 4 + channel])] += 1
          }
        }
        let base = (row * columns.count + column) * 256
        let table = lookupTable(histogram: histogram, clipLimit: clipLimit)
        for value in 0..<256 {
          tables[base + value] = table[value]
        }
      }
    }
    return tables
  }

  /// Строит таблицу замены по гистограмме. Пустая плитка и однотонная плитка дают тождественную таблицу.
  private static func lookupTable(histogram input: [Int], clipLimit: Double?) -> [Double] {
    var histogram = input
    let total = histogram.reduce(0, +)
    let identity = (0..<256).map { Double($0) }
    guard total > 0 else { return identity }

    if let clipLimit {
      let average = Double(total) / 256
      let limit = max(1, Int((clipLimit * average).rounded(.down)))
      var excess = 0
      for value in 0..<256 where histogram[value] > limit {
        excess += histogram[value] - limit
        histogram[value] = limit
      }
      let share = excess / 256
      let remainder = excess % 256
      for value in 0..<256 {
        histogram[value] += share + (value < remainder ? 1 : 0)
      }
    }

    var cumulative = [Int](repeating: 0, count: 256)
    var running = 0
    for value in 0..<256 {
      running += histogram[value]
      cumulative[value] = running
    }
    let minimum = cumulative.first { $0 > 0 } ?? 0
    let denominator = total - minimum
    guard denominator > 0 else { return identity }
    return (0..<256).map { value in
      let scaled = Double(cumulative[value] - minimum) * 255 / Double(denominator)
      return min(255, max(0, scaled.rounded()))
    }
  }
}
