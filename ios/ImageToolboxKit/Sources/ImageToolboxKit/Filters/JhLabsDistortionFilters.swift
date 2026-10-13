import Foundation

/// Искажения Jh Labs: рябь, щипок и калейдоскоп.
///
/// Источник: T8RIN/ImageToolboxLibs 8.1.0, `libs/jhlabs/src/main/rust/jhlabs/src/lib.rs`
/// (`transform_filter`, ветки `"RippleFilter"`, `"PinchFilter"`, `"KaleidoscopeFilter"`; `bilinear`,
/// `sample`, `triangle`) и Java-классы `com.jhlabs.*` в том же теге (значения по умолчанию).
enum JhLabsTransform {
  /// Что отдаёт выборка за краем картинки (`edgeAction` в Jh Labs).
  enum Edge {
    /// `CLAMP`: крайний пиксель целиком, вместе с альфой.
    case clamp
    /// `RGB_CLAMP` (значение по умолчанию в `TransformFilter`): крайний пиксель, но альфа 0.
    case rgbClamp
  }

  /// Для каждого пикселя результата `source` даёт точку исходной картинки; значение берётся
  /// билинейно. Всё во `Float`, байт получается отбрасыванием дробной части (`as i32`).
  /// Цвет premultiplied, как хранит `RasterImage`. У `rgbClamp` за краем альфа 0, а цвет остаётся,
  /// поэтому на краях цвет может превысить альфу; такие пиксели приводятся к допустимому
  /// premultiplied-виду (цвет не больше альфы), как это делает сохранение в PNG на Android.
  static func run(
    _ image: RasterImage, edge: Edge,
    source: @Sendable (_ x: Float, _ y: Float) -> (Float, Float)
  ) -> RasterImage {
    let width = image.width
    let height = image.height
    var output = [UInt8](repeating: 0, count: image.pixels.count)
    image.pixels.withUnsafeBufferPointer { input in
      let reader = SharedConstBuffer(base: input.baseAddress!)
      output.withUnsafeMutableBufferPointer { target in
        let writer = SharedBuffer(base: target.baseAddress!)
        ParallelBands.run(rows: height) { rows in
          for y in rows {
            for x in 0..<width {
              let (sourceX, sourceY) = source(Float(x), Float(y))
              bilinear(
                reader.base, width: width, height: height, edge: edge,
                x: sourceX, y: sourceY, into: writer.base + (y * width + x) * 4)
            }
          }
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: output)
  }

  private static func bilinear(
    _ pixels: UnsafePointer<UInt8>, width: Int, height: Int, edge: Edge,
    x: Float, y: Float, into target: UnsafeMutablePointer<UInt8>
  ) {
    // NaN и бесконечности из пользовательских параметров: как `as isize` в Rust (NaN даёт 0).
    let safeX = x.isNaN ? 0 : min(max(x, -1e6), 1e6)
    let safeY = y.isNaN ? 0 : min(max(y, -1e6), 1e6)
    let left = safeX.rounded(.down)
    let top = safeY.rounded(.down)
    let xWeight = safeX - left
    let yWeight = safeY - top
    let x0 = Int(left)
    let y0 = Int(top)
    var corners = (SIMD4<Float>(), SIMD4<Float>(), SIMD4<Float>(), SIMD4<Float>())
    corners.0 = texel(pixels, width, height, edge, x0, y0)
    corners.1 = texel(pixels, width, height, edge, x0 + 1, y0)
    corners.2 = texel(pixels, width, height, edge, x0, y0 + 1)
    corners.3 = texel(pixels, width, height, edge, x0 + 1, y0 + 1)
    let north = corners.0 * (1 - xWeight) + corners.1 * xWeight
    let south = corners.2 * (1 - xWeight) + corners.3 * xWeight
    let mixed = north * (1 - yWeight) + south * yWeight
    let alpha = UInt8(min(max(Int(mixed[3]), 0), 255))
    for channel in 0..<3 {
      target[channel] = min(UInt8(min(max(Int(mixed[channel]), 0), 255)), alpha)
    }
    target[3] = alpha
  }

  private static func texel(
    _ pixels: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ edge: Edge, _ x: Int, _ y: Int
  ) -> SIMD4<Float> {
    let inside = x >= 0 && y >= 0 && x < width && y < height
    let column = min(max(x, 0), width - 1)
    let row = min(max(y, 0), height - 1)
    let index = (row * width + column) * 4
    let alpha: UInt8 = inside || edge == .clamp ? pixels[index + 3] : 0
    return SIMD4(
      Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]), Float(alpha))
  }

  /// `triangle` из Jh Labs: пилообразная волна 0...1...0 с периодом 1 (`rem_euclid` во `Float`).
  static func triangle(_ value: Float) -> Float {
    var remainder = fmodf(value, 1)
    if remainder < 0 { remainder += 1 }
    return 2 * (remainder < 0.5 ? remainder : 1 - remainder)
  }
}

