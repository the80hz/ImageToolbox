import Foundation

/// Conversion between CIE L*a*b* and 8-bit sRGB, with the D65 white point.
///
/// The formulas follow the Android `ColorUtils.LABToColor` and `ColorUtils.colorToLAB` functions,
/// which the palette module uses. L* runs from 0 to 100, and a* and b* are usually -128 to 127.
/// Colours outside the sRGB gamut are clamped, and each channel is rounded to 8 bits.
public enum PaletteLab {

  /// The D65 reference white on the 0 to 100 scale used by `ColorUtils`.
  private static let whiteX = 95.047
  private static let whiteY = 100.0
  private static let whiteZ = 108.883
  private static let epsilon = 0.008856
  private static let kappa = 903.3

  /// The 8-bit sRGB colour of an L*a*b* colour.
  public static func toSRGB(l: Double, a: Double, b: Double) -> (
    red: UInt8, green: UInt8, blue: UInt8
  ) {
    let fy = (l + 16) / 116
    let fx = a / 500 + fy
    let fz = fy - b / 200

    let x = whiteX * inversePivot(fx)
    let y = whiteY * (l > kappa * epsilon ? pow(fy, 3) : l / kappa)
    let z = whiteZ * inversePivot(fz)

    // XYZ on the 0 to 100 scale, converted to linear sRGB with the D65 matrix.
    let linearRed = (3.2406 * x - 1.5372 * y - 0.4986 * z) / 100
    let linearGreen = (-0.9689 * x + 1.8758 * y + 0.0415 * z) / 100
    let linearBlue = (0.0557 * x - 0.2040 * y + 1.0570 * z) / 100
    return (
      channel(encodeGamma(linearRed)),
      channel(encodeGamma(linearGreen)),
      channel(encodeGamma(linearBlue))
    )
  }

  /// The L*a*b* colour of an 8-bit sRGB colour.
  public static func fromSRGB(red: UInt8, green: UInt8, blue: UInt8) -> (
    l: Double, a: Double, b: Double
  ) {
    let linearRed = decodeGamma(Double(red) / 255)
    let linearGreen = decodeGamma(Double(green) / 255)
    let linearBlue = decodeGamma(Double(blue) / 255)
    let x = 100 * (0.4124 * linearRed + 0.3576 * linearGreen + 0.1805 * linearBlue)
    let y = 100 * (0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue)
    let z = 100 * (0.0193 * linearRed + 0.1192 * linearGreen + 0.9505 * linearBlue)

    let fx = pivot(x / whiteX)
    let fy = pivot(y / whiteY)
    let fz = pivot(z / whiteZ)
    return (l: max(0, 116 * fy - 16), a: 500 * (fx - fy), b: 200 * (fy - fz))
  }

  /// The inverse of `pivot` for the X and Z components.
  private static func inversePivot(_ value: Double) -> Double {
    let cube = pow(value, 3)
    return cube > epsilon ? cube : (116 * value - 16) / kappa
  }

  private static func pivot(_ value: Double) -> Double {
    value > epsilon ? pow(value, 1.0 / 3.0) : (kappa * value + 16) / 116
  }

  /// The sRGB transfer function, which maps linear light to encoded values.
  private static func encodeGamma(_ value: Double) -> Double {
    value > 0.0031308 ? 1.055 * pow(value, 1 / 2.4) - 0.055 : 12.92 * value
  }

  /// The inverse of `encodeGamma`.
  private static func decodeGamma(_ value: Double) -> Double {
    value < 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  /// An 8-bit channel for a value in the range 0 to 1. NaN becomes 0.
  private static func channel(_ unit: Double) -> UInt8 {
    guard !unit.isNaN else { return 0 }
    return UInt8((min(max(unit, 0), 1) * 255).rounded())
  }
}
