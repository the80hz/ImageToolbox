import Foundation

/// Motion blur libblur 0.19.4 (`motion_blur.rs`) в варианте Aire 0.18.1: линия Брезенхэма в ядре
/// `size x size` и двумерная свёртка с фиксированной точкой (`filter2d`, обработчик
/// `convolve_segment_neon_2d_u8_i16_fp`).
///
/// Ядро: концы линии `(⌈size/2 + size cos a⌉, ⌈size/2 + size sin a⌉)` и симметричная ей точка
/// относительно центра ядра (`size - 1 - x`); в ядро попадают только пиксели линии внутри
/// `0..<size`, вес каждого `1 / n` (`Float`). Вес в свёртке — `round(вес * 32767)` как `i16`, сумма
/// целая, результат `(сумма + 2^14) >> 15` с ограничением 0...255. Края — рамка `AireArena` с её
/// дефектом у границ (верхняя и нижняя полосы зеркальны по горизонтали, левая и правая по
/// вертикали).
enum LibblurMotion {
  /// Точки ядра `(столбец, строка)` линии под углом `degrees`, как `generate_motion_kernel`.
  static func points(size: Int, degrees: Float) -> [(x: Int, y: Int)] {
    let angle = degrees * Float.pi / 180.0
    let start = Float(size / 2)
    let endX = Int(max(0, (start + Float(size) * cos(angle)).rounded(.up)))
    let endY = Int(max(0, (start + Float(size) * sin(angle)).rounded(.up)))
    return bresenham(
      size, size, x0: endX, y0: endY, x1: size - endX - 1, y1: size - endY - 1)
  }

  private static func bresenham(
    _ width: Int, _ height: Int, x0: Int, y0: Int, x1: Int, y1: Int
  ) -> [(x: Int, y: Int)] {
    let dx = abs(x1 - x0)
    let dy = -abs(y1 - y0)
    var error = dx + dy
    var x = x0
    var y = y0
    let stepX = x0 < x1 ? 1 : -1
    let stepY = y0 < y1 ? 1 : -1
    var result: [(x: Int, y: Int)] = []
    while x != x1 || y != y1 {
      if x >= 0, x < width, y >= 0, y < height { result.append((x, y)) }
      let doubled = 2 * error
      if doubled >= dy {
        error += dy
        x += stepX
      }
      if doubled <= dx {
        error += dx
        y += stepY
      }
    }
    if x >= 0, x < width, y >= 0, y < height { result.append((x, y)) }
    return result
  }

  static func blur(
    _ source: [UInt8], width: Int, height: Int, size: Int, degrees: Float, edge: BlurBorderMode
  ) -> [UInt8] {
    let line = points(size: size, degrees: degrees)
    // `0 / 0` в Rust при пустой линии даёт `NaN`, `NaN as i16` равно 0: все веса нулевые.
    let weight = line.isEmpty ? Float.nan : Float(1) / Float(line.count)
    let fixed: Int32 = {
      let scaled = (Double(weight) * 32767).rounded()
      if scaled.isNaN { return 0 }
      return Int32(min(max(scaled, -32768), 32767))
    }()
    let pad = size / 2
    var output = [UInt8](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { sourceBuffer in
      let arena = AireArena.make(
        sourceBuffer, width: width, height: height, padX: pad, padY: pad, mode: edge, tail: 64)
      arena.withUnsafeBufferPointer { arenaBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
          guard let arenaBase = arenaBuffer.baseAddress, let target = outputBuffer.baseAddress
          else { return }
          let reader = SharedConstBuffer(base: arenaBase)
          let writer = SharedBuffer(base: target)
          let arenaWidth = width + 2 * pad
          ParallelBands.run(rows: height, minimumRows: 8) { band in
            for y in band {
              convolveRow(
                reader.base, writer.base + y * width * 4, y: y, width: width,
                arenaWidth: arenaWidth, points: line, weight: fixed)
            }
          }
        }
      }
    }
    return output
  }

  private static func convolveRow(
    _ arena: UnsafePointer<UInt8>, _ result: UnsafeMutablePointer<UInt8>, y: Int, width: Int,
    arenaWidth: Int, points: [(x: Int, y: Int)], weight: Int32
  ) {
    let total = width * 4
    let offsets = points.map { ($0.y + y) * arenaWidth * 4 + $0.x * 4 }
    var offset = 0
    while offset + 16 <= total {
      var accumulator = SIMD16<Int32>(repeating: 0)
      for base in offsets {
        let bytes = UnsafeRawPointer(arena + base + offset).loadUnaligned(as: SIMD16<UInt8>.self)
        accumulator &+= SIMD16<Int32>(truncatingIfNeeded: bytes) &* weight
      }
      let shifted = (accumulator &+ 16384) &>> 15
      let clamped = shifted.clamped(
        lowerBound: SIMD16(repeating: 0), upperBound: SIMD16(repeating: 255))
      UnsafeMutableRawPointer(result + offset).storeBytes(
        of: SIMD16<UInt8>(truncatingIfNeeded: clamped), as: SIMD16<UInt8>.self)
      offset += 16
    }
    while offset < total {
      var sum: Int32 = 0
      for base in offsets { sum &+= Int32(arena[base + offset]) &* weight }
      result[offset] = UInt8(truncatingIfNeeded: min(max((sum &+ 16384) >> 15, 0), 255))
      offset += 1
    }
  }
}
