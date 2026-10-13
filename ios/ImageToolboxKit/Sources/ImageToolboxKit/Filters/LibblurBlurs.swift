import Foundation

/// Размытия libblur 0.19.4, которые вызывает Aire 0.18.1 над байтами RGBA (`Channels4`): box
/// (`box_filter/box_blur.rs`), tent (там же, `tent_blur`), stack blur (`stackblur/`) и медианный
/// фильтр (`median_blur.rs`).
///
/// У всех краевой режим не настраивается: пиксели за краем повторяют крайний (clamp). Проходы идут
/// по строкам, затем по столбцам, после каждого результат округляется до байта. Суммы целые,
/// поэтому порядок слагаемых не важен и можно считать скользящими суммами за время, не зависящее от
/// радиуса. Все четыре канала обрабатываются одинаково, альфа тоже (premultiplied).
enum LibblurBlurs {
  // MARK: Box

  /// `box_blur` с ядром `2 radius + 1` (`radius >= 1`): среднее по окну, `round(сумма / ядро)`.
  /// Множитель — `Float`, `1 / ядро`, как в libblur. Горизонтальный проход, затем вертикальный.
  static func box(_ source: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    let weight = Float(1) / Float(2 * radius + 1)
    var transient = [UInt8](repeating: 0, count: source.count)
    var output = [UInt8](repeating: 0, count: source.count)
    runHorizontal(source, &transient, width: width, height: height) { line, result in
      boxLine(line, result, length: width, radius: radius, weight: weight)
    }
    runVertical(transient, &output, width: width, height: height) { source, target, range in
      boxColumns(
        source, target, range: range, stride: width * 4, height: height, radius: radius,
        weight: weight)
    }
    return output
  }

  private static func boxLine(
    _ line: UnsafePointer<UInt8>, _ result: UnsafeMutablePointer<UInt8>, length: Int, radius: Int,
    weight: Float
  ) {
    var sums = SIMD4<Int32>(repeating: 0)
    let first = pixel(line, 0)
    sums = first &* Int32(radius + 1)
    if radius >= 1 {
      for offset in 1...radius { sums &+= pixel(line, min(offset, length - 1)) }
    }
    for x in 0..<length {
      store(result, x, roundedBytes(sums, weight))
      sums &+= pixel(line, min(x + radius + 1, length - 1))
      sums &-= pixel(line, max(x - radius, 0))
    }
  }

  private static func boxColumns(
    _ source: UnsafePointer<UInt8>, _ target: UnsafeMutablePointer<UInt8>, range: Range<Int>,
    stride: Int, height: Int, radius: Int, weight: Float
  ) {
    let count = range.count
    let sums = UnsafeMutablePointer<Int32>.allocate(capacity: count)
    defer { sums.deallocate() }
    let top = source + range.lowerBound
    for index in 0..<count { sums[index] = Int32(top[index]) * Int32(radius + 1) }
    if radius >= 1 {
      for offset in 1...radius {
        let row = source + min(offset, height - 1) * stride + range.lowerBound
        for index in 0..<count { sums[index] &+= Int32(row[index]) }
      }
    }
    for y in 0..<height {
      let next = source + min(y + radius + 1, height - 1) * stride + range.lowerBound
      let previous = source + max(y - radius, 0) * stride + range.lowerBound
      let line = target + y * stride + range.lowerBound
      for index in 0..<count {
        let sum = sums[index]
        line[index] = UInt8(truncatingIfNeeded: Int((Float(sum) * weight).rounded()))
        sums[index] = sum &+ Int32(next[index]) &- Int32(previous[index])
      }
    }
  }

  // MARK: Tent

  /// `tent_blur`: два прохода box (по строкам и столбцам каждый). Размеры окон — `create_box_gauss`
  /// из libblur: по ним радиус каждого прохода `sizes[i]`, ядро `2 sizes[i] + 1`.
  static func tent(_ source: [UInt8], width: Int, height: Int, sigma: Float) -> [UInt8] {
    let sizes = boxSizes(sigma: sigma, count: 2)
    var current = source
    for size in sizes {
      current = box(current, width: width, height: height, radius: max(size, 1))
    }
    return current
  }

