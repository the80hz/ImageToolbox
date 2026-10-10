import Foundation

/// Draws the FastNoise presets with the native texture code of the Android fast-noise module
/// (see `NativeTextureRenderer`). The preset's id selects its texture code, parameters and colours
/// from `NativeTextureTable`, so the picture follows the Android code step by step.
enum FastNoiseRenderer {
  /// Renders a FastNoise preset as an opaque picture. Returns nil when the preset is not one of the
  /// native textures.
  static func render(_ preset: TexturePreset, seed: UInt64, width: Int, height: Int) -> RasterImage?
  {
    guard let entry = NativeTextureTable.entry(for: preset.id) else { return nil }
    let pixels = NativeTextureRenderer.render(
      code: entry.code,
      width: width,
      height: height,
      seed: Int32(truncatingIfNeeded: seed),
      parameters: entry.parameters,
      colours: entry.colours)
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// ARGB to red, green and blue in 0...1.
  static func colour(_ argb: UInt32) -> SIMD3<Double> {
    SIMD3(
      Double((argb >> 16) & 0xFF) / 255,
      Double((argb >> 8) & 0xFF) / 255,
      Double(argb & 0xFF) / 255)
  }

  /// Piecewise linear blend through the colours, so 3 colours give two segments and 4 give three.
  static func ramp(_ colours: [SIMD3<Double>], at t: Double) -> SIMD3<Double> {
    guard colours.count > 1 else { return colours.first ?? .zero }
    let position = min(max(t, 0), 1) * Double(colours.count - 1)
    let index = min(Int(position), colours.count - 2)
    let fraction = position - Double(index)
    return colours[index] + (colours[index + 1] - colours[index]) * fraction
  }
}
