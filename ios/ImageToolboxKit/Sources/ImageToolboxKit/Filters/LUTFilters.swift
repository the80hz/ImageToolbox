import CoreImage
import Foundation
import ImageIO

/// Таблицы цвета (LUT): 12 пресетов Android на таблицах `lookup_*.webp` (512 × 512) из `Resources/LUT`
/// и общий путь через `CIColorCube`. Каждый пресет — `LUT512x512Filter` с одной таблицей и силой 0...1.
///
/// Статус — приближение: раскладка 8 × 8 взята из стандартных LUT-решёток, а нативный Trickle
/// `applyLut`, которым Android применяет таблицу, в репозитории отсутствует. Не сверено с Android.
/// `LUT512x512Filter` без таблицы (выбор файла) и `CubeLutFilter` (файл от пользователя) не
/// зарегистрированы: `FilterParameter` не умеет передавать файл.
enum LUTFilters {
  static let descriptors: [FilterDescriptor] = presets.map { preset in
    FilterDescriptor(
      id: preset.id,
      titleKey: preset.titleKey,
      category: .lut,
      engine: .coreImage,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "strength",
          kind: .number(range: 0...1, step: 0.01, defaultValue: 1))
      ],
      make: { LUTPresetFilter(table: preset.table, intensity: $0.number("value")) }
    )
  }

  /// Идентификатор и ключ заголовка совпадают с Android. `table` — имя файла без расширения.
  private static let presets: [(id: String, titleKey: String, table: String)] = [
    ("AmatorkaFilter", "amatorka", "lookup_amatorka"),
    ("KodakFilter", "kodak", "lookup_kodak"),
    ("BleachBypassFilter", "bleach_bypass", "lookup_bleach_bypass"),
    ("CandlelightFilter", "candlelight", "lookup_candlelight"),
    ("CelluloidFilter", "celluloid", "lookup_celluloid"),
    ("CoffeeFilter", "coffee", "lookup_coffee"),
    ("DropBluesFilter", "drop_blues", "lookup_drop_blues"),
    ("EdgyAmberFilter", "edgy_amber", "lookup_edgy_amber"),
    ("FallColorsFilter", "fall_colors", "lookup_fall_colors"),
    ("FilmStock50Filter", "film_stock_50", "lookup_filmstock_50"),
    ("FoggyNightFilter", "foggy_night", "lookup_foggy_night"),
    ("GoldenForestFilter", "golden_forest", "lookup_golden_forest"),
  ]
}

/// Загрузка таблицы из ресурсов пакета. Декодирование при каждом применении: пока без кэша.
enum LUTAtlas {
  /// The 512 × 512 lookup table bundled as `Resources/LUT/<name>.webp`, or nil if it cannot be read.
  static func table(named name: String) -> LUTTable? {
    guard
      let url = Bundle.module.url(forResource: name, withExtension: "webp", subdirectory: "LUT"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let raster = RasterImage(cgImage)
    else { return nil }
    return LUTTable(lookup: raster)
  }
}

/// Пресет: таблица из ресурсов, смешанная с тождеством силой `intensity`.
struct LUTPresetFilter: Filter {
  let table: String
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    guard let lut = LUTAtlas.table(named: table) else {
      throw FilterError.renderFailed(table)
    }
    return try applyColorCube(lut, intensity: intensity, filterID: table, to: image)
  }
}

/// Трёхмерная таблица цвета `size` × `size` × `size`. Значения каналов в 0...1.
///
/// Порядок записей как у `.cube` и `CIColorCube`: красный меняется быстрее всего, затем зелёный,
/// затем синий. Запись с индексами (r, g, b) лежит по смещению `((b * size + g) * size + r) * 3`.
struct LUTTable: Sendable, Equatable {
  let size: Int
  let values: [Float]

  init?(size: Int, values: [Float]) {
    guard size >= 2, values.count == size * size * size * 3 else { return nil }
    self.size = size
    self.values = values
  }

