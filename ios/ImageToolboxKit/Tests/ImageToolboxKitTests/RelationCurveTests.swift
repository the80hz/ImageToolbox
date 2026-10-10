import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Hue, saturation and value curves")
struct RelationCurveTests {

  /// A curve at one height across the whole range.
  private static func flat(_ height: Double) -> ToneCurve {
    ToneCurve(points: [CurvePoint(x: 0, y: height), CurvePoint(x: 1, y: height)])
  }

  private static func render(
    _ red: UInt8, _ green: UInt8, _ blue: UInt8, alpha: UInt8 = 255,
    kind: RelationCurveKind, curve: ToneCurve
  ) throws -> RasterImage {
    let source = TestImages.solid(
      RGBA(red: red, green: green, blue: blue, alpha: alpha), width: 2, height: 2)
    var relations = RelationCurves()
    relations[kind] = curve
    let raster = try #require(RasterImage(source))
    return CurveRenderer.apply(raster, curves: .identity, relations: relations)
  }

  @Test("neutral curves are identity and are not stored")
  func neutralIsIdentity() {
    var relations = RelationCurves()
    #expect(relations.isIdentity)
    relations[.hueVsSat] = RelationCurves.neutral
    #expect(relations.isIdentity)
    relations[.hueVsSat] = Self.flat(0.9)
    #expect(!relations.isIdentity)
    relations[.hueVsSat] = RelationCurves.neutral
    #expect(relations.isIdentity)
  }

  @Test("a saturation curve above neutral makes a colour more saturated")
  func saturationUp() throws {
    let output = try Self.render(200, 100, 100, kind: .hueVsSat, curve: Self.flat(0.9))
    // Saturation grows from 0.5 to about 0.77, so the green channel falls from 100 to about 47.
    #expect(output.pixel(x: 0, y: 0).green < 70)
    #expect(output.pixel(x: 0, y: 0).red == 200)
  }

  @Test("a saturation curve at zero removes all colour")
  func saturationDown() throws {
    let output = try Self.render(200, 100, 40, kind: .satVsSat, curve: Self.flat(0))
    let pixel = output.pixel(x: 0, y: 0)
    #expect(abs(Int(pixel.red) - Int(pixel.green)) <= 1)
    #expect(abs(Int(pixel.green) - Int(pixel.blue)) <= 1)
  }

  @Test("a hue curve shifts hue by the change from neutral, in turns")
  func hueShift() throws {
    // A change of one third of a turn turns red into green.
    let output = try Self.render(255, 0, 0, kind: .hueVsHue, curve: Self.flat(0.5 + 1.0 / 3.0))
    let pixel = output.pixel(x: 0, y: 0)
    #expect(pixel.green > 200)
    #expect(pixel.red < 50)
  }

  @Test("a luma curve at the top brightens a saturated colour towards white")
  func lumaUp() throws {
    let output = try Self.render(200, 100, 100, kind: .hueVsLuma, curve: Self.flat(1))
    let pixel = output.pixel(x: 0, y: 0)
    #expect(pixel.red > 240 && pixel.green > 240 && pixel.blue > 240)
  }

  @Test("alpha is kept when a relation curve changes colour")
  func alphaKept() throws {
    let output = try Self.render(
      100, 50, 25, alpha: 128, kind: .hueVsHue, curve: Self.flat(0.6))
    #expect(output.pixel(x: 0, y: 0).alpha == 128)
  }

  @Test("only the curves that differ from neutral are applied")
  func onlyChangedTables() {
    var relations = RelationCurves()
    #expect(relations.changeTables().isEmpty)
    relations[.lumaVsHue] = Self.flat(0.7)
    let tables = relations.changeTables()
    #expect(tables.count == 1)
    #expect(tables.first?.kind == .lumaVsHue)
    #expect(tables.first?.table.count == 256)
  }

  @Test("RGB to HSV and back returns the same colour")
  func hsvRoundTrip() {
    for (red, green, blue) in [(0.9, 0.2, 0.4), (0.1, 0.1, 0.1), (0.5, 0.5, 0.9), (0, 0, 0)] {
      let hsv = RelationAdjuster.toHSV(red: red, green: green, blue: blue)
      let back = RelationAdjuster.toRGB(hsv)
      #expect(abs(back.red - red) < 1e-9)
      #expect(abs(back.green - green) < 1e-9)
      #expect(abs(back.blue - blue) < 1e-9)
    }
  }
}
