import Foundation

/// Гауссово размытие libblur 0.19.4 (`gaussian_blur`, режим `FixedPoint`) в варианте для arm64 с
/// расширением RDM, которое выполняет Android: `filter_1d_approx` и «симметричные» обработчики
/// строк и столбцов `filter_row_symm_neon_u8_i32_rdm`, `filter_column_symm_neon_u8_i32_rdm` и
/// `..._rdm_x3` (каталог `filter1d/neon`). Здесь только ядра от 29 отсчётов; для коротких ядер
/// (`BlurFilters.swift`, `shortKernelGaussian`) строки идут другим обработчиком (`binter`).
///
/// Арифметика целая. Веса — `Float`-ядро `gaussian_kernel_1d`, умноженное на 2^15 и усечённое до
/// целого (обработчики берут их как `i16`). Пиксель считается по векторному пути: `acc = Σ ((a + b)
/// * w + 256) >> 9` (то есть `vqrdmulhq_s16` над значениями, сдвинутыми влево на 6, с округлением
/// каждого слагаемого), результат `(acc + 32) >> 6`. Последний пиксель строки (последние 4 байта,
/// не попавшие ни в один векторный блок) считается скалярно и точнее: `(Σ (a + b) * w + 2^14) >>
/// 15`. Это относится и к строкам, и к столбцам.
///
/// Края:
/// - строки: слева и справа от строки `ядро / 2` пикселей, отражённых по режиму, но справа
///   записанных в обратном порядке (`write_arena_row`, `row.chunks_exact_mut(CN).rev()`);
/// - столбцы при ядре до 61 — скользящий буфер: над первой строкой стоит копия строки 0
///   (предзагрузка верхнего края), под последней — строки по режиму;
/// - столбцы при ядре больше 61 — `create_brows` берёт строки верхней и нижней подушек по индексам
///   `pad - k - 1` и `k - pad - 1`, которые на самом деле ведут к другим строкам (см.
///   `columnSource`), а обработчик по три строки (`..._x3`) оставляет последние `высота mod 3`
///   строк одиночному обработчику с номером строки, отсчитанным от нуля: они повторяют строки
///   `0..<высота mod 3` результата. Это поведение Android, оно воспроизведено как есть.
enum LibblurGaussian {
  /// Ядра короче этого строки обрабатывает другой код (`binter`), здесь они не поддерживаются.
  static let minimumTaps = 29

  /// `gaussian_kernel_1d`: веса `exp(-0.5 ((x - mean) / sigma)^2) / (sqrt(2 pi) sigma)`,
  /// нормированные на сумму 1, все операции во `Float`.
  static func kernel(taps: Int, sigma: Float) -> [Float] {
    let scale = 1 / ((2 * Float.pi).squareRoot() * sigma)
    let mean = Float(taps / 2)
    var weights = [Float](repeating: 0, count: taps)
    var total: Float = 0
    for index in 0..<taps {
      let dx = (Float(index) - mean) / sigma
      let weight = exp(-0.5 * dx * dx) * scale
      weights[index] = weight
      total += weight
    }
    if total != 0 {
      let factor = 1 / total
      for index in 0..<taps { weights[index] *= factor }
    }
    return weights
  }

  static func blur(
    _ source: [UInt8], width: Int, height: Int, taps: Int, sigma: Float, edge: BlurBorderMode
  ) -> [UInt8] {
    let weights = kernel(taps: taps, sigma: sigma).map {
      Int32(($0 * 32768).rounded(.towardZero))
    }
    let transient = rows(source, width: width, height: height, weights: weights, edge: edge)
    return columns(transient, width: width, height: height, weights: weights, edge: edge)
  }

  // MARK: Строки

