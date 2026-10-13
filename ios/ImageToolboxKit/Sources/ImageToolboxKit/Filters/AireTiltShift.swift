import Foundation

/// Tilt-shift из Aire 0.18.1 (`jni/ShiftPipelines.cpp`, `shift/TiltShift.cpp`): картинка
/// размывается `gaussBlurU8` (`blur/GaussBlur.cpp`, `base/Convolve1D.cpp`), затем размытая и
/// исходная смешиваются по доле, растущей с кубом расстояния от зоны фокуса. Все вычисления в
/// `Float`, цвета делятся на 255 и смешиваются как `x * (1 - a) + y * a`, результат в байт
/// усечением; альфа берётся из исходной картинки.
enum AireTiltShift {
  // MARK: gaussBlurU8

  /// Гауссово ядро Aire `compute1DGaussianKernel(width, sigma)`: `width` отсчётов (не `2 width +
  /// 1`), центр `width / 2`, веса `exp(-0.5 ((x - mean) / sigma)^2) / (sqrt(2 pi) sigma)`,
  /// нормированные делением на сумму.
  static func kernel(width: Int, sigma: Float) -> [Float] {
    let mean = width / 2
    let scale = 1 / (Float(2 * Double.pi).squareRoot() * sigma)
    var weights = [Float](repeating: 0, count: width)
    var total: Float = 0
    for index in 0..<width {
      let distance = Float(index - mean) / sigma
      let weight = exp(-0.5 * (distance * distance)) * scale
      weights[index] = weight
      total += weight
    }
    for index in 0..<width { weights[index] /= total }
    return weights
  }

