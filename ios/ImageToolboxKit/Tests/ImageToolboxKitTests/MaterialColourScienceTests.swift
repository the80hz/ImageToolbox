import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("CAM16, HCT, tonal palettes and the Material 3 scheme")
struct MaterialColourScienceTests {

  private static func maxChannelDifference(_ a: RGBA, _ b: RGBA) -> Int {
    max(
      abs(Int(a.red) - Int(b.red)), abs(Int(a.green) - Int(b.green)),
      abs(Int(a.blue) - Int(b.blue)))
  }

  /// A coarse grid over the sRGB cube, plus the corners.
  private static let grid: [RGBA] = {
    var colours: [RGBA] = []
    for r in stride(from: 0, through: 255, by: 15) {
      for g in stride(from: 0, through: 255, by: 15) {
        for b in stride(from: 0, through: 255, by: 15) {
          colours.append(RGBA(red: UInt8(r), green: UInt8(g), blue: UInt8(b)))
        }
      }
    }
    return colours
  }()

  // MARK: CAM16

  @Test("CAM16 of the sRGB primaries and white matches the published values")
  func cam16ReferenceValues() {
    let cases: [(UInt32, Double, Double, Double)] = [
      (0xFFFF_0000, 27.408, 113.357, 46.445),
      (0xFF00_FF00, 142.139, 108.410, 79.331),
      (0xFF00_00FF, 282.788, 87.230, 25.465),
      (0xFFFF_FFFF, 209.492, 2.869, 100.0),
    ]
    for (argb, hue, chroma, lightness) in cases {
      let cam = Cam16(argb: argb)
      #expect(abs(cam.hue - hue) < 0.005)
      #expect(abs(cam.chroma - chroma) < 0.005)
      #expect(abs(cam.j - lightness) < 0.005)
    }
    let black = Cam16(argb: 0xFF00_0000)
    #expect(black.j == 0 && black.chroma == 0)
  }

  @Test("CAM16 and HCT round trips return the sRGB colour within one unit")
  func roundTrips() {
    var worstCam = 0
    var worstHct = 0
    for colour in Self.grid {
      let argb = MaterialColour.argb(colour)
      worstCam = max(
        worstCam,
        Self.maxChannelDifference(colour, MaterialColour.rgba(Cam16(argb: argb).argb)))
      let hct = Hct(colour)
      let back = Hct(hue: hct.hue, chroma: hct.chroma, tone: hct.tone).rgba
      worstHct = max(worstHct, Self.maxChannelDifference(colour, back))
    }
    #expect(worstCam <= 1)
    #expect(worstHct <= 1)
  }

  @Test("the solver returns the requested tone, and never more chroma than asked for")
  func solverHonoursToneAndChroma() {
    for hue in stride(from: 0.0, to: 360.0, by: 30.0) {
      for chroma in [8.0, 36.0, 80.0, 150.0] {
        for tone in stride(from: 5.0, through: 95.0, by: 10.0) {
          let solved = Hct(hue: hue, chroma: chroma, tone: tone)
          #expect(abs(solved.tone - tone) < 0.6, "tone at hue \(hue) chroma \(chroma)")
          // 8-bit rounding can add a little chroma; out-of-gamut requests lose a lot.
          #expect(solved.chroma < chroma + 2.5, "chroma at hue \(hue) tone \(tone)")
        }
      }
    }
  }

  @Test("a request without chroma gives an exact grey of the requested tone")
  func zeroChromaIsGrey() {
    for tone in stride(from: 0.0, through: 100.0, by: 5.0) {
      let solved = Hct(hue: 123, chroma: 0, tone: tone)
      let colour = solved.rgba
      #expect(colour.red == colour.green && colour.green == colour.blue)
      #expect(abs(solved.tone - tone) < 0.4)
      // CAM16 reads a neutral sRGB grey as slightly chromatic (white is 2.87), so chroma is
      // small but not zero.
      #expect(solved.chroma < 3.0)
    }
  }

  @Test("an in-gamut request keeps its chroma and hue")
  func inGamutRequestIsExact() {
    let solved = Hct(hue: 270, chroma: 30, tone: 50)
    #expect(abs(solved.chroma - 30) < 1.0)
    #expect(abs(solved.hue - 270) < 1.0)
    #expect(abs(solved.tone - 50) < 0.5)
  }

