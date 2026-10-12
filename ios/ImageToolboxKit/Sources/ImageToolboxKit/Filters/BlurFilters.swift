import Foundation

/// Размытия: гауссово, box, motion, zoom, bokeh, tilt-shift и прочие из Android.
///
/// Нативные алгоритмы Aire, Trickle и GPUImage в репозитории не лежат, поэтому каждый фильтр
/// считает операцию по видимым в Kotlin параметрам и значениям по умолчанию. Там, где точная
/// формула неизвестна, фильтр помечен как приближение (см. комментарий у структуры).
///
/// Each filter is a struct conforming to `Filter` in this file, with its descriptor listed below.
enum BlurFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "BoxBlurFilter",
      titleKey: "box_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "box_blur",
          kind: .number(range: 0...100, step: 1, defaultValue: 10))
      ],
      make: { BoxBlurFilter(radius: Int($0.number("value"))) }
    ),
    FilterDescriptor(
      id: "GaussianBlurFilter",
      titleKey: "gaussian_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "radius", titleKey: "radius",
          kind: .number(range: 0...100, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "sigma", titleKey: "sigma",
          kind: .number(range: 1...100, step: 0.01, defaultValue: 10)),
        FilterParameter(
          key: "edgeMode", titleKey: "edge_mode",
          kind: .choice(options: BlurBorderMode.allOptions, defaultValue: "Reflect101")),
      ],
      make: {
        GaussianBlurFilter(
          radius: Int($0.number("radius")), sigma: $0.number("sigma"),
          edge: BlurBorderMode.from($0.choice("edgeMode")))
      }
    ),
    FilterDescriptor(
      id: "MotionBlurFilter",
      titleKey: "motion_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "justSize", titleKey: "just_size",
          kind: .number(range: 0...201, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "angle", titleKey: "angle",
          kind: .number(range: 0...360, step: 0.01, defaultValue: 45)),
        FilterParameter(
          key: "edgeMode", titleKey: "edge_mode",
          kind: .choice(options: BlurBorderMode.allOptions, defaultValue: "Reflect101")),
      ],
      make: {
        MotionBlurFilter(
          size: $0.number("justSize"), degrees: $0.number("angle"),
          edge: BlurBorderMode.from($0.choice("edgeMode")))
      }
    ),
    FilterDescriptor(
      id: "ZoomBlurFilter",
      titleKey: "zoom_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "blurCenterX", titleKey: "blur_center_x",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "blurCenterY", titleKey: "blur_center_y",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "blurSize", titleKey: "blur_size",
          kind: .number(range: 0...10, step: 0.01, defaultValue: 5)),
      ],
      make: {
        ZoomBlurFilter(
          centerX: $0.number("blurCenterX"), centerY: $0.number("blurCenterY"),
          size: $0.number("blurSize"))
      }
    ),
    FilterDescriptor(
      id: "BokehFilter",
      titleKey: "bokeh",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "justSize", titleKey: "just_size",
          kind: .number(range: 1...150, step: 1, defaultValue: 6)),
        FilterParameter(
          key: "amount", titleKey: "amount",
          kind: .number(range: 3...40, step: 1, defaultValue: 6)),
      ],
      make: {
        BokehFilter(size: $0.number("justSize"), sides: $0.number("amount"))
      }
    ),
    FilterDescriptor(
      id: "LinearTiltShiftFilter",
      titleKey: "linear_tilt_shift",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "blurRadius", titleKey: "blur_radius",
          kind: .number(range: 1...100, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "sigma", titleKey: "sigma",
          kind: .number(range: 1...50, step: 0.01, defaultValue: 10)),
        FilterParameter(
          key: "centerX", titleKey: "center_x",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "centerY", titleKey: "center_y",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "size", titleKey: "size",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.2)),
        FilterParameter(
          key: "angle", titleKey: "angle",
          kind: .number(range: 0...360, step: 1, defaultValue: 45)),
      ],
      make: {
        LinearTiltShiftFilter(
          blurRadius: Int($0.number("blurRadius")), sigma: $0.number("sigma"),
          anchorX: $0.number("centerX"), anchorY: $0.number("centerY"),
          hole: $0.number("size"), degrees: $0.number("angle"))
      }
    ),
    FilterDescriptor(
      id: "RadialTiltShiftFilter",
      titleKey: "tilt_shift",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "blurRadius", titleKey: "blur_radius",
          kind: .number(range: 1...100, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "sigma", titleKey: "sigma",
          kind: .number(range: 1...50, step: 0.01, defaultValue: 10)),
        FilterParameter(
          key: "centerX", titleKey: "center_x",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "centerY", titleKey: "center_y",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "radius", titleKey: "radius",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 0.2)),
      ],
      make: {
        RadialTiltShiftFilter(
          blurRadius: Int($0.number("blurRadius")), sigma: $0.number("sigma"),
          anchorX: $0.number("centerX"), anchorY: $0.number("centerY"),
          hole: $0.number("radius"))
      }
    ),
    FilterDescriptor(
      id: "FastBlurFilter",
      titleKey: "fast_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "scale", titleKey: "scale",
          kind: .number(range: 0.1...1, step: 0.01, defaultValue: 0.5)),
        FilterParameter(
          key: "radius", titleKey: "radius",
          kind: .number(range: 0...100, step: 1, defaultValue: 5)),
      ],
      make: {
        FastBlurFilter(scale: $0.number("scale"), radius: Int($0.number("radius").rounded()))
      }
    ),
    FilterDescriptor(
      id: "NativeStackBlurFilter",
      titleKey: "native_stack_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "native_stack_blur",
          kind: .number(range: 3...250, step: 1, defaultValue: 25))
      ],
      make: { NativeStackBlurFilter(radius: Int($0.number("value"))) }
    ),
    FilterDescriptor(
      id: "MedianBlurFilter",
      titleKey: "median_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "radius",
          kind: .number(range: 0...100, step: 1, defaultValue: 10))
      ],
      make: { MedianBlurFilter(radius: Int($0.number("value"))) }
    ),
    FilterDescriptor(
      id: "TentBlurFilter",
      titleKey: "tent_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "tent_blur",
          kind: .number(range: 1...300, step: 1, defaultValue: 10))
      ],
      make: { TentBlurFilter(size: $0.number("value")) }
    ),
    FilterDescriptor(
      id: "BilaterialBlurFilter",
      titleKey: "bilaterial_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "radius", titleKey: "radius",
          kind: .number(range: 1...50, step: 1, defaultValue: 12)),
        FilterParameter(
          key: "sigma", titleKey: "sigma",
          kind: .number(range: 1...100, step: 0.1, defaultValue: 10)),
        FilterParameter(
          key: "spatialSigma", titleKey: "spatial_sigma",
          kind: .number(range: 1...100, step: 0.1, defaultValue: 3)),
        FilterParameter(
          key: "edgeMode", titleKey: "edge_mode",
          kind: .choice(options: BlurBorderMode.allOptions, defaultValue: "Reflect101")),
      ],
      make: {
        // Заголовки в Ui: "sigma" управляет spatialSigma, "spatial_sigma" - rangeSigma
        // (порядок полей BilaterialBlurParams и значения по умолчанию совпадают с этим).
        BilaterialBlurFilter(
          radius: Int($0.number("radius")), spatialSigma: $0.number("sigma"),
          rangeSigma: $0.number("spatialSigma"), edge: BlurBorderMode.from($0.choice("edgeMode")))
      }
    ),
    FilterDescriptor(
      id: "FastBilaterialBlurFilter",
      titleKey: "fast_bilaterial_blur",
      category: .blur,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "justSize", titleKey: "just_size",
          kind: .number(range: 1...200, step: 1, defaultValue: 11)),
        FilterParameter(
          key: "sigma", titleKey: "sigma",
          kind: .number(range: 1...100, step: 0.1, defaultValue: 10)),
        FilterParameter(
          key: "spatialSigma", titleKey: "spatial_sigma",
          kind: .number(range: 1...100, step: 0.1, defaultValue: 3)),
      ],
      make: {
        // Как и в BilaterialBlurFilter: "sigma" - пространственная, "spatialSigma" - по цвету.
        FastBilaterialBlurFilter(
          size: $0.number("justSize"), spatialSigma: $0.number("sigma"),
          rangeSigma: $0.number("spatialSigma"))
      }
    ),
  ]
}