  /// `gaussBlurU8`: сначала строки, затем столбцы; край повторяет крайний пиксель; после каждого
  /// прохода сумма округляется до чётного (`Round`) и ограничивается 0...255.
  ///
  /// У строкового прохода при ядре не 3, 5, 7 и 9 есть дефект Aire: блоки по четыре отсчёта читают
  /// четыре подряд идущих пикселя от `clamp(x + r)`, а не по пикселю на отсчёт. Слева от картинки
  /// это даёт пиксели 0, 1, 2, 3 вместо повторов пикселя 0. Блоки идут, пока `r + 4 <= max` и `x +
  /// r + 4 < width`, остаток считается по одному отсчёту с ограничением индекса.
  static func gaussianBlur(
    _ source: [UInt8], width: Int, height: Int, size: Int, sigma: Float
  ) -> [UInt8] {
    let weights = kernel(width: max(size, 1), sigma: sigma)
    var transient = [UInt8](repeating: 0, count: source.count)
    var output = [UInt8](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { sourceBuffer in
      transient.withUnsafeMutableBufferPointer { transientBuffer in
        guard let input = sourceBuffer.baseAddress, let middle = transientBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: middle)
        ParallelBands.run(rows: height, minimumRows: 8) { band in
          for y in band {
            horizontal(
              reader.base + y * width * 4, writer.base + y * width * 4, width: width,
              weights: weights)
          }
        }
      }
    }
    transient.withUnsafeBufferPointer { transientBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = transientBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: height, minimumRows: 8) { band in
          vertical(
            reader.base, writer.base, band: band, width: width, height: height, weights: weights)
        }
      }
    }
    return output
  }

  @inline(__always)
  private static func pixel(_ line: UnsafePointer<UInt8>, _ x: Int) -> SIMD4<Float> {
    let p = line + x * 4
    return SIMD4(Float(p[0]), Float(p[1]), Float(p[2]), Float(p[3]))
  }

  @inline(__always)
  private static func roundedStore(
    _ value: SIMD4<Float>, _ target: UnsafeMutablePointer<UInt8>
  ) {
    for lane in 0..<4 {
      let rounded = value[lane].rounded(.toNearestOrEven)
      target[lane] = UInt8(clamping: Int(min(max(rounded, 0), 255)))
    }
  }

  private static func horizontal(
    _ line: UnsafePointer<UInt8>, _ result: UnsafeMutablePointer<UInt8>, width: Int,
    weights: [Float]
  ) {
    let length = weights.count
    let half = length / 2
    let maximum = length % 2 == 0 ? half - 1 : half
    let plain = length == 3 || length == 5 || length == 7 || length == 9
    weights.withUnsafeBufferPointer { weightBuffer in
      guard let w = weightBuffer.baseAddress else { return }
      for x in 0..<width {
        var sum = SIMD4<Float>(repeating: 0)
        if plain || (x - half >= 0 && x + maximum < width) {
          // Каждый отсчёт — пиксель x + r (без выхода за край или с повтором крайнего).
          for r in -half...maximum {
            let index = min(max(x + r, 0), width - 1)
            sum = sum + pixel(line, index) * w[r + half]
          }
        } else {
          var r = -half
          while r + 4 <= maximum && x + r + 4 < width {
            let base = min(max(x + r, 0), width - 1)
            for offset in 0..<4 {
              sum = sum + pixel(line, base + offset) * w[r + half + offset]
            }
            r += 4
          }
          while r <= maximum {
            let index = min(max(x + r, 0), width - 1)
            sum = sum + pixel(line, index) * w[r + half]
            r += 1
          }
        }
        roundedStore(sum, result + x * 4)
      }
    }
  }

  private static func vertical(
    _ source: UnsafePointer<UInt8>, _ target: UnsafeMutablePointer<UInt8>, band: Range<Int>,
    width: Int, height: Int, weights: [Float]
  ) {
    let length = weights.count
    let half = length / 2
    let maximum = length % 2 == 0 ? half - 1 : half
    let total = width * 4
    let accumulator = UnsafeMutablePointer<Float>.allocate(capacity: total)
    defer { accumulator.deallocate() }
    for y in band {
      accumulator.initialize(repeating: 0, count: total)
      for r in -half...maximum {
        let row = source + min(max(y + r, 0), height - 1) * total
        let weight = weights[r + half]
        for index in 0..<total {
          accumulator[index] = accumulator[index] + Float(row[index]) * weight
        }
      }
      let line = target + y * total
      for index in 0..<total {
        let rounded = accumulator[index].rounded(.toNearestOrEven)
        line[index] = UInt8(clamping: Int(min(max(rounded, 0), 255)))
      }
    }
  }

  // MARK: Смешивание

  /// Круговой tilt-shift (`aire::tiltShift`): расстояние от якоря в пикселях делится на `корень(w^2
  /// + h^2) * radius`, доля размытия — куб этого отношения, не больше 1.
  static func radial(
    _ source: [UInt8], width: Int, height: Int, radius: Int, sigma: Float, anchorX: Float,
    anchorY: Float, hole: Float
  ) -> [UInt8] {
    let blurred = gaussianBlur(source, width: width, height: height, size: radius, sigma: sigma)
    let available = Float(Double(height * height + width * width).squareRoot())
    let minimum = available * hole
    let centreX = Int(Float(width) * anchorX)
    let centreY = Int(Float(height) * anchorY)
    return blend(source, blurred, width: width, height: height) { x, y in
      let dx = Float(x - centreX)
      let dy = Float(y - centreY)
      let distance = (dx * dx + dy * dy).squareRoot()
      let ratio = distance / minimum
      return min(max(ratio * ratio * ratio, 0), 1)
    }
  }

  /// Линейный tilt-shift (`aire::horizontalTiltShift`): точка поворачивается на `angle` вокруг
  /// якоря (в целых), расстояние берётся по x или по y в зависимости от угла.
  static func linear(
    _ source: [UInt8], width: Int, height: Int, radius: Int, sigma: Float, anchorX: Float,
    anchorY: Float, hole: Float, angle: Float
  ) -> [UInt8] {
    let blurred = gaussianBlur(source, width: width, height: height, size: radius, sigma: sigma)
    let cosine = cos(angle)
    let sine = sin(angle)
    let newWidth = Int(abs(Float(width) * cosine) + abs(Float(height) * sine))
    let newHeight = Int(abs(Float(width) * sine) + abs(Float(height) * cosine))
    let rotation = Float(
      (Double(angle) + Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi) - Double.pi)
    let rangeMin = Float(-Double.pi / 4.0)
    let rangeMax = Float(Double.pi / 4.0)
    let horizontal = rotation >= rangeMin && rotation <= rangeMax
    let available =
      horizontal
      ? Float(Double(newWidth * newWidth).squareRoot())
      : Float(Double(newHeight * newHeight).squareRoot())
    let minimum = available * hole
    let anchorPixelX = Int(Float(width) * anchorX)
    let anchorPixelY = Int(Float(height) * anchorY)
    return blend(source, blurred, width: width, height: height) { x, y in
      let relativeX = Float(x - anchorPixelX)
      let relativeY = Float(y - anchorPixelY)
      let rotatedX = Int(relativeX * cosine - relativeY * sine + Float(anchorPixelX))
      let rotatedY = Int(relativeX * sine + relativeY * cosine + Float(anchorPixelY))
      let dx = Float(rotatedX - anchorPixelX)
      let dy = Float(rotatedY - anchorPixelY)
      let distance = horizontal ? (dx * dx).squareRoot() : (dy * dy).squareRoot()
      let ratio = distance / minimum
      return min(max(ratio * ratio * ratio, 0), 1)
    }
  }

  private static func blend(
    _ source: [UInt8], _ blurred: [UInt8], width: Int, height: Int,
    fraction: @Sendable (Int, Int) -> Float
  ) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { sourceBuffer in
      blurred.withUnsafeBufferPointer { blurredBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
          guard let original = sourceBuffer.baseAddress, let soft = blurredBuffer.baseAddress,
            let target = outputBuffer.baseAddress
          else { return }
          let originalReader = SharedConstBuffer(base: original)
          let softReader = SharedConstBuffer(base: soft)
          let writer = SharedBuffer(base: target)
          ParallelBands.run(rows: height, minimumRows: 8) { band in
            for y in band {
              for x in 0..<width {
                let index = (y * width + x) * 4
                let sharp = originalReader.base + index
                let soft = softReader.base + index
                let share = Float(soft[3]) * fraction(x, y)
                let mix = share / 255.0
                let out = writer.base + index
                out[3] = sharp[3]
                // `NaN` (нулевой радиус зоны фокуса в самой точке якоря) Android приводит к байту как 0.
                if mix.isNaN {
                  out[0] = 0
                  out[1] = 0
                  out[2] = 0
                  continue
                }
                for channel in 0..<3 {
                  let colour = Float(sharp[channel]) / 255.0
                  let blur = Float(soft[channel]) / 255.0
                  let blended = colour * (1.0 - mix) + blur * mix
                  let scaled = min(max(blended * 255.0, 0), 255)
                  out[channel] = UInt8(clamping: Int(scaled))
                }
              }
            }
          }
        }
      }
    }
    return output
  }
}