  @Test("tone zero and one hundred are black and white, and tone 50 is the mid grey")
  func toneExtremes() {
    #expect(Hct(hue: 120, chroma: 60, tone: 0).rgba == RGBA(red: 0, green: 0, blue: 0))
    #expect(Hct(hue: 120, chroma: 60, tone: 100).rgba == RGBA(red: 255, green: 255, blue: 255))
    #expect(Hct(hue: 120, chroma: 0, tone: 50).rgba == RGBA(red: 119, green: 119, blue: 119))
  }

  // MARK: Tonal palettes

  @Test("tones of a palette get monotonically lighter")
  func paletteTonesAreMonotonic() {
    for hue in [0.0, 60.0, 130.0, 200.0, 270.0, 320.0] {
      let palette = TonalPalette(hue: hue, chroma: 40)
      var previous = -1.0
      for tone in stride(from: 0.0, through: 100.0, by: 5.0) {
        let current = palette.hct(tone: tone).tone
        #expect(current > previous, "hue \(hue) tone \(tone)")
        previous = current
      }
    }
  }

  @Test("a palette built from a colour has the hue and chroma of that colour")
  func paletteFromColour() {
    let colour = RGBA(red: 0x67, green: 0x50, blue: 0xA4)
    let hct = Hct(colour)
    let palette = TonalPalette(colour)
    #expect(palette.hue == hct.hue && palette.chroma == hct.chroma)
    #expect(palette.keyColor == hct)
    // Tone 40 of the palette lies on the colour itself, whose tone is 40.08.
    #expect(Self.maxChannelDifference(palette.colour(tone: 40), colour) <= 2)
  }

  @Test("the key colour of a hue and chroma pair reaches that chroma where the gamut allows")
  func keyColour() {
    let key = TonalPalette(hue: 270, chroma: 36).keyColor
    #expect(abs(key.chroma - 36) < 1.5)
    #expect(abs(key.hue - 270) < 3)
  }

  // MARK: Contrast and tone solving

  @Test("contrast ratios follow the tone scale")
  func contrastRatios() {
    #expect(abs(Contrast.ratio(ofTones: 0, 100) - 21) < 1e-9)
    #expect(Contrast.ratio(ofTones: 50, 50) == 1)
    for tone in [20.0, 40.0, 60.0, 80.0] {
      for ratio in [3.0, 4.5, 7.0] {
        let lighter = Contrast.lighter(tone: tone, ratio: ratio)
        if lighter >= 0 {
          #expect(Contrast.ratio(ofTones: tone, lighter) >= ratio - 0.02)
        }
        let darker = Contrast.darker(tone: tone, ratio: ratio)
        if darker >= 0 {
          #expect(Contrast.ratio(ofTones: tone, darker) >= ratio - 0.02)
        }
      }
    }
  }

  @Test("the contrast curve interpolates between its four levels")
  func contrastCurve() {
    let curve = ContrastCurve(3, 4.5, 7, 11)
    #expect(curve.value(at: -2) == 3)
    #expect(curve.value(at: -1) == 3)
    #expect(curve.value(at: 0) == 4.5)
    #expect(curve.value(at: 0.5) == 7)
    #expect(curve.value(at: 1) == 11)
    #expect(abs(curve.value(at: -0.5) - 3.75) < 1e-9)
    #expect(abs(curve.value(at: 0.75) - 9) < 1e-9)
  }

  // MARK: Reference scheme

  /// The stock tonal-spot scheme of Material Color Utilities for the default Material 3 seed,
  /// as the Material Theme Builder shows it.
  @Test("stock tonal spot for the seed #6750A4 gives the Material Theme Builder colours")
  func stockTonalSpotReference() {
    let seed = Hct(RGBA(hex: "#6750A4")!)
    func roles(dark: Bool) -> [MaterialColourRole: String] {
      let scheme = DynamicScheme(style: .tonalSpot, source: seed, isDark: dark, contrastLevel: 0)
      return Dictionary(
        uniqueKeysWithValues: MaterialColourRole.allCases.map {
          ($0, MaterialColour.rgba($0.definition.argb(scheme)).hexString)
        })
    }
    let light = roles(dark: false)
    #expect(light[.primary] == "#65558F")
    #expect(light[.onPrimary] == "#FFFFFF")
    #expect(light[.primaryContainer] == "#E9DDFF")
    #expect(light[.secondary] == "#625B71")
    #expect(light[.secondaryContainer] == "#E8DEF8")
    #expect(light[.onSecondaryContainer] == "#4A4458")
    #expect(light[.tertiary] == "#7E5260")
    #expect(light[.tertiaryContainer] == "#FFD9E3")
    #expect(light[.error] == "#BA1A1A")
    #expect(light[.errorContainer] == "#FFDAD6")
    #expect(light[.onErrorContainer] == "#93000A")
    #expect(light[.onSurface] == "#1D1B20")

    let dark = roles(dark: true)
    #expect(dark[.primary] == "#CFBDFE")
    #expect(dark[.onPrimaryContainer] == "#E9DDFF")
    #expect(dark[.surface] == "#141218")
    #expect(dark[.onSurface] == "#E6E0E9")
    #expect(dark[.error] == "#FFB4AB")
    #expect(dark[.errorContainer] == "#93000A")
  }