  /// Таблица из решётки 512 × 512: 8 × 8 квадратов по 64 × 64. Квадрат с номером `b` (по строкам)
  /// хранит срез синего `b`; внутри квадрата x — красный, y — зелёный.
  ///
  /// Допущение: раскладка взята из стандартных LUT-решёток, а не из нативной Trickle, которой
  /// в репозитории нет. Поэтому статус фильтров с этой таблицей — «приближение».
  init?(lookup image: RasterImage) {
    guard image.width == 512, image.height == 512 else { return nil }
    var values: [Float] = []
    values.reserveCapacity(64 * 64 * 64 * 3)
    for blue in 0..<64 {
      let tileX = (blue % 8) * 64
      let tileY = (blue / 8) * 64
      for green in 0..<64 {
        for red in 0..<64 {
          let index = ((tileY + green) * 512 + tileX + red) * 4
          values.append(Float(image.pixels[index]) / 255)
          values.append(Float(image.pixels[index + 1]) / 255)
          values.append(Float(image.pixels[index + 2]) / 255)
        }
      }
    }
    self.init(size: 64, values: values)
  }

  /// Разбор текста `.cube`: `LUT_3D_SIZE`, строки «r g b». Поддерживается только домен 0...1,
  /// как в `DOMAIN_MIN 0 0 0` и `DOMAIN_MAX 1 1 1`; другой домен даёт `nil`, а не тихую ошибку.
  init?(cubeText: String) {
    var size: Int?
    var values: [Float] = []
    for rawLine in cubeText.split(whereSeparator: \.isNewline) {
      // Комментарий начинается с `#` и идёт до конца строки.
      let content = rawLine.prefix { $0 != "#" }
      let parts = content.split(whereSeparator: \.isWhitespace).map(String.init)
      guard let keyword = parts.first else { continue }
      switch keyword {
      case "LUT_3D_SIZE":
        guard parts.count == 2, let value = Int(parts[1]) else { return nil }
        size = value
      case "DOMAIN_MIN":
        guard parts.dropFirst().compactMap(Float.init) == [0, 0, 0] else { return nil }
      case "DOMAIN_MAX":
        guard parts.dropFirst().compactMap(Float.init) == [1, 1, 1] else { return nil }
      case "LUT_1D_SIZE":
        return nil
      case "TITLE":
        continue
      default:
        guard parts.count == 3, let red = Float(parts[0]), let green = Float(parts[1]),
          let blue = Float(parts[2])
        else { return nil }
        values += [red, green, blue]
      }
    }
    guard let size else { return nil }
    self.init(size: size, values: values)
  }

  /// Байты для `CIColorCube`: RGBA по 4 Float на запись. Сила `intensity` (0...1) уже учтена:
  /// запись = (1 - t) * тождество + t * таблица. Линейная интерполяция куба совпадает со смешением
  /// результатов, поэтому отдельный шаг смешения не нужен.
  func cubeData(intensity: Double) -> Data {
    let mix = Float(min(max(intensity, 0), 1))
    let scale = Float(size - 1)
    var output: [Float] = []
    output.reserveCapacity(size * size * size * 4)
    for blue in 0..<size {
      for green in 0..<size {
        for red in 0..<size {
          let index = ((blue * size + green) * size + red) * 3
          let identity: [Float] = [Float(red) / scale, Float(green) / scale, Float(blue) / scale]
          for channel in 0..<3 {
            output.append((1 - mix) * identity[channel] + mix * values[index + channel])
          }
          output.append(1)
        }
      }
    }
    return output.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}

/// Применяет таблицу цвета из решётки 512 × 512 (Android `LUT512x512Filter`, Trickle `applyLut`).
/// `intensity` 0...1: 0 не меняет картинку, 1 даёт полный эффект таблицы.
struct LUT512x512Filter: Filter {
  let table: LUTTable
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    try applyColorCube(table, intensity: intensity, filterID: "LUT512x512Filter", to: image)
  }
}

/// Применяет таблицу из `.cube` (Android `CubeLutFilter`, Trickle `applyCubeLut`).
/// `intensity` 0...1, как у `LUT512x512Filter`.
struct CubeLutFilter: Filter {
  let table: LUTTable
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    try applyColorCube(table, intensity: intensity, filterID: "CubeLutFilter", to: image)
  }
}

/// Общий путь обоих фильтров: один `CIColorCube` на всю картинку.
private func applyColorCube(
  _ table: LUTTable, intensity: Double, filterID: String, to image: RasterImage
) throws -> RasterImage {
  let data = table.cubeData(intensity: intensity)
  return try CoreImageBridge.render(image, filterID: filterID) { input in
    input.applyingFilter(
      "CIColorCube",
      parameters: [
        "inputCubeDimension": table.size,
        "inputCubeData": data,
      ])
  }
}
