import Foundation

/// Глитч-фильтры, CRT, эффекты плёнки и градиентные карты.
///
/// Перенесены: `GlitchFilter` (приближение) и `GradientMapFilter`. Остальные фильтры группы
/// опираются на нативный код (Aire, Trickle, G'MIC, GPUImage) или на LUT-ресурсы, которых в
/// пакете нет, поэтому здесь не реализованы. Причины записаны в отчёте группы.
enum GlitchCRTFilters {
  static let descriptors: [FilterDescriptor] = [
    FilterDescriptor(
      id: "GlitchFilter",
      titleKey: "glitch",
      category: .glitchAndCRT,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "amount", titleKey: "amount",
          kind: .number(range: 0...100, step: 1, defaultValue: 20)),
        FilterParameter(
          key: "seed", titleKey: "seed",
          kind: .number(range: 0...100, step: 1, defaultValue: 15)),
        FilterParameter(
          key: "repeatCount", titleKey: "repeat_count",
          kind: .number(range: 0...100, step: 1, defaultValue: 9)),
      ],
      make: {
        GlitchFilter(
          amount: Int($0.number("amount")),
          seed: Int($0.number("seed")),
          iterations: Int($0.number("repeatCount")))
      }
    ),
    FilterDescriptor(
      id: "GradientMapFilter",
      titleKey: "gradient_map",
      category: .glitchAndCRT,
      engine: .cpu,
      parameters: [
        FilterParameter(
          key: "value", titleKey: "gradient_map",
          kind: .choice(options: GradientPaletteTable.names, defaultValue: "Spectral"))
      ],
      make: { GradientMapFilter(palette: $0.choice("value")) }
    ),
  ]
}

/// Портит JPEG-байты, как `GlitchTool.jpegGlitch` в Android: картинка кодируется в JPEG
/// с качеством 100, затем `iterations` раз в байт записывается значение `amount` в позицию,
/// которую задаёт `seed`, и результат декодируется обратно.
///
/// Приближение: Android пишет JPEG своим кодером, ImageIO пишет его иначе. Поэтому байты
/// правок попадают в другие места потока, и картина похожа по характеру, но не совпадает
/// побайтно. Если результат не декодируется, фильтр возвращает входную картинку, а Android
/// в этом случае получает `null`. Это отличие записано в отчёте.
///
/// Структура алгоритма с Android совпадает (`JpegGlitch.kt`: поиск `FF DA`, участки, `Float`-арифметика
/// позиций, значение `floor(amount / 100 * 256)`). Побайтный результат зависит от точных байт JPEG
/// libjpeg-turbo в Skia (заголовки, таблицы, ICC, подвыборка) и от поведения его декодера на
/// испорченных данных; ни то ни другое ImageIO не повторяет (FILTERS.md, решение 18).
/// Статус: приближение, расхождение с эталоном (среднее 81.18, наибольшее 255).
struct GlitchFilter: Filter {
  /// Значение байта в процентах, 0...100. Записывается как `floor(amount / 100 * 256)`.
  let amount: Int
  /// Позиция правки внутри каждого участка, в процентах, 0...100.
  let seed: Int
  /// Число правок, 0...100. При нуле картинка только перекодируется в JPEG.
  let iterations: Int

  func apply(to image: RasterImage) async throws -> RasterImage {
    let failure = FilterError.renderFailed("GlitchFilter")
    guard let picture = image.toCGImage(),
      let jpeg = ImageCodec.encode(picture, as: .jpeg, quality: 1)
    else { throw failure }

    var bytes = [UInt8](jpeg)
    let header = Self.jpegHeaderSize(bytes)
    for pos in 0..<max(iterations, 0) {
      Self.corruptByte(
        &bytes, pos: pos, header: header, amount: amount, seed: seed, iterations: iterations)
    }

    // Правка заголовка может сделать JPEG нечитаемым. Android тогда получает null, а здесь
    // картинка остаётся без изменений, чтобы цепочка фильтров не падала.
    guard let decoded = ImageCodec.decode(Data(bytes)),
      let raster = RasterImage(decoded),
      raster.width == image.width, raster.height == image.height
    else { return image }
    return raster
  }