/// Что делать с пикселями за краем картинки. Названия совпадают с `BlurEdgeMode` из Kotlin.
enum BlurBorderMode: String, CaseIterable, Sendable {
  case clamp = "Clamp"
  case wrap = "Wrap"
  case reflect = "Reflect"
  case reflect101 = "Reflect101"

  static var allOptions: [String] { allCases.map(\.rawValue) }

  /// Режим по имени; неизвестное имя даёт `reflect101`, как значение по умолчанию.
  static func from(_ name: String) -> BlurBorderMode {
    BlurBorderMode(rawValue: name) ?? .reflect101
  }

  /// Переводит индекс вне отрезка `0..<n` внутрь него по правилам режима.
  func index(_ i: Int, count n: Int) -> Int {
    guard n > 1 else { return 0 }
    switch self {
    case .clamp:
      return min(max(i, 0), n - 1)
    case .wrap:
      return ((i % n) + n) % n
    case .reflect:
      // d c b a | a b c d: период 2n
      let period = 2 * n
      let j = ((i % period) + period) % period
      return j < n ? j : period - 1 - j
    case .reflect101:
      // d c b | a b c d: период 2(n-1)
      let period = 2 * (n - 1)
      let j = ((i % period) + period) % period
      return j < n ? j : period - j
    }
  }
}

