import CoreImage
import Foundation
import ImageIO

/// Таблицы цвета (LUT): 12 пресетов Android на таблицах `lookup_*.webp` (512 × 512) из `Resources/LUT`.
/// Каждый пресет — `LUT512x512Filter` с одной таблицей и силой 0...1.
///
/// Источник: Trickle 1.9.3 (github.com/T8RIN/Trickle), `trickle/src/main/cpp/ProcessingFilters.cpp`,
/// `applyLutImpl`: поиск по ближайшей записи без интерполяции (см. `LUT512x512Filter`).
/// Статус: проверено по эталону.
/// `LUT512x512Filter` без таблицы (выбор файла) и `CubeLutFilter` (файл от пользователя) не
/// зарегистрированы: `FilterParameter` не умеет передавать файл.
enum LUTFilters {
  static let descriptors: [FilterDescriptor] = presets.map { preset in
    FilterDescriptor(
      id: preset.id,
      titleKey: preset.titleKey,
      category: .lut,
      engine: .cpu,
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
  /// The 512 × 512 lookup image bundled as `Resources/LUT/<name>.webp`, or nil if it cannot be read.
  static func image(named name: String) -> RasterImage? {
    guard
      let url = Bundle.module.url(forResource: name, withExtension: "webp", subdirectory: "LUT"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let raster = RasterImage(cgImage),
      raster.width == 512, raster.height == 512
    else { return nil }
    return raster
  }
}

/// Пресет: таблица из ресурсов, смешанная с тождеством силой `intensity`.
struct LUTPresetFilter: Filter {
  let table: String
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    guard let lookup = LUTAtlas.image(named: table) else {
      throw FilterError.renderFailed(table)
    }
    return LUT512x512Filter(lookup: lookup, intensity: intensity).render(image)
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
///
/// Как в Trickle 1.9.3 `applyLutImpl`: каждый канал делится на 4 нацело (`r`, `g`, `b` в 0...63),
/// запись берётся в квадрате `b` (8 × 8 квадратов по 64 × 64: `x = (b % 8) * 64 + r`,
/// `y = (b / 8) * 64 + g`) без интерполяции, результат = round(c * 4 + intensity * (lut - c * 4)),
/// где `c * 4` — канал, округлённый вниз до кратного 4. Альфа не меняется.
struct LUT512x512Filter: Filter {
  let lookup: RasterImage
  let intensity: Double

  func apply(to image: RasterImage) async throws -> RasterImage {
    guard lookup.width == 512, lookup.height == 512 else {
      throw FilterError.renderFailed("LUT512x512Filter")
    }
    return render(image)
  }

  /// `lookup` должен быть 512 × 512.
  func render(_ image: RasterImage) -> RasterImage {
    let strength = Float(intensity)
    func mix(_ level: Int, _ entry: UInt8) -> UInt8 {
      let base = Float(level * 4)
      let mixed = (base + strength * (Float(entry) - base)).rounded(.toNearestOrAwayFromZero)
      return UInt8(min(max(mixed, 0), 255))
    }
    var output = image.pixels
    for index in stride(from: 0, to: output.count, by: 4) {
      let red = Int(output[index] / 4)
      let green = Int(output[index + 1] / 4)
      let blue = Int(output[index + 2] / 4)
      let lutIndex = ((blue / 8) * 64 + green) * 512 + (blue % 8) * 64 + red
      output[index] = mix(red, lookup.pixels[lutIndex * 4])
      output[index + 1] = mix(green, lookup.pixels[lutIndex * 4 + 1])
      output[index + 2] = mix(blue, lookup.pixels[lutIndex * 4 + 2])
    }
    return RasterImage(width: image.width, height: image.height, pixels: output)
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
