import Foundation

/// Colour arithmetic for the palette formats. The formulas are the ones the Android palette module
/// uses (`PaletteColor` and `ColorUtils`), so the same file gives the same colours on both
/// platforms. Components are unit values from 0 to 1 unless a name says otherwise.
enum PaletteMath {

  /// A value clamped to 0 through 1. NaN becomes 0.
  static func clampUnit(_ value: Double) -> Double {
    guard !value.isNaN else { return 0 }
    return min(max(value, 0), 1)
  }

  /// An 8-bit channel for a unit value.
  static func channel(_ unit: Double) -> UInt8 {
    UInt8((clampUnit(unit) * 255).rounded())
  }

  /// The unit value of an 8-bit channel.
  static func unit(_ channel: UInt8) -> Double {
    Double(channel) / 255
  }

  /// A colour from unit RGB components and an optional alpha.
  static func colour(
    name: String?, red: Double, green: Double, blue: Double, alpha: Double = 1
  ) -> PaletteColour {
    PaletteColour(
      name: name, red: channel(red), green: channel(green), blue: channel(blue),
      alpha: channel(alpha))
  }

  /// A grey colour with the same value in each channel.
  static func grey(name: String?, white: Double, alpha: Double = 1) -> PaletteColour {
    colour(name: name, red: white, green: white, blue: white, alpha: alpha)
  }

  /// A colour from CMYK components, where 0 is no ink.
  static func cmyk(
    name: String?, cyan: Double, magenta: Double, yellow: Double, black: Double,
    alpha: Double = 1
  ) -> PaletteColour {
    let (red, green, blue) = cmykToRGB(
      clampUnit(cyan), clampUnit(magenta), clampUnit(yellow), clampUnit(black))
    return colour(name: name, red: red, green: green, blue: blue, alpha: alpha)
  }

  /// The RGB components of CMYK components, as `PaletteColor.toRgb` computes them.
  static func cmykToRGB(_ c: Double, _ m: Double, _ y: Double, _ k: Double) -> (
    Double, Double, Double
  ) {
    ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k))
  }

  /// The CMYK components of RGB components, as `PaletteColor.toCmyk` computes them.
  static func rgbToCMYK(_ red: Double, _ green: Double, _ blue: Double) -> (
    c: Double, m: Double, y: Double, k: Double
  ) {
    let k = 1 - max(red, green, blue)
    guard k < 1 else { return (0, 0, 0, k) }
    return (
      (1 - red - k) / (1 - k), (1 - green - k) / (1 - k), (1 - blue - k) / (1 - k), k
    )
  }

  /// The RGB components of hue, saturation and brightness, as `PaletteColor.hsb` computes them.
  static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> (
    Double, Double, Double
  ) {
    let h = clampUnit(hue)
    let s = clampUnit(saturation)
    let b = clampUnit(brightness)
    let chroma = b * s
    let x = chroma * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
    return rgbFromSector(h, chroma: chroma, x: x, offset: b - chroma)
  }

  /// The RGB components of hue, saturation and lightness, as `PaletteColor.hsl` computes them.
  static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (
    Double, Double, Double
  ) {
    let h = clampUnit(hue)
    let s = clampUnit(saturation)
    let l = clampUnit(lightness)
    let chroma = (1 - abs(2 * l - 1)) * s
    let x = chroma * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
    return rgbFromSector(h, chroma: chroma, x: x, offset: l - chroma / 2)
  }

  /// The hue, saturation and brightness of RGB components, as `PaletteColor.toHsb` computes them.
  /// The hue is a fraction of a turn.
  static func rgbToHSB(_ red: Double, _ green: Double, _ blue: Double) -> (
    hue: Double, saturation: Double, brightness: Double
  ) {
    let high = max(red, green, blue)
    let low = min(red, green, blue)
    let delta = high - low
    var hue: Double
    if delta == 0 {
      hue = 0
    } else if high == red {
      hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) * 60
    } else if high == green {
      hue = ((blue - red) / delta + 2) * 60
    } else {
      hue = ((red - green) / delta + 4) * 60
    }
    if hue < 0 {
      hue += 360
    }
    let saturation = high == 0 ? 0 : delta / high
    return (hue / 360, saturation, high)
  }

  /// The channels of a hex colour as the Android `extractHexRGBA` reads them. Every character that
  /// is not a hex digit is ignored. Three or four digits repeat each digit, and six or eight digits
  /// hold two each. The result has three channels, or four when an alpha channel is present.
  static func hexChannels(_ text: String) -> [UInt8]? {
    let digits = text.compactMap(\.hexDigitValue)
    switch digits.count {
    case 3, 4:
      return digits.map { UInt8($0 * 17) }
    case 6, 8:
      return stride(from: 0, to: digits.count, by: 2).map {
        UInt8(digits[$0] << 4 | digits[$0 + 1])
      }
    default:
      return nil
    }
  }

  /// The sRGB transfer function, which turns encoded values into linear light.
  static func linear(fromSRGB value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  /// The inverse of `linear(fromSRGB:)`.
  static func sRGB(fromLinear value: Double) -> Double {
    value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
  }

  /// `value` rounded to `places` decimal places, with ties to even as `kotlin.math.round` does.
  static func rounded(_ value: Double, places: Int) -> Double {
    let factor = pow(10.0, Double(places))
    return (value * factor).rounded(.toNearestOrEven) / factor
  }

  private static func rgbFromSector(
    _ hue: Double, chroma: Double, x: Double, offset: Double
  ) -> (Double, Double, Double) {
    let sector: (Double, Double, Double)
    switch hue {
    case ..<(1.0 / 6): sector = (chroma, x, 0)
    case ..<(2.0 / 6): sector = (x, chroma, 0)
    case ..<(3.0 / 6): sector = (0, chroma, x)
    case ..<(4.0 / 6): sector = (0, x, chroma)
    case ..<(5.0 / 6): sector = (x, 0, chroma)
    default: sector = (chroma, 0, x)
    }
    return (
      clampUnit(sector.0 + offset), clampUnit(sector.1 + offset), clampUnit(sector.2 + offset)
    )
  }
}