/// Premultiplied RGBA как `Float` в диапазоне 0...255. Строка 0 сверху.
private struct BlurPlane {
  let width: Int
  let height: Int
  var values: [Float]

  init(width: Int, height: Int, values: [Float]) {
    self.width = width
    self.height = height
    self.values = values
  }

  init(_ image: RasterImage) {
    width = image.width
    height = image.height
    values = image.pixels.map { Float($0) }
  }

  /// Округляет и ограничивает значения. Цвет не больше альфы, чтобы premultiplied остался верным.
  func raster() -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: values.count)
    for index in stride(from: 0, to: values.count, by: 4) {
      let alpha = min(max(values[index + 3].rounded(), 0), 255)
      pixels[index + 3] = UInt8(alpha)
      for channel in 0..<3 {
        pixels[index + channel] = UInt8(min(max(values[index + channel].rounded(), 0), alpha))
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }
}

/// Прогоняет картинку через `body` в виде `BlurPlane` и возвращает результат того же размера.
private func filtered(_ image: RasterImage, _ body: (BlurPlane) -> BlurPlane) -> RasterImage {
  body(BlurPlane(image)).raster()
}

/// Индексы отсчётов: для позиции `i` и смещения `offsets[k]` элемент `i * offsets.count + k`.
private func edgeTable(length: Int, offsets: [Int], edge: BlurBorderMode) -> [Int] {
  var table = [Int](repeating: 0, count: length * offsets.count)
  for i in 0..<length {
    for (k, offset) in offsets.enumerated() {
      table[i * offsets.count + k] = edge.index(i + offset, count: length)
    }
  }
  return table
}

/// Нормирует веса так, чтобы их сумма была 1.
private func normalized(_ raw: [Double]) -> [Float] {
  let total = raw.reduce(0, +)
  return raw.map { Float($0 / total) }
}

/// Одинаковые веса на `2r+1` отсчётов.
private func boxWeights(radius: Int) -> [Float] {
  normalized(Array(repeating: 1.0, count: 2 * max(0, radius) + 1))
}

/// Треугольные веса `r + 1 - |k|`: свёртка двух box-фильтров (stack blur).
private func triangleWeights(radius: Int) -> [Float] {
  let r = max(0, radius)
  return normalized((-r...r).map { Double(r + 1 - abs($0)) })
}

/// Гауссово ядро, каждый вес - интеграл плотности по отрезку пикселя (как `GaussianPreciseLevel.INTEGRAL`).
private func gaussianWeights(radius: Int, sigma: Double) -> [Float] {
  let s = max(sigma, 1e-6) * 2.0.squareRoot()
  return normalized(
    (-max(0, radius)...max(0, radius)).map { offset -> Double in
      let k = Double(offset)
      return 0.5 * (erf((k + 0.5) / s) - erf((k - 0.5) / s))
    })
}

/// Ближайшее нечётное число; как `roundToNearestOdd` в Kotlin.
private func nearestOdd(_ value: Double) -> Int {
  let n = max(0, Int(value.rounded()))
  return n % 2 == 0 ? n + 1 : n
}

