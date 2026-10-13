import Foundation

/// Билатеральные размытия libblur 0.19.4 в варианте Aire 0.18.1 для arm64: `bilateral_filter`
/// (`bilateral/bp8.rs`, `bilateral/neon/bp8.rs`) и `fast_bilateral_filter`
/// (`fast_bilateral_filter.rs`). Оба считают каналы R, G, B и A независимо (альфа тоже, значения
/// premultiplied).
enum LibblurBilateral {
  // MARK: Точный билатеральный фильтр

  /// `bilateral_filter` с окном `kernel x kernel` (нечётное, не больше 254).
  ///
  /// Пространственный вес окна — `exp(-(dx^2 + dy^2) / (2 spatialSigma^2))`, цветовой —
  /// `exp(-(Δ/255)^2 / (2 rangeSigma^2))` по тому же каналу (`Δ` — разница канала соседа и центра),
  /// всё во `Float`. Сумма по окну идёт строка за строкой слева направо: `z = w_пространства *
  /// w_цвета`, `сумма = fma(z, значение, сумма)`, `вес += z`, результат `round(сумма / вес)` (вес 0
  /// заменяется на 1). Порядок и слияние умножения со сложением важны для точного совпадения,
  /// поэтому сумма не переупорядочивается.
  ///
  /// Края — рамка `AireArena` (режим из параметров). У ширин, не кратных 4 байтам на 16, у
  /// NEON-кода libblur есть дефект: пиксели правого края, не попавшие в блоки по 4 пикселя (1...3
  /// штуки), берут окно с левого края строки, а центр свой. Скалярный остаток считает без слияния.
  /// Воспроизведено по исходнику; на эталоне не проверено (его ширина кратна 4).
  static func filter(
    _ source: [UInt8], width: Int, height: Int, kernel: Int, spatialSigma: Float,
    rangeSigma: Float, edge: BlurBorderMode
  ) -> [UInt8] {
    let size = min(kernel, 254)
    guard size > 1 else { return source }
    let pad = size / 2
    let spatialFactor = 1.0 / (2.0 * spatialSigma * spatialSigma)
    let rangeFactor = 1.0 / (2.0 * rangeSigma * rangeSigma)
    var spatial = [Float](repeating: 0, count: size * size)
    for dy in 0..<size {
      for dx in 0..<size {
        let zx = Float(pad - dx)
        let zy = Float(pad - dy)
        spatial[dy * size + dx] = exp(-((zx * zx + zy * zy) * spatialFactor))
      }
    }
    var intensity = [Float](repeating: 0, count: 65536)
    for pixel in 0..<256 {
      for other in 0..<256 {
        let difference = Float(pixel) / 255.0 - Float(other) / 255.0
        intensity[pixel * 256 + other] = exp(-((difference * difference) * rangeFactor))
      }
    }
    var output = [UInt8](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { sourceBuffer in
      let arena = AireArena.make(
        sourceBuffer, width: width, height: height, padX: pad, padY: pad, mode: edge, tail: 64)
      arena.withUnsafeBufferPointer { arenaBuffer in
        spatial.withUnsafeBufferPointer { spatialBuffer in
          intensity.withUnsafeBufferPointer { intensityBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
              guard let arenaBase = arenaBuffer.baseAddress,
                let spatialBase = spatialBuffer.baseAddress,
                let intensityBase = intensityBuffer.baseAddress,
                let sourceBase = sourceBuffer.baseAddress,
                let target = outputBuffer.baseAddress
              else { return }
              let context = BilateralContext(
                arena: arenaBase, source: sourceBase, spatial: spatialBase,
                intensity: intensityBase, width: width, size: size)
              let writer = SharedBuffer(base: target)
              ParallelBands.run(rows: height, minimumRows: 2) { band in
                for y in band { context.row(y, into: writer.base + y * width * 4) }
              }
            }
          }
        }
      }
    }
    return output
  }

  private struct BilateralContext: @unchecked Sendable {
    let arena: UnsafePointer<UInt8>
    let source: UnsafePointer<UInt8>
    let spatial: UnsafePointer<Float>
    let intensity: UnsafePointer<Float>
    let width: Int
    let size: Int

    func row(_ y: Int, into target: UnsafeMutablePointer<UInt8>) {
      let total = width * 4
      // Полные блоки по 4 пикселя (16 байт), затем блок на 2 пикселя (8 байт), затем скалярный
      // остаток в 1 пиксель. Блок на 2 пикселя и остаток берут окно с левого края (дефект libblur).
      let blocks = total / 16
      let remainder = total - blocks * 16
      for pixel in 0..<(blocks * 4) {
        write(y, pixel, window: pixel, fused: true, target)
      }
      var next = blocks * 4
      if remainder >= 8 {
        write(y, next, window: 0, fused: true, target)
        write(y, next + 1, window: 0, fused: true, target)
        next += 2
      }
      if next < width {
        write(y, next, window: 0, fused: false, target)
      }
    }

