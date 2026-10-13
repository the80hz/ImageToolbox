import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Raymarch background and environment")
struct TextureRaymarchTests {
  private func catalogue(_ id: String) throws -> TexturePreset {
    try #require(TexturePresets.preset(id: id))
  }

  /// A raymarch preset with the given colours, from the catalogue entry of the same scene.
  private func withColours(_ preset: TexturePreset, _ colours: [UInt32]) -> TexturePreset {
    TexturePreset(
      id: preset.id, category: preset.category, source: preset.source, scale: preset.scale,
      colours: colours, parameters: preset.parameters)
  }

  /// The pixel at `(x, y)` as 0xAARRGGBB.
  private func argb(_ image: RasterImage, _ x: Int, _ y: Int) -> UInt32 {
    let index = (y * image.width + x) * 4
    return UInt32(image.pixels[index + 3]) << 24 | UInt32(image.pixels[index]) << 16
      | UInt32(image.pixels[index + 1]) << 8 | UInt32(image.pixels[index + 2])
  }

  /// A picture of one colour, `width` by `height`, as an environment image.
  private func flat(_ colour: (UInt8, UInt8, UInt8), width: Int = 16, height: Int = 8)
    -> RasterImage
  {
    var pixels = [UInt8]()
    for _ in 0..<(width * height) {
      pixels += [colour.0, colour.1, colour.2, 255]
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  @Test("a ray that misses the scene is transparent by default, as on Android")
  func transparentBackground() throws {
    let image = try #require(
      TexturePresetRenderer.render(try catalogue("Sphere3D"), seed: 1, width: 64, height: 64))
    #expect(argb(image, 0, 0) == 0x0000_0000)
    #expect(argb(image, 63, 63) == 0x0000_0000)
    // The sphere is in the middle and is opaque there.
    #expect(argb(image, 32, 32) >> 24 == 255)
  }

  @Test("the second colour is the background, drawn opaque when it has alpha")
  func backgroundColour() throws {
    let preset = withColours(try catalogue("Cube3D"), [0xFFB9_ABE5, 0xFF10_2030])
    let image = try #require(
      TexturePresetRenderer.render(preset, seed: 1, width: 64, height: 64))
    #expect(argb(image, 0, 0) == 0xff10_2030)
  }

  @Test("the first colour's alpha is the alpha of the object")
  func objectAlpha() throws {
    let preset = withColours(try catalogue("Sphere3D"), [0x80B9_ABE5, 0x0000_0000])
    let image = try #require(
      TexturePresetRenderer.render(preset, seed: 1, width: 64, height: 64))
    #expect(argb(image, 32, 32) >> 24 == 0x80)
    #expect(argb(image, 0, 0) >> 24 == 0)
  }

  @Test("an environment image replaces the sky in the reflections")
  func environmentImage() throws {
    let preset = try catalogue("Sphere3D")
    let sky = try #require(
      TexturePresetRenderer.render(preset, seed: 1, width: 64, height: 64))
    let dark = try #require(
      TexturePresetRenderer.render(
        preset, seed: 1, width: 64, height: 64, environment: flat((0, 0, 0))))
    #expect(sky.pixels != dark.pixels)
    let skyCentre = argb(sky, 32, 32)
    let darkCentre = argb(dark, 32, 32)
    let skySum = (skyCentre >> 16 & 0xff) + (skyCentre >> 8 & 0xff) + (skyCentre & 0xff)
    let darkSum = (darkCentre >> 16 & 0xff) + (darkCentre >> 8 & 0xff) + (darkCentre & 0xff)
    #expect(darkSum < skySum)
  }

  @Test("a transparent environment texel adds no light")
  func transparentEnvironment() throws {
    let preset = try catalogue("Sphere3D")
    let empty = RasterImage(
      width: 16, height: 8, pixels: [UInt8](repeating: 0, count: 16 * 8 * 4))
    let image = try #require(
      TexturePresetRenderer.render(
        preset, seed: 1, width: 32, height: 32, environment: empty))
    let black = try #require(
      TexturePresetRenderer.render(
        preset, seed: 1, width: 32, height: 32, environment: flat((0, 0, 0))))
    #expect(image.pixels == black.pixels)
  }
}