  /// Смещение после первого маркера начала скана (FF DA). Если маркера нет, 417, как в Android.
  static func jpegHeaderSize(_ bytes: [UInt8]) -> Int {
    var index = 0
    while index + 1 < bytes.count {
      if bytes[index] == 0xFF && bytes[index + 1] == 0xDA {
        return index + 2
      }
      index += 1
    }
    return 417
  }

  /// Одна правка: участок `pos` из `iterations` делится по `seed`, в его точке пишется байт.
  /// Арифметика во Float, как в Kotlin, чтобы позиции совпадали.
  static func corruptByte(
    _ bytes: inout [UInt8],
    pos: Int,
    header: Int,
    amount: Int,
    seed: Int,
    iterations: Int
  ) {
    let maxIndex = Float(bytes.count - header) - 4
    let slice = maxIndex / Float(iterations)
    let pxMin = slice * Float(pos)
    let pxMax = slice * Float(pos + 1)
    let delta = pxMax - pxMin
    var pxIndex = pxMin + delta * Float(seed) / 100
    if pxIndex > maxIndex {
      pxIndex = maxIndex
    }
    let index = Int(floor(Double(Float(header) + pxIndex)))
    guard bytes.indices.contains(index) else { return }
    let value = Int(floor(Double(Float(amount) / 100 * 256)))
    bytes[index] = UInt8(truncatingIfNeeded: value)
  }
}

/// Заменяет цвет каждого пикселя цветом палитры по его яркости, как `GradientMapFilter` в Android.
///
/// Яркость целочисленная: `(77 R + 150 G + 29 B) >> 8` по прямым (не premultiplied) каналам.
/// Альфа сохраняется. Палитра берётся из `GradientPaletteTable`, на 256 уровней яркости.
/// Проверено по эталону (`GradientMapFilter`, раздел 10): совпадение точное.
struct GradientMapFilter: Filter {
  /// Имя палитры из `GradientPaletteTable.names`.
  let palette: String

  func apply(to image: RasterImage) async throws -> RasterImage {
    guard let stops = GradientPaletteTable.stops[palette] else {
      throw FilterError.unknownFilter(palette)
    }
    let colors = Self.sampleColors(stops, count: 256)

    var output = image.pixels
    for index in stride(from: 0, to: output.count, by: 4) {
      let alpha = image.pixels[index + 3]
      // Premultiplied пиксель с нулевой альфой уже нулевой, его цвет не нужен.
      guard alpha > 0 else { continue }
      let scale = 255 / Double(alpha)
      let red = Int(min(255, (Double(image.pixels[index]) * scale).rounded()))
      let green = Int(min(255, (Double(image.pixels[index + 1]) * scale).rounded()))
      let blue = Int(min(255, (Double(image.pixels[index + 2]) * scale).rounded()))

      let luminance = (red * 77 + green * 150 + blue * 29) >> 8
      let color = Int(colors[luminance])
      let mapped = [(color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF]
      for channel in 0..<3 {
        let straight = Double(mapped[channel])
        output[index + channel] = UInt8(min(255, (straight * Double(alpha) / 255).rounded()))
      }
    }
    return RasterImage(width: image.width, height: image.height, pixels: output)
  }

  /// `count` цветов, равномерно по опорным точкам палитры. Как `GradientPalette.sampleColors`.
  static func sampleColors(_ stops: [UInt32], count: Int) -> [UInt32] {
    (0..<count).map { index in
      let position = Double(index) / Double(count - 1)
      let scaled = position * Double(stops.count - 1)
      let first = min(max(Int(floor(scaled)), 0), stops.count - 1)
      let second = min(first + 1, stops.count - 1)
      return interpolate(stops[first], stops[second], fraction: scaled - Double(first))
    }
  }

  /// Линейная интерполяция по каналам ARGB с округлением половинок вверх, как `roundToInt`.
  static func interpolate(_ first: UInt32, _ second: UInt32, fraction: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
      let start = Double((first >> shift) & 0xFF)
      let end = Double((second >> shift) & 0xFF)
      let value = Int(floor(start + (end - start) * fraction + 0.5))
      return UInt32(min(max(value, 0), 255))
    }
    return channel(24) << 24 | channel(16) << 16 | channel(8) << 8 | channel(0)
  }
}

