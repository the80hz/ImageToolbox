import Foundation

/// Искажения: fish eye, bulge, swirl, twirl, pinch, ripple, калейдоскоп, сферы, стеклянные плитки и спирали.
///
/// Все фильтры работают на CPU: для каждого пикселя результата ищется точка источника и берётся
/// билинейная выборка с краевым зажимом. Центры, радиусы и диапазоны взяты из `Ui*Filter.kt`.
/// Плитки и спирали повторяют GLSL из `ProceduralShaders.kt`. Остальные фильтры в Android сделаны
/// нативным кодом (GPUImage, Jh Labs, G'MIC); их формулы перенесены по публичным исходникам и
/// сверены с эталонами (раздел 10 FILTERS.md). Рябь, щипок и калейдоскоп лежат в
/// `JhLabsDistortionFilters.swift`, `FishEyeFilter` в `GmicFishEyeFilter.swift`. Статус каждого
/// фильтра записан в его doc-комментарии.
enum DistortionFilters {
  static let descriptors: [FilterDescriptor] = [
    // status: проверено по эталону (G'MIC fisheye, GmicFishEyeFilter.swift)
    FilterDescriptor(
      id: "FishEyeFilter",
      titleKey: "gmic_filter_fish_eye",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("radius", "radius", 0...100, defaultValue: 70),
        number("amplitude", "amplitude", 0...2, defaultValue: 1),
      ],
      make: { FishEyeFilter(radius: $0.number("radius"), amplitude: $0.number("amplitude")) }
    ),
    // status: приближение (GPUImage bulge не в репозитории)
    FilterDescriptor(
      id: "BulgeDistortionFilter",
      titleKey: "bulge",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("radius", "radius", 0...1, defaultValue: 0.25),
        number("scale", "scale", -1...1, defaultValue: 0.5),
      ],
      make: { BulgeDistortionFilter(radius: $0.number("radius"), scale: $0.number("scale")) }
    ),
    // status: приближение (GPUImage swirl не в репозитории)
    FilterDescriptor(
      id: "SwirlDistortionFilter",
      titleKey: "swirl",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("radius", "radius", 0...1, defaultValue: 0.5),
        number("angle", "angle", -1...1, defaultValue: 1),
        number("centerX", "center_x", 0.01...1, defaultValue: 0.5),
        number("centerY", "center_y", 0.01...1, defaultValue: 0.5),
      ],
      make: {
        SwirlDistortionFilter(
          radius: $0.number("radius"), angle: $0.number("angle"),
          centreX: $0.number("centerX"), centreY: $0.number("centerY"))
      }
    ),
    // status: проверено по эталону (Jh Labs 8.1.0)
    FilterDescriptor(
      id: "TwirlFilter",
      titleKey: "twirl",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("angle", "angle", -360...360, defaultValue: 45),
        number("centerX", "center_x", 0...1, defaultValue: 0.5),
        number("centerY", "center_y", 0...1, defaultValue: 0.5),
        number("radius", "radius", 0...1, defaultValue: 0.5),
      ],
      make: {
        TwirlFilter(
          angle: $0.number("angle"), centreX: $0.number("centerX"),
          centreY: $0.number("centerY"), radius: $0.number("radius"))
      }
    ),
    // status: проверено по эталону (Jh Labs 8.1.0, JhLabsDistortionFilters.swift)
    FilterDescriptor(
      id: "PinchFilter",
      titleKey: "whirl_and_pinch",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("angle", "angle", 0...360, step: 1, defaultValue: 15),
        number("centerX", "center_x", 0...1, defaultValue: 0.5),
        number("centerY", "center_y", 0...1, defaultValue: 0.5),
        number("radius", "radius", 0...2, defaultValue: 1),
        number("amount", "amount", -1...1, defaultValue: 0.5),
      ],
      make: {
        PinchFilter(
          angle: $0.number("angle"), centreX: $0.number("centerX"),
          centreY: $0.number("centerY"), radius: $0.number("radius"), amount: $0.number("amount"))
      }
    ),
    // status: проверено по эталону (Jh Labs 8.1.0, JhLabsDistortionFilters.swift)
    FilterDescriptor(
      id: "KaleidoscopeFilter",
      titleKey: "kaleidoscope",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("angle", "angle", 0...360, step: 1, defaultValue: 0),
        number("secondaryAngle", "secondary_angle", 0...360, step: 1, defaultValue: 0),
        number("centerX", "center_x", 0...1, defaultValue: 0.5),
        number("centerY", "center_y", 0...1, defaultValue: 0.5),
        number("sides", "sides", 2...12, step: 1, defaultValue: 5),
        number("radius", "radius", 0...100, defaultValue: 0),
      ],
      make: {
        KaleidoscopeFilter(
          angle: $0.number("angle"), secondaryAngle: $0.number("secondaryAngle"),
          centreX: $0.number("centerX"), centreY: $0.number("centerY"),
          sides: $0.number("sides"), radius: $0.number("radius"))
      }
    ),
    // status: приближение (GPUImage sphere refraction не в репозитории)
    FilterDescriptor(
      id: "SphereRefractionFilter",
      titleKey: "sphere_refraction",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("radius", "radius", 0...1, defaultValue: 0.25),
        number("refractiveIndex", "refractive_index", 0...1, defaultValue: 0.71),
      ],
      make: {
        SphereRefractionFilter(
          radius: $0.number("radius"), refractiveIndex: $0.number("refractiveIndex"))
      }
    ),
    // status: приближение (GPUImage glass sphere не в репозитории)
    FilterDescriptor(
      id: "GlassSphereRefractionFilter",
      titleKey: "glass_sphere_refraction",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("radius", "radius", 0...1, defaultValue: 0.25),
        number("refractiveIndex", "refractive_index", 0...1, defaultValue: 0.71),
      ],
      make: {
        GlassSphereRefractionFilter(
          radius: $0.number("radius"), refractiveIndex: $0.number("refractiveIndex"))
      }
    ),
    // Формулы из ProceduralShaders.kt, перенесены точно.
    glassTiles(
      id: "GlassHexTilesFilter", titleKey: "glass_hex_tiles",
      make: {
        GlassHexTilesFilter(
          intensity: $0.number("intensity"), distortion: $0.number("distortion"),
          frequency: $0.number("frequency"))
      }),
    glassTiles(
      id: "GlassRectTilesFilter", titleKey: "glass_rect_tiles",
      make: {
        GlassRectTilesFilter(
          intensity: $0.number("intensity"), distortion: $0.number("distortion"),
          frequency: $0.number("frequency"))
      }),
    glassTiles(
      id: "GlassTriangleTilesFilter", titleKey: "glass_triangle_tiles",
      make: {
        GlassTriangleTilesFilter(
          intensity: $0.number("intensity"), distortion: $0.number("distortion"),
          frequency: $0.number("frequency"))
      }),
    // Формула из ProceduralShaders.kt, перенесена точно.
    FilterDescriptor(
      id: "LogarithmicSpiralFilter",
      titleKey: "logarithmic_spiral",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("count", "procedural_count", 1...32, step: 1, defaultValue: 2),
        number("intensity", "texture_intensity", -4...4, step: 0.001, defaultValue: 1),
      ],
      make: {
        LogarithmicSpiralFilter(count: $0.number("count"), intensity: $0.number("intensity"))
      }
    ),
    // Формула из ProceduralShaders.kt, перенесена точно.
    FilterDescriptor(
      id: "SpiralDrosteFilter",
      titleKey: "spiral_droste",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("intensity", "texture_intensity", 1.1...8, step: 0.001, defaultValue: 2),
        number("distortion", "distortion", -1...1, step: 0.001, defaultValue: 0.2),
      ],
      make: {
        SpiralDrosteFilter(intensity: $0.number("intensity"), distortion: $0.number("distortion"))
      }
    ),
    // status: проверено по эталону (Jh Labs 8.1.0, JhLabsDistortionFilters.swift)
    FilterDescriptor(
      id: "RippleFilter",
      titleKey: "ripple",
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("xAmplitude", "x_amplitude", 0...100, step: 0.1, defaultValue: 5),
        number("xWavelength", "x_wavelength", 1...200, step: 0.1, defaultValue: 16),
        number("yAmplitude", "y_amplitude", 0...100, step: 0.1, defaultValue: 5),
        number("yWavelength", "y_wavelength", 1...200, step: 0.1, defaultValue: 16),
      ],
      make: {
        RippleFilter(
          xAmplitude: $0.number("xAmplitude"), xWavelength: $0.number("xWavelength"),
          yAmplitude: $0.number("yAmplitude"), yWavelength: $0.number("yWavelength"))
      }
    ),
    // Droste (G'MIC) не перенесён: см. отчёт. Четыре угла, сдвиг, зум и режимы рисования
    // не воспроизводятся без исходника G'MIC.
  ]

  private static func number(
    _ key: String, _ titleKey: String, _ range: ClosedRange<Double>,
    step: Double = 0.01, defaultValue: Double
  ) -> FilterParameter {
    FilterParameter(
      key: key, titleKey: titleKey,
      kind: .number(range: range, step: step, defaultValue: defaultValue))
  }

  /// Три стеклянные плитки имеют одинаковые параметры из `UiProceduralFilter`.
  private static func glassTiles(
    id: String, titleKey: String, make: @escaping @Sendable (FilterValues) -> any Filter
  ) -> FilterDescriptor {
    FilterDescriptor(
      id: id,
      titleKey: titleKey,
      category: .distortion,
      engine: .cpu,
      parameters: [
        number("intensity", "texture_intensity", -1...1, step: 0.001, defaultValue: 0.2),
        number("distortion", "distortion", -1...1, step: 0.001, defaultValue: 0.25),
        number("frequency", "frequency", 1...40, step: 0.001, defaultValue: 8),
      ],
      make: make
    )
  }
}

