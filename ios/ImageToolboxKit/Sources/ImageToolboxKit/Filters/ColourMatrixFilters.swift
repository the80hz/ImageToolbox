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
      engine: .coreImage,
      make: { _ in ProtanopiaFilter() }
    ),
    FilterDescriptor(
      id: "DeuteranopiaFilter",
      titleKey: "deuteranopia",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in DeuteranopiaFilter() }
    ),
    FilterDescriptor(
      id: "TritanopiaFilter",
      titleKey: "tritanopia",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in TritanopiaFilter() }
    ),
    FilterDescriptor(
      id: "AchromatopsiaFilter",
      titleKey: "achromatopsia",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in AchromatopsiaFilter() }
    ),
    FilterDescriptor(
      id: "ProtonomalyFilter",
      titleKey: "protonomaly",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in ProtonomalyFilter() }
    ),
    FilterDescriptor(
      id: "DeutaromalyFilter",
      titleKey: "deutaromaly",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in DeutaromalyFilter() }
    ),
    FilterDescriptor(
      id: "TritonomalyFilter",
      titleKey: "tritonomaly",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in TritonomalyFilter() }
    ),
    FilterDescriptor(
      id: "AchromatomalyFilter",
      titleKey: "achromatomaly",
      category: .colourMatrix,
      engine: .coreImage,
      make: { _ in AchromatomalyFilter() }
    ),
  ]
}

/// Матрицы 3x3 в порядке строк: каждая строка — коэффициенты одного выходного канала (R, G, B).
enum ColourMatrixMath {
  static let identity: [CGFloat] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

  /// Machado 2009, протанопия (severity 1.0).
  static let protanopia: [CGFloat] = [
    0.152286, 1.052583, -0.204868,
    0.114503, 0.786281, 0.099216,
    -0.003882, -0.048116, 1.051998,
  ]

  /// Machado 2009, дейтеранопия (severity 1.0).
  static let deuteranopia: [CGFloat] = [
    0.367322, 0.860646, -0.227968,
    0.280085, 0.672501, 0.047413,
    -0.011820, 0.042940, 0.968881,
  ]

  /// Machado 2009, тританопия (severity 1.0).
  static let tritanopia: [CGFloat] = [
    1.255528, -0.076749, -0.178779,
    -0.078411, 0.930809, 0.147602,
    0.004733, 0.691367, 0.303900,
  ]

  /// Чистая яркость по коэффициентам Rec. 601: ахроматопсия без цвета.
  static let achromatopsia: [CGFloat] = [
    0.299, 0.587, 0.114,
    0.299, 0.587, 0.114,
    0.299, 0.587, 0.114,
  ]

  /// Аномалия приближена смесью 50% исходной матрицы и матрицы дихромазии.
  /// Точная матрица аномалии в Aire недоступна.
  static let anomalyWeight: CGFloat = 0.5

  static let protonomaly = blend(identity, protanopia, anomalyWeight)
  static let deutaromaly = blend(identity, deuteranopia, anomalyWeight)
  static let tritonomaly = blend(identity, tritanopia, anomalyWeight)
  static let achromatomaly = blend(identity, achromatopsia, anomalyWeight)

  /// Поэлементная смесь: `weight` задаёт долю матрицы `second`.
  static func blend(_ first: [CGFloat], _ second: [CGFloat], _ weight: CGFloat) -> [CGFloat] {
    zip(first, second).map { $0 * (1 - weight) + $1 * weight }
  }

  /// Применяет матрицу к RGB через `CIColorMatrix`. Альфа-канал не меняется.
  static func apply(_ image: RasterImage, filterID: String, matrix m: [CGFloat]) throws
    -> RasterImage
  {
    try CoreImageBridge.render(image, filterID: filterID) { input in
      input.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: m[0], y: m[1], z: m[2], w: 0),
          "inputGVector": CIVector(x: m[3], y: m[4], z: m[5], w: 0),
          "inputBVector": CIVector(x: m[6], y: m[7], z: m[8], w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
    }
  }
}

/// Протанопия: отсутствие красных колбочек. Приближение.
struct ProtanopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "ProtanopiaFilter", matrix: ColourMatrixMath.protanopia)
  }
}

/// Дейтеранопия: отсутствие зелёных колбочек. Приближение.
struct DeuteranopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "DeuteranopiaFilter", matrix: ColourMatrixMath.deuteranopia)
  }
}

/// Тританопия: отсутствие синих колбочек. Приближение.
struct TritanopiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "TritanopiaFilter", matrix: ColourMatrixMath.tritanopia)
  }
}

/// Ахроматопсия: только яркость, без цвета. Приближение: в Android матрица из Aire.
struct AchromatopsiaFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "AchromatopsiaFilter", matrix: ColourMatrixMath.achromatopsia)
  }
}

/// Протаномалия: аномальное зрение с красными колбочками. Приближение (смесь 50%).
struct ProtonomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "ProtonomalyFilter", matrix: ColourMatrixMath.protonomaly)
  }
}

/// Дейтераномалия: аномальное зрение с зелёными колбочками. Приближение (смесь 50%).
struct DeutaromalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "DeutaromalyFilter", matrix: ColourMatrixMath.deutaromaly)
  }
}

/// Тританомалия: аномальное зрение с синими колбочками. Приближение (смесь 50%).
struct TritonomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "TritonomalyFilter", matrix: ColourMatrixMath.tritonomaly)
  }
}

/// Ахромаломия: частичная потеря цвета. Приближение (смесь 50% с ахроматопсией).
struct AchromatomalyFilter: Filter {
  func apply(to image: RasterImage) async throws -> RasterImage {
    try ColourMatrixMath.apply(
      image, filterID: "AchromatomalyFilter", matrix: ColourMatrixMath.achromatomaly)
  }
}
