import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Distortion filters")
struct DistortionFilterTests {

  @Test("fish eye with a positive amplitude changes the picture")
  func fishEyeChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await FishEyeFilter(radius: 70, amplitude: 1).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("fish eye with amplitude 0 changes nothing")
  func fishEyeNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await FishEyeFilter(radius: 70, amplitude: 0).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("fish eye keeps the size at the extremes")
  func fishEyeExtremes() async throws {
    try await expectSizePreserved(FishEyeFilter(radius: 0, amplitude: 0))
    try await expectSizePreserved(FishEyeFilter(radius: 100, amplitude: 2))
  }

  @Test("bulge changes the picture inside its circle")
  func bulgeChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await BulgeDistortionFilter(radius: 0.5, scale: 0.5).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("bulge with scale 0 changes nothing")
  func bulgeNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await BulgeDistortionFilter(radius: 0.5, scale: 0).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("bulge keeps the size at the extremes")
  func bulgeExtremes() async throws {
    try await expectSizePreserved(BulgeDistortionFilter(radius: 0, scale: -1))
    try await expectSizePreserved(BulgeDistortionFilter(radius: 1, scale: 1))
  }

  @Test("swirl changes the picture when the angle is not 0")
  func swirlChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await SwirlDistortionFilter(radius: 0.5, angle: 1, centreX: 0.5, centreY: 0.5)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("swirl with angle 0 changes nothing")
  func swirlNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await SwirlDistortionFilter(radius: 0.5, angle: 0, centreX: 0.5, centreY: 0.5)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("swirl keeps the size at the extremes")
  func swirlExtremes() async throws {
    try await expectSizePreserved(
      SwirlDistortionFilter(radius: 0, angle: -1, centreX: 0.01, centreY: 0.01))
    try await expectSizePreserved(
      SwirlDistortionFilter(radius: 1, angle: 1, centreX: 1, centreY: 1))
  }

  @Test("twirl changes the picture when the angle is not 0")
  func twirlChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await TwirlFilter(angle: 90, centreX: 0.5, centreY: 0.5, radius: 0.5)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("twirl with angle 0 changes nothing")
  func twirlNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await TwirlFilter(angle: 0, centreX: 0.5, centreY: 0.5, radius: 0.5)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("twirl keeps the size at the extremes")
  func twirlExtremes() async throws {
    try await expectSizePreserved(TwirlFilter(angle: -360, centreX: 0, centreY: 0, radius: 0))
    try await expectSizePreserved(TwirlFilter(angle: 360, centreX: 1, centreY: 1, radius: 1))
  }

  @Test("pinch changes the picture when the amount is not 0")
  func pinchChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await PinchFilter(
      angle: 15, centreX: 0.5, centreY: 0.5, radius: 1, amount: 0.5
    ).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("pinch with angle 0 and amount 0 changes nothing")
  func pinchNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await PinchFilter(
      angle: 0, centreX: 0.5, centreY: 0.5, radius: 1, amount: 0
    ).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("pinch keeps the size at the extremes")
  func pinchExtremes() async throws {
    try await expectSizePreserved(
      PinchFilter(angle: 0, centreX: 0, centreY: 0, radius: 0, amount: -1))
    try await expectSizePreserved(
      PinchFilter(angle: 360, centreX: 1, centreY: 1, radius: 2, amount: 1))
  }

  @Test("kaleidoscope changes the picture")
  func kaleidoscopeChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await KaleidoscopeFilter(
      angle: 0, secondaryAngle: 0, centreX: 0.5, centreY: 0.5, sides: 5, radius: 0
    ).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("kaleidoscope keeps the size at the extremes")
  func kaleidoscopeExtremes() async throws {
    try await expectSizePreserved(
      KaleidoscopeFilter(
        angle: 0, secondaryAngle: 0, centreX: 0, centreY: 0, sides: 2, radius: 0))
    try await expectSizePreserved(
      KaleidoscopeFilter(
        angle: 360, secondaryAngle: 360, centreX: 1, centreY: 1, sides: 12, radius: 100))
  }

