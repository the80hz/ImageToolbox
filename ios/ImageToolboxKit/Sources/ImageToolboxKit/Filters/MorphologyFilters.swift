import Foundation

/// Морфология из Android: дилатация, эрозия, открытие, закрытие, top-hat, black-hat и
/// морфологический градиент.
///
/// Android вызывает `Aire.morphology` (Aire 0.18.1, `aire-filters/src/morph.rs`, крейт
/// `fast_morphology` 0.3.1) с ядром `MorphKernels.box(size)` или `MorphKernels.circle(size)`,
/// границей `REFLECT_101` и размером `size x size`. Ядро-круг (`ConvolveKernels.circle`): точки,
/// чьё расстояние до центра `(size / 2, size / 2)` не больше `Float(size) / 3`; ядро-квадрат: все
/// точки. Границы у `fast_morphology` нестандартные (см. `MorphologyEngine`). Если у картинки есть
/// пиксель с альфой не 255, Aire обрабатывает и альфу как обычный канал (режим RGBA), иначе только
/// RGB, а альфа результата 255. Android не принимает круг размером меньше 5 (бросает исключение),
/// здесь формула применяется и к таким размерам.
///
/// Статус: проверено по эталону (разделы 7 и 10 FILTERS.md; размер 25, круг).
enum MorphologyFilters {
  static let descriptors: [FilterDescriptor] = [
    descriptor(id: "DilationFilter", titleKey: "dilation") { size, circle in
      DilationFilter(size: size, circle: circle)
    },
    descriptor(id: "ErodeFilter", titleKey: "erode") { size, circle in
      ErodeFilter(size: size, circle: circle)
    },
    descriptor(id: "OpeningFilter", titleKey: "opening") { size, circle in
      OpeningFilter(size: size, circle: circle)
    },
    descriptor(id: "ClosingFilter", titleKey: "closing") { size, circle in
      ClosingFilter(size: size, circle: circle)
    },
    descriptor(id: "TopHatFilter", titleKey: "top_hat") { size, circle in
      TopHatFilter(size: size, circle: circle)
    },
    descriptor(id: "BlackHatFilter", titleKey: "black_hat") { size, circle in
      BlackHatFilter(size: size, circle: circle)
    },
    descriptor(
      id: "MorphologicalGradientFilter", titleKey: "morphological_gradient"
    ) { size, circle in
      MorphologicalGradientFilter(size: size, circle: circle)
    },
  ]

  /// Все семь фильтров одинаковы по параметрам: размер ядра 1...150 и флаг формы круга.
  private static func descriptor(
    id: String,
    titleKey: String,
    make: @escaping @Sendable (_ size: Int, _ circle: Bool) -> any Filter
  ) -> FilterDescriptor {
    FilterDescriptor(
      id: id,
      titleKey: titleKey,
      category: .morphology,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "size", titleKey: "just_size",
          kind: .number(range: 1...150, step: 1, defaultValue: 25)),
        FilterParameter(
          key: "useCircleKernel", titleKey: "use_circle_kernel",
          kind: .flag(defaultValue: true)),
      ],
      make: { values in
        make(Int(values.number("size").rounded()), values.flag("useCircleKernel"))
      }
    )
  }
}

/// Дилатация: максимум по окрестности каждого канала (`MorphOp.DILATE`).
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct DilationFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.dilate, on: image, size: size, circle: circle)
  }
}

/// Эрозия: минимум по окрестности каждого канала (`MorphOp.ERODE`).
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct ErodeFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.erode, on: image, size: size, circle: circle)
  }
}

/// Открытие: эрозия, затем дилатация. Убирает светлые детали меньше ядра.
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct OpeningFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.opening, on: image, size: size, circle: circle)
  }
}

/// Закрытие: дилатация, затем эрозия. Заполняет тёмные детали меньше ядра.
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct ClosingFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.closing, on: image, size: size, circle: circle)
  }
}

/// Top-hat: исходное изображение минус открытие. Выделяет светлые детали меньше ядра.
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct TopHatFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.topHat, on: image, size: size, circle: circle)
  }
}

/// Black-hat: закрытие минус исходное изображение. Выделяет тёмные детали меньше ядра.
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct BlackHatFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.blackHat, on: image, size: size, circle: circle)
  }
}

/// Морфологический градиент: дилатация минус эрозия. Подсвечивает границы.
///
/// Источник: Aire 0.18.1, `Aire.morphology`, `fast_morphology` 0.3.1.
/// Статус: проверено по эталону.
struct MorphologicalGradientFilter: Filter {
  let size: Int
  let circle: Bool

