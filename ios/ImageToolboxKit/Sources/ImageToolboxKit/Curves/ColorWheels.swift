import Foundation

/// A colour wheel control. Its direction is the hue pushed towards, its length the amount, which is
/// limited to 1. The origin means no change.
public struct ColorWheelPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double = 0, y: Double = 0) {
    self.x = x
    self.y = y
  }

  /// The same direction, with the length limited to 1.
  public var normalized: ColorWheelPoint {
    let length = (x * x + y * y).squareRoot()
    guard length > 1 else { return self }
    return ColorWheelPoint(x: x / length, y: y / length)
  }

  public var isDefault: Bool {
    x * x + y * y < 1e-12
  }
}

/// Three colour wheels, one each for the shadows, midtones and highlights, and the edges control.
/// The edges control sets how sharply each wheel is limited to its tonal range. The colour change is
/// made in Oklab, as the Android app does, so it keeps lightness.
public struct ColorWheels: Equatable, Sendable {
  public static let defaultEdges = 0.5

  public var shadows: ColorWheelPoint
  public var midtones: ColorWheelPoint
  public var highlights: ColorWheelPoint
  /// 0...1. Higher values make the tonal ranges sharper.
  public var edges: Double

  public static let identity = ColorWheels()

  public init(
    shadows: ColorWheelPoint = ColorWheelPoint(),
    midtones: ColorWheelPoint = ColorWheelPoint(),
    highlights: ColorWheelPoint = ColorWheelPoint(),
    edges: Double = ColorWheels.defaultEdges
  ) {
    self.shadows = shadows.normalized
    self.midtones = midtones.normalized
    self.highlights = highlights.normalized
    self.edges = min(max(edges, 0), 1)
  }

  /// True when no wheel moves a colour. The edges control has no effect on its own.
  public var isIdentity: Bool {
    shadows.isDefault && midtones.isDefault && highlights.isDefault
  }

  /// The chroma each wheel pushes towards, computed once per picture rather than per pixel.
  struct Balances {
    let shadows: (a: Double, b: Double)
    let midtones: (a: Double, b: Double)
    let highlights: (a: Double, b: Double)
  }

  func balances() -> Balances {
    Balances(
      shadows: Self.balance(shadows),
      midtones: Self.balance(midtones),
      highlights: Self.balance(highlights))
  }

  /// Returns the adjusted straight sRGB colour. Components are 0...1.
  func adjusted(
    red: Double, green: Double, blue: Double, balances: Balances
  ) -> (red: Double, green: Double, blue: Double) {
    let linear = (
      OklabColour.srgbToLinear(red), OklabColour.srgbToLinear(green),
      OklabColour.srgbToLinear(blue)
    )
    var lab = OklabColour.linearToOklab(red: linear.0, green: linear.1, blue: linear.2)

    // The tonal weights use the gamma-encoded colour, as the Android shader does.
    let tonalLuma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    let sharpness = 0.8 + (16 - 0.8) * Self.smoothstep(edges)
    let distances = (tonalLuma, abs(tonalLuma - 0.5), 1 - tonalLuma)
    var weights = (
      exp(-sharpness * distances.0 * distances.0),
      exp(-sharpness * distances.1 * distances.1),
      exp(-sharpness * distances.2 * distances.2)
    )
    let total = max(weights.0 + weights.1 + weights.2, 0.0001)
    weights = (weights.0 / total, weights.1 / total, weights.2 / total)

    lab.a +=
      (balances.shadows.a * weights.0 + balances.midtones.a * weights.1
        + balances.highlights.a * weights.2) * 0.115
    lab.b +=
      (balances.shadows.b * weights.0 + balances.midtones.b * weights.1
        + balances.highlights.b * weights.2) * 0.115

    let back = OklabColour.oklabToLinear(lab)
    return (
      min(max(OklabColour.linearToSRGB(back.red), 0), 1),
      min(max(OklabColour.linearToSRGB(back.green), 0), 1),
      min(max(OklabColour.linearToSRGB(back.blue), 0), 1)
    )
  }

  /// The chroma direction of a wheel at its hue, scaled by how far the wheel is pushed.
  private static func balance(_ wheel: ColorWheelPoint) -> (a: Double, b: Double) {
    let strength = min((wheel.x * wheel.x + wheel.y * wheel.y).squareRoot(), 1)
    let angle = atan2(-wheel.y, wheel.x)
    let turns = angle - Double.pi / 2
    let hue = turns / (2 * Double.pi) - (turns / (2 * Double.pi)).rounded(.down)
    let rgb = OklabColour.hsvToRGB(hue: hue, saturation: 1, value: 1)
    let lab = OklabColour.linearToOklab(
      red: OklabColour.srgbToLinear(rgb.red),
      green: OklabColour.srgbToLinear(rgb.green),
      blue: OklabColour.srgbToLinear(rgb.blue))
    let length = max((lab.a * lab.a + lab.b * lab.b).squareRoot(), 0.0001)
    return (lab.a / length * strength, lab.b / length * strength)
  }

  private static func smoothstep(_ edges: Double) -> Double {
    let t = min(max(edges, 0), 1)
    return t * t * (3 - 2 * t)
  }
}

/// Colour conversions used by the colour wheels: sRGB, linear light, Oklab and HSV.
enum OklabColour {

  static func srgbToLinear(_ value: Double) -> Double {
    value < 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  static func linearToSRGB(_ value: Double) -> Double {
    let safe = max(value, 0)
    return safe < 0.0031308 ? safe * 12.92 : 1.055 * pow(safe, 1 / 2.4) - 0.055
  }

  static func linearToOklab(red: Double, green: Double, blue: Double) -> (
    l: Double, a: Double, b: Double
  ) {
    let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    let lc = signedCubeRoot(l)
    let mc = signedCubeRoot(m)
    let sc = signedCubeRoot(s)
    return (
      0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc,
      1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc,
      0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
    )
  }

  static func oklabToLinear(_ lab: (l: Double, a: Double, b: Double)) -> (
    red: Double, green: Double, blue: Double
  ) {
    let l = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
    let m = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
    let s = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
    let lc = l * l * l
    let mc = m * m * m
    let sc = s * s * s
    return (
      4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
      -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
      -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc
    )
  }

  static func hsvToRGB(hue: Double, saturation: Double, value: Double) -> (
    red: Double, green: Double, blue: Double
  ) {
    func channel(_ offset: Double) -> Double {
      let shifted = hue + offset
      let fraction = shifted - shifted.rounded(.down)
      let p = abs(fraction * 6 - 3)
      let mixed = min(max(p - 1, 0), 1)
      return value * ((1 - saturation) + saturation * mixed)
    }
    return (channel(0), channel(2.0 / 3.0), channel(1.0 / 3.0))
  }

  private static func signedCubeRoot(_ value: Double) -> Double {
    (value < 0 ? -1 : 1) * pow(abs(value), 1.0 / 3.0)
  }
}
