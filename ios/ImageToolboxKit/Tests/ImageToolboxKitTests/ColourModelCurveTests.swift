import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("CMYK and Lab curves, and the adjustment stages")
struct ColourModelCurveTests {

  private static func flat(_ height: Double) -> ToneCurve {
    ToneCurve(points: [CurvePoint(x: 0, y: height), CurvePoint(x: 1, y: height)])
  }

  @Test("identity CMYK and Lab curves return the colour, within one byte step")
  func identityRoundTrip() {
    let cmyk = CMYKTransform(CMYKCurves())
    let out = cmyk.apply(red: 0.2, green: 0.5, blue: 0.8)
    #expect(abs(out.red - 0.2) < 0.01)
    #expect(abs(out.green - 0.5) < 0.01)
    #expect(abs(out.blue - 0.8) < 0.01)

    let lab = LabTransform(LabCurves())
    let back = lab.apply(red: 0.2, green: 0.5, blue: 0.8)
    #expect(abs(back.red - 0.2) < 0.02)
    #expect(abs(back.green - 0.5) < 0.02)
    #expect(abs(back.blue - 0.8) < 0.02)
  }

  @Test("a black curve at zero removes the key ink, so black becomes white")
  func blackCurveToZero() {
    let curves = CMYKCurves(black: Self.flat(0))
    let out = CMYKTransform(curves).apply(red: 0, green: 0, blue: 0)
    #expect(out.red > 0.99 && out.green > 0.99 && out.blue > 0.99)
  }

  @Test("a lightness curve at zero makes any colour black")
  func lightnessToZero() {
    let curves = LabCurves(lightness: Self.flat(0))
    let out = LabTransform(curves).apply(red: 0.8, green: 0.8, blue: 0.8)
    #expect(out.red < 0.05 && out.green < 0.05 && out.blue < 0.05)
  }

  @Test("the default adjustments are the identity and each stage breaks it")
  func identityFlags() {
    #expect(CurveAdjustments().isIdentity)
    #expect(!CurveAdjustments(cmyk: CMYKCurves(cyan: Self.flat(0.3))).isIdentity)
    #expect(!CurveAdjustments(lab: LabCurves(a: Self.flat(0.3))).isIdentity)
  }

  @Test("the adjustment stages run in the Android order and keep alpha")
  func stagesRun() throws {
    // RGB inverts the red channel first. CMYK then has no effect, so the result matches the RGB
    // curves alone.
    let source = TestImages.image(width: 2, height: 2) { _, _ in
      RGBA(red: 100, green: 50, blue: 25, alpha: 128)
    }
    let raster = try #require(RasterImage(source))
    let inverted = ToneCurve(points: [CurvePoint(x: 0, y: 1), CurvePoint(x: 1, y: 0)])
    let adjustments = CurveAdjustments(
      curves: CurveSet(red: inverted),
      cmyk: CMYKCurves(cyan: .identity))
    let output = CurveRenderer.apply(raster, adjustments: adjustments)
    #expect(output.pixel(x: 0, y: 0).alpha == 128)
    // Straight red of the source is about 199, so the inverse is about 56.
    #expect(abs(Int(output.pixel(x: 0, y: 0).red) - 56) <= 3)
  }
}