  func apply(to image: RasterImage) async throws -> RasterImage {
    MorphologyEngine.run(.gradient, on: image, size: size, circle: circle)
  }
}

/// Морфология как в `fast_morphology` 0.3.1 (Aire 0.18.1): те же ядра, та же рамка вокруг картинки
/// (`AireArena`, режим `REFLECT_101` с её дефектом у границ).
///
/// Вычисление: для каждой строки ядра берётся отрезок подряд идущих точек. Максимум (минимум) по
/// отрезку длины `n` даёт два перекрывающихся окна степени двойки из пирамиды `M(j)[x] =
/// op(M(j-1)[x], M(j-1)[x + 2^(j-1)])`, которая строится по каждой строке рамки один раз. Время
/// растёт линейно с числом строк ядра, не с числом его точек; байты обрабатываются по 16 штук
/// (`SIMD16`).
enum MorphologyEngine {
  enum Operation: Sendable {
    case erode
    case dilate
    case opening
    case closing
    case topHat
    case blackHat
    case gradient
  }

  /// Подряд идущие точки одной строки ядра: столбцы `lo...hi` строки `row` (индексы в ядре).
  struct Run: Hashable {
    let row: Int
    let lo: Int
    let hi: Int
  }

  /// Структурный элемент `width x height`; якорь в `(width / 2, height / 2)`.
  struct Kernel {
    let width: Int
    let height: Int
    let runs: [Run]

    /// Ядро по маске строк сверху вниз (`true` — точка ядра), как массив `IntArray` в Aire.
    init(width: Int, height: Int, mask: [Bool]) {
      precondition(mask.count == width * height, "kernel mask size mismatch")
      var runs: [Run] = []
      for row in 0..<height {
        var column = 0
        while column < width {
          guard mask[row * width + column] else {
            column += 1
            continue
          }
          let start = column
          while column < width, mask[row * width + column] { column += 1 }
          runs.append(Run(row: row, lo: start, hi: column - 1))
        }
      }
      self.width = width
      self.height = height
      self.runs = runs
    }

    /// `MorphKernels.box(size)`: все точки квадрата.
    static func box(size: Int) -> Kernel {
      Kernel(width: size, height: size, mask: [Bool](repeating: true, count: size * size))
    }

    /// `MorphKernels.circle(size)` (`ConvolveKernels.circle`): точки, чьё расстояние до `(size / 2,
    /// size / 2)` не больше `Float(size) / 3`. Android принимает такое ядро только от размера 5, на
    /// меньших размерах бросает исключение; здесь формула применяется и к ним.
    static func circle(size: Int) -> Kernel {
      let centre = size / 2
      let radius = Double(Float(size) / 3)
      var mask = [Bool](repeating: false, count: size * size)
      for row in 0..<size {
        for column in 0..<size {
          let dy = Double(row - centre)
          let dx = Double(column - centre)
          mask[row * size + column] = (dy * dy + dx * dx).squareRoot() <= radius
        }
      }
      return Kernel(width: size, height: size, mask: mask)
    }
  }

  /// Применяет операцию к RGBA-картинке (premultiplied, как хранит Android).
  static func run(
    _ operation: Operation, on image: RasterImage, size: Int, circle: Bool
  ) -> RasterImage {
    let side = max(1, size)
    return run(operation, on: image, kernel: circle ? .circle(size: side) : .box(size: side))
  }

  /// Применяет операцию с произвольным ядром. Если у всех пикселей альфа 255 (`checkHasAlpha` в
  /// Trickle ложно), Aire работает в режиме RGB: альфа результата 255. Иначе все четыре канала
  /// обрабатываются одинаково, включая альфу.
  static func run(_ operation: Operation, on image: RasterImage, kernel: Kernel) -> RasterImage {
    guard !kernel.runs.isEmpty else { return image }
    let width = image.width
    let height = image.height
    let source = image.pixels
    var result: [UInt8]
    switch operation {
    case .erode:
      result = extremum(source, width: width, height: height, kernel: kernel, isMax: false)
    case .dilate:
      result = extremum(source, width: width, height: height, kernel: kernel, isMax: true)
    case .opening:
      let eroded = extremum(source, width: width, height: height, kernel: kernel, isMax: false)
      result = extremum(eroded, width: width, height: height, kernel: kernel, isMax: true)
    case .closing:
      let dilated = extremum(source, width: width, height: height, kernel: kernel, isMax: true)
      result = extremum(dilated, width: width, height: height, kernel: kernel, isMax: false)
    case .gradient:
      let dilated = extremum(source, width: width, height: height, kernel: kernel, isMax: true)
      let eroded = extremum(source, width: width, height: height, kernel: kernel, isMax: false)
      result = saturatingDifference(dilated, eroded)
    case .topHat:
      let eroded = extremum(source, width: width, height: height, kernel: kernel, isMax: false)
      let opened = extremum(eroded, width: width, height: height, kernel: kernel, isMax: true)
      result = saturatingDifference(source, opened)
    case .blackHat:
      let dilated = extremum(source, width: width, height: height, kernel: kernel, isMax: true)
      let closed = extremum(dilated, width: width, height: height, kernel: kernel, isMax: false)
      result = saturatingDifference(closed, source)
    }
    if !hasTransparency(source) {
      for index in stride(from: 3, to: result.count, by: 4) { result[index] = 255 }
    }
    return RasterImage(width: width, height: height, pixels: result)
  }

