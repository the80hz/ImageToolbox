import Foundation

/// Гистограммные фильтры: выравнивание по накопленной гистограмме (Equalize).
/// CLAHE и адаптивное выравнивание сюда не входят, они в `ClaheFilters.swift`.
///
/// Все фильтры работают на процессоре и совпадают с эталоном Android. Формулы взяты из исходников:
/// `EqualizeFilter` из Jh Labs (T8RIN/ImageToolboxLibs 8.1.0), остальные из Aire 0.18.1
/// (`aire-filters/src/hists.rs`, `equalize_hist.rs`) и крейтов, которые он собирает:
/// `histogram_equalization` 0.2.4, `colorutils-rs` 0.7.5, `yuv` 0.8.6, `erydanos` 0.2.
/// Все четыре Aire-фильтра считают по сохранённым (premultiplied) байтам, альфа не меняется.
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

/// Android: Jh Labs `EqualizeFilter` (T8RIN/ImageToolboxLibs 8.1.0,
/// `libs/jhlabs/src/main/rust/jhlabs/src/lib.rs`, функция `equalize`). Каждый канал R, G, B своей
/// таблицей: `round(накопленное число * 255 / N)` во `Float`, без вычитания минимума. Поэтому
/// однотонная картинка становится белой (255). Альфа не меняется, байты берутся как есть, без
/// снятия premultiplied.
/// Статус: проверено по эталону.
struct EqualizeFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    let count = image.width * image.height
    guard count > 0 else { return image }
    var pixels = image.pixels
    var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      for channel in 0..<3 {
        histograms[channel][Int(pixels[index + channel])] += 1
      }
    }
    let tables = histograms.map { histogram -> [UInt8] in
      var sum = 0
      return histogram.map { entry in
        sum += entry
        return UInt8((Float(sum) * 255 / Float(count)).rounded())
      }
    }
    for index in stride(from: 0, to: pixels.count, by: 4) {
      for channel in 0..<3 {
        pixels[index + channel] = tables[channel][Int(pixels[index + channel])]
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `Aire.equalizeHist` (`hists.rs`, `equalizeHistImpl`, крейт `histogram_equalization`
/// 0.2.4, `hist_equal_yuv_impl.rs`). Картинка переводится в YCgCo, выравнивается гистограмма
/// яркости Y (256 корзин, `round(255 (cdf - cdfMin) / (N - cdfMin))`), цветоразностные Cg и Co
/// остаются, затем обратный перевод. Перевод целочисленный, формулы крейта `yuv` 0.8.6
/// (`rgb_to_ycgco.rs`).
/// Статус: проверено по эталону.
struct EqualizeHistogramFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    let count = image.width * image.height
    guard count > 0 else { return image }
    var pixels = image.pixels
    var histogram = [Int](repeating: 0, count: 256)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let source = AireYCgCo.components(
        Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
      histogram[source.luma] += 1
    }
    let table = AireHistogram.equalizationTable(histogram, pixelCount: Double(count))
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let source = AireYCgCo.components(
        Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
      let rgb = AireYCgCo.rgb(luma: table[source.luma], cg: source.cg, co: source.co)
      pixels[index] = UInt8(rgb.red)
      pixels[index + 1] = UInt8(rgb.green)
      pixels[index + 2] = UInt8(rgb.blue)
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `Aire.equalizeHistHSV` (`hists.rs`, `equalizeHistHSVImpl`, `histogram_equalization`
/// 0.2.4, `hist_equal_impl.rs`, цвет через `colorutils-rs` 0.7.5). Картинка переводится в HSV, где
/// H в целых градусах, S и V целые в `0...bins-1`; выравнивается гистограмма V по `bins` корзинам
/// (`round((bins-1) (cdf - cdfMin) / (N - cdfMin))`), H и S остаются, затем обратный перевод.
///
/// В `colorutils-rs` блоки по 16 и по 8 пикселей идут NEON-кодом (`neon/colors.rs`), хвост строки
/// скалярным (`hsv.rs`). Они считают по-разному: NEON берёт оценку `1 / x` (`vrecpeq_f32`),
/// округляет H, S, V и результат до ближайшего целого, скалярный путь усекает H и результат. Оба
/// пути здесь воспроизведены, число пикселей NEON-пути — `AireHSV.vectorPixelCount`. Если все V в
/// картинке одинаковы, `cdf - cdfMin` для них 0 и деление на `N - cdfMin` даёт `NaN`; Rust `min`
/// отдаёт тогда верхнюю границу, и V становится максимальным.
/// Статус: проверено по эталону.
struct EqualizeHistogramHSVFilter: Filter {
  /// Number of value buckets, 2...256.
  let bins: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let count = image.width * image.height
    guard count > 0 else { return image }
    let bins = max(2, bins)
    let scale = Float(bins - 1)
    let inverseScale = 1 / scale
    let vectorEnd = AireHSV.vectorPixelCount(width: image.width)
    var pixels = image.pixels

    var histogram = [Int](repeating: 0, count: bins)
    pixels.withUnsafeBufferPointer { buffer in
      for row in 0..<image.height {
        for column in 0..<image.width {
          let index = (row * image.width + column) * 4
          let quantized = AireHSV.quantize(
            buffer[index], buffer[index + 1], buffer[index + 2],
            scale: scale, vector: column < vectorEnd)
          histogram[min(quantized.value, bins - 1)] += 1
        }
      }
    }
    let table = AireHistogram.equalizationTable(histogram, pixelCount: Double(count))

    pixels.withUnsafeMutableBufferPointer { buffer in
      for row in 0..<image.height {
        for column in 0..<image.width {
          let index = (row * image.width + column) * 4
          let isVector = column < vectorEnd
          let quantized = AireHSV.quantize(
            buffer[index], buffer[index + 1], buffer[index + 2], scale: scale, vector: isVector)
          let rgb = AireHSV.rgb(
            hue: quantized.hue, saturation: quantized.saturation,
            value: table[min(quantized.value, bins - 1)],
            inverseScale: inverseScale, vector: isVector)
          buffer[index] = rgb.red
          buffer[index + 1] = rgb.green
          buffer[index + 2] = rgb.blue
        }
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `Aire.equalizeHistSquares` (`aire-filters/src/equalize_hist.rs`,
/// `equalize_histogram_squares_rgba`). Картинка делится на плитки размером `width / gridX` на
/// `height / gridY` (последняя плитка ряда и столбца забирает остаток), в каждой плитке свой HSV
/// (скалярный `colorutils-rs`, H и S в `Float`) и гистограмма V из 101 корзины (`round(V * 100)`);
/// новая V — `round(100 (cdf - cdfMin) / (N - cdfMin)) / 100`, результат усекается до байта.
/// Плитка из одного пикселя (по умолчанию 64x64 на сетке 50x50) всегда получает V = 1.
///
/// Если плитка больше картинки (сетка 100 на картинке в 50 пикселей), Rust делит на нуль и падает;
/// здесь размер плитки не меньше одного пикселя.
/// Статус: проверено по эталону.
struct EqualizeHistogramPixelationFilter: Filter {
  let gridX: Int
  let gridY: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return image }
    let tileWidth = max(1, width / max(1, gridX))
    let tileHeight = max(1, height / max(1, gridY))
    let columns = width / tileWidth
    let rows = height / tileHeight
    var pixels = image.pixels
    pixels.withUnsafeMutableBufferPointer { buffer in
      for tileRow in 0..<rows {
        let top = tileRow * tileHeight
        let bottom = tileRow + 1 == rows ? height : (tileRow + 1) * tileHeight
        for tileColumn in 0..<columns {
          let left = tileColumn * tileWidth
          let right = tileColumn + 1 == columns ? width : (tileColumn + 1) * tileWidth
          equalize(buffer, width: width, left: left, right: right, top: top, bottom: bottom)
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// Выравнивает V в одной плитке (границы справа и снизу не входят).
  private func equalize(
    _ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int,
    left: Int, right: Int, top: Int, bottom: Int
  ) {
    var histogram = [Int](repeating: 0, count: 101)
    for y in top..<bottom {
      for x in left..<right {
        let index = (y * width + x) * 4
        let hsv = AireHSV.scalarHSV(buffer[index], buffer[index + 1], buffer[index + 2])
        histogram[AireHSV.percentBin(hsv.value)] += 1
      }
    }
    let pixelCount = Double((right - left) * (bottom - top))
    let cumulative = AireHistogram.cumulative(histogram)
    let minimum = Double(cumulative.min() ?? 0)
    let distance = 1 / (pixelCount - minimum)
    let levels = cumulative.map { entry -> Float in
      let scaled = (100 * (Double(entry) - minimum) * distance).rounded()
      return Float(AireHistogram.rustMin(scaled, 100)) / 100
    }
    for y in top..<bottom {
      for x in left..<right {
        let index = (y * width + x) * 4
        let hsv = AireHSV.scalarHSV(buffer[index], buffer[index + 1], buffer[index + 2])
        let rgb = AireHSV.scalarRGB(
          hue: hsv.hue, saturation: hsv.saturation, value: levels[AireHSV.percentBin(hsv.value)])
        buffer[index] = rgb.red
        buffer[index + 1] = rgb.green
        buffer[index + 2] = rgb.blue
      }
    }
  }
}

/// Накопленные гистограммы и таблицы выравнивания `histogram_equalization` 0.2.4
/// (`hist_support.rs`).
enum AireHistogram {
  /// Rust `f64::min`: `NaN` в одном из аргументов отдаёт другой.
  static func rustMin(_ lhs: Double, _ rhs: Double) -> Double {
    if lhs.isNaN { return rhs }
    if rhs.isNaN { return lhs }
    return min(lhs, rhs)
  }

  static func cumulative(_ histogram: [Int]) -> [Int] {
    var sum = 0
    return histogram.map { entry in
      sum += entry
      return sum
    }
  }

  /// Таблица замены корзины: `round(top (cdf - cdfMin) / (pixelCount - cdfMin))`, `top = bins - 1`,
  /// в диапазоне `0...top`. Минимум берётся по всем корзинам, то есть это `cdf[0]`. Если деление
  /// даёт `NaN` (все пиксели в корзине 0), результат `top`, как у Rust `.min(top)`.
  static func equalizationTable(_ histogram: [Int], pixelCount: Double) -> [Int] {
    let top = Double(histogram.count - 1)
    let cumulative = cumulative(histogram)
    let minimum = Double(cumulative.min() ?? 0)
    let distance = 1 / (pixelCount - minimum)
    return cumulative.map { entry in
      let scaled = (top * (Double(entry) - minimum) * distance).rounded()
      return Int(max(rustMin(scaled, top), 0))
    }
  }
}

/// YCgCo полного диапазона, целочисленный, 13 бит точности: `yuv` 0.8.6, `rgb_to_ycgco.rs` (4:4:4)
/// и `ycgco_to_rgb_alpha.rs`.
enum AireYCgCo {
  @inline(__always)
  static func components(_ red: Int, _ green: Int, _ blue: Int) -> (luma: Int, cg: Int, co: Int) {
    let bias = 4095
    let chromaBias = 128 * 8192 + 4095
    let luma = (4096 * green + 2048 * (red + blue) + bias) >> 13
    let cg = (4096 * green - 2048 * (red + blue) + chromaBias) >> 13
    let co = (4096 * (red - blue) + chromaBias) >> 13
    return (min(max(luma, 0), 255), min(max(cg, 0), 255), min(max(co, 0), 255))
  }

  @inline(__always)
  static func rgb(luma: Int, cg: Int, co: Int) -> (red: Int, green: Int, blue: Int) {
    let shifted = luma - (cg - 128)
    let chroma = co - 128
    return (
      min(max(shifted + chroma, 0), 255),
      min(max(luma + (cg - 128), 0), 255),
      min(max(shifted - chroma, 0), 255)
    )
  }
}

/// HSV `colorutils-rs` 0.7.5 в двух вариантах: скалярный (`hsv.rs`) и NEON (`neon/colors.rs`).
enum AireHSV {
  private static let byteScale = 1 / Float(255)
  private static let sixtieth = 1 / Float(60)

  /// Сколько первых пикселей строки обрабатывает NEON: блоки по 16 и затем по 8 (`while cx + 16 <
  /// width`, `while cx + 8 < width`).
  static func vectorPixelCount(width: Int) -> Int {
    var count = 0
    while count + 16 < width { count += 16 }
    while count + 8 < width { count += 8 }
    return count
  }

  /// `(v * 100).round().min(100).max(0)` для корзин по 101 (`make_histogram_channel_3_region`).
  static func percentBin(_ value: Float) -> Int {
    let scaled = (value * 100).rounded()
    return scaled.isNaN ? 100 : Int(min(max(scaled, 0), 100))
  }

  /// Rust `as u8`: усечение с насыщением, `NaN` даёт 0.
  private static func saturatingByte(_ value: Float) -> UInt8 {
    guard value > 0 else { return 0 }
    return value >= 255 ? 255 : UInt8(value)
  }

  // MARK: Скалярный путь

  static func scalarHSV(_ red: UInt8, _ green: UInt8, _ blue: UInt8)
    -> (hue: Float, saturation: Float, value: Float)
  {
    let r = Float(red) * byteScale
    let g = Float(green) * byteScale
    let b = Float(blue) * byteScale
    let maximum = max(r, g, b)
    let delta = maximum - min(r, g, b)
    var hue: Float = 0
    var saturation: Float = 0
    if delta > 0 {
      if maximum == r {
        hue = 60 * fmodf((g - b) / delta, 6)
      } else if maximum == g {
        hue = 60 * ((b - r) / delta + 2)
      } else if maximum == b {
        hue = 60 * ((r - g) / delta + 4)
      }
      if maximum > 0 { saturation = delta / maximum }
    }
    if hue < 0 { hue += 360 }
    return (hue, saturation, maximum)
  }

  static func scalarRGB(hue: Float, saturation: Float, value: Float)
    -> (red: UInt8, green: UInt8, blue: UInt8)
  {
    let chroma = value * saturation
    let sector = fmodf(hue / 60, 6)
    let x = chroma * (1 - abs(fmodf(sector, 2) - 1))
    let offset = value - chroma
    let parts: (Float, Float, Float)
    switch sector {
    case 0..<1: parts = (chroma, x, 0)
    case 1..<2: parts = (x, chroma, 0)
    case 2..<3: parts = (0, chroma, x)
    case 3..<4: parts = (0, x, chroma)
    case 4..<5: parts = (x, 0, chroma)
    case 5..<6: parts = (chroma, 0, x)
    default: parts = (0, 0, 0)
    }
    return (
      saturatingByte((parts.0 + offset) * 255),
      saturatingByte((parts.1 + offset) * 255),
      saturatingByte((parts.2 + offset) * 255)
    )
  }

  // MARK: Перевод в целые H, S, V и обратно (пайплайн `u16`)

  /// `rgba_to_hsv` в `u16`: H в градусах, S и V умножены на `scale` и округлены. Скалярный путь
  /// усекает H, NEON округляет.
  static func quantize(
    _ red: UInt8, _ green: UInt8, _ blue: UInt8, scale: Float, vector: Bool
  ) -> (hue: Int, saturation: Int, value: Int) {
    if !vector {
      let hsv = scalarHSV(red, green, blue)
      return (
        Int(hsv.hue), Int((hsv.saturation * scale).rounded()), Int((hsv.value * scale).rounded())
      )
    }
    let r = Float(red) * byteScale
    let g = Float(green) * byteScale
    let b = Float(blue) * byteScale
    let maximum = max(r, g, b)
    let delta = maximum - min(r, g, b)
    let reciprocal = NEONEmulation.reciprocalEstimate(delta)
    var hue: Float = 0
    if maximum == r { hue = NEONEmulation.fmod((g - b) * reciprocal, 6) * 60 }
    if maximum == g { hue = ((b - r) * reciprocal + 2) * 60 }
    if maximum == b { hue = ((r - g) * reciprocal + 4) * 60 }
    if delta == 0 { hue = 0 }
    let saturation: Float =
      maximum == 0 ? 0 : delta * NEONEmulation.reciprocalEstimate(maximum)
    if hue < 0 { hue += 360 }
    return (
      NEONEmulation.roundToUnsigned(hue),
      NEONEmulation.roundToUnsigned(saturation * scale),
      NEONEmulation.roundToUnsigned(maximum * scale)
    )
  }

  /// `hsv_to_rgba` из `u16`. Скалярный путь усекает результат, NEON округляет.
  static func rgb(
    hue: Int, saturation: Int, value: Int, inverseScale: Float, vector: Bool
  ) -> (red: UInt8, green: UInt8, blue: UInt8) {
    let s = Float(saturation) * inverseScale
    let v = Float(value) * inverseScale
    if !vector {
      return scalarRGB(hue: Float(hue), saturation: s, value: v)
    }
    let chroma = s * v
    let sector = NEONEmulation.fmod(Float(hue) * sixtieth, 6)
    let x = (1 - abs(NEONEmulation.fmod(sector, 2) - 1)) * chroma
    let offset = v - chroma
    var red: Float = 0
    var green: Float = 0
    var blue: Float = 0
    switch sector {
    case 0..<1: (red, green) = (chroma, x)
    case 1..<2: (red, green) = (x, chroma)
    case 2..<3: (green, blue) = (chroma, x)
    case 3..<4: (green, blue) = (x, chroma)
    case 4..<5: (red, blue) = (x, chroma)
    case 5..<6: (red, blue) = (chroma, x)
    default: break
    }
    return (
      UInt8(min(NEONEmulation.roundToUnsigned((red + offset) * 255), 255)),
      UInt8(min(NEONEmulation.roundToUnsigned((green + offset) * 255), 255)),
      UInt8(min(NEONEmulation.roundToUnsigned((blue + offset) * 255), 255))
    )
  }
}
