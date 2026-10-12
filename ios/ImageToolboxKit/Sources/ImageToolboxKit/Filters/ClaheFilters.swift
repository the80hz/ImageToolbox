import Foundation

/// CLAHE и адаптивная эквализация гистограммы.
///
/// Оба фильтра совпадают с эталоном Android. Android вызывает Aire 0.18.1
/// (`aire-filters/src/hists.rs`, `claheImpl` и `equalizeHistAdaptiveImpl`), а тот крейт
/// `histogram_equalization` 0.2.4 (`clahe_yuv_impl.rs`): картинка переводится в YCgCo (`yuv`
/// 0.8.6), плитки выравниваются только по яркости Y, цветоразностные Cg и Co остаются, значения Y
/// интерполируются между четырьмя плитками. Альфа не меняется, байты берутся как есть
/// (premultiplied).
///
/// Перевод в Lab, Luv, HSL, HSV, Oklab, Oklch и Jzazbz не перенесён: на Android это отдельные
/// вызовы Aire (`claheLAB`, `equalizeHistAdaptiveHSV` и другие), в списке фильтров их нет.
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

/// Android: `Aire.clahe(threshold, gridSizeHorizontal, gridSizeVertical)` (Aire 0.18.1, `hists.rs`,
/// `claheImpl`, `histogram_equalization` 0.2.4, `clahe_yuv_impl.rs` с `AheImplementation::Clahe`).
///
/// Обрезка гистограммы плитки (`clip_hist_clahe`) считает предел `trunc(threshold · w · h / 256)` и
/// прибавляет ко всем корзинам `trunc(excess / 256)`, где `excess` — сумма корзин, превысивших
/// предел (целиком, не только излишки). Из-за этого при `threshold` по умолчанию 0.5 и сетке 8x8 на
/// плитке 8x8 предел равен 0 и плитка обнуляется, картинка становится почти чёрной. Так считает
/// Android, это не ошибка переноса. Отрицательный `threshold` даёт предел 0.
/// Статус: проверено по эталону.
struct ClaheFilter: Filter {
  let threshold: Double
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    TileHistogramEqualizer.apply(
      image, gridX: gridX, gridY: gridY, clipThreshold: Float(threshold))
  }
}

/// Android: `Aire.equalizeHistAdaptive(gridSizeHorizontal, gridSizeVertical)` (Aire 0.18.1,
/// `hists.rs`, `equalizeHistAdaptiveImpl`, `ahe_yuv_rgba`: тот же `clahe_yuv_impl.rs` без обрезки
/// гистограммы).
/// Статус: проверено по эталону.
struct EqualizeHistogramAdaptiveFilter: Filter {
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    TileHistogramEqualizer.apply(image, gridX: gridX, gridY: gridY, clipThreshold: nil)
  }
}

/// Общий расчёт для CLAHE и адаптивной эквализации (`clahe_yuv_impl`).
///
/// Размер плитки `width / gridX` на `height / gridY` (целочисленное деление), плиток
/// `width / размер` по горизонтали и `height / размер` по вертикали; последняя плитка ряда и
/// столбца забирает остаток. Таблица плитки: `round(255 (cdf - cdfMin) / (w h - cdfMin))`. Пиксель
/// получает значение из таблиц четырёх плиток по билинейной интерполяции во `Float`; усечение до
/// байта.
///
/// Если сетка больше картинки, размер плитки в Rust оказывается нулевым и деление на него падает;
/// здесь размер плитки не меньше одного пикселя.
enum TileHistogramEqualizer {
  /// Положение пикселя вдоль одной оси: две плитки и доля второй.
  private struct Axis {
    let first: Int
    let second: Int
    let fraction: Float
  }

  /// `clipThreshold == nil` отключает обрезку гистограммы (адаптивная эквализация без CLAHE).
  static func apply(
    _ image: RasterImage, gridX: Int, gridY: Int, clipThreshold: Float?
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return image }
    let tileWidth = max(1, width / max(1, gridX))
    let tileHeight = max(1, height / max(1, gridY))
    let columns = width / tileWidth
    let rows = height / tileHeight

