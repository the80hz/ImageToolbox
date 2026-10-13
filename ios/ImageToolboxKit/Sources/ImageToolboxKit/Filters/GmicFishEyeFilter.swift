import Foundation

/// «Рыбий глаз» из G'MIC: команда `fisheye` из стандартной библиотеки G'MIC 4.0.2.
///
/// Источник: T8RIN/ImageToolboxLibs 8.1.0, `libs/gmic` (`TransformFilters.kt`, класс `FishEye`;
/// `gmic_jni.cpp`, перевод Bitmap в `float` и обратно; `third_party/gmic/gmic_stdlib_community.h`
/// v4.0.2, распакованная библиотека, команда `fisheye`; `CImg.h`, функции `distance`, `normalize`,
/// `pow`, `get_resize`, `get_warp`, `_linear_atXY`). Команда в библиотеке:
///
/// ```
/// fisheye : _center_x,_center_y,0<=_radius<=100,_amplitude>=0   (50, 50, 50, 1.2)
/// 100%,100%,1,1 =. 1,$1%,$2% distance. 1 c. 0,$3% *. -1 n. 0,1 ^. {1/$4}
/// i.. ({-$1/100},{1-$1/100};...^{-$2/100},{-$2/100};...) r.. .,.,1,2,3
/// n. 0,{max(w,h)} *[-2,-1] warp.. .,1,1,1
/// ```
///
/// Android вызывает `fisheye radius,amplitude`, то есть передаёт радиус и амплитуду на места первых
/// двух аргументов, центра. Поэтому `radius` (по умолчанию 70) на деле задаёт центр по x в процентах,
/// `amplitude` (по умолчанию 1) центр по y в процентах, а настоящие радиус 50 и амплитуда 1.2 берутся
/// из значений по умолчанию G'MIC. Здесь это перенесено как есть (см. решение 18 в FILTERS.md).
///
/// Расчёт: карта силы — расстояние до точки `(x, y)` с центром `round(p * (размер - 1) / 100)`,
/// обрезанное по половине наибольшего расстояния, нормированное в 0...1 с инверсией, в степени
/// `1 / 1.2`, затем масштабированное на `max(w, h)`. Поле смещения — линейные рампы
/// `[-c, 1-c]` по осям, умноженные на карту силы. Результат — обратное относительное смещение
/// (`warp` режим 1), билинейно, край `Neumann`. Всё во `Float`, как в CImg, рампа и сила считаются на
/// лету. Каналы — RGBA без premultiplied (в Android бит-карта premultiplied, `gmic_jni.cpp` снимает
/// альфу при входе и накладывает при выходе, байт — округление `+ 0.5`).
///
/// Статус: проверено по эталону.
struct FishEyeFilter: Filter {
  /// Первый аргумент Android: попадает в центр по x, проценты.
  let radius: Double
  /// Второй аргумент Android: попадает в центр по y, проценты.
  let amplitude: Double

  /// Значения по умолчанию G'MIC `fisheye` для третьего и четвёртого аргументов.
  private static let gmicRadius = 50.0
  private static let gmicAmplitude = 1.2

