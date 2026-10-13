import Foundation

/// Размытия: гауссово, box, motion, zoom, bokeh, tilt-shift и прочие из Android.
///
/// Размытия Aire, Trickle и GPUImage перенесены по исходникам (Aire 0.18.1, libblur 0.19.4, Trickle
/// 1.9.3, шейдеры GPUImage) и проверены по эталонам Android; ссылки на файлы и статус каждого
/// фильтра — в комментарии у его структуры. Тяжёлые вычисления лежат в `LibblurBlurs`,
/// `LibblurGaussian`, `LibblurBilateral`, `LibblurMotion`, `AireTiltShift`, `TrickleFastBlur` и
/// `MorphologyEngine` (боке).
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

/// Ближайшее нечётное число; как `roundToNearestOdd` в Kotlin.
private func nearestOdd(_ value: Double) -> Int {
  let n = max(0, Int(value.rounded()))
  return n % 2 == 0 ? n + 1 : n
}

/// Нормирует веса так, чтобы их сумма была 1.
private func normalized(_ raw: [Double]) -> [Float] {
  let total = raw.reduce(0, +)
  return raw.map { Float($0 / total) }
}

/// Одномерная свёртка вдоль строк (`horizontal`) или столбцов по таблице отсчётов `table` (элемент
/// `позиция * taps + k` — индекс источника для отсчёта `k`).
private func convolve(
  _ plane: BlurPlane, weights: [Float], horizontal: Bool, table: [Int]
) -> BlurPlane {
  let taps = weights.count
  let width = plane.width
  let length = horizontal ? plane.width : plane.height
  let lines = horizontal ? plane.height : plane.width
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

/// Веса `exp(-x^2 / (2 sigma^2))` в `taps` точках, нормированные на сумму 1: ядро
/// `gaussian_kernel_1d` из libblur. Центр ядра стоит в `taps / 2`.
private func pointGaussianWeights(taps: Int, sigma: Double) -> [Float] {
  let s = max(sigma, 1e-6)
  let mean = taps / 2
  return normalized(
    (0..<taps).map { index -> Double in
      let d = Double(index - mean) / s
      return exp(-0.5 * d * d)
    })
}

/// Таблица отсчётов для коротких ядер (до 28 отсчётов) libblur 0.19.4: над первой строкой стоит
/// копия строки 0 (предзагрузка верхнего края в `filter_1d_approx_sliding_buffer`), остальные края
/// ведут себя по режиму. Обработчик строк `binter` берёт обычные края.
private func shortKernelEdgeTable(
  length: Int, taps: Int, edge: BlurBorderMode, clampedTop: Bool
) -> [Int] {
  let pad = taps / 2
  var table = [Int](repeating: 0, count: length * taps)
  for position in 0..<length {
    for tap in 0..<taps {
      let index = position + tap - pad
      let source = index < 0 && clampedTop ? 0 : edge.index(index, count: length)
      table[position * taps + tap] = source
    }
  }
  return table
}

/// Гауссово размытие с ядром до 28 отсчётов как `libblur::gaussian_blur` (`FixedPoint`) на Android.
/// Строки идут через `binter` с обычными краями, столбцы через скользящий буфер (над первой строкой
/// копия строки 0). Веса считаются с плавающей точкой; целочисленная арифметика обработчиков
/// Android воспроизведена только для ядер от 29 (`LibblurGaussian`), поэтому здесь возможна разница
/// в один уровень.
private func shortKernelGaussian(
  _ plane: BlurPlane, taps: Int, sigma: Double, edge: BlurBorderMode
) -> BlurPlane {
  let weights = pointGaussianWeights(taps: taps, sigma: sigma)
  let rows = convolve(
    plane, weights: weights, horizontal: true,
    table: shortKernelEdgeTable(length: plane.width, taps: taps, edge: edge, clampedTop: false))
  return convolve(
    rows, weights: weights, horizontal: false,
    table: shortKernelEdgeTable(length: plane.height, taps: taps, edge: edge, clampedTop: true))
}

/// Ядро боке `Aire.getBokehKernel` (`algo/EigenUtils.h`, `getBokehEffect`): контур правильного
/// многоугольника с `sides` вершинами на окружности радиуса `0.85 * size / 2` вокруг `(size / 2,
/// size / 2)`, ломаная линиями Брезенхэма (координаты вершин усечены до целых, `Float`), затем
/// заливка изнутри от центра. Возвращает ядро для морфологии (дилатации).
func bokehMorphologyKernel(size: Int, sides: Int) -> MorphologyEngine.Kernel {
  var mask = [Bool](repeating: false, count: size * size)
  let centre = Float(Double(size) / 2)
  let radius = centre * 0.85
  let tau = 2 * Float.pi
  for side in 0..<sides {
    let angle1 = tau * Float(side) / Float(sides)
    let angle2 = tau * Float(side + 1) / Float(sides)
    var x1 = Int(centre + radius * cos(angle1))
    var y1 = Int(centre + radius * sin(angle1))
    let x2 = Int(centre + radius * cos(angle2))
    let y2 = Int(centre + radius * sin(angle2))
    let dx = abs(x2 - x1)
    let dy = -abs(y2 - y1)
    let stepX = x1 < x2 ? 1 : -1
    let stepY = y1 < y2 ? 1 : -1
    var error = dx + dy
    while true {
      if x1 >= 0, x1 < size, y1 >= 0, y1 < size { mask[y1 * size + x1] = true }
      if x1 == x2, y1 == y2 { break }
      let doubled = 2 * error
      if doubled >= dy {
        error += dy
        x1 += stepX
      }
      if doubled <= dx {
        error += dx
        y1 += stepY
      }
    }
  }
  // Заливка по четырём соседям от центра, как `floodFill` в Aire.
  var queue = [size / 2 * size + size / 2]
  var head = 0
  while head < queue.count {
    let cell = queue[head]
    head += 1
    guard !mask[cell] else { continue }
    mask[cell] = true
    let x = cell % size
    let y = cell / size
    if x + 1 < size { queue.append(cell + 1) }
    if x > 0 { queue.append(cell - 1) }
    if y + 1 < size { queue.append(cell + size) }
    if y > 0 { queue.append(cell - size) }
  }
  return MorphologyEngine.Kernel(width: size, height: size, mask: mask)
}

/// Box blur как `Aire.boxBlur` -> `libblur::box_blur` (Aire 0.18.1 `aire-filters/src/blur.rs`,
/// libblur 0.19.4 `box_filter/box_blur.rs`): ядро `2 * Int(value) + 1`, пиксели за краем повторяют
/// крайний, проход по строкам, затем по столбцам, после каждого `round(сумма / ядро)` во `Float`.
/// При `radius = 0` ядро 1 и картинка не меняется. Края не настраиваются.
///
/// Статус: проверено по эталону.
struct BoxBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    guard radius >= 1 else { return image }
    let pixels = LibblurBlurs.box(
      image.pixels, width: image.width, height: image.height, radius: radius)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Гауссово размытие как `Aire.gaussianBlur` -> `libblur::gaussian_blur` (режим `FixedPoint`, Aire
/// 0.18.1, libblur 0.19.4): ядро `2r+1` с весами `exp(-x^2 / (2 sigma^2))` в целых точках, sigma и
/// краевой режим из Kotlin. Для ядер от 29 отсчётов арифметика целая, как у обработчиков arm64 с
/// RDM (`LibblurGaussian`), с особенностями libblur у границ: справа от строки отражённые пиксели
/// записаны в обратном порядке, над первой строкой при ядре до 61 стоит копия строки 0, а при ядре
/// больше 61 столбцы берут строки подушек по смещённым индексам и последние `высота mod 3` строк
/// повторяют первые. Для ядер короче 29 (строки через `binter`) расчёт в `Float`: эталон для ядра 11
/// совпал побитово, на других коротких ядрах возможна разница в один уровень. Эталоны: радиусы 5,
/// 25 и 40 (ядра 11, 51, 81), Reflect101.
///
/// Статус: проверено по эталону.
struct GaussianBlurFilter: Filter {
  let radius: Int
  let sigma: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    let taps = 2 * max(0, radius) + 1
    if taps >= LibblurGaussian.minimumTaps {
      let pixels = LibblurGaussian.blur(
        image.pixels, width: image.width, height: image.height, taps: taps,
        sigma: Float(sigma), edge: edge)
      return RasterImage(width: image.width, height: image.height, pixels: pixels)
    }
    return shortKernelGaussian(BlurPlane(image), taps: taps, sigma: sigma, edge: edge).raster()
  }
}

/// Линейное размытие как `Aire.motionBlur` -> `libblur::motion_blur` (Aire 0.18.1, libblur 0.19.4
/// `motion_blur.rs`): ядро размера `nearestOdd(size)` с линией Брезенхэма под углом `degrees`,
/// двумерная свёртка в фиксированной точке (`LibblurMotion`), края по режиму с дефектом
/// `AireArena`.
///
/// Статус: проверено по эталону.
struct MotionBlurFilter: Filter {
  let size: Double
  let degrees: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurMotion.blur(
      image.pixels, width: image.width, height: image.height, size: nearestOdd(size),
      degrees: Float(degrees), edge: edge)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Размытие к центру по шейдеру GPUImage `ZOOM_BLUR_FRAGMENT_SHADER`: девять отсчётов вдоль луча к
/// центру. Шаг равен `0.01 * (центр - пиксель) * size`, веса 0.18, 0.15, 0.12, 0.09, 0.05
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

/// Размытие по ядру-многоугольнику: дилатация (максимум) по форме боке.
///
/// Android: `Aire.morphology` с ядром `Aire.getBokehKernel(size, sides)` (aire 0.18.1,
/// `EigenUtils.h` и `fast_morphology` 0.3.1), операция `DILATE`, `REFLECT_101`; размер и число
/// сторон округляются `roundToInt`. Границы рамки у `fast_morphology` нестандартные (см.
/// `MorphologyEngine`). Android бросает исключение при размере или числе сторон меньше 3; здесь
/// ядро строится и для них.
///
/// Статус: проверено по эталону.
struct BokehFilter: Filter {
  let size: Double
  let sides: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let kernel = bokehMorphologyKernel(
      size: max(1, Int(size.rounded())), sides: max(1, Int(sides.rounded())))
    return MorphologyEngine.run(.dilate, on: image, kernel: kernel)
  }
}

/// Линейный tilt-shift как `Aire.horizontalTiltShift` (Aire 0.18.1, `jni/ShiftPipelines.cpp`,
/// `shift/TiltShift.cpp`): размытие `gaussBlurU8` с ядром длиной `blurRadius` и смешивание по кубу
/// расстояния до линии фокуса, повёрнутой на `degrees` (`AireTiltShift`).
///
/// Статус: проверено по эталону.
struct LinearTiltShiftFilter: Filter {
  let blurRadius: Int
  let sigma: Double
  let anchorX: Double
  let anchorY: Double
  let hole: Double
  let degrees: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = AireTiltShift.linear(
      image.pixels, width: image.width, height: image.height, radius: blurRadius,
      sigma: Float(sigma), anchorX: Float(anchorX), anchorY: Float(anchorY), hole: Float(hole),
      angle: Float(degrees) * Float.pi / 180)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Круговой tilt-shift как `Aire.tiltShift` (Aire 0.18.1, `jni/ShiftPipelines.cpp`,
/// `shift/TiltShift.cpp`): размытие `gaussBlurU8` с ядром длиной `blurRadius` и смешивание по кубу
/// расстояния до якоря (`AireTiltShift`).
///
/// Статус: проверено по эталону.
struct RadialTiltShiftFilter: Filter {
  let blurRadius: Int
  let sigma: Double
  let anchorX: Double
  let anchorY: Double
  let hole: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = AireTiltShift.radial(
      image.pixels, width: image.width, height: image.height, radius: blurRadius,
      sigma: Float(sigma), anchorX: Float(anchorX), anchorY: Float(anchorY), hole: Float(hole))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Быстрое размытие как `Trickle.fastBlur` (Trickle 1.9.3, `Utils.cpp`, `fastBlurImpl`): уменьшение
/// до `scale` билинейным фильтром Skia, box-размытие радиусом `radius`, увеличение обратно
/// (`TrickleFastBlur`). Альфа результата 255, при `radius < 1` картинка не меняется. Android
/// возвращает размер `Int(w / scale)` на `Int(h / scale)`, который может отличаться от исходного;
/// здесь размер сохраняется. Эталон снят для масштаба 0.5; билинейная выборка Skia для других
/// масштабов воспроизведена по устройству `SkBitmapProcState` и на эталоне не проверена.
///
/// Статус: проверено по эталону.
struct FastBlurFilter: Filter {
  let scale: Double
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    TrickleFastBlur.apply(image, scale: Float(scale), radius: radius)
  }
}

/// Stack blur как `Aire.stackBlur` -> `libblur::stack_blur` (Aire 0.18.1, libblur 0.19.4
/// `stackblur/`): треугольное ядро `radius + 1 - |k|` радиусом не меньше 1, делитель `(radius +
/// 1)^2`, край повторяет крайний пиксель, строки, затем столбцы, `round` после каждого прохода.
///
/// Статус: проверено по эталону.
struct NativeStackBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurBlurs.stack(
      image.pixels, width: image.width, height: image.height, radius: max(1, radius))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Медианный фильтр как `Aire.medianBlur` -> `libblur::median_blur` (Aire 0.18.1, libblur 0.19.4
/// `median_blur.rs`). Aire передаёт в libblur радиус `2 * round(value) + 1`. Алгоритм гистограммы
/// libblur воспроизведён вместе с его особенностями (см. `LibblurBlurs.median`): окно по столбцам
/// несимметрично, один столбец выпадает, «медиана» на единицу ниже середины.
///
/// Статус: проверено по эталону.
struct MedianBlurFilter: Filter {
  let radius: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurBlurs.median(
      image.pixels, width: image.width, height: image.height, radius: 2 * max(0, radius) + 1)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Tent blur как `Aire.tentBlur` -> `libblur::tent_blur` (Aire 0.18.1, libblur 0.19.4
/// `box_filter/box_blur.rs`): два box-размытия с окнами из `create_box_gauss`, sigma — `size`,
/// округлённый до нечётного. Край повторяет крайний пиксель.
///
/// Статус: проверено по эталону.
struct TentBlurFilter: Filter {
  let size: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurBlurs.tent(
      image.pixels, width: image.width, height: image.height, sigma: Float(nearestOdd(size)))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Билатеральное размытие как `Aire.bilateralBlur` -> `libblur::bilateral_filter` (Aire 0.18.1,
/// libblur 0.19.4 `bilateral/bp8.rs`, `bilateral/neon/bp8.rs`): окно `2r+1`, каналы отдельно
/// (`LibblurBilateral.filter`). Aire передаёт в libblur сигмы в другом порядке, чем называет их
/// Kotlin: пространственной сигмой (в пикселях) служит `rangeSigma` фильтра, цветовой (в долях 1)
/// `spatialSigma`. По умолчанию это 3 и 10, поэтому цветовой вес почти не влияет. Поля структуры
/// названы как в Kotlin.
///
/// Статус: проверено по эталону.
struct BilaterialBlurFilter: Filter {
  let radius: Int
  let spatialSigma: Double
  let rangeSigma: Double
  let edge: BlurBorderMode

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurBilateral.filter(
      image.pixels, width: image.width, height: image.height, kernel: 2 * max(0, radius) + 1,
      spatialSigma: Float(rangeSigma), rangeSigma: Float(spatialSigma), edge: edge)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Быстрый билатеральный фильтр как `Aire.fastBilateralBlur` -> `libblur::fast_bilateral_filter`
/// (Aire 0.18.1, libblur 0.19.4 `fast_bilateral_filter.rs`): билатеральная сетка по каждому каналу
/// и гауссово ядро `size`, округлённое до нечётного (`LibblurBilateral.fast`). Сигмы идут в libblur
/// в том же порядке, что и в Kotlin (`spatialSigma`, `rangeSigma`).
///
/// Статус: проверено по эталону.
struct FastBilaterialBlurFilter: Filter {
  let size: Double
  let spatialSigma: Double
  let rangeSigma: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let pixels = LibblurBilateral.fast(
      image.pixels, width: image.width, height: image.height, kernelSize: nearestOdd(size),
      spatialSigma: Float(spatialSigma), rangeSigma: Float(rangeSigma))
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}