    /// Пиксель `x` строки `y` с окном, начинающимся в столбце `window` рамки.
    @inline(__always)
    private func write(
      _ y: Int, _ x: Int, window: Int, fused: Bool, _ target: UnsafeMutablePointer<UInt8>
    ) {
      let centre = source + (y * width + x) * 4
      let lut0 = intensity + Int(centre[0]) * 256
      let lut1 = intensity + Int(centre[1]) * 256
      let lut2 = intensity + Int(centre[2]) * 256
      let lut3 = intensity + Int(centre[3]) * 256
      var sum = SIMD4<Float>(repeating: 0)
      var weight = SIMD4<Float>(repeating: 0)
      let arenaWidth = width + 2 * (size / 2)
      for ky in 0..<size {
        var cursor = arena + ((y + ky) * arenaWidth + window) * 4
        let weights = spatial + ky * size
        for kx in 0..<size {
          let w = weights[kx]
          let z = SIMD4<Float>(
            w * lut0[Int(cursor[0])], w * lut1[Int(cursor[1])], w * lut2[Int(cursor[2])],
            w * lut3[Int(cursor[3])])
          let value = SIMD4<Float>(
            Float(cursor[0]), Float(cursor[1]), Float(cursor[2]), Float(cursor[3]))
          if fused {
            sum.addProduct(z, value)
          } else {
            sum += z * value
          }
          weight += z
          cursor += 4
        }
      }
      for lane in 0..<4 {
        let divisor = weight[lane] == 0 ? 1 : weight[lane]
        let value = (sum[lane] / divisor).rounded()
        target[x * 4 + lane] = UInt8(clamping: Int(min(max(value, 0), 255)))
      }
    }
  }

  // MARK: Быстрый билатеральный фильтр

