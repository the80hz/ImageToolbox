import Foundation

/// Рамка вокруг картинки из `fast_morphology` 0.3.1 (`make_arena`) и libblur 0.19.4
/// (`filter1d/arena.rs`, `make_arena`): ею пользуются морфология, билатеральное размытие и motion
/// blur в Aire 0.18.1.
///
/// Рамка строится с отступом `padX`, `padY` с каждой стороны четырьмя полосами: верхняя и нижняя на
/// всю ширину рамки, левая и правая только между ними. Каждый пиксель полосы берёт источник по
/// индексам строки и столбца, пересчитанным краевой функцией. У режимов `reflect` и `reflect101`
/// функция написана как `n - 1 - i mod (n - 1)` (и `n - i mod n - 1`), и для индексов внутри
/// картинки она даёт зеркальный индекс, а не тот же. Поэтому верхняя и нижняя полосы зеркальны по
/// горизонтали, левая и правая по вертикали. Режимы `clamp` и `wrap` внутри картинки возвращают тот
/// же индекс и дефекта не имеют. Это поведение Android, оно воспроизведено как есть.
enum AireArena {
  /// Индекс источника для индекса `i` относительно картинки длины `n`.
  @inline(__always)
  static func index(_ i: Int, count n: Int, mode: BlurBorderMode) -> Int {
    switch mode {
    case .clamp:
      return min(max(i, 0), n - 1)
    case .wrap:
      let remainder = i % n
      return remainder < 0 ? remainder + n : remainder
    case .reflect:
      let remainder = i % n
      return n - (remainder < 0 ? remainder + n : remainder) - 1
    case .reflect101:
      let last = n - 1
      if last == 0 { return 0 }
      let remainder = i % last
      return last - (remainder < 0 ? remainder + last : remainder)
    }
  }

  /// Строит рамку `(width + 2 padX) x (height + 2 padY)` пикселей RGBA, после неё `tail` нулевых
  /// байт (запас для чтения векторами за концом последней строки).
  static func make(
    _ pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, padX: Int, padY: Int,
    mode: BlurBorderMode, tail: Int
  ) -> [UInt8] {
    let arenaWidth = width + 2 * padX
    let arenaHeight = height + 2 * padY
    var arena = [UInt8](repeating: 0, count: arenaWidth * arenaHeight * 4 + tail)
    let columns = (0..<arenaWidth).map { index($0 - padX, count: width, mode: mode) }
    arena.withUnsafeMutableBufferPointer { destination in
      guard let source = pixels.baseAddress, let target = destination.baseAddress else { return }
      for row in 0..<arenaHeight {
        let inside = row >= padY && row < padY + height
        let mirrored = source + index(row - padY, count: height, mode: mode) * width * 4
        let rowTarget = target + row * arenaWidth * 4
        if inside {
          for column in 0..<padX {
            copyPixel(mirrored + columns[column] * 4, rowTarget + column * 4)
          }
          (rowTarget + padX * 4).update(from: source + (row - padY) * width * 4, count: width * 4)
          for column in (padX + width)..<arenaWidth {
            copyPixel(mirrored + columns[column] * 4, rowTarget + column * 4)
          }
        } else {
          for column in 0..<arenaWidth {
            copyPixel(mirrored + columns[column] * 4, rowTarget + column * 4)
          }
        }
      }
    }
    return arena
  }

  @inline(__always)
  private static func copyPixel(_ from: UnsafePointer<UInt8>, _ to: UnsafeMutablePointer<UInt8>) {
    UnsafeMutableRawPointer(to).storeBytes(
      of: UnsafeRawPointer(from).loadUnaligned(as: UInt32.self), as: UInt32.self)
  }
}