  /// Есть ли пиксель с альфой не 255 (`isImageHasAlpha` в Trickle).
  private static func hasTransparency(_ pixels: [UInt8]) -> Bool {
    for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] != 255 {
      return true
    }
    return false
  }

  /// `max(a - b, 0)` по байтам (`morph_gradient` с насыщением).
  private static func saturatingDifference(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: a.count)
    for index in 0..<a.count {
      output[index] = a[index] > b[index] ? a[index] - b[index] : 0
    }
    return output
  }

  /// Максимум или минимум пикселей под ядром для каждой позиции. Размер результата как у входа.
  private static func extremum(
    _ pixels: [UInt8], width: Int, height: Int, kernel: Kernel, isMax: Bool
  ) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: pixels.count)
    guard !pixels.isEmpty else { return output }
    pixels.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        guard let target = destination.baseAddress else { return }
        if isMax {
          extremum(MaxOperation.self, source, target, width, height, kernel)
        } else {
          extremum(MinOperation.self, source, target, width, height, kernel)
        }
      }
    }
    return output
  }

  /// Геометрия рамки и пирамиды окон для одного вызова.
  private struct Layout: Sendable {
    let width: Int
    let height: Int
    let arenaWidth: Int
    let rowBytes: Int
    let rowStride: Int
    let levels: Int
    let kernelRows: Int
    let runs: [Run]
  }

  private static func extremum<Operation: ExtremumOperation>(
    _: Operation.Type, _ source: UnsafeBufferPointer<UInt8>, _ target: UnsafeMutablePointer<UInt8>,
    _ width: Int, _ height: Int, _ kernel: Kernel
  ) {
    let padX = kernel.width / 2
    let padY = kernel.height / 2
    let arena = AireArena.make(
      source, width: width, height: height, padX: padX, padY: padY, mode: .reflect101, tail: 64)
    let longest = kernel.runs.map { $0.hi - $0.lo + 1 }.max() ?? 1
    let rowBytes = (width + 2 * padX) * 4
    let layout = Layout(
      width: width, height: height, arenaWidth: width + 2 * padX, rowBytes: rowBytes,
      rowStride: rowBytes + 64, levels: Int.bitWidth - 1 - longest.leadingZeroBitCount,
      kernelRows: kernel.height, runs: kernel.runs)
    let shared = SharedBuffer(base: target)
    arena.withUnsafeBufferPointer { arenaBuffer in
      guard let arenaBase = arenaBuffer.baseAddress else { return }
      let arenaPointer = SharedConstBuffer(base: arenaBase)
      ParallelBands.run(rows: height, minimumRows: 32) { band in
        process(Operation.self, band, layout, arenaPointer.base, shared.base)
      }
    }
  }

  /// Строит пирамиду окон строки рамки `row` в слоте кольца `row % kernelRows`.
  private static func buildPyramid<Operation: ExtremumOperation>(
    _: Operation.Type, row: Int, _ layout: Layout, arena: UnsafePointer<UInt8>,
    ring: UnsafeMutablePointer<UInt8>
  ) {
    guard layout.levels > 0 else { return }
    let slot = ring + (row % layout.kernelRows) * layout.levels * layout.rowStride
    var previous = arena + row * layout.rowBytes
    for level in 1...layout.levels {
      let current = slot + (level - 1) * layout.rowStride
      let valid = (layout.arenaWidth - (1 << level) + 1) * 4
      let shift = 4 << (level - 1)
      var offset = 0
      while offset + 16 <= valid {
        let a = UnsafeRawPointer(previous + offset).loadUnaligned(as: SIMD16<UInt8>.self)
        let b = UnsafeRawPointer(previous + offset + shift).loadUnaligned(as: SIMD16<UInt8>.self)
        UnsafeMutableRawPointer(current + offset).storeBytes(
          of: Operation.combine(a, b), as: SIMD16<UInt8>.self)
        offset += 16
      }
      while offset < valid {
        current[offset] = Operation.combine(previous[offset], previous[offset + shift])
        offset += 1
      }
      previous = UnsafePointer(current)
    }
  }

  /// Считает строки `band` результата. Кольцо хранит пирамиды `kernelRows` последних строк рамки.
  private static func process<Operation: ExtremumOperation>(
    _: Operation.Type, _ band: Range<Int>, _ layout: Layout, _ arena: UnsafePointer<UInt8>,
    _ target: UnsafeMutablePointer<UInt8>
  ) {
    let runs = layout.runs
    let ring = UnsafeMutablePointer<UInt8>.allocate(
      capacity: max(1, layout.kernelRows * layout.levels * layout.rowStride))
    let starts = UnsafeMutablePointer<UnsafePointer<UInt8>>.allocate(capacity: runs.count)
    let ends = UnsafeMutablePointer<UnsafePointer<UInt8>>.allocate(capacity: runs.count)
    defer {
      ring.deallocate()
      starts.deallocate()
      ends.deallocate()
    }
    for row in band.lowerBound..<(band.lowerBound + layout.kernelRows - 1) {
      buildPyramid(Operation.self, row: row, layout, arena: arena, ring: ring)
    }
    let total = layout.width * 4
    for y in band {
      buildPyramid(Operation.self, row: y + layout.kernelRows - 1, layout, arena: arena, ring: ring)
      for (index, run) in runs.enumerated() {
        let row = y + run.row
        let level = Int.bitWidth - 1 - (run.hi - run.lo + 1).leadingZeroBitCount
        var base = arena + row * layout.rowBytes
        if level > 0 {
          let slot = (row % layout.kernelRows) * layout.levels + (level - 1)
          base = UnsafePointer(ring + slot * layout.rowStride)
        }
        starts[index] = base + run.lo * 4
        ends[index] = base + (run.hi - (1 << level) + 1) * 4
      }
      let line = target + y * total
      var offset = 0
      while offset + 16 <= total {
        var best = Operation.identityVector
        for index in 0..<runs.count {
          let a = UnsafeRawPointer(starts[index] + offset).loadUnaligned(as: SIMD16<UInt8>.self)
          let b = UnsafeRawPointer(ends[index] + offset).loadUnaligned(as: SIMD16<UInt8>.self)
          best = Operation.combine(best, Operation.combine(a, b))
        }
        UnsafeMutableRawPointer(line + offset).storeBytes(of: best, as: SIMD16<UInt8>.self)
        offset += 16
      }
      while offset < total {
        var best = Operation.identityScalar
        for index in 0..<runs.count {
          best = Operation.combine(
            best, Operation.combine(starts[index][offset], ends[index][offset]))
        }
        line[offset] = best
        offset += 1
      }
    }
  }
}