/// Одномерная свёртка вдоль строк (`horizontal`) или столбцов. Веса нечётной длины, центр посередине.
private func convolve(
  _ plane: BlurPlane, weights: [Float], horizontal: Bool, edge: BlurBorderMode
) -> BlurPlane {
  let taps = weights.count
  let offsets = (0..<taps).map { $0 - taps / 2 }
  let width = plane.width
  let length = horizontal ? plane.width : plane.height
  let lines = horizontal ? plane.height : plane.width
  let table = edgeTable(length: length, offsets: offsets, edge: edge)
  var values = [Float](repeating: 0, count: plane.values.count)
  for line in 0..<lines {
    for position in 0..<length {
      let target =
        horizontal
        ? (line * width + position) * 4
        : (position * width + line) * 4
      for k in 0..<taps {
        let sample = table[position * taps + k]
        let source = horizontal ? (line * width + sample) * 4 : (sample * width + line) * 4
        let weight = weights[k]
        for c in 0..<4 {
          values[target + c] += weight * plane.values[source + c]
        }
      }
    }
  }
  return BlurPlane(width: plane.width, height: plane.height, values: values)
}

/// Два прохода свёртки: по строкам, затем по столбцам.
private func separable(_ plane: BlurPlane, weights: [Float], edge: BlurBorderMode) -> BlurPlane {
  let rows = convolve(plane, weights: weights, horizontal: true, edge: edge)
  return convolve(rows, weights: weights, horizontal: false, edge: edge)
}

/// Медиана по квадрату `(2r+1) x (2r+1)` отдельно для каждого канала.
private func medianBlur(_ plane: BlurPlane, radius: Int, edge: BlurBorderMode) -> BlurPlane {
  let r = max(0, radius)
  let offsets = Array(-r...r)
  let taps = offsets.count
  let columns = edgeTable(length: plane.width, offsets: offsets, edge: edge)
  let rows = edgeTable(length: plane.height, offsets: offsets, edge: edge)
  var values = [Float](repeating: 0, count: plane.values.count)
  var window: [Float] = []
  window.reserveCapacity(taps * taps)
  for y in 0..<plane.height {
    for x in 0..<plane.width {
      for c in 0..<4 {
        window.removeAll(keepingCapacity: true)
        for ky in 0..<taps {
          let row = rows[y * taps + ky]
          for kx in 0..<taps {
            let column = columns[x * taps + kx]
            window.append(plane.values[(row * plane.width + column) * 4 + c])
          }
        }
        window.sort()
        values[(y * plane.width + x) * 4 + c] = window[window.count / 2]
      }
    }
  }
  return BlurPlane(width: plane.width, height: plane.height, values: values)
}

/// Билатеральный фильтр: веса по расстоянию и по разнице цветов RGB (шкала 0...255).
/// Точная сумма по окну, без быстрой сеточной аппроксимации.
private func bilateral(
  _ plane: BlurPlane, radius: Int, spatialSigma: Double, rangeSigma: Double, edge: BlurBorderMode
) -> BlurPlane {
  let r = max(0, radius)
  let offsets = Array(-r...r)
  let taps = offsets.count
  let columns = edgeTable(length: plane.width, offsets: offsets, edge: edge)
  let rows = edgeTable(length: plane.height, offsets: offsets, edge: edge)
  var spatial = [Double](repeating: 0, count: taps * taps)
  let spatialDenominator = 2 * spatialSigma * spatialSigma
  for ky in 0..<taps {
    for kx in 0..<taps {
      let dx = Double(offsets[kx])
      let dy = Double(offsets[ky])
      spatial[ky * taps + kx] = exp(-(dx * dx + dy * dy) / spatialDenominator)
    }
  }
  let rangeDenominator = 2 * rangeSigma * rangeSigma
  var values = [Float](repeating: 0, count: plane.values.count)
  var sums = [Double](repeating: 0, count: 4)
  for y in 0..<plane.height {
    for x in 0..<plane.width {
      let centre = (y * plane.width + x) * 4
      for c in 0..<4 { sums[c] = 0 }
      var total = 0.0
      for ky in 0..<taps {
        for kx in 0..<taps {
          let source = (rows[y * taps + ky] * plane.width + columns[x * taps + kx]) * 4
          var difference = 0.0
          for c in 0..<3 {
            let delta = Double(plane.values[source + c] - plane.values[centre + c])
            difference += delta * delta
          }
          let weight = spatial[ky * taps + kx] * exp(-difference / rangeDenominator)
          total += weight
          for c in 0..<4 {
            sums[c] += weight * Double(plane.values[source + c])
          }
        }
      }
      for c in 0..<4 {
        values[centre + c] = Float(sums[c] / total)
      }
    }
  }
  return BlurPlane(width: plane.width, height: plane.height, values: values)
}