  private static func rows(
    _ source: [UInt8], width: Int, height: Int, weights: [Int32], edge: BlurBorderMode
  ) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: source.count)
    let pad = weights.count / 2
    // Индексы столбцов рамки: слева отражение, справа в обратном порядке.
    let sourceColumns: [Int] = (0..<(width + 2 * pad)).map { slot in
      if slot < pad { return edge.index(slot - pad, count: width) }
      if slot < pad + width { return slot - pad }
      return edge.index(width + pad - 1 - (slot - pad - width), count: width)
    }
    let shortWeights = weights.map { Int32(Int16(truncatingIfNeeded: $0)) }
    source.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: height, minimumRows: 8) { band in
          let arena = UnsafeMutablePointer<UInt8>.allocate(capacity: (width + 2 * pad) * 4 + 64)
          defer { arena.deallocate() }
          arena.initialize(repeating: 0, count: (width + 2 * pad) * 4 + 64)
          for y in band {
            let line = reader.base + y * width * 4
            for slot in 0..<(width + 2 * pad) {
              let from = line + sourceColumns[slot] * 4
              UnsafeMutableRawPointer(arena + slot * 4).storeBytes(
                of: UnsafeRawPointer(from).loadUnaligned(as: UInt32.self), as: UInt32.self)
            }
            filterRow(
              UnsafePointer(arena), writer.base + y * width * 4, width: width,
              weights: weights, shortWeights: shortWeights)
          }
        }
      }
    }
    return output
  }

  /// Одна строка: пиксель `x` берёт отсчёты рамки `x...x + ядро - 1`.
  private static func filterRow(
    _ arena: UnsafePointer<UInt8>, _ result: UnsafeMutablePointer<UInt8>, width: Int,
    weights: [Int32], shortWeights: [Int32]
  ) {
    let length = weights.count
    let half = length / 2
    var x = 0
    while x + 4 <= width {
      var accumulator = quantised(load(arena + (x + half) * 4), shortWeights[half])
      for index in 0..<half {
        let pair =
          load(arena + (x + index) * 4) &+ load(arena + (x + length - 1 - index) * 4)
        accumulator &+= quantised(pair, shortWeights[index])
      }
      store(result + x * 4, finish(accumulator))
      x += 4
    }
    while x < width {
      for channel in 0..<4 {
        var accumulator =
          (Int32(arena[(x + half) * 4 + channel]) &* shortWeights[half] &+ 256) >> 9
        for index in 0..<half {
          let pair =
            Int32(arena[(x + index) * 4 + channel])
            + Int32(arena[(x + length - 1 - index) * 4 + channel])
          accumulator &+= (pair &* shortWeights[index] &+ 256) >> 9
        }
        result[x * 4 + channel] = UInt8(clamping: (accumulator &+ 32) >> 6)
      }
      x += 1
    }
    // Последний пиксель строки считается скалярно с округлением в конце.
    let last = width - 1
    for channel in 0..<4 {
      var total = Int32(arena[(last + half) * 4 + channel]) &* weights[half]
      for index in 0..<half {
        let pair =
          Int32(arena[(last + index) * 4 + channel])
          + Int32(arena[(last + length - 1 - index) * 4 + channel])
        total &+= pair &* weights[index]
      }
      result[last * 4 + channel] = UInt8(clamping: (total &+ 16384) >> 15)
    }
  }

  // MARK: Столбцы

  private static func columns(
    _ source: [UInt8], width: Int, height: Int, weights: [Int32], edge: BlurBorderMode
  ) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: source.count)
    let length = weights.count
    let shortWeights = weights.map { Int32(Int16(truncatingIfNeeded: $0)) }
    let large = length > 61
    // Строки, считаемые на самом деле: при большом ядре последние `height % 3` строк повторяют
    // первые, поэтому считаем только `height - height % 3` (или все, если их меньше трёх).
    let computed = large && height >= 3 ? height - height % 3 : height
    source.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: computed, minimumRows: 4) { band in
          let sources = UnsafeMutablePointer<UnsafePointer<UInt8>>.allocate(capacity: length)
          defer { sources.deallocate() }
          for y in band {
            for tap in 0..<length {
              let row = columnSource(
                y: y, tap: tap, length: length, height: height, large: large, edge: edge)
              sources[tap] = reader.base + row * width * 4
            }
            filterColumn(
              sources, writer.base + y * width * 4, width: width, weights: weights,
              shortWeights: shortWeights)
          }
        }
        if computed < height {
          for y in computed..<height {
            (writer.base + y * width * 4).update(
              from: writer.base + (y - computed) * width * 4, count: width * 4)
          }
        }
      }
    }
    return output
  }

  /// Строка, из которой выходная строка `y` берёт отсчёт `tap`.
  /// - до 61: над картинкой строка 0, под картинкой отражение по режиму;
  /// - больше 61: `create_brows` берёт у верха `top_pad[length/2 - tap - 1]` и у низа
  ///   `bottom_pad[tap - length/2 - 1]`, где `top_pad[i]` — строка `i - length/2` по режиму и
  ///   `bottom_pad[i]` — строка `i + height`. Номер подушки от `y` не зависит (так в libblur).
  private static func columnSource(
    y: Int, tap: Int, length: Int, height: Int, large: Bool, edge: BlurBorderMode
  ) -> Int {
    let half = length / 2
    let virtual = y - half + tap
    if virtual < 0 {
      if !large { return 0 }
      return edge.index(-tap - 1, count: height)
    }
    if virtual >= height {
      if !large { return edge.index(virtual, count: height) }
      return edge.index(tap - half - 1 + height, count: height)
    }
    return virtual
  }

  private static func filterColumn(
    _ rows: UnsafePointer<UnsafePointer<UInt8>>, _ result: UnsafeMutablePointer<UInt8>,
    width: Int, weights: [Int32], shortWeights: [Int32]
  ) {
    let length = weights.count
    let half = length / 2
    let total = width * 4
    var offset = 0
    while offset + 16 <= total {
      var accumulator = quantised(load(rows[half] + offset), shortWeights[half])
      for index in 0..<half {
        let pair = load(rows[index] + offset) &+ load(rows[length - 1 - index] + offset)
        accumulator &+= quantised(pair, shortWeights[index])
      }
      store(result + offset, finish(accumulator))
      offset += 16
    }
    while offset < total {
      var accumulator = (Int32(rows[half][offset]) &* shortWeights[half] &+ 256) >> 9
      for index in 0..<half {
        let pair = Int32(rows[index][offset]) + Int32(rows[length - 1 - index][offset])
        accumulator &+= (pair &* shortWeights[index] &+ 256) >> 9
      }
      result[offset] = UInt8(clamping: (accumulator &+ 32) >> 6)
      offset += 1
    }
    for byte in (total - 4)..<total {
      var sum = Int32(rows[half][byte]) &* weights[half]
      for index in 0..<half {
        let pair = Int32(rows[index][byte]) + Int32(rows[length - 1 - index][byte])
        sum &+= pair &* weights[index]
      }
      result[byte] = UInt8(clamping: (sum &+ 16384) >> 15)
    }
  }

  // MARK: Арифметика

  @inline(__always)
  private static func load(_ pointer: UnsafePointer<UInt8>) -> SIMD16<Int32> {
    SIMD16<Int32>(
      truncatingIfNeeded: UnsafeRawPointer(pointer).loadUnaligned(as: SIMD16<UInt8>.self))
  }

  @inline(__always)
  private static func store(_ pointer: UnsafeMutablePointer<UInt8>, _ value: SIMD16<UInt8>) {
    UnsafeMutableRawPointer(pointer).storeBytes(of: value, as: SIMD16<UInt8>.self)
  }

  /// `vqrdmulhq_s16(значение << 6, вес)`: `(значение * вес + 256) >> 9`.
  @inline(__always)
  private static func quantised(_ value: SIMD16<Int32>, _ weight: Int32) -> SIMD16<Int32> {
    (value &* weight &+ 256) &>> 9
  }

  /// `vqrshrun_n_s16::<6>`: `(acc + 32) >> 6` с ограничением 0...255.
  @inline(__always)
  private static func finish(_ accumulator: SIMD16<Int32>) -> SIMD16<UInt8> {
    let shifted = (accumulator &+ 32) &>> 6
    let clamped = shifted.clamped(
      lowerBound: SIMD16(repeating: 0), upperBound: SIMD16(repeating: 255))
    return SIMD16<UInt8>(truncatingIfNeeded: clamped)
  }
}