  @Test("the Android pipeline keeps the seed as the primary role of a light scheme")
  func androidPipelineKeepsSeed() {
    let seed = RGBA(hex: "#6750A4")!
    let light = MaterialColourScheme.from(seedRGB: seed, dark: false)
    let dark = MaterialColourScheme.from(seedRGB: seed, dark: true)
    #expect(light.seed == seed)
    // Android builds the primary palette from the seed's own hue and chroma, so tone 40 lies
    // on the seed (tone 40.08).
    #expect(Self.maxChannelDifference(light[.primary], seed) <= 3)
    // Dark primary is the light tone 80 of the same palette, so it is lighter.
    #expect(Hct(dark[.primary]).tone > Hct(light[.primary]).tone + 30)
    #expect(Hct(light[.onPrimary]).tone > 90)
    #expect(light[.primary].contrastRatio(with: light[.onPrimary]) >= 4.5)
    #expect(dark[.primary].contrastRatio(with: dark[.onPrimary]) >= 4.5)
  }

  @Test("every style, contrast level and brightness gives readable text colours")
  func allStylesAreReadable() {
    let seed = RGBA(hex: "#3F8F5A")!
    for style in MaterialSchemeStyle.allCases {
      for dark in [false, true] {
        var previous = 0.0
        for contrast in [-1.0, 0.0, 0.5, 1.0] {
          let scheme = MaterialColourScheme.from(
            seedRGB: seed, dark: dark,
            options: .init(style: style, contrastLevel: contrast))
          let ratio = scheme[.onSurface].contrastRatio(with: scheme[.surface])
          #expect(ratio >= 4.5, "\(style) dark \(dark) contrast \(contrast)")
          #expect(ratio >= previous - 0.01, "\(style) dark \(dark) contrast \(contrast)")
          previous = ratio
          let onPrimary = scheme[.onPrimary].contrastRatio(with: scheme[.primary])
          #expect(onPrimary >= 3, "\(style) dark \(dark) contrast \(contrast)")
        }
      }
    }
  }

  @Test("the stock monochrome scheme is grey in every role but the error ones")
  func stockMonochromeIsGrey() {
    let source = Hct(RGBA(hex: "#D03030")!)
    for dark in [false, true] {
      let scheme = DynamicScheme(
        style: .monochrome, source: source, isDark: dark, contrastLevel: 0)
      for role in MaterialColourRole.allCases where !role.rawValue.lowercased().contains("error") {
        let colour = MaterialColour.rgba(role.definition.argb(scheme))
        #expect(colour.red == colour.green && colour.green == colour.blue, "\(role) dark \(dark)")
      }
    }
  }

  @Test("the Android pipeline keeps the accent roles of monochrome grey, and tints the surfaces")
  func androidMonochrome() {
    let scheme = MaterialColourScheme.from(
      seedRGB: RGBA(hex: "#D03030")!, dark: false, options: .init(style: .monochrome))
    for role in [MaterialColourRole.primary, .secondary, .tertiary] {
      let colour = scheme[role]
      #expect(colour.red == colour.green && colour.green == colour.blue, "\(role)")
    }
    // The app derives its light surfaces from the hue and chroma CAM16 reads in the grey
    // surface (about 2.9), scaled up to 1.8 times, so they are not pure grey. This matches
    // the Android output and stays small.
    let variant = scheme[.surfaceVariant]
    #expect(
      Self.maxChannelDifference(
        variant, RGBA(red: variant.red, green: variant.red, blue: variant.red)) <= 8)
  }
}