/// Точки ядра `size x size` внутри правильного многоугольника с `sides` сторонами (индексы в квадрате).
private func bokehKernel(size: Int, sides: Int) -> [(Int, Int)] {
  let half = size / 2
  let radius = Double(size) / 2
  let apothem = radius * cos(Double.pi / Double(sides))
  var points: [(Int, Int)] = []
  for iy in 0..<size {
    for ix in 0..<size {
      let dx = Double(ix - half)
      let dy = Double(iy - half)
      let inside = (0..<sides).allSatisfy { i -> Bool in
        let normal = -Double.pi / 2 + (2 * Double(i) + 1) * Double.pi / Double(sides)
        return dx * cos(normal) + dy * sin(normal) <= apothem + 1e-9
      }
      if inside { points.append((ix, iy)) }
    }
  }
  return points
}

/// Морфологическая дилатация (максимум по ядру) с границей reflect101.
private func dilate(_ plane: BlurPlane, size: Int, points: [(Int, Int)]) -> BlurPlane {
  let offsets = (0..<size).map { $0 - size / 2 }
  let columns = edgeTable(length: plane.width, offsets: offsets, edge: .reflect101)
  let rows = edgeTable(length: plane.height, offsets: offsets, edge: .reflect101)
  var values = [Float](repeating: 0, count: plane.values.count)
  for y in 0..<plane.height {
    for x in 0..<plane.width {
      let target = (y * plane.width + x) * 4
      for (ix, iy) in points {
        let source = (rows[y * size + iy] * plane.width + columns[x * size + ix]) * 4
        for c in 0..<4 {
          values[target + c] = max(values[target + c], plane.values[source + c])
        }
      }
    }
  }
  return BlurPlane(width: plane.width, height: plane.height, values: values)
}

/// Ближайший сосед: передискретизация картинки в `width x height`.
private func resampleNearest(_ plane: BlurPlane, width: Int, height: Int) -> BlurPlane {
  var values = [Float](repeating: 0, count: width * height * 4)
  for y in 0..<height {
    let sy = min(plane.height - 1, Int((Double(y) + 0.5) * Double(plane.height) / Double(height)))
    for x in 0..<width {
      let sx = min(plane.width - 1, Int((Double(x) + 0.5) * Double(plane.width) / Double(width)))
      let source = (sy * plane.width + sx) * 4
      let target = (y * width + x) * 4
      for c in 0..<4 {
        values[target + c] = plane.values[source + c]
      }
    }
  }
  return BlurPlane(width: width, height: height, values: values)
}

/// Доля размытия в точке: 0 в зоне фокуса, 1 за зоной перехода. Ширина перехода равна `hole`.
/// `degrees` задаёт линию фокуса (линейный режим); `nil` - круговой фокус вокруг якоря.
private func focusMask(
  _ plane: BlurPlane, anchorX: Double, anchorY: Double, hole: Double, degrees: Double?
) -> [Float] {
  // Расстояния меряем в долях большей стороны, чтобы не искажать форму при не квадратной картинке.
  let size = Double(max(plane.width, plane.height))
  let ax = anchorX * Double(plane.width) / size
  let ay = anchorY * Double(plane.height) / size
  let normal = degrees.map { angle -> (Double, Double) in
    let radians = angle * Double.pi / 180
    return (-sin(radians), cos(radians))
  }
  var mask = [Float](repeating: 0, count: plane.width * plane.height)
  for y in 0..<plane.height {
    for x in 0..<plane.width {
      let dx = (Double(x) + 0.5) / size - ax
      let dy = (Double(y) + 0.5) / size - ay
      let distance: Double
      if let normal {
        distance = abs(dx * normal.0 + dy * normal.1)
      } else {
        distance = hypot(dx, dy)
      }
      let share: Double
      if hole > 0 {
        share = min(max((distance - hole) / hole, 0), 1)
      } else {
        share = distance > 0 ? 1 : 0
      }
      mask[y * plane.width + x] = Float(share)
    }
  }
  return mask
}