  func apply(to image: RasterImage) async throws -> RasterImage {
    let width = image.width
    let height = image.height
    let seedX = Self.percentToIndex(radius, count: width)
    let seedY = Self.percentToIndex(amplitude, count: height)
    // Самое далёкое расстояние (до угла), как `max` по карте `distance`.
    let farX = max(seedX, width - 1 - seedX)
    let farY = max(seedY, height - 1 - seedY)
    let maximum = Self.distance(squared: farX * farX + farY * farY)
    // `cut 0,50%`: порог double, затем во float.
    let cutValue = Float(0 + (Double(maximum) - 0) * Self.gmicRadius / 100)
    guard cutValue > 0 else { return image }
    let exponent = Float(1 / Self.gmicAmplitude)
    let scale = Float(max(width, height))
    let rampX = Self.ramp(count: width, first: -radius / 100, second: 1 - radius / 100)
    let rampY = Self.ramp(count: height, first: -amplitude / 100, second: 1 - amplitude / 100)

    var output = [UInt8](repeating: 0, count: image.pixels.count)
    image.pixels.withUnsafeBufferPointer { input in
      let reader = SharedConstBuffer(base: input.baseAddress!)
      output.withUnsafeMutableBufferPointer { target in
        let writer = SharedBuffer(base: target.baseAddress!)
        ParallelBands.run(rows: height) { rows in
          for y in rows {
            let dy = y - seedY
            for x in 0..<width {
              let dx = x - seedX
              var distance = Self.distance(squared: dx * dx + dy * dy)
              if distance > cutValue { distance = cutValue }
              // `n. 0,1` после `*. -1`: минимум -cutValue, максимум 0.
              var force = (-distance - -cutValue) / (0 - -cutValue) * 1 + 0
              force = powf(force, exponent)
              if scale != 1 { force = force / 1 * scale + 0 }
              let shiftX = rampX[x] * force
              let shiftY = rampY[y] * force
              Self.sample(
                reader.base, width: width, height: height,
                x: Float(x) - shiftX, y: Float(y) - shiftY,
                into: writer.base + (y * width + x) * 4)
            }
          }
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  /// `round(percent * (count - 1) / 100)` как в команде `=` G'MIC (`cimg::round`: половина вверх).
  private static func percentToIndex(_ percent: Double, count: Int) -> Int {
    let value = percent * Double(count - 1) / 100
    guard value.isFinite else { return 0 }
    return min(max(Int((value + 0.5).rounded(.down)), 0), count - 1)
  }

  /// `distance` + `sqrt` в CImg: квадрат расстояния хранится во `Float`, корень берётся в `double`.
  @inline(__always)
  private static func distance(squared: Int) -> Float {
    Float(Double(Float(squared)).squareRoot())
  }

  /// Матрица 2x2 `[first, second; first, second]` (для оси x), растянутая в `count` значений
  /// линейным `resize` CImg с границей Dirichlet: ось, вдоль которой значения меняются.
  /// Первый проход CImg (`get_resize`, интерполяция 3) повторён по шагам, включая накопление
  /// шага `curr` в `double`.
  private static func ramp(count: Int, first: Double, second: Double) -> [Float] {
    let source = [Float(first), Float(second)]
    guard count > 1 else { return [Float((Double(source[0]) + Double(source[1])) / 2)] }
    let step = 1.0 / Double(count - 1)
    var result = [Float](repeating: 0, count: count)
    var position = 0.0
    var cursor = 0
    for index in 0..<count {
      let fraction = position - Double(UInt(position))
      let previous = position
      position = min(1.0, position + step)
      let value1 = source[cursor]
      let value2 = cursor < 1 ? source[cursor + 1] : value1
      result[index] = Float((1 - fraction) * Double(value1) + fraction * Double(value2))
      cursor += Int(UInt(position)) - Int(UInt(previous))
    }
    return result
  }

  /// `_linear_atXY` CImg: Neumann, формула `Icc + (Inc - Icc + (Icc + Inn - Icn - Inc) * dy) * dx
  /// + (Icn - Icc) * dy` во `Float`; затем `gmic_jni.cpp` накладывает альфу и округляет.
  private static func sample(
    _ pixels: UnsafePointer<UInt8>, width: Int, height: Int, x: Float, y: Float,
    into target: UnsafeMutablePointer<UInt8>
  ) {
    let clampedX = x.isNaN ? 0 : min(max(x, 0), Float(width) - 1)
    let clampedY = y.isNaN ? 0 : min(max(y, 0), Float(height) - 1)
    let column = Int(clampedX)
    let row = Int(clampedY)
    let dx = clampedX - Float(column)
    let dy = clampedY - Float(row)
    let nextColumn = dx > 0 ? column + 1 : column
    let nextRow = dy > 0 ? row + 1 : row
    let topLeft = (row * width + column) * 4
    let topRight = (row * width + nextColumn) * 4
    let bottomLeft = (nextRow * width + column) * 4
    let bottomRight = (nextRow * width + nextColumn) * 4
    var values = SIMD4<Float>()
    for channel in 0..<4 {
      let icc = straight(pixels, topLeft, channel)
      let inc = straight(pixels, topRight, channel)
      let icn = straight(pixels, bottomLeft, channel)
      let inn = straight(pixels, bottomRight, channel)
      values[channel] = icc + (inc - icc + (icc + inn - icn - inc) * dy) * dx + (icn - icc) * dy
    }
    let alpha = clamp(values[3])
    let premultiply = alpha / 255
    target[0] = byte(values[0] * premultiply)
    target[1] = byte(values[1] * premultiply)
    target[2] = byte(values[2] * premultiply)
    target[3] = byte(alpha)
  }

  /// Канал без premultiplied, как `copyBitmapToGmic`: `255 / a` во `Float`, без округления.
  @inline(__always)
  private static func straight(_ pixels: UnsafePointer<UInt8>, _ index: Int, _ channel: Int)
    -> Float
  {
    let alpha = pixels[index + 3]
    if channel == 3 { return Float(alpha) }
    if alpha == 255 { return Float(pixels[index + channel]) }
    if alpha == 0 { return 0 }
    return clamp(Float(pixels[index + channel]) * (255 / Float(alpha)))
  }

  @inline(__always)
  private static func clamp(_ value: Float) -> Float {
    guard value > 0 else { return 0 }
    return value >= 255 ? 255 : value
  }

  @inline(__always)
  private static func byte(_ value: Float) -> UInt8 {
    UInt8(clamp(value) + 0.5)
  }
}