/// Палитры градиентной карты: опорные цвета из `GradientPalette.kt` (core/domain),
/// в порядке `GradientPalette.entries`. Цвета ARGB; `rgb(...)` переведён так же, как в Kotlin.
enum GradientPaletteTable {
  /// Палитры в порядке `GradientPalette.entries`. `Custom` не переносится.
  static let names: [String] = [
    "Classic",
    "Fire",
    "Ocean",
    "Viridis",
    "Magma",
    "Inferno",
    "Plasma",
    "Turbo",
    "Twilight",
    "Ice",
    "Forest",
    "Neon",
    "Cividis",
    "Cubehelix",
    "Spectral",
    "Aurora",
    "Sunset",
    "Copper",
    "Rocket",
    "Mako",
    "Amethyst",
    "Vaporwave",
    "Earth",
    "Rainbow",
    "Cool",
    "Hot",
    "PurpleDream",
    "Lava",
    "Galaxy",
    "Mint",
    "Cherry",
    "XfAlternatingGrey",
    "XfBlues",
    "XfChromatic",
    "XfDefault",
    "XfDefaultWhite",
    "XfFireStorm",
    "XfFroth3",
    "XfFroth316",
    "XfFroth6",
    "XfFroth616",
    "XfGamma1",
    "XfGamma2",
    "XfGlasses1",
    "XfGlasses2",
    "XfGoodEga",
    "XfGreen",
    "XfGrey",
    "XfGrid",
    "XfHeadache2",
    "XfHeadache",
    "XfLandscape",
    "XfLyapunov",
    "XfNeon",
    "XfPaintJet",
    "XfRoyal",
    "XfTopo",
    "XfVolcano",
    "Rgb",
    "Ryb",
    "Cmyk",
    "HsvWheel",
    "RedChannel",
    "GreenChannel",
    "BlueChannel",
    "Heatmap",
    "ColdFire",
    "Ultraviolet",
    "ToxicWaste",
    "BloodMoon",
    "Abyss",
    "ElectricCandy",
    "BlackGold",
    "Ghost",
    "Grayscale",
    "SoftRainbow",
  ]