  /// `fast_bilateral_filter`: канал строится в трёхмерную сетку (x, y, яркость), сетка сглаживается
  /// гауссовым ядром `kernelSize` по трём осям и выбирается трилинейно. Параметры, шкалы сетки и
  /// порядок всех операций — как в Rust (`Float` на каждом шаге). Каждый канал считается отдельно.
  static func fast(
    _ source: [UInt8], width: Int, height: Int, kernelSize: Int, spatialSigma: Float,
    rangeSigma: Float
  ) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: source.count)
    var plane = [Float](repeating: 0, count: width * height)
    let scale: Float = 1.0 / 255.0
    for channel in 0..<4 {
      for index in 0..<(width * height) {
        plane[index] = Float(source[index * 4 + channel]) * scale
      }
      let result = fastPlane(
        plane, width: width, height: height, kernelSize: kernelSize, spatialSigma: spatialSigma,
        rangeSigma: rangeSigma)
      for index in 0..<(width * height) {
        let value = min(max(result[index] * 255.0, 0), 255).rounded()
        output[index * 4 + channel] = UInt8(clamping: Int(value))
      }
    }
    return output
  }

  private static func fastPlane(
    _ plane: [Float], width: Int, height: Int, kernelSize: Int, spatialSigma: Float,
    rangeSigma: Float
  ) -> [Float] {
    var baseMax = -Float.greatestFiniteMagnitude
    var baseMin = Float.greatestFiniteMagnitude
    for value in plane {
      baseMin = min(value, baseMin)
      baseMax = max(value, baseMax)
    }
    let baseDelta = baseMax - baseMin
    let padding: Float = 2

    let spatialScale: Float
    if spatialSigma > 1 {
      spatialScale = max(
        min(1 / spatialSigma * (spatialSigma > 1.3 ? 1.3 : 1), 1 / 1.2), 1 / 5)
    } else {
      spatialScale = 1
    }
    let rangeScale: Float
    if rangeSigma > 1 {
      rangeScale = max(min(1 / rangeSigma, 1 / 1.1), 1 / 5)
    } else {
      rangeScale = 1
    }
    let gridWidth = floatToIndex(Float(width - 1) * spatialScale + 1 + 2 * padding)
    let gridHeight = floatToIndex(Float(height - 1) * spatialScale + 1 + 2 * padding)
    let gridDepth = floatToIndex(baseDelta * rangeScale + 1 + 2 * padding)
    let count = gridWidth * gridHeight * gridDepth
    var data = [SIMD2<Float>](repeating: SIMD2(0, 0), count: count)

    func cell(_ x: Int, _ y: Int, _ z: Int) -> Int { (x * gridHeight + y) * gridDepth + z }

    for x in 0..<width {
      let smallX = Int((Float(x) * spatialScale + 0.5) + padding)
      for y in 0..<height {
        let pixel = plane[y * width + x]
        let z = pixel - baseMin
        let smallY = Int((Float(y) * spatialScale + 0.5) + padding)
        let smallZ = Int((z * rangeScale + 0.5) + padding)
        let index = cell(smallX, smallY, smallZ)
        var value = data[index]
        value.x += pixel
        value.y += 1
        data[index] = value
      }
    }

    let preferredSigma = (spatialSigma * spatialSigma + rangeSigma * rangeSigma).squareRoot()
    let gaussian = LibblurGaussian.kernel(taps: kernelSize, sigma: preferredSigma)
    let half = gaussian.count / 2
    data = convolve(
      data, axisLength: gridWidth, stride: gridHeight * gridDepth, kernel: gaussian, half: half)
    data = convolve(
      data, axisLength: gridDepth, stride: 1, kernel: gaussian, half: half)
    data = convolve(
      data, axisLength: gridHeight, stride: gridDepth, kernel: gaussian, half: half)

    var result = plane
    let minimum = baseMin
    data.withUnsafeBufferPointer { gridBuffer in
      result.withUnsafeMutableBufferPointer { resultBuffer in
        guard let grid = gridBuffer.baseAddress, let target = resultBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: grid)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: height, minimumRows: 8) { band in
          for y in band {
            for x in 0..<width {
              let value = writer.base[y * width + x]
              let z = value - minimum
              let sample = trilinear(
                reader.base, gridWidth, gridHeight, gridDepth,
                Float(x) * spatialScale + padding, Float(y) * spatialScale + padding,
                z * rangeScale + padding)
              writer.base[y * width + x] = sample.y != 0 ? sample.x / sample.y : 0
            }
          }
        }
      }
    }
    return result
  }

  /// Приведение `Float` к индексу как `as usize` в Rust (отрицательное и `NaN` дают 0).
  private static func floatToIndex(_ value: Float) -> Int {
    value.isNaN || value < 0 ? 0 : Int(value)
  }

  /// Свёртка вдоль одной оси сетки. Ядро несимметрично по шагам, как в libblur: для веса `i`
  /// берутся отсчёты `i - half` и `half - 1 - i` от текущей позиции (с повтором крайнего), плюс
  /// центральный с весом `kernel[half]`: `сумма = центр * g[half]; сумма += (a + b) * g[i]`.
  private static func convolve(
    _ data: [SIMD2<Float>], axisLength: Int, stride: Int, kernel: [Float], half: Int
  ) -> [SIMD2<Float>] {
    var result = data
    let total = data.count
    data.withUnsafeBufferPointer { sourceBuffer in
      result.withUnsafeMutableBufferPointer { targetBuffer in
        guard let source = sourceBuffer.baseAddress, let target = targetBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: source)
        let writer = SharedBuffer(base: target)
        let blocks = max(1, total / 4096)
        ParallelBands.blocks(count: blocks) { block in
          let start = block * total / blocks
          let end = (block + 1) * total / blocks
          for index in start..<end {
            let position = (index / stride) % axisLength
            let centre = reader.base[index]
            var sum = centre * kernel[half]
            for i in 0..<half {
              let low = min(max(position + i - half, 0), axisLength - 1)
              let high = min(max(position + (half - 1 - i), 0), axisLength - 1)
              let a = reader.base[index + (low - position) * stride]
              let b = reader.base[index + (high - position) * stride]
              sum += (a + b) * kernel[i]
            }
            writer.base[index] = sum
          }
        }
      }
    }
    return result
  }

  /// `Array3D::trilinear_interpolation`: восемь соседних ячеек, порядок слагаемых как в Rust.
  private static func trilinear(
    _ grid: UnsafePointer<SIMD2<Float>>, _ width: Int, _ height: Int, _ depth: Int,
    _ x: Float, _ y: Float, _ z: Float
  ) -> SIMD2<Float> {
    func clamp(_ value: Float, _ upper: Int) -> Float { min(max(value, 0), Float(upper)) }
    let xIndex = clamp(x, width - 1)
    let xx = Int(clamp(xIndex + 1, width - 1))
    let yIndex = clamp(y, height - 1)
    let yy = Int(clamp(yIndex + 1, height - 1))
    let zIndex = clamp(z, depth - 1)
    let zz = Int(clamp(zIndex + 1, depth - 1))
    let xa = x - xIndex
    let ya = y - yIndex
    let za = z - zIndex
    let x0 = Int(xIndex)
    let y0 = Int(yIndex)
    let z0 = Int(zIndex)
    func get(_ i: Int, _ j: Int, _ k: Int) -> SIMD2<Float> { grid[(i * height + j) * depth + k] }
    let one: Float = 1
    var result = get(x0, y0, z0) * (one - xa) * (one - ya) * (one - za)
    result += xa * (one - ya) * (one - za) * get(xx, y0, z0)
    result += (one - xa) * ya * (one - za) * get(x0, yy, z0)
    result += xa * ya * (one - za) * get(xx, yy, z0)
    result += (one - xa) * (one - ya) * za * get(x0, y0, zz)
    result += xa * (one - ya) * za * get(xx, y0, zz)
    result += (one - xa) * ya * za * get(x0, yy, zz)
    result += xa * ya * za * get(xx, yy, zz)
    return result
  }
}
