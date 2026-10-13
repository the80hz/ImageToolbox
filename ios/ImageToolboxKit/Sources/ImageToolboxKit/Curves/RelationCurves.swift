import Foundation

/// A curve that changes one pixel property by another: hue, saturation or value (brightness).
public enum RelationCurveKind: CaseIterable, Sendable {
  case hueVsSat
  case hueVsHue
  case hueVsLuma
  case lumaVsSat
  case lumaVsHue
  case satVsSat

  /// The property the curve reads, in the order the Android app applies the curves.
  var input: Property {
    switch self {
    case .hueVsSat, .hueVsHue, .hueVsLuma: .hue
    case .lumaVsSat, .lumaVsHue: .value
    case .satVsSat: .saturation
    }
  }

  enum Property: Sendable {
    case hue
    case saturation
    case value
  }
}

/// The six hue, saturation and value curves. Each is centred on 0.5: the curve's output minus 0.5 is
/// the change. A curve that stays at 0.5 changes nothing.
public struct RelationCurves: Equatable, Sendable {
  /// A flat curve at the neutral height. The default for every kind.
  public static let neutral = ToneCurve(points: [
    CurvePoint(x: 0, y: 0.5), CurvePoint(x: 1, y: 0.5),
  ])

  /// Only curves that differ from neutral are stored, so equal states compare equal.
  private var curves: [RelationCurveKind: ToneCurve] = [:]

  public init() {}

  public subscript(kind: RelationCurveKind) -> ToneCurve {
    get { curves[kind] ?? Self.neutral }
    set { curves[kind] = newValue == Self.neutral ? nil : newValue }
  }

  /// True when every curve is neutral.
  public var isIdentity: Bool {
    curves.isEmpty
  }

  /// The change for each 8-bit level of the kind's input, for the kinds that are not neutral.
  func changeTables() -> [(kind: RelationCurveKind, table: [Double])] {
    RelationCurveKind.allCases.compactMap { kind in
      guard let curve = curves[kind] else { return nil }
      let table = (0..<256).map { level in curve.value(at: Double(level) / 255) - 0.5 }
      return (kind, table)
    }
  }
}

/// Applies one relation curve to a pixel in hue, saturation and value form.
enum RelationAdjuster {

  struct HSV {
    var hue: Double
    var saturation: Double
    var value: Double
  }

  static func input(of hsv: HSV, for kind: RelationCurveKind) -> Double {
    switch kind.input {
    case .hue: hsv.hue
    case .saturation: hsv.saturation
    case .value: hsv.value
    }
  }

  static func adjust(_ hsv: HSV, kind: RelationCurveKind, change: Double) -> HSV {
    switch kind {
    case .hueVsSat, .lumaVsSat, .satVsSat:
      var result = hsv
      result.saturation = min(max(hsv.saturation + saturationChange(change), 0), 1)
      return result
    case .hueVsHue, .lumaVsHue:
      var result = hsv
      let shifted = hsv.hue + change
      result.hue = shifted - shifted.rounded(.down)
      return result
    case .hueVsLuma:
      return lumaAdjusted(hsv, change: change)
    }
  }

  /// Positive changes are weaker than negative ones, as in the Android shader.
  private static func saturationChange(_ change: Double) -> Double {
    change >= 0 ? change * 2 / 3 : change * 2
  }

  /// Moves the luma towards the target. Chroma with little saturation changes less.
  private static func lumaAdjusted(_ hsv: HSV, change: Double) -> HSV {
    let rgb = OklabColour.hsvToRGB(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value)
    let luma = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    let chroma = hsv.saturation * hsv.value
    let chromaWeight = smoothstep(0.04, 0.30, chroma)
    let target = min(max(luma + change * 2 * chromaWeight, 0), 1)

    var adjusted = rgb
    if target < luma {
      let scale = target / max(luma, 0.00001)
      adjusted = (rgb.red * scale, rgb.green * scale, rgb.blue * scale)
    } else {
      let amount = (target - luma) / max(1 - luma, 0.00001)
      adjusted = (
        rgb.red * (1 - amount) + amount,
        rgb.green * (1 - amount) + amount,
        rgb.blue * (1 - amount) + amount
      )
    }
    return toHSV(
      red: min(max(adjusted.0, 0), 1),
      green: min(max(adjusted.1, 0), 1),
      blue: min(max(adjusted.2, 0), 1))
  }

  static func toHSV(red: Double, green: Double, blue: Double) -> HSV {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    var hue = 0.0
    if delta > 0 {
      if maximum == red {
        hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
      } else if maximum == green {
        hue = (blue - red) / delta + 2
      } else {
        hue = (red - green) / delta + 4
      }
      hue /= 6
      if hue < 0 { hue += 1 }
    }
    let saturation = maximum > 0 ? delta / maximum : 0
    return HSV(hue: hue, saturation: saturation, value: maximum)
  }

  static func toRGB(_ hsv: HSV) -> (red: Double, green: Double, blue: Double) {
    OklabColour.hsvToRGB(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value)
  }

  private static func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
    let t = min(max((value - lower) / (upper - lower), 0), 1)
    return t * t * (3 - 2 * t)
  }
}