  /// Опорные цвета по имени палитры.
  static let stops: [String: [UInt32]] = [
    "Classic": [0xFF05_051A, 0xFF12_3EAB, 0xFF26_BCE1, 0xFFF8_E16C, 0xFFF0_6A24, 0xFF3A_0812],
    "Fire": [0xFF09_0004, 0xFF5A_0900, 0xFFD3_3A00, 0xFFFF_A51F, 0xFFFF_FFB0],
    "Ocean": [0xFF02_0B22, 0xFF06_3B73, 0xFF08_7E8B, 0xFF31_C5C0, 0xFFD8_FFF2],
    "Viridis": [0xFF44_0154, 0xFF3B_528B, 0xFF21_918C, 0xFF5E_C962, 0xFFFD_E725],
    "Magma": [0xFF00_0004, 0xFF3B_0F70, 0xFF8C_2981, 0xFFDE_4968, 0xFFFE_9F6D, 0xFFFC_FDBF],
    "Inferno": [0xFF00_0004, 0xFF42_0A68, 0xFF93_2667, 0xFFDD_513A, 0xFFFC_A50A, 0xFFFC_FFA4],
    "Plasma": [0xFF0D_0887, 0xFF6A_00A8, 0xFFB1_2A90, 0xFFE1_6462, 0xFFFC_A636, 0xFFF0_F921],
    "Turbo": [
      0xFF30_123B, 0xFF41_45AB, 0xFF2A_9DF4, 0xFF20_D5A5, 0xFF8B_EB55, 0xFFF9_D423, 0xFFF3_6B1B,
      0xFF7A_0403,
    ],
    "Twilight": [
      0xFF20_134E, 0xFF6D_3580, 0xFFC7_5D75, 0xFFF6_B36B, 0xFF8E_D1C5, 0xFF31_5A8A, 0xFF20_134E,
    ],
    "Ice": [0xFF02_040F, 0xFF10_2A56, 0xFF2D_78B7, 0xFF8B_E4F0, 0xFFF5_FFFF],
    "Forest": [0xFF07_150A, 0xFF17_4B2B, 0xFF3B_7D3A, 0xFF9B_BF48, 0xFFF1_E7A1],
    "Neon": [0xFF05_0011, 0xFF74_00B8, 0xFFFF_007A, 0xFFFF_C800, 0xFF00_F5D4, 0xFF00_77FF],
    "Cividis": [0xFF00_204C, 0xFF2E_4A7D, 0xFF66_6870, 0xFFA0_8A5B, 0xFFD6_AF3C, 0xFFFF_E945],
    "Cubehelix": [0xFF00_0000, 0xFF1D_2B53, 0xFF5E_3C99, 0xFFB3_5C8C, 0xFFE3_A35D, 0xFFFF_FFFF],
    "Spectral": [
      0xFF9E_0142, 0xFFD5_3E4F, 0xFFF4_6D43, 0xFFFE_E08B, 0xFFE6_F598, 0xFF66_C2A5, 0xFF32_88BD,
      0xFF5E_4FA2,
    ],
    "Aurora": [0xFF07_152B, 0xFF44_318D, 0xFF0B_8F9C, 0xFF35_D07F, 0xFFD9_F36A],
    "Sunset": [0xFF10_143D, 0xFF4A_236B, 0xFFA3_3B69, 0xFFF0_6A4D, 0xFFFF_C56E, 0xFFFF_F0B3],
    "Copper": [0xFF08_0403, 0xFF3A_1C12, 0xFF81_4425, 0xFFC8_783E, 0xFFF0_B878, 0xFFFF_E0B8],
    "Rocket": [
      0xFF03_051A, 0xFF3F_1B43, 0xFF84_1E5A, 0xFFCB_1B4F, 0xFFF0_6043, 0xFFF6_B48F, 0xFFFA_EBDD,
    ],
    "Mako": [
      0xFF0B_0405, 0xFF34_2032, 0xFF3B_496C, 0xFF35_7BA3, 0xFF39_A7A5, 0xFF8B_DAB2, 0xFFDE_F5E5,
    ],
    "Amethyst": [0xFF10_002B, 0xFF24_0046, 0xFF5A_189A, 0xFF9D_4EDD, 0xFFE0_AAFF, 0xFFFF_F0FF],
    "Vaporwave": [0xFF17_002E, 0xFF58_00A3, 0xFFB5_179E, 0xFFF7_2585, 0xFF4C_C9F0, 0xFF00_F5D4],
    "Earth": [0xFF07_1A12, 0xFF1D_4D32, 0xFF60_7D3B, 0xFFB4_9A55, 0xFFD9_C9A2, 0xFFF2_EFE6],
    "Rainbow": [
      0xFFFF_0000, 0xFFFF_8000, 0xFFFF_FF00, 0xFF00_FF00, 0xFF00_FFFF, 0xFF00_00FF, 0xFF80_00FF,
      0xFFFF_0080,
    ],
    "Cool": [
      0xFF00_FFFF, 0xFF20_DFFF, 0xFF40_BFFF, 0xFF60_9FFF, 0xFF80_80FF, 0xFF9F_60FF, 0xFFBF_40FF,
      0xFFFF_00FF,
    ],
    "Hot": [
      0xFF00_0000, 0xFF40_0000, 0xFF80_0000, 0xFFBF_4000, 0xFFFF_8000, 0xFFFF_BF40, 0xFFFF_FF80,
      0xFFFF_FFFF,
    ],
    "PurpleDream": [
      0xFF0D_001A, 0xFF1A_0033, 0xFF40_0066, 0xFF66_0099, 0xFF8C_26BF, 0xFFB3_4DE6, 0xFFD9_99FF,
      0xFFFF_E6FF,
    ],
    "Lava": [
      0xFF0D_0000, 0xFF1A_0000, 0xFF4D_0000, 0xFF80_0000, 0xFFB3_1A00, 0xFFD9_4D00, 0xFFFF_8000,
      0xFFFF_CC33,
    ],
    "Galaxy": [
      0xFF06_0013, 0xFF0D_0026, 0xFF26_0059, 0xFF4D_0080, 0xFF80_1AB3, 0xFFB3_40CC, 0xFFD9_73D9,
      0xFFFF_B3E6,
    ],
    "Mint": [
      0xFF00_2626, 0xFF00_4D4D, 0xFF1A_6666, 0xFF33_8080, 0xFF4D_998C, 0xFF80_CCB3, 0xFFB3_EBD9,
      0xFFD9_FFF2,
    ],
    "Cherry": [
      0xFF26_000D, 0xFF4D_001A, 0xFF73_0026, 0xFF99_0033, 0xFFBF_1A4D, 0xFFE6_4D73, 0xFFFF_8CA6,
      0xFFFF_CCD9,
    ],
    "XfAlternatingGrey": [
      0xFF00_0000, 0xFFDC_D8D8, 0xFFB4_B4B4, 0xFF90_9090, 0xFF68_6C6C, 0xFF44_4848, 0xFF24_2028,
      0xFF00_0000,
    ],
    "XfBlues": [
      0xFF00_0000, 0xFF00_18CC, 0xFF3C_D4FC, 0xFFB8_FCFC, 0xFF00_F8FC, 0xFF00_38FC, 0xFF00_0094,
      0xFF00_0000,
    ],
    "XfChromatic": [
      0xFF30_3030, 0xFF30_60E0, 0xFF98_E098, 0xFFE0_4030, 0xFFD0_30E0, 0xFF30_E098, 0xFFE0_E060,
      0xFF28_3030,
    ],
    "XfDefault": [
      0xFF00_0000, 0xFFFC_00FC, 0xFF7C_FC7C, 0xFF70_0054, 0xFF38_7044, 0xFF40_0020, 0xFF20_4030,
      0xFF00_0000,
    ],
    "XfDefaultWhite": [
      0xFF00_0000, 0xFFFC_9C3C, 0xFF3C_7C5C, 0xFF7C_3C7C, 0xFF9C_DC7C, 0xFFDC_9C9C, 0xFFFC_5CBC,
      0xFFFC_FCFC,
    ],
    "XfFireStorm": [
      0xFF00_0000, 0xFFEA_0E87, 0xFFF9_6421, 0xFFAB_D102, 0xFF3E_FF41, 0xFF01_CCB1, 0xFF23_61FA,
      0xFF8D_0BE6,
    ],
    "XfFroth3": [
      0xFF00_0000, 0xFF98_0000, 0xFF68_0000, 0xFF00_A800, 0xFF00_7800, 0xFF00_00D0, 0xFF00_0088,
      0xFF00_0058,
    ],
    "XfFroth316": [
      0xFF00_0000, 0xFFD4_0000, 0xFF7C_0000, 0xFF00_FC00, 0xFF00_A800, 0xFF00_5000, 0xFF00_00D4,
      0xFF00_0050,
    ],
    "XfFroth6": [
      0xFF00_0000, 0xFF70_0070, 0xFF88_0000, 0xFF9C_9C00, 0xFF00_B400, 0xFF00_00C8, 0xFF00_E0E0,
      0xFFFC_FCFC,
    ],
    "XfFroth616": [
      0xFF00_0000, 0xFFA0_00A0, 0xFFA0_0000, 0xFFA0_A000, 0xFF00_A000, 0xFF00_00A0, 0xFF00_A0A0,
      0xFFFC_FCFC,
    ],
    "XfGamma1": [
      0xFF00_0000, 0xFF5C_6060, 0xFF84_8880, 0xFFA8_A4A0, 0xFFC0_BCC4, 0xFFD4_D4DC, 0xFFE8_E8F0,
      0xFFFC_FCFC,
    ],
    "XfGamma2": [
      0xFF00_0000, 0xFF24_2420, 0xFF48_4840, 0xFF6C_6C68, 0xFF8C_9094, 0xFFB4_B4B4, 0xFFDC_D4DC,
      0xFFFC_FCFC,
    ],
    "XfGlasses1": [
      0xFF00_0000, 0xFF48_0000, 0xFF90_0000, 0xFFD8_0000, 0xFF00_0020, 0xFF00_006C, 0xFF00_00B4,
      0xFF00_00FC,
    ],
    "XfGlasses2": [
      0xFF00_0000, 0xFF40_0020, 0xFF80_0040, 0xFFD0_0060, 0xFF10_0090, 0xFF60_00B0, 0xFFA0_00D0,
      0xFFF0_00F0,
    ],
    "XfGoodEga": [
      0xFF00_0000, 0xFFFC_5400, 0xFFFC_7E00, 0xFFFC_A800, 0xFFFC_D200, 0xFFFC_FC00, 0xFFFC_FC7E,
      0xFFFC_FCFC,
    ],
    "XfGreen": [
      0xFF00_0000, 0xFF00_D800, 0xFF00_B400, 0xFF00_9000, 0xFF00_6C00, 0xFF00_4800, 0xFF00_2000,
      0xFF00_0000,
    ],
    "XfGrey": [
      0xFF00_0000, 0xFFDC_DCDC, 0xFFB7_B7B7, 0xFF93_9393, 0xFF6E_6E6E, 0xFF4A_4A4A, 0xFF25_2525,
      0xFF00_0000,
    ],
    "XfGrid": [
      0xFF00_0000, 0xFF24_00FF, 0xFF49_00FF, 0xFF6D_00FF, 0xFF92_00FF, 0xFFB6_00FF, 0xFFDB_00FF,
      0xFFFF_00FF,
    ],
    "XfHeadache2": [
      0xFFF0_0000, 0xFFF0_2000, 0xFFF0_4400, 0xFFF4_6800, 0xFF00_6C90, 0xFF00_48B4, 0xFF00_24D8,
      0xFF00_8080,
    ],
    "XfHeadache": [
      0xFF00_0000, 0xFF00_DC20, 0xFF00_B844, 0xFFF4_6800, 0xFFF4_8C00, 0xFF00_48B4, 0xFF00_24D8,
      0xFF00_8080,
    ],
    "XfLandscape": [
      0xFF00_0000, 0xFF00_00A8, 0xFF00_00A8, 0xFF40_5300, 0xFF40_2E00, 0xFF40_0E00, 0xFFD2_D2FF,
      0xFFFF_FFFF,
    ],
    "XfLyapunov": [
      0xFF00_0000, 0xFFDC_A000, 0xFFB8_7C00, 0xFF90_5400, 0xFF6C_3000, 0xFF48_0C00, 0xFF24_0000,
      0xFF00_0000,
    ],
    "XfNeon": [
      0xFF00_0000, 0xFFE0_486C, 0xFF00_0000, 0xFF00_E400, 0xFF00_0000, 0xFFAC_AC00, 0xFF30_3000,
      0xFF00_0000,
    ],
    "XfPaintJet": [
      0xFF18_140C, 0xFFC4_4448, 0xFFF0_E848, 0xFFBC_306C, 0xFF18_140C, 0xFFC4_4448, 0xFFF0_E848,
      0xFF28_74C4,
    ],
    "XfRoyal": [
      0xFF00_0000, 0xFF5C_007C, 0xFF8C_24AC, 0xFFD8_B8E0, 0xFFFC_FCB4, 0xFFFC_FC20, 0xFFA8_8C24,
      0xFF3C_0050,
    ],
    "XfTopo": [
      0xFF00_0000, 0xFF44_84E8, 0xFF3C_8C10, 0xFF64_B438, 0xFF94_E46C, 0xFFE8_E468, 0xFFE8_AC24,
      0xFFFC_FCFC,
    ],
    "XfVolcano": [
      0xFF00_0000, 0xFFFC_1C00, 0xFFFC_FC3C, 0xFFFC_E4CC, 0xFFFC_983C, 0xFFFC_2800, 0xFFB4_0000,
      0xFF3C_3C3C,
    ],
    "Rgb": [
      0xFFFF_0000, 0xFFFF_FF00, 0xFF00_FF00, 0xFF00_FFFF, 0xFF00_00FF, 0xFFFF_00FF, 0xFFFF_0000,
    ],
    "Ryb": [0xFFF2_0D0D, 0xFFFF_8C00, 0xFFFF_F20D, 0xFF1A_66E6, 0xFF73_0DBF, 0xFFF2_0D0D],
    "Cmyk": [
      0xFF00_FFFF, 0xFF00_33FF, 0xFFFF_00FF, 0xFFFF_3300, 0xFFFF_FF00, 0xFF00_0000, 0xFF00_FFFF,
    ],
    "HsvWheel": [
      0xFFFF_0000, 0xFFFF_8000, 0xFFFF_FF00, 0xFF00_FF00, 0xFF00_FFFF, 0xFF00_00FF, 0xFF80_00FF,
      0xFFFF_00FF, 0xFFFF_0000,
    ],
    "RedChannel": [0xFF00_0000, 0xFF40_0000, 0xFF8C_0000, 0xFFD9_0D05, 0xFFFF_7340, 0xFFFF_FFFF],
    "GreenChannel": [0xFF00_0000, 0xFF00_3808, 0xFF00_8514, 0xFF1F_D12E, 0xFF8C_FF7A, 0xFFFF_FFFF],
    "BlueChannel": [0xFF00_0000, 0xFF03_0847, 0xFF05_1F9E, 0xFF0D_66F2, 0xFF66_D1FF, 0xFFFF_FFFF],
    "Heatmap": [0xFF00_0000, 0xFF40_0066, 0xFFBF_001A, 0xFFFF_5900, 0xFFFF_F200, 0xFFFF_FFFF],
    "ColdFire": [
      0xFF00_051F, 0xFF00_40BF, 0xFF00_F2FF, 0xFFFF_FFFF, 0xFFFF_A600, 0xFFBF_000D, 0xFF14_0000,
    ],
    "Ultraviolet": [0xFF03_000D, 0xFF14_0047, 0xFF59_00B3, 0xFFB8_00FF, 0xFFFF_33D1, 0xFF73_D9FF],
    "ToxicWaste": [0xFF00_0500, 0xFF0A_2900, 0xFF33_7A00, 0xFF94_E600, 0xFFE6_FF0D, 0xFF1F_5926],
    "BloodMoon": [0xFF03_0000, 0xFF1F_0003, 0xFF61_0005, 0xFFB8_0D05, 0xFFFF_470D, 0xFFFF_B84D],
    "Abyss": [0xFF00_0005, 0xFF00_051F, 0xFF00_1F3D, 0xFF00_617A, 0xFF14_B8AD, 0xFF8C_FFE0],
    "ElectricCandy": [
      0xFF05_0014, 0xFF40_00D9, 0xFFFF_00B8, 0xFFFF_590D, 0xFFE6_FF00, 0xFF00_FFB8, 0xFF05_0014,
    ],
    "BlackGold": [
      0xFF00_0000, 0xFF14_0E03, 0xFF47_2E06, 0xFF9E_6B0F, 0xFFF2_BF38, 0xFFFF_F2AD, 0xFF00_0000,
    ],
    "Ghost": [
      0xFF00_0000, 0xFF14_1A24, 0xFF3D_4D61, 0xFF7A_9EB3, 0xFFC7_EBF0, 0xFFFF_FFFF, 0xFF00_0000,
    ],
    "Grayscale": [0xFF00_0000, 0xFF40_4040, 0xFF90_9090, 0xFFFF_FFFF],
    "SoftRainbow": [
      0xFF3F_CEBC, 0xFF3C_BCEB, 0xFF5F_96E7, 0xFF81_6FE3, 0xFF9F_5EE2, 0xFFBD_4CE0, 0xFFDE_589F,
      0xFFFF_645E, 0xFFFD_A859, 0xFFFA_EC54, 0xFF9E_E671, 0xFF67_E282, 0xFF3F_CEBC,
    ],
  ]
}