/// Смешивает резкую картинку с размытой по маске фокуса.
private func tiltShift(
  _ plane: BlurPlane, radius: Int, sigma: Double, anchorX: Double, anchorY: Double,
  hole: Double, degrees: Double?
) -> BlurPlane {
  let blurred = separable(
    plane, weights: gaussianWeights(radius: radius, sigma: sigma), edge: .reflect101)
  let mask = focusMask(
    plane, anchorX: anchorX, anchorY: anchorY, hole: hole, degrees: degrees)
  var values = plane.values
  for pixel in 0..<mask.count {
    let share = mask[pixel]
    for c in 0..<4 {
      let index = pixel * 4 + c
      values[index] = plane.values[index] * (1 - share) + blurred.values[index] * share
    }
  }
  return BlurPlane(width: plane.width, height: plane.height, values: values)
}

/// Box blur: среднее по квадрату `(2r+1) x (2r+1)`, два прохода.
///
/// Статус: приближение. Краевой режим Aire по умолчанию в вызове не виден, взят reflect101.
struct BoxBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) { separable($0, weights: boxWeights(radius: radius), edge: .reflect101) }
  }
}

/// Гауссово размытие, ядро `2r+1` с интегралом по пикселю, sigma и краевой режим из Kotlin.
///
/// Статус: приближение. Android вызывает `Aire.gaussianBlur` (нативный код, в репозитории его нет).
/// Сверка с эталоном (по умолчанию: радиус 25, sigma 10, Reflect101): среднее отличие 1.63, максимум 19.
/// Известное расхождение, см. `AndroidReferenceParityTests`.
struct GaussianBlurFilter: Filter {
  let radius: Int
  let sigma: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) {
      separable($0, weights: gaussianWeights(radius: radius, sigma: sigma), edge: edge)
    }
  }
}

/// Линейное размытие длиной `size` (нечётная) под углом `degrees`, среднее по отрезку.
///
/// Статус: приближение. Направление и округление координат выбраны сами (Aire нативный).
struct MotionBlurFilter: Filter {
  let size: Double
  let degrees: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    let length = nearestOdd(size)
    let half = length / 2
    let radians = degrees * Double.pi / 180
    let dx = cos(radians)
    let dy = sin(radians)
    return filtered(image) { plane in
      var values = [Float](repeating: 0, count: plane.values.count)
      for y in 0..<plane.height {
        for x in 0..<plane.width {
          let target = (y * plane.width + x) * 4
          for t in -half...half {
            let sx = edge.index(Int((Double(x) + Double(t) * dx).rounded()), count: plane.width)
            let sy = edge.index(Int((Double(y) + Double(t) * dy).rounded()), count: plane.height)
            let source = (sy * plane.width + sx) * 4
            for c in 0..<4 {
              values[target + c] += plane.values[source + c]
            }
          }
          for c in 0..<4 {
            values[target + c] /= Float(length)
          }
        }
      }
      return BlurPlane(width: plane.width, height: plane.height, values: values)
    }
  }
}

/// Размытие к центру по шейдеру GPUImage `ZOOM_BLUR_FRAGMENT_SHADER`: девять отсчётов вдоль луча
/// к центру. Шаг равен `0.01 * (центр - пиксель) * size`, веса 0.18, 0.15, 0.12, 0.09, 0.05
/// симметрично относительно центрального отсчёта.
///
/// Статус: проверено по эталону (`ZoomBlurFilter`, раздел 10).
struct ZoomBlurFilter: Filter {
  let centerX: Double
  let centerY: Double
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let taps: [(Double, Double)] = [
      (0, 0.18), (1, 0.15), (2, 0.12), (3, 0.09), (4, 0.05),
      (-1, 0.15), (-2, 0.12), (-3, 0.09), (-4, 0.05),
    ]
    return DistortionSampling.render(image) { u, v, sample in
      let stepX = 0.01 * (centerX - u) * size
      let stepY = 0.01 * (centerY - v) * size
      var sum = SIMD4<Double>(repeating: 0)
      for (tap, weight) in taps {
        sum += sample(u + tap * stepX, v + tap * stepY) * weight
      }
      return sum
    }
  }
}

/// Размытие по ядру-многоугольнику: максимум по форме боке (дилатация).
///
/// Статус: приближение. Форму ядра Aire.getBokehKernel строим сами. Для больших ядер работает
/// медленно: O(пикселей x точек ядра).
struct BokehFilter: Filter {
  let size: Double
  let sides: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let kernelSize = max(1, Int(size.rounded()))
    let points = bokehKernel(size: kernelSize, sides: max(3, Int(sides.rounded())))
    return filtered(image) { dilate($0, size: kernelSize, points: points) }
  }
}

