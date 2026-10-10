import Foundation

/// Curves applied to cyan, magenta, yellow and black, the four components of the CMYK model.
/// Each curve maps 0...1 to 0...1.
public struct CMYKCurves: Equatable, Sendable {
  public var cyan: ToneCurve
  public var magenta: ToneCurve
  public var yellow: ToneCurve
  public var black: ToneCurve

  public init(
    cyan: ToneCurve = .identity, magenta: ToneCurve = .identity,
    yellow: ToneCurve = .identity, black: ToneCurve = .identity
  ) {
    self.cyan = cyan
    self.magenta = magenta
    self.yellow = yellow
    self.black = black
  }

  public var isIdentity: Bool {
    cyan == .identity && magenta == .identity && yellow == .identity && black == .identity
  }
}

/// Curves applied to the Lab components of a pixel. Each component is first encoded to 0...1 the
/// way the Android app does it: lightness divided by 100, and a and b shifted by 128 and divided
/// by 255.
public struct LabCurves: Equatable, Sendable {
  public var lightness: ToneCurve
  public var a: ToneCurve
  public var b: ToneCurve

  public init(lightness: ToneCurve = .identity, a: ToneCurve = .identity, b: ToneCurve = .identity)
  {
    self.lightness = lightness
    self.a = a
    self.b = b
  }

  public var isIdentity: Bool {
    lightness == .identity && a == .identity && b == .identity
  }
}

/// A curve as 256 bytes, read with linear interpolation between neighbours. The Android app stores
/// its curves the same way, in a 256-texel texture.
struct SampledCurve {
  private let values: [Double]

  init(_ curve: ToneCurve) {
    values = curve.lookupTable().map { Double($0) / 255 }
  }

  func value(_ input: Double) -> Double {
    let position = min(max(input, 0), 1) * 255
    let lower = Int(position.rounded(.down))
    let upper = min(lower + 1, 255)
    let fraction = position - Double(lower)
    return values[lower] * (1 - fraction) + values[upper] * fraction
  }
}

/// CMYK curves applied to one straight sRGB pixel. Components are 0...1.
struct CMYKTransform {
  private let cyan: SampledCurve
  private let magenta: SampledCurve
  private let yellow: SampledCurve
  private let black: SampledCurve

  init(_ curves: CMYKCurves) {
    cyan = SampledCurve(curves.cyan)
    magenta = SampledCurve(curves.magenta)
    yellow = SampledCurve(curves.yellow)
    black = SampledCurve(curves.black)
  }

  func apply(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double)
  {
    let key = 1 - max(red, green, blue)
    let denominator = max(1 - key, 0.00001)
    let c = cyan.value((1 - red - key) / denominator)
    let m = magenta.value((1 - green - key) / denominator)
    let y = yellow.value((1 - blue - key) / denominator)
    let k = black.value(key)
    return (
      min(max((1 - c) * (1 - k), 0), 1),
      min(max((1 - m) * (1 - k), 0), 1),
      min(max((1 - y) * (1 - k), 0), 1)
    )
  }
}

/// Lab curves applied to one straight sRGB pixel, using the D65 conversion of the Android shader.
struct LabTransform {
  private let lightness: SampledCurve
  private let a: SampledCurve
  private let b: SampledCurve

  init(_ curves: LabCurves) {
    lightness = SampledCurve(curves.lightness)
    a = SampledCurve(curves.a)
    b = SampledCurve(curves.b)
  }

  func apply(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double)
  {
    let linearRed = OklabColour.srgbToLinear(red)
    let linearGreen = OklabColour.srgbToLinear(green)
    let linearBlue = OklabColour.srgbToLinear(blue)
    let x = 0.4124564 * linearRed + 0.3575761 * linearGreen + 0.1804375 * linearBlue
    let y = 0.2126729 * linearRed + 0.7151522 * linearGreen + 0.0721750 * linearBlue
    let z = 0.0193339 * linearRed + 0.1191920 * linearGreen + 0.9503041 * linearBlue

    let fx = Self.forward(x / 0.95047)
    let fy = Self.forward(y)
    let fz = Self.forward(z / 1.08883)
    let encodedL = (116 * fy - 16) / 100
    let encodedA = (500 * (fx - fy) + 128) / 255
    let encodedB = (200 * (fy - fz) + 128) / 255

    let curvedL = lightness.value(min(max(encodedL, 0), 1)) * 100
    let curvedA = a.value(min(max(encodedA, 0), 1)) * 255 - 128
    let curvedB = b.value(min(max(encodedB, 0), 1)) * 255 - 128

    let newFY = (curvedL + 16) / 116
    let newFX = newFY + curvedA / 500
    let newFZ = newFY - curvedB / 200
    let newX = 0.95047 * Self.inverse(newFX)
    let newY = Self.inverse(newFY)
    let newZ = 1.08883 * Self.inverse(newFZ)

    let outRed = 3.2404542 * newX - 1.5371385 * newY - 0.4985314 * newZ
    let outGreen = -0.9692660 * newX + 1.8760108 * newY + 0.0415560 * newZ
    let outBlue = 0.0556434 * newX - 0.2040259 * newY + 1.0572252 * newZ
    return (
      min(max(OklabColour.linearToSRGB(outRed), 0), 1),
      min(max(OklabColour.linearToSRGB(outGreen), 0), 1),
      min(max(OklabColour.linearToSRGB(outBlue), 0), 1)
    )
  }

  private static func forward(_ value: Double) -> Double {
    value > 0.008856 ? pow(value, 1.0 / 3.0) : 7.787 * value + 16.0 / 116.0
  }

  private static func inverse(_ value: Double) -> Double {
    let cube = value * value * value
    return cube > 0.008856 ? cube : (value - 16.0 / 116.0) / 7.787
  }
}
