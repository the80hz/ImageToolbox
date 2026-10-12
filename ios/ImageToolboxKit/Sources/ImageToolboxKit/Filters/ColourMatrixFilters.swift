import CoreImage
import Foundation

/// Имитация дальтонизма: протанопия, дейтеранопия, тританопия, ахроматопсия и их аномальные варианты.
///
/// Все фильтры — линейное преобразование каналов RGB, поэтому считаются через `CIColorMatrix`.
/// Матрицы дихромазии взяты из Machado, Oliveira, Fernandes (2009), таблица для severity 1.0.
/// Android берёт их из нативной библиотеки Aire, значения в репозитории не видны, поэтому
/// перенос помечен как приближение: матрица применяется к sRGB без перехода в линейное пространство.
enum ColourMatrixFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "ProtanopiaFilter",
      titleKey: "protanopia",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in ProtanopiaFilter() }
    ),
    FilterDescriptor(
      id: "DeuteranopiaFilter",
      titleKey: "deuteranopia",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in DeuteranopiaFilter() }
    ),
    FilterDescriptor(
      id: "TritanopiaFilter",
      titleKey: "tritanopia",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in TritanopiaFilter() }
    ),
    FilterDescriptor(
      id: "AchromatopsiaFilter",
      titleKey: "achromatopsia",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in AchromatopsiaFilter() }
    ),
    FilterDescriptor(
      id: "ProtonomalyFilter",
      titleKey: "protonomaly",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in ProtonomalyFilter() }
    ),
    FilterDescriptor(
      id: "DeutaromalyFilter",
      titleKey: "deutaromaly",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in DeutaromalyFilter() }
    ),
    FilterDescriptor(
      id: "TritonomalyFilter",
      titleKey: "tritonomaly",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in TritonomalyFilter() }
    ),
    FilterDescriptor(
      id: "AchromatomalyFilter",
      titleKey: "achromatomaly",
      category: .colourMatrix,
      engine: .cpu,
      make: { _ in AchromatomalyFilter() }
    ),
    FilterDescriptor(
      id: "ColorMatrix3x3Filter",
      titleKey: "color_matrix_3x3",
      category: .colourMatrix,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "color_matrix_3x3",
          kind: .matrix(size: 3, defaultValue: ColourMatrixMath.identityRows(size: 3)))
      ],
      make: { ColorMatrix3x3Filter(matrix: $0.matrix("value")) }
    ),
    FilterDescriptor(
      id: "ColorMatrix4x4Filter",
      titleKey: "color_matrix_4x4",
      category: .colourMatrix,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "color_matrix_4x4",
          kind: .matrix(size: 4, defaultValue: ColourMatrixMath.identityRows(size: 4)))
      ],
      make: { ColorMatrix4x4Filter(matrix: $0.matrix("value")) }
    ),
  ]
}

/// Матрицы 3x3 в порядке строк: каждая строка — коэффициенты одного выходного канала (R, G, B).
enum ColourMatrixMath {
  // Матрицы взяты из `ColorMatrices.Assistance` библиотеки Aire 0.18.1 (константы вынуты из
  // classes.jar артефакта). Строка — выходной канал R, G, B; применяются через `apply3x3`.

  static let protanopia: [Double] = [
    0.567, 0.433, 0.0,
    0.558, 0.442, 0.0,
    0.0, 0.242, 0.758,
  ]

  /// В Aire константа называется `DEUTARONOPIA`.
  static let deuteranopia: [Double] = [
    0.625, 0.375, 0.0,
    0.7, 0.3, 0.0,
    0.0, 0.3, 0.7,
  ]

  static let tritanopia: [Double] = [
    0.95, 0.05, 0.0,
    0.0, 0.433, 0.567,
    0.0, 0.475, 0.525,
  ]

  static let achromatopsia: [Double] = [
    0.299, 0.587, 0.114,
    0.299, 0.587, 0.114,
    0.299, 0.587, 0.114,
  ]

  static let protonomaly: [Double] = [
    0.817, 0.183, 0.0,
    0.333, 0.667, 0.0,
    0.0, 0.125, 0.875,
  ]

  /// В Aire константа называется `DEUTAROMALY`.
  static let deutaromaly: [Double] = [
    0.8, 0.2, 0.0,
    0.258, 0.742, 0.0,
    0.0, 0.142, 0.858,
  ]

  static let tritonomaly: [Double] = [
    0.967, 0.033, 0.0,
    0.0, 0.733, 0.267,
    0.0, 0.183, 0.817,
  ]

  static let achromatomaly: [Double] = [
    0.618, 0.32, 0.062,
    0.163, 0.775, 0.062,
    0.163, 0.32, 0.516,
  ]