/// Общие шаги для искажений: обратное отображение и билинейная выборка.
///
/// Координаты пикселей идут в пикселях, центр пикселя (x, y) имеет координаты (x + 0.5, y + 0.5).
/// Строка 0 сверху, как в `RasterImage`.
enum DistortionSampling {
  /// Для каждого пикселя результата `source` возвращает точку источника в пикселях.
  static func warp(
    _ image: RasterImage,
    _ source: (Double, Double) -> (Double, Double)
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    var output = [UInt8](repeating: 0, count: image.pixels.count)
    image.pixels.withUnsafeBufferPointer { pixels in
      for y in 0..<height {
        for x in 0..<width {
          let (sx, sy) = source(Double(x) + 0.5, Double(y) + 0.5)
          let color = bilinear(pixels, width: width, height: height, x: sx, y: sy)
          let index = (y * width + x) * 4
          for channel in 0..<4 {
            output[index + channel] = UInt8(min(max(color[channel].rounded(), 0), 255))
          }
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Для каждого пикселя результата вызывает `color` с центром пикселя в нормированных координатах
  /// (0...1) и функцией выборки из `image`. Выборка билинейная, за краем берётся край картинки,
  /// как у GPUImage с линейной фильтрацией и `clamp to edge`.
  static func render(
    _ image: RasterImage,
    _ color: (Double, Double, (Double, Double) -> SIMD4<Double>) -> SIMD4<Double>
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    var output = [UInt8](repeating: 0, count: image.pixels.count)
    image.pixels.withUnsafeBufferPointer { pixels in
      func sample(_ u: Double, _ v: Double) -> SIMD4<Double> {
        bilinear(pixels, width: width, height: height, x: u * Double(width), y: v * Double(height))
      }
      for y in 0..<height {
        for x in 0..<width {
          let value = color(
            (Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height), sample)
          let index = (y * width + x) * 4
          for channel in 0..<4 {
            output[index + channel] = UInt8(min(max(value[channel].rounded(), 0), 255))
          }
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// Билинейная выборка premultiplied RGBA. Точки за краем берутся с края картинки.
  private static func bilinear(
    _ pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, x: Double, y: Double
  ) -> SIMD4<Double> {
    let fx = min(max(x.isFinite ? x - 0.5 : 0, 0), Double(width - 1))
    let fy = min(max(y.isFinite ? y - 0.5 : 0, 0), Double(height - 1))
    let x0 = Int(fx)
    let y0 = Int(fy)
    let x1 = min(x0 + 1, width - 1)
    let y1 = min(y0 + 1, height - 1)
    let tx = fx - Double(x0)
    let ty = fy - Double(y0)
    func texel(_ px: Int, _ py: Int) -> SIMD4<Double> {
      let i = (py * width + px) * 4
      return SIMD4(
        Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]), Double(pixels[i + 3]))
    }
    let top = texel(x0, y0) * (1 - tx) + texel(x1, y0) * tx
    let bottom = texel(x0, y1) * (1 - tx) + texel(x1, y1) * tx
    return top * (1 - ty) + bottom * ty
  }

  /// Остаток по модулю, как `mod` в GLSL: результат всегда в [0, b).
  static func mod(_ a: Double, _ b: Double) -> Double {
    a - b * (a / b).rounded(.down)
  }

  /// Дробная часть, как `fract` в GLSL.
  static func fract(_ a: Double) -> Double {
    a - a.rounded(.down)
  }

  /// Точка поля, как `toField` в шейдере: центр в нуле, короткая сторона картинки равна 1.
  static func fieldPoint(x: Double, y: Double, width: Double, height: Double) -> (Double, Double) {
    let short = max(min(width, height), 1)
    return (
      (x / width - 0.5) * (width / short),
      (y / height - 0.5) * (height / short)
    )
  }

  /// Точка поля обратно в пиксели, как `sampleField`: за краем картинка отражается.
  static func pixel(fromField q: (Double, Double), width: Double, height: Double) -> (
    Double, Double
  ) {
    let short = max(min(width, height), 1)
    let u = mirror(q.0 / (width / short) + 0.5)
    let v = mirror(q.1 / (height / short) + 0.5)
    return (u * width, v * height)
  }

  private static func mirror(_ value: Double) -> Double {
    1 - abs(mod(value, 2) - 1)
  }
}

/// Выпуклость: внутри круга картинка растягивается от центра.
///
/// Статус: проверено по эталону (`BulgeDistortionFilter`, раздел 10): совпадение в допуске на
/// эталонном входе. Радиус в долях ширины, расчёт расстояния с поправкой на пропорции.
/// При `scale` 0 картинка не меняется.
struct BulgeDistortionFilter: Filter {
  let radius: Double
  let scale: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    let aspect = h / w
    return DistortionSampling.warp(image) { x, y in
      let u = x / w - 0.5
      let v = (y / h - 0.5) * aspect
      let distance = (u * u + v * v).squareRoot()
      guard radius > 0, distance < radius else { return (x, y) }
      var percent = 1 - ((radius - distance) / radius) * scale
      percent *= percent
      return (w / 2 + (x - w / 2) * percent, h / 2 + (y - h / 2) * percent)
    }
  }
}

/// Водоворот: угол поворота падает от центра к краю круга.
///
/// Статус: проверено по эталону (`SwirlDistortionFilter`, раздел 10): совпадение в допуске на
/// эталонном входе. Расчёт в долях картинки, как в исходном шейдере. При `angle` 0 картинка
/// не меняется.
struct SwirlDistortionFilter: Filter {
  let radius: Double
  let angle: Double
  let centreX: Double
  let centreY: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    return DistortionSampling.warp(image) { x, y in
      let u = x / w - centreX
      let v = y / h - centreY
      let distance = (u * u + v * v).squareRoot()
      guard radius > 0, distance < radius else { return (x, y) }
      let percent = (radius - distance) / radius
      let theta = percent * percent * angle * 8
      let c = cos(theta)
      let s = sin(theta)
      return ((centreX + u * c - v * s) * w, (centreY + u * s + v * c) * h)
    }
  }
}

/// Закрутка: угол поворота линейно падает от центра к краю круга.
///
/// Источник: Jh Labs `TwirlFilter` в T8RIN/ImageToolboxLibs 8.1.0, `libs/jhlabs/src/main/rust/jhlabs/
/// src/lib.rs` (`transform_filter`, ветка `"TwirlFilter"`, `bilinear`, `sample`). Всё в `Float`:
/// центр `centre * размер` и координаты пикселя целые (без сдвига на 0.5), радиус
/// `radius * max(w, h) / 2` (в `Float`, как в Kotlin), угол в радианах. Вне круга (`distance > radius`)
/// пиксель берётся как есть, внутри угол равен `angle * (radius - distance) / radius`. Выборка
/// билинейная, байт получается отбрасыванием дробной части, за краем координата прижимается к краю
/// (`CLAMP`, цвет сохраняется). Цвет берётся premultiplied, как хранит `RasterImage`.
/// Радиус 0 в Jh Labs означает меньшую из половин размера, здесь это тоже так; если и она 0
/// (центр на краю), картинка не меняется: в Jh Labs там получилось бы деление на ноль.
/// Статус: проверено по эталону.
struct TwirlFilter: Filter {
  let angle: Double
  let centreX: Double
  let centreY: Double
  let radius: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let width = image.width
    let height = image.height
    let centreXPixels = Float(centreX) * Float(width)
    let centreYPixels = Float(centreY) * Float(height)
    let turn = Float(angle * .pi / 180)
    let scaled = Float(radius) * (Float(max(width, height)) / 2)
    let limit = scaled == 0 ? min(centreXPixels, centreYPixels) : scaled
    var output = image.pixels
    for y in 0..<height {
      for x in 0..<width {
        let dx = Float(x) - centreXPixels
        let dy = Float(y) - centreYPixels
        let distance = (dx * dx + dy * dy).squareRoot()
        guard limit > 0, distance <= limit else { continue }
        let theta = turn * (limit - distance) / limit
        let sine = sinf(theta)
        let cosine = cosf(theta)
        let sourceX = centreXPixels + cosine * dx - sine * dy
        let sourceY = centreYPixels + sine * dx + cosine * dy
        let index = (y * width + x) * 4
        for channel in 0..<4 {
          output[index + channel] = Self.bilinear(
            image, x: sourceX, y: sourceY, channel: channel)
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  private static func bilinear(_ image: RasterImage, x: Float, y: Float, channel: Int) -> UInt8 {
    let left = min(max(x, -1e6), 1e6).rounded(.down)
    let top = min(max(y, -1e6), 1e6).rounded(.down)
    let xWeight = x - left
    let yWeight = y - top
    func value(_ dx: Int, _ dy: Int) -> Float {
      let column = min(max(Int(left) + dx, 0), image.width - 1)
      let row = min(max(Int(top) + dy, 0), image.height - 1)
      return Float(image.pixels[(row * image.width + column) * 4 + channel])
    }
    let north = value(0, 0) * (1 - xWeight) + value(1, 0) * xWeight
    let south = value(0, 1) * (1 - xWeight) + value(1, 1) * xWeight
    return UInt8(min(max(Int(north * (1 - yWeight) + south * yWeight), 0), 255))
  }
}

/// Сферическая линза по шейдеру GPUImage `SPHERE_FRAGMENT_SHADER`: внутри круга пиксель берётся
/// из точки, куда его преломляет шар с индексом `refractiveIndex`. Вне круга результат чёрный:
/// шейдер умножает цвет на `step(distance, radius)`.
///
/// Статус: проверено по эталону (`SphereRefractionFilter`, раздел 10).
struct SphereRefractionFilter: Filter {
  let radius: Double
  let refractiveIndex: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    sphereLens(image, radius: radius, refractiveIndex: refractiveIndex, glass: false)
  }
}

/// Стеклянная сфера по шейдеру GPUImage `GlassSphere`: вектор преломления удваивается и
/// отражается по осям, поверх добавляется освещение (рассеянное и блик от точки (-0.5, 0.5, 1)).
///
/// Статус: проверено по эталону (`GlassSphereRefractionFilter`, раздел 10).
struct GlassSphereRefractionFilter: Filter {
  let radius: Double
  let refractiveIndex: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    sphereLens(image, radius: radius, refractiveIndex: refractiveIndex, glass: true)
  }
}

/// Общая часть двух шаров. Координаты как в шейдере: y умножается на соотношение сторон,
/// центр картинки — (0.5, 0.5), глубина сферы `radius * sqrt(1 - (d / radius)^2)`.
private func sphereLens(
  _ image: RasterImage, radius: Double, refractiveIndex eta: Double, glass: Bool
) -> RasterImage {
  let aspect = Double(image.height) / Double(image.width)
  let lightLength = (0.25 + 0.25 + 1.0).squareRoot()
  let light = (-0.5 / lightLength, 0.5 / lightLength, 1.0 / lightLength)
  return DistortionSampling.render(image) { u, v, sample in
    let dx = u - 0.5
    let dy = v * aspect + 0.5 - 0.5 * aspect - 0.5
    let distance = (dx * dx + dy * dy).squareRoot()
    guard radius > 0, distance <= radius else { return .zero }
    let scaled = distance / radius
    let depth = radius * (1 - scaled * scaled).squareRoot()
    let length = (dx * dx + dy * dy + depth * depth).squareRoot()
    let normal = (x: dx / length, y: dy / length, z: depth / length)
    // refract((0, 0, -1), N, eta) из GLSL. При отрицательном подкоренном выражении вектор нулевой.
    let cosine = -normal.z
    let discriminant = 1 - eta * eta * (1 - cosine * cosine)
    var refracted = (x: 0.0, y: 0.0)
    if discriminant >= 0 {
      let factor = eta * cosine + discriminant.squareRoot()
      refracted = (-factor * normal.x, -factor * normal.y)
    }
    guard glass else {
      return sample((refracted.x + 1) * 0.5, (refracted.y + 1) * 0.5)
    }
    let texel = sample((-2 * refracted.x + 1) * 0.5, (-2 * refracted.y + 1) * 0.5)
    let ambient = 2.5 * (1 - pow(min(max(normal.z, 0), 1), 0.25))
    let dot = light.0 * normal.x + light.1 * normal.y + light.2 * normal.z
    let highlight = pow(min(max(dot, 0), 1), 15)
    let shade = (ambient + 0.8 * highlight) * 255
    return SIMD4(texel.x + shade, texel.y + shade, texel.z + shade, 255)
  }
}

/// Стеклянные плитки, квадратная сетка. Формула из `ProceduralShaders.kt` перенесена точно,
/// проверена по эталону (`GlassRectTilesFilter`, раздел 10).
struct GlassRectTilesFilter: Filter {
  let intensity: Double
  let distortion: Double
  let frequency: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    return DistortionSampling.warp(image) { x, y in
      let p = DistortionSampling.fieldPoint(x: x, y: y, width: w, height: h)
      let local = (
        DistortionSampling.fract(p.0 * frequency + 0.5) - 0.5,
        DistortionSampling.fract(p.1 * frequency + 0.5) - 0.5
      )
      let gain = intensity + distortion * (local.0 * local.0 + local.1 * local.1) * 4
      let q = (p.0 + local.0 * gain / frequency, p.1 + local.1 * gain / frequency)
      return DistortionSampling.pixel(fromField: q, width: w, height: h)
    }
  }
}

/// Стеклянные плитки, шестиугольная сетка. Формула из `ProceduralShaders.kt` перенесена точно,
/// проверена по эталону (`GlassHexTilesFilter`, раздел 10).
struct GlassHexTilesFilter: Filter {
  let intensity: Double
  let distortion: Double
  let frequency: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    let stepX = 1.7320508
    let stepY = 3.0
    return DistortionSampling.warp(image) { x, y in
      let p = DistortionSampling.fieldPoint(x: x, y: y, width: w, height: h)
      let gx = p.0 * frequency
      let gy = p.1 * frequency
      let a = (
        DistortionSampling.mod(gx, stepX) - stepX * 0.5,
        DistortionSampling.mod(gy, stepY) - stepY * 0.5
      )
      let b = (
        DistortionSampling.mod(gx - stepX * 0.5, stepX) - stepX * 0.5,
        DistortionSampling.mod(gy - stepY * 0.5, stepY) - stepY * 0.5
      )
      let aSquared = a.0 * a.0 + a.1 * a.1
      let bSquared = b.0 * b.0 + b.1 * b.1
      let local = aSquared < bSquared ? a : b
      let gain = intensity + distortion * (local.0 * local.0 + local.1 * local.1)
      let q = (p.0 + local.0 * gain / frequency, p.1 + local.1 * gain / frequency)
      return DistortionSampling.pixel(fromField: q, width: w, height: h)
    }
  }
}

/// Стеклянные плитки, треугольная сетка. Формула из `ProceduralShaders.kt` перенесена точно,
/// проверена по эталону (`GlassTriangleTilesFilter`, раздел 10).
struct GlassTriangleTilesFilter: Filter {
  let intensity: Double
  let distortion: Double
  let frequency: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    return DistortionSampling.warp(image) { x, y in
      let p = DistortionSampling.fieldPoint(x: x, y: y, width: w, height: h)
      let gx = (p.0 - p.1 / 1.7320508) * frequency
      let gy = p.1 * 1.1547005 * frequency
      let cellX = gx.rounded(.down)
      let cellY = gy.rounded(.down)
      let inside = (gx - cellX) + (gy - cellY) < 1
      let offset = inside ? 0.3333333 : 0.6666667
      let lx = gx - (cellX + offset)
      let ly = gy - (cellY + offset)
      let local = (lx + ly * 0.5, ly * 0.8660254)
      let gain = intensity + distortion * (local.0 * local.0 + local.1 * local.1) * 3
      let q = (p.0 + local.0 * gain / frequency, p.1 + local.1 * gain / frequency)
      return DistortionSampling.pixel(fromField: q, width: w, height: h)
    }
  }
}

/// Логарифмическая спираль. Формула из `ProceduralShaders.kt` перенесена точно, выборка
/// без зеркала, как в шейдере (`fract` по текстурным координатам). Проверена по эталону
/// (`LogarithmicSpiralFilter`, раздел 10).
struct LogarithmicSpiralFilter: Filter {
  let count: Double
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    let tau = 6.28318530718
    return DistortionSampling.warp(image) { x, y in
      let p = DistortionSampling.fieldPoint(x: x, y: y, width: w, height: h)
      let r = max((p.0 * p.0 + p.1 * p.1).squareRoot(), 0.00001)
      let angle = angleOf(p) / tau
      let uvX = angle * count + log(r) * intensity
      let uvY = angle + log(r)
      return (DistortionSampling.fract(uvX) * w, DistortionSampling.fract(uvY) * h)
    }
  }

  private func angleOf(_ p: (Double, Double)) -> Double {
    p.0 * p.0 + p.1 * p.1 < 0.00000001 ? 0 : atan2(p.1, p.0)
  }
}

/// Спираль Droste. Формула из `ProceduralShaders.kt` перенесена точно, проверена по эталону
/// (`SpiralDrosteFilter`, раздел 10).
struct SpiralDrosteFilter: Filter {
  let intensity: Double
  let distortion: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let w = Double(image.width)
    let h = Double(image.height)
    let tau = 6.28318530718
    return DistortionSampling.warp(image) { x, y in
      let p = DistortionSampling.fieldPoint(x: x, y: y, width: w, height: h)
      let r = max((p.0 * p.0 + p.1 * p.1).squareRoot(), 0.00001)
      let angle = p.0 * p.0 + p.1 * p.1 < 0.00000001 ? 0 : atan2(p.1, p.0)
      let period = log(intensity)
      let logRadius = log(r / 0.5) - distortion * angle
      let layer = (logRadius / period).rounded(.down)
      let radius = exp(DistortionSampling.mod(logRadius, period)) * 0.5 / intensity
      let turn = angle + distortion * layer * tau
      let q = (radius * cos(turn), radius * sin(turn))
      return DistortionSampling.pixel(fromField: q, width: w, height: h)
    }
  }
}