/// Линейный tilt-shift: резкая полоса вдоль линии под углом `degrees`, по краям размытие.
///
/// Статус: приближение. Нативный Aire.horizontalTiltShift не виден; переход и масштаб выбраны сами.
struct LinearTiltShiftFilter: Filter {
  let blurRadius: Int
  let sigma: Double
  let anchorX: Double
  let anchorY: Double
  let hole: Double
  let degrees: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let plane = BlurPlane(image)
    let result = tiltShift(
      plane, radius: blurRadius, sigma: sigma, anchorX: anchorX, anchorY: anchorY,
      hole: hole, degrees: degrees)
    return result.raster()
  }
}

/// Круговой tilt-shift: резкий круг вокруг якоря, размытие снаружи.
///
/// Статус: приближение. Нативный Aire.tiltShift не виден; переход и масштаб выбраны сами.
struct RadialTiltShiftFilter: Filter {
  let blurRadius: Int
  let sigma: Double
  let anchorX: Double
  let anchorY: Double
  let hole: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let plane = BlurPlane(image)
    let result = tiltShift(
      plane, radius: blurRadius, sigma: sigma, anchorX: anchorX, anchorY: anchorY,
      hole: hole, degrees: nil)
    return result.raster()
  }
}

/// Быстрое размытие: уменьшить до `scale`, box-размытие радиусом `radius`, растянуть обратно.
///
/// Статус: приближение. Нативный Trickle.fastBlur не виден, порядок шагов и передискретизация
/// выбраны сами.
struct FastBlurFilter: Filter {
  let scale: Double
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) { plane in
      let small = resampleNearest(
        plane,
        width: max(1, Int((Double(plane.width) * scale).rounded())),
        height: max(1, Int((Double(plane.height) * scale).rounded())))
      let blurred = separable(small, weights: boxWeights(radius: radius), edge: .reflect101)
      return resampleNearest(blurred, width: plane.width, height: plane.height)
    }
  }
}

/// Stack blur: треугольное ядро радиуса `radius` (не меньше 1), два прохода.
///
/// Статус: приближение. Нативный Aire.stackBlur не виден, краевой режим reflect101 выбран сами.
struct NativeStackBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) {
      separable($0, weights: triangleWeights(radius: max(1, radius)), edge: .reflect101)
    }
  }
}

/// Медианный фильтр по квадрату `(2r+1)`.
///
/// Статус: приближение. Определение медианы точное, краевой режим Aire не виден: reflect101.
struct MedianBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) { medianBlur($0, radius: radius, edge: .reflect101) }
  }
}

/// Tent blur: треугольное ядро размера `size`, округлённого до нечётного.
///
/// Статус: приближение. Нативный Aire.tentBlur не виден; трактовка `sigma` как размера ядра
/// выбрана сама.
struct TentBlurFilter: Filter {
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let radius = (nearestOdd(size) - 1) / 2
    return filtered(image) {
      separable($0, weights: triangleWeights(radius: radius), edge: .reflect101)
    }
  }
}

/// Билатеральное размытие: ядро `2r+1`, веса по расстоянию и по цвету.
///
/// Статус: приближение. Шкала цветового сигма 0...255 и краевой режим выбраны сами (Aire нативный).
/// Порядок sigma/spatialSigma в Ui не совпадает с полями Kotlin, см. описание дескриптора.
struct BilaterialBlurFilter: Filter {
  let radius: Int
  let spatialSigma: Double
  let rangeSigma: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    filtered(image) {
      bilateral(
        $0, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma, edge: edge)
    }
  }
}

/// Быстрый билатеральный фильтр: та же формула, что и `BilaterialBlurFilter`, с ядром `size`.
///
/// Статус: приближение. Aire.fastBilateralBlur сеточный и нативный; здесь точная сумма по окну,
/// поэтому результат близок по формуле, но не побитово. Медленно при больших ядрах.
struct FastBilaterialBlurFilter: Filter {
  let size: Double
  let spatialSigma: Double
  let rangeSigma: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let radius = nearestOdd(size) / 2
    return filtered(image) {
      bilateral(
        $0, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma,
        edge: .reflect101)
    }
  }
}