  /// Единичная матрица `size` x `size`, строками.
  static func identityRows(size: Int) -> [Double] {
    (0..<size * size).map { $0 % (size + 1) == 0 ? 1 : 0 }
  }

  /// Матрица 3x3 на CPU, как `ColorMatrix3x3Filter` на Android (Aire): строки — выходные каналы R, G, B.
  /// Сумма считается в Float в порядке `m0 r + m1 g + m2 b`, затем обрезается до 0...255 и
  /// записывается усечением дробной части. Альфа не меняется.
  static func apply3x3(_ image: RasterImage, rows: [Double]) -> RasterImage {
    let m = rows.map { Float($0) }
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Float(image.pixels[index])
      let green = Float(image.pixels[index + 1])
      let blue = Float(image.pixels[index + 2])
      for row in 0..<3 {
        let value = m[row * 3] * red + m[row * 3 + 1] * green + m[row * 3 + 2] * blue
        // Бесконечность и NaN могут появиться из крупных коэффициентов: NaN даёт 0.
        pixels[index + row] = value.isNaN ? 0 : UInt8(min(max(value, 0), 255))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }

  /// Матрица 4x4 на CPU, как `ColorMatrix4x4Filter` на Android (GPUImage: `textureColor * colorMatrix`).
  /// Матрица передаётся в GL без транспонирования, поэтому строка `i` даёт выходной канал `i`
  /// (R, G, B, A). Вычисление в Double, результат округляется до ближайшего уровня, как при записи в GL.
  static func apply4x4(_ image: RasterImage, rows: [Double]) -> RasterImage {
    var pixels = image.pixels
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Double(image.pixels[index]) / 255
      let green = Double(image.pixels[index + 1]) / 255
      let blue = Double(image.pixels[index + 2]) / 255
      let alpha = Double(image.pixels[index + 3]) / 255
      for row in 0..<4 {
        let base = row * 4
        let value =
          rows[base] * red + rows[base + 1] * green + rows[base + 2] * blue
          + rows[base + 3] * alpha
        let clamped = value.isNaN ? 0 : min(max(value, 0), 1)
        pixels[index + row] = UInt8((clamped * 255).rounded())
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }
}

/// Android: `ColorMatrix3x3Filter` (Aire). Матрица задаётся параметром «матрица», по умолчанию единичная.
/// Сверка с эталоном: нестандартная матрица даёт расхождение 1 уровень в 236 из 12288 значений
/// (среднее 0.019), причина не установлена, см. `AndroidReferenceParityTests`.
struct ColorMatrix3x3Filter: Filter {
  /// Девять коэффициентов по строкам.
  let matrix: [Double]

  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: matrix)
  }
}

/// Android: `ColorMatrix4x4Filter` (GPUImage, `intensity` 1). Матрица задаётся параметром «матрица».
/// Сверка с эталоном: точное совпадение.
struct ColorMatrix4x4Filter: Filter {
  /// Шестнадцать коэффициентов по строкам (R, G, B, A).
  let matrix: [Double]

  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply4x4(image, rows: matrix)
  }
}

/// Протанопия: отсутствие красных колбочек.
/// Матрица `ColorMatrices.Assistance.PROTANOPIA` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct ProtanopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.protanopia)
  }
}

/// Дейтеранопия: отсутствие зелёных колбочек.
/// Матрица `ColorMatrices.Assistance.DEUTARONOPIA` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct DeuteranopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.deuteranopia)
  }
}

/// Тританопия: отсутствие синих колбочек.
/// Матрица `ColorMatrices.Assistance.TRITANOPIA` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct TritanopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.tritanopia)
  }
}

/// Ахроматопсия: только яркость, без цвета.
/// Матрица `ColorMatrices.Assistance.ACHROMATOPSIA` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct AchromatopsiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.achromatopsia)
  }
}

/// Протаномалия: аномальное зрение с красными колбочками.
/// Матрица `ColorMatrices.Assistance.PROTANOMALY` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct ProtonomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.protonomaly)
  }
}

/// Дейтераномалия: аномальное зрение с зелёными колбочками.
/// Матрица `ColorMatrices.Assistance.DEUTAROMALY` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct DeutaromalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.deutaromaly)
  }
}

/// Тританомалия: аномальное зрение с синими колбочками.
/// Матрица `ColorMatrices.Assistance.TRITONOMALY` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct TritonomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.tritonomaly)
  }
}

/// Ахроматомалия: частичная потеря цвета.
/// Матрица `ColorMatrices.Assistance.ACHROMATOMALY` из Aire 0.18.1.
/// Статус: проверено по эталону.
struct AchromatomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    ColourMatrixMath.apply3x3(image, rows: ColourMatrixMath.achromatomaly)
  }
}