  /// `create_box_gauss(sigma, n)` из libblur (все операции во `Float`, как в Rust).
  static func boxSizes(sigma: Float, count: Int) -> [Int] {
    let n = Float(count)
    let ideal = (12.0 * sigma * sigma / n).squareRoot() + 1.0
    var lower = Int(ideal.rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let upper = lower + 2
    let lowerFloat = Float(lower)
    let mIdeal =
      (12.0 * sigma * sigma - n * lowerFloat * lowerFloat - 4.0 * n * lowerFloat - 3.0 * n)
      / (-4.0 * lowerFloat - 4.0)
    let rounded = mIdeal.rounded()
    let m = rounded.isNaN || rounded < 0 ? 0 : Int(min(rounded, 1_000_000))
    return (0..<count).map { index in
      var value = (index < m ? lower : upper) / 2
      if value % 2 == 0 { value += 1 }
      return value
    }
  }

  // MARK: Stack blur

  /// `stack_blur` с радиусом `radius >= 1`: треугольное ядро `radius + 1 - |k|`, делитель `(radius
  /// + 1)^2`, `round`. Строки, затем столбцы.
  static func stack(_ source: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    let weight = Float(1) / (Float(radius + 1) * Float(radius + 1))
    var transient = [UInt8](repeating: 0, count: source.count)
    var output = [UInt8](repeating: 0, count: source.count)
    runHorizontal(source, &transient, width: width, height: height) { line, result in
      stackLine(line, result, length: width, radius: radius, weight: weight)
    }
    runVertical(transient, &output, width: width, height: height) { source, target, range in
      stackColumns(
        source, target, range: range, stride: width * 4, height: height, radius: radius,
        weight: weight)
    }
    return output
  }

  /// Скользящие суммы: `S(y + 1) = S(y) + A(y) - B(y)`, где `A(y)` — сумма `p(y + 1)...p(y + r +
  /// 1)`, `B(y)` — сумма `p(y - r)...p(y)`. Начальные значения считаются по определению.
  private static func stackLine(
    _ line: UnsafePointer<UInt8>, _ result: UnsafeMutablePointer<UInt8>, length: Int, radius: Int,
    weight: Float
  ) {
    func at(_ index: Int) -> SIMD4<Int32> { pixel(line, min(max(index, 0), length - 1)) }
    var sums = SIMD4<Int32>(repeating: 0)
    for offset in -radius...radius { sums &+= at(offset) &* Int32(radius + 1 - abs(offset)) }
    var after = SIMD4<Int32>(repeating: 0)
    for offset in 1...(radius + 1) { after &+= at(offset) }
    var before = at(0) &* Int32(radius + 1)
    for x in 0..<length {
      store(result, x, roundedBytes(sums, weight))
      sums &+= after &- before
      after &+= at(x + radius + 2) &- at(x + 1)
      before &+= at(x + 1) &- at(x - radius)
    }
  }

  private static func stackColumns(
    _ source: UnsafePointer<UInt8>, _ target: UnsafeMutablePointer<UInt8>, range: Range<Int>,
    stride: Int, height: Int, radius: Int, weight: Float
  ) {
    let count = range.count
    let buffer = UnsafeMutablePointer<Int32>.allocate(capacity: count * 3)
    defer { buffer.deallocate() }
    let sums = buffer
    let after = buffer + count
    let before = buffer + 2 * count
    func row(_ index: Int) -> UnsafePointer<UInt8> {
      source + min(max(index, 0), height - 1) * stride + range.lowerBound
    }
    for index in 0..<count {
      sums[index] = 0
      after[index] = 0
      before[index] = Int32(row(0)[index]) * Int32(radius + 1)
    }
    for offset in -radius...radius {
      let line = row(offset)
      let factor = Int32(radius + 1 - abs(offset))
      for index in 0..<count { sums[index] &+= Int32(line[index]) &* factor }
    }
    for offset in 1...(radius + 1) {
      let line = row(offset)
      for index in 0..<count { after[index] &+= Int32(line[index]) }
    }
    for y in 0..<height {
      let output = target + y * stride + range.lowerBound
      let entering = row(y + radius + 2)
      let nextRow = row(y + 1)
      let leaving = row(y - radius)
      for index in 0..<count {
        let sum = sums[index]
        output[index] = UInt8(truncatingIfNeeded: Int((Float(sum) * weight).rounded()))
        sums[index] = sum &+ after[index] &- before[index]
        after[index] = after[index] &+ Int32(entering[index]) &- Int32(nextRow[index])
        before[index] = before[index] &+ Int32(nextRow[index]) &- Int32(leaving[index])
      }
    }
  }

  // MARK: Median

  /// `median_blur` с радиусом `radius` (в Aire это `2 * round(value) + 1`). Гистограмма окна
  /// ведётся так же, как в libblur, вместе с её особенностями:
  /// - окно по строкам `y - radius...y + radius` без отражения, на краю укороченное;
  /// - по столбцам для `x = 0` в гистограмму входят столбцы `0..<radius`, дальше при сдвиге
  ///   добавляется столбец `x + radius` и убирается `x - radius`. Столбец `radius` в гистограмму не
  ///   попадает вовсе, а убирается при `x = 2 radius`, поэтому счётчики там могут стать
  ///   отрицательными;
  /// - «медиана» — первый бин, где накопленная сумма достигает `n / 2` (целое деление), то есть при
  ///   нечётном `n` не середина, а на единицу ниже. Время растёт линейно с радиусом, не с его
  ///   квадратом.
  static func median(_ source: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let shared = SharedBuffer(base: target)
        let reader = SharedConstBuffer(base: input)
        ParallelBands.run(rows: height, minimumRows: 8) { band in
          medianRows(
            reader.base, shared.base, band: band, width: width, height: height, radius: radius)
        }
      }
    }
    return output
  }

  private static func medianRows(
    _ source: UnsafePointer<UInt8>, _ target: UnsafeMutablePointer<UInt8>, band: Range<Int>,
    width: Int, height: Int, radius: Int
  ) {
    let stride = width * 4
    // Четыре гистограммы по 256 бинов подряд: канал * 256 + значение.
    let histogram = UnsafeMutablePointer<Int32>.allocate(capacity: 1024)
    defer { histogram.deallocate() }

    func update(column: Int, row: Int, delta: Int32) -> Int32 {
      guard column >= 0, column < width else { return 0 }
      let first = max(row - radius, 0)
      let last = min(row + radius, height - 1)
      guard first <= last else { return 0 }
      var line = source + first * stride + column * 4
      for _ in first...last {
        histogram[Int(line[0])] &+= delta
        histogram[256 + Int(line[1])] &+= delta
        histogram[512 + Int(line[2])] &+= delta
        histogram[768 + Int(line[3])] &+= delta
        line += stride
      }
      return delta * Int32(last - first + 1)
    }

    for y in band {
      histogram.update(repeating: 0, count: 1024)
      var total: Int32 = 0
      for x in 0..<width {
        if x == 0 {
          for column in 0..<min(radius, width) {
            total &+= update(column: column, row: y, delta: 1)
          }
        } else {
          total &+= update(column: x - radius, row: y, delta: -1)
          total &+= update(column: x + radius, row: y, delta: 1)
        }
        let out = target + y * stride + x * 4
        if total > 0 {
          let threshold = total / 2
          for channel in 0..<4 {
            out[channel] = medianBin(histogram + channel * 256, threshold)
          }
        } else {
          let input = source + y * stride + x * 4
          for channel in 0..<4 { out[channel] = input[channel] }
        }
      }
    }
  }

  /// Первый бин, где накопленная сумма доходит до `threshold` (`median_filter` в libblur). Если не
  /// дошла ни в одном, результат 256, который при записи в байт даёт 0.
  @inline(__always)
  private static func medianBin(_ bins: UnsafeMutablePointer<Int32>, _ threshold: Int32) -> UInt8 {
    var remaining = threshold
    var index = 0
    while index < 256 {
      remaining &-= bins[index]
      if remaining > 0 { index += 1 } else { break }
    }
    return UInt8(truncatingIfNeeded: index)
  }

  // MARK: Общее

  @inline(__always)
  private static func pixel(_ line: UnsafePointer<UInt8>, _ x: Int) -> SIMD4<Int32> {
    let p = line + x * 4
    return SIMD4(Int32(p[0]), Int32(p[1]), Int32(p[2]), Int32(p[3]))
  }

  @inline(__always)
  private static func store(_ line: UnsafeMutablePointer<UInt8>, _ x: Int, _ value: SIMD4<UInt8>) {
    UnsafeMutableRawPointer(line + x * 4).storeBytes(of: value, as: SIMD4<UInt8>.self)
  }

  /// `round(сумма * множитель)` для четырёх каналов, как `f32::round` с насыщением в байт.
  @inline(__always)
  private static func roundedBytes(_ sums: SIMD4<Int32>, _ weight: Float) -> SIMD4<UInt8> {
    var result = SIMD4<UInt8>(repeating: 0)
    for lane in 0..<4 {
      let value = (Float(sums[lane]) * weight).rounded()
      result[lane] = UInt8(truncatingIfNeeded: Int(min(max(value, 0), 255)))
    }
    return result
  }

  /// Применяет `body` к каждой строке картинки (параллельно по полосам строк).
  private static func runHorizontal(
    _ source: [UInt8], _ output: inout [UInt8], width: Int, height: Int,
    _ body: @Sendable (UnsafePointer<UInt8>, UnsafeMutablePointer<UInt8>) -> Void
  ) {
    source.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: height, minimumRows: 16) { band in
          for y in band { body(reader.base + y * width * 4, writer.base + y * width * 4) }
        }
      }
    }
  }

  /// Применяет `body` к полосам столбцов (диапазоны байт строки), параллельно по блокам.
  private static func runVertical(
    _ source: [UInt8], _ output: inout [UInt8], width: Int, height: Int,
    _ body:
      @Sendable (UnsafePointer<UInt8>, UnsafeMutablePointer<UInt8>, Range<Int>) -> Void
  ) {
    let total = width * 4
    let block = 1024
    let count = (total + block - 1) / block
    source.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.blocks(count: count) { index in
          let start = index * block
          body(reader.base, writer.base, start..<min(total, start + block))
        }
      }
    }
  }
}