/// Максимум или минимум: единственное, что отличает дилатацию от эрозии.
private protocol ExtremumOperation: Sendable {
  static var identityVector: SIMD16<UInt8> { get }
  static var identityScalar: UInt8 { get }
  static func combine(_ a: SIMD16<UInt8>, _ b: SIMD16<UInt8>) -> SIMD16<UInt8>
  static func combine(_ a: UInt8, _ b: UInt8) -> UInt8
}

private enum MaxOperation: ExtremumOperation {
  static var identityVector: SIMD16<UInt8> { SIMD16(repeating: 0) }
  static var identityScalar: UInt8 { 0 }
  @inline(__always)
  static func combine(_ a: SIMD16<UInt8>, _ b: SIMD16<UInt8>) -> SIMD16<UInt8> {
    a.replacing(with: b, where: b .> a)
  }
  @inline(__always)
  static func combine(_ a: UInt8, _ b: UInt8) -> UInt8 { max(a, b) }
}

private enum MinOperation: ExtremumOperation {
  static var identityVector: SIMD16<UInt8> { SIMD16(repeating: 255) }
  static var identityScalar: UInt8 { 255 }
  @inline(__always)
  static func combine(_ a: SIMD16<UInt8>, _ b: SIMD16<UInt8>) -> SIMD16<UInt8> {
    a.replacing(with: b, where: b .< a)
  }
  @inline(__always)
  static func combine(_ a: UInt8, _ b: UInt8) -> UInt8 { min(a, b) }
}