/// Рябь: синусоидальный сдвиг строк и столбцов.
///
/// Источник: Jh Labs `RippleFilter` (8.1.0, `lib.rs`, ветка `"RippleFilter"`, волна `sin`).
/// Точка источника `(x + sin(y / xWavelength) * xAmplitude, y + sin(x / yWavelength) * yAmplitude)`
/// в пикселях, период волны `2π * wavelength` (без множителя `2π` в аргументе). Край `RGB_CLAMP`:
/// за картинкой цвет крайнего пикселя, но с нулевой альфой, поэтому край результата полупрозрачный.
/// При нулевых амплитудах картинка не меняется.
/// Статус: проверено по эталону.
struct RippleFilter: Filter {
  let xAmplitude: Double
  let xWavelength: Double
  let yAmplitude: Double
  let yWavelength: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let xAmplitude = Float(xAmplitude)
    let xWavelength = Float(xWavelength)
    let yAmplitude = Float(yAmplitude)
    let yWavelength = Float(yWavelength)
    return JhLabsTransform.run(image, edge: .rgbClamp) { x, y in
      (x + sinf(y / xWavelength) * xAmplitude, y + sinf(x / yWavelength) * yAmplitude)
    }
  }
}

/// Щипок и поворот внутри круга.
///
/// Источник: Jh Labs `PinchFilter` (8.1.0, `lib.rs`, ветка `"PinchFilter"`). Угол в градусах
/// переводится в радианы, радиус `radius * max(w, h) / 2` в пикселях, как в `PinchFilter.kt`
/// (`createFilter(image)`). Внутри круга точка источника — вектор от центра, умноженный на
/// `sin(π/2 * d / r) ^ -amount` и повёрнутый на `angle * (1 - d / r)^2`. Радиус 0 в Jh Labs означает
/// меньшую из половин размера. Край `RGB_CLAMP`. При `angle` 0 и `amount` 0 картинка не меняется.
/// Статус: проверено по эталону.
struct PinchFilter: Filter {
  let angle: Double
  let centreX: Double
  let centreY: Double
  let radius: Double
  let amount: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let centreXPixels = Float(centreX) * Float(image.width)
    let centreYPixels = Float(centreY) * Float(image.height)
    let scaled = Float(radius) * (Float(max(image.width, image.height)) / 2)
    let limit = scaled == 0 ? min(centreXPixels, centreYPixels) : scaled
    let turn = Float(angle * .pi / 180)
    let amount = Float(amount)
    return JhLabsTransform.run(image, edge: .rgbClamp) { x, y in
      let dx = x - centreXPixels
      let dy = y - centreYPixels
      let squared = dx * dx + dy * dy
      guard !(squared > limit * limit || squared == 0) else { return (x, y) }
      let distance = squared.squareRoot()
      let pinch = powf(sinf(Float.pi / 2 * distance / limit), -amount)
      let remaining = 1 - distance / limit
      let theta = turn * (remaining * remaining)
      let sine = sinf(theta)
      let cosine = cosf(theta)
      return (
        centreXPixels + pinch * (cosine * dx - sine * dy),
        centreYPixels + pinch * (sine * dx + cosine * dy)
      )
    }
  }
}

/// Калейдоскоп: сектор с `sides` зеркальными копиями вокруг центра.
///
/// Источник: Jh Labs `KaleidoscopeFilter` (8.1.0, `lib.rs`, ветка `"KaleidoscopeFilter"`). Расчёт
/// в `Double`, волна `triangle` во `Float`, край `CLAMP` (в Java-конструкторе). Углы `angle` и
/// `secondaryAngle` Android передаёт в Jh Labs как есть, то есть в радианах, хотя ползунок идёт
/// 0...360 (`UiKaleidoscopeFilter`); здесь то же. `sides` — целое. `radius` не 0 — пиксельный
/// радиус отражающей рамки, 0 — без неё.
/// Статус: проверено по эталону.
struct KaleidoscopeFilter: Filter {
  let angle: Double
  let secondaryAngle: Double
  let centreX: Double
  let centreY: Double
  let sides: Double
  let radius: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    let centreXPixels = Float(centreX) * Float(image.width)
    let centreYPixels = Float(centreY) * Float(image.height)
    let angle = Double(Float(angle))
    let secondaryAngle = Double(Float(secondaryAngle))
    let sideCount = Double(Int(sides.isFinite ? sides : 0))
    let effectRadius = Double(Float(radius))
    return JhLabsTransform.run(image, edge: .clamp) { x, y in
      let dx = Double(x - centreXPixels)
      let dy = Double(y - centreYPixels)
      var distance = (dx * dx + dy * dy).squareRoot()
      let fold = (atan2(dy, dx) - angle - secondaryAngle) / Double.pi * sideCount * 0.5
      var theta = Double(JhLabsTransform.triangle(Float(fold)))
      if effectRadius != 0 {
        let radiusCosine = effectRadius / cos(theta)
        distance = radiusCosine * Double(JhLabsTransform.triangle(Float(distance / radiusCosine)))
      }
      theta += angle
      return (
        centreXPixels + Float(distance * cos(theta)),
        centreYPixels + Float(distance * sin(theta))
      )
    }
  }
}
