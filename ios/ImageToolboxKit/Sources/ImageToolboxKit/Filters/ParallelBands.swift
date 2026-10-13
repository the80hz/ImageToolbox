import Foundation

/// Указатель на буфер, в который параллельные полосы пишут непересекающиеся участки.
struct SharedBuffer<Element>: @unchecked Sendable {
  let base: UnsafeMutablePointer<Element>
}

/// Указатель на буфер, который читают все параллельные полосы.
struct SharedConstBuffer<Element>: @unchecked Sendable {
  let base: UnsafePointer<Element>
}

/// Параллельная обработка строк картинки полосами.
enum ParallelBands {
  /// Делит `rows` строк на полосы по числу ядер (полоса не короче `minimumRows`, если строк
  /// хватает) и вызывает `body` для каждой полосы. Полосы не пересекаются, порядок вызовов не
  /// определён.
  static func run(rows: Int, minimumRows: Int = 16, _ body: @Sendable (Range<Int>) -> Void) {
    guard rows > 0 else { return }
    let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let count = max(1, min(cores, rows / max(1, minimumRows)))
    if count == 1 {
      body(0..<rows)
      return
    }
    let step = (rows + count - 1) / count
    DispatchQueue.concurrentPerform(iterations: count) { band in
      let start = band * step
      let end = min(rows, start + step)
      if start < end { body(start..<end) }
    }
  }

  /// Вызывает `body` для номеров `0..<count` параллельно. Для независимых блоков одинакового
  /// размера.
  static func blocks(count: Int, _ body: @Sendable (Int) -> Void) {
    guard count > 0 else { return }
    if count == 1 {
      body(0)
      return
    }
    DispatchQueue.concurrentPerform(iterations: count, execute: body)
  }
}
