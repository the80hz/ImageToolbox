import CoreGraphics
import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Colour wheels in Oklab")
struct ColorWheelTests {

  @Test("identity wheels leave every pixel unchanged")
  func identityIsNoOp() throws {
    let source = TestImages.solid(RGBA(red: 90, green: 140, blue: 200), width: 4, height: 4)
    let raster = try #require(RasterImage(source))
    let output = CurveRenderer.apply(raster, curves: .identity, wheels: .identity)
    #expect(output.pixels == raster.pixels)
  }

  @Test("a shadows wheel pointed at blue cools a dark colour")
  func shadowsTowardBlue() {
    // The blue hue sits at direction (0.866, 0.5): hue 2/3 in the wheel's angle convention.
    let wheels = ColorWheels(shadows: ColorWheelPoint(x: 0.866, y: 0.5))
    let balances = wheels.balances()
    let adjusted = wheels.adjusted(
      red: 40.0 / 255, green: 40.0 / 255, blue: 40.0 / 255, balances: balances)
    #expect(adjusted.blue > adjusted.red)
    #expect(adjusted.blue > adjusted.green)
  }

  @Test("a shadows wheel leaves white highlights neutral")
  func shadowsWheelLeavesHighlightsNeutral() {
    let wheels = ColorWheels(shadows: ColorWheelPoint(x: 0.866, y: 0.5))
    let balances = wheels.balances()
    let light = wheels.adjusted(
      red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255, balances: balances)
    // A white highlight has no shadow weight, so it stays neutral.
    #expect(abs(light.red - light.blue) < 0.02)
  }

  @Test("the wheel length is limited to 1 and the direction is kept")
  func normalisedPoint() {
    let point = ColorWheelPoint(x: 3, y: 4).normalized
    #expect(abs(point.x - 0.6) < 1e-12)
    #expect(abs(point.y - 0.8) < 1e-12)
    #expect(ColorWheelPoint(x: 0.2, y: 0.1).normalized == ColorWheelPoint(x: 0.2, y: 0.1))
  }

  @Test("edges are clamped to 0...1")
  func edgesClamped() {
    #expect(ColorWheels(edges: 2).edges == 1)
    #expect(ColorWheels(edges: -1).edges == 0)
    #expect(ColorWheels.identity.edges == ColorWheels.defaultEdges)
  }

  @Test("alpha is kept when the wheels change colour")
  func alphaKept() throws {
    let source = TestImages.image(width: 2, height: 2) { _, _ in
      RGBA(red: 40, green: 40, blue: 40, alpha: 100)
    }
    let raster = try #require(RasterImage(source))
    let wheels = ColorWheels(shadows: ColorWheelPoint(x: 0.866, y: 0.5))
    let output = CurveRenderer.apply(raster, curves: .identity, wheels: wheels)
    #expect(output.pixel(x: 0, y: 0).alpha == 100)
  }

  @Test("hue 0 is pure red and hue 1/3 is green")
  func hsvHues() {
    let red = OklabColour.hsvToRGB(hue: 0, saturation: 1, value: 1)
    #expect(abs(red.red - 1) < 1e-12 && red.green < 1e-12 && red.blue < 1e-12)
    let green = OklabColour.hsvToRGB(hue: 1.0 / 3.0, saturation: 1, value: 1)
    #expect(abs(green.green - 1) < 1e-9 && green.red < 1e-9 && green.blue < 1e-9)
  }

  @Test("sRGB and Oklab conversions round-trip")
  func conversionsRoundTrip() {
    for value in [0.0, 0.02, 0.2, 0.5, 0.9, 1.0] {
      let linear = OklabColour.srgbToLinear(value)
      #expect(abs(OklabColour.linearToSRGB(linear) - value) < 1e-9)
    }
    // The Oklab matrices are published to 10 digits, so the round trip is exact to about 1e-7.
    let lab = OklabColour.linearToOklab(red: 0.3, green: 0.6, blue: 0.1)
    let back = OklabColour.oklabToLinear(lab)
    #expect(abs(back.red - 0.3) < 1e-6)
    #expect(abs(back.green - 0.6) < 1e-6)
    #expect(abs(back.blue - 0.1) < 1e-6)
  }
}