    var luma = [UInt8](repeating: 0, count: width * height)
    for pixel in 0..<(width * height) {
      let index = pixel * 4
      luma[pixel] = UInt8(
        AireYCgCo.components(
          Int(image.pixels[index]), Int(image.pixels[index + 1]), Int(image.pixels[index + 2])
        ).luma)
    }

    var tables = [Float](repeating: 0, count: rows * columns * 256)
    for tileRow in 0..<rows {
      let top = tileRow * tileHeight
      let bottom = tileRow + 1 == rows ? height : (tileRow + 1) * tileHeight
      for tileColumn in 0..<columns {
        let left = tileColumn * tileWidth
        let right = tileColumn + 1 == columns ? width : (tileColumn + 1) * tileWidth
        var histogram = [Int](repeating: 0, count: 256)
        for y in top..<bottom {
          for x in left..<right {
            histogram[Int(luma[y * width + x])] += 1
          }
        }
        if let clipThreshold {
          clip(&histogram, threshold: clipThreshold, width: right - left, height: bottom - top)
        }
        let table = AireHistogram.equalizationTable(
          histogram, pixelCount: Double(bottom - top) * Double(right - left))
        let base = (tileRow * columns + tileColumn) * 256
        for value in 0..<256 {
          tables[base + value] = Float(table[value])
        }
      }
    }

    let horizontal = axes(length: width, tile: tileWidth, count: columns)
    let vertical = axes(length: height, tile: tileHeight, count: rows)
    var pixels = image.pixels
    tables.withUnsafeBufferPointer { tables in
      for y in 0..<height {
        let row = vertical[y]
        for x in 0..<width {
          let column = horizontal[x]
          let value = Int(luma[y * width + x])
          let topLeft = tables[(row.first * columns + column.first) * 256 + value]
          let topRight = tables[(row.first * columns + column.second) * 256 + value]
          let bottomLeft = tables[(row.second * columns + column.first) * 256 + value]
          let bottomRight = tables[(row.second * columns + column.second) * 256 + value]
          let upper = lerp(topLeft, topRight, column.fraction)
          let lower = lerp(bottomLeft, bottomRight, column.fraction)
          let interpolated = lerp(upper, lower, row.fraction)

          let index = (y * width + x) * 4
          let source = AireYCgCo.components(
            Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
          let rgb = AireYCgCo.rgb(
            luma: Int(min(max(interpolated, 0), 255)), cg: source.cg, co: source.co)
          pixels[index] = UInt8(rgb.red)
          pixels[index + 1] = UInt8(rgb.green)
          pixels[index + 2] = UInt8(rgb.blue)
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// `a (1 - f) + b f` без слияния умножения со сложением, как `lerp` в `hist_support.rs`.
  private static func lerp(_ first: Float, _ second: Float, _ fraction: Float) -> Float {
    first * (1 - fraction) + second * fraction
  }

  /// `clip_hist_clahe`: предел `trunc(level w h / 256)` во `Double`; к корзинам выше предела
  /// добавляется весь их счёт в `excess`, сами они срезаются до предела; ко всем корзинам
  /// прибавляется `trunc(excess / 256)`.
  private static func clip(_ histogram: inout [Int], threshold: Float, width: Int, height: Int) {
    let limitValue = Double(threshold) * Double(width) * Double(height) / Double(histogram.count)
    let limit = limitValue > 0 ? Int(min(limitValue, 1e15)) : 0
    var excess = 0
    for index in histogram.indices where histogram[index] > limit {
      excess += histogram[index]
      histogram[index] = limit
    }
    let share = Int(Double(excess) / Double(histogram.count))
    for index in histogram.indices {
      histogram[index] += share
    }
  }

  /// Для каждой координаты вдоль оси: плитки по сторонам и доля второй.
  private static func axes(length: Int, tile: Int, count: Int) -> [Axis] {
    let tileSize = Float(tile)
    return (0..<length).map { position in
      let coordinate = Float(position)
      let tileFloat = (coordinate - tileSize / 2) / tileSize
      let fraction = (coordinate - (tileFloat.rounded(.towardZero) + 0.5) * tileSize) / tileSize
      let first = min(Int(max(tileFloat, 0)), count - 1)
      return Axis(first: first, second: min(first + 1, count - 1), fraction: fraction)
    }
  }
}