  @Test("sphere refraction changes the picture inside its circle")
  func sphereChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await SphereRefractionFilter(radius: 0.5, refractiveIndex: 0.71)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  // Шейдер GPUImage умножает цвет на step(distance, radius): вне круга результат чёрный, без тождества.
  @Test("sphere refraction paints the corners outside its circle black")
  func sphereOutsideIsBlack() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await SphereRefractionFilter(radius: 0.5, refractiveIndex: 0.71)
      .apply(to: picture)
    #expect(Array(output.pixels[0..<4]) == [0, 0, 0, 0])
  }

  @Test("glass sphere refraction keeps the size at the extremes")
  func sphereExtremes() async throws {
    try await expectSizePreserved(SphereRefractionFilter(radius: 0, refractiveIndex: 0))
    try await expectSizePreserved(SphereRefractionFilter(radius: 1, refractiveIndex: 1))
    try await expectSizePreserved(GlassSphereRefractionFilter(radius: 0, refractiveIndex: 0))
    try await expectSizePreserved(GlassSphereRefractionFilter(radius: 1, refractiveIndex: 1))
  }

  @Test("glass hex tiles change the picture and keep the size at the extremes")
  func glassHexTiles() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await GlassHexTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await expectSizePreserved(GlassHexTilesFilter(intensity: -1, distortion: -1, frequency: 1))
    try await expectSizePreserved(GlassHexTilesFilter(intensity: 1, distortion: 1, frequency: 40))
  }

  @Test("glass hex tiles with zero intensity and distortion change nothing")
  func glassHexNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await GlassHexTilesFilter(intensity: 0, distortion: 0, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("glass rect tiles change the picture and keep the size at the extremes")
  func glassRectTiles() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await GlassRectTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await expectSizePreserved(GlassRectTilesFilter(intensity: -1, distortion: -1, frequency: 1))
    try await expectSizePreserved(GlassRectTilesFilter(intensity: 1, distortion: 1, frequency: 40))
  }

  @Test("glass rect tiles with zero intensity and distortion change nothing")
  func glassRectNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await GlassRectTilesFilter(intensity: 0, distortion: 0, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("glass triangle tiles change the picture and keep the size at the extremes")
  func glassTriangleTiles() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await GlassTriangleTilesFilter(intensity: 0.2, distortion: 0.25, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await expectSizePreserved(
      GlassTriangleTilesFilter(intensity: -1, distortion: -1, frequency: 1))
    try await expectSizePreserved(
      GlassTriangleTilesFilter(intensity: 1, distortion: 1, frequency: 40))
  }

  @Test("glass triangle tiles with zero intensity and distortion change nothing")
  func glassTriangleNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await GlassTriangleTilesFilter(intensity: 0, distortion: 0, frequency: 8)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("logarithmic spiral changes the picture and keeps the size at the extremes")
  func logarithmicSpiral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await LogarithmicSpiralFilter(count: 2, intensity: 1).apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await expectSizePreserved(LogarithmicSpiralFilter(count: 1, intensity: -4))
    try await expectSizePreserved(LogarithmicSpiralFilter(count: 32, intensity: 4))
  }

  @Test("spiral droste changes the picture and keeps the size at the extremes")
  func spiralDroste() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await SpiralDrosteFilter(intensity: 2, distortion: 0.2).apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await expectSizePreserved(SpiralDrosteFilter(intensity: 1.1, distortion: -1))
    try await expectSizePreserved(SpiralDrosteFilter(intensity: 8, distortion: 1))
  }

  @Test("ripple changes the picture when the amplitude is not 0")
  func rippleChanges() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await RippleFilter(
      xAmplitude: 5, xWavelength: 16, yAmplitude: 5, yWavelength: 16
    ).apply(to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("ripple with zero amplitudes changes nothing")
  func rippleNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 16, height: 16)
    let output = try await RippleFilter(
      xAmplitude: 0, xWavelength: 16, yAmplitude: 0, yWavelength: 16
    ).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("ripple keeps the size at the extremes")
  func rippleExtremes() async throws {
    try await expectSizePreserved(
      RippleFilter(xAmplitude: 0, xWavelength: 1, yAmplitude: 0, yWavelength: 1))
    try await expectSizePreserved(
      RippleFilter(xAmplitude: 100, xWavelength: 200, yAmplitude: 100, yWavelength: 200))
  }

  /// Одно изображение 1×1 и 5×3: результат того же размера, без падения.
  private func expectSizePreserved(_ filter: any Filter) async throws {
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      let output = try await filter.apply(to: picture)
      #expect(output.width == picture.width)
      #expect(output.height == picture.height)
      #expect(output.pixels.count == picture.pixels.count)
    }
  }
}
