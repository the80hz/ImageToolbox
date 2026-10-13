import Foundation

/// Renders any texture preset of the catalogue on the CPU.
public enum TexturePresetRenderer {
  /// Draws a preset as a `width` x `height` picture with row 0 at the top.
  ///
  /// Most presets are opaque. A raymarch background is transparent by default, as on Android, and
  /// an FBM with an amount below one is partly transparent.
  ///
  /// The seed drives every random choice of the preset: noise permutations, feature points, and
  /// the shuffled patterns. The same preset, seed and size always give the same picture. The
  /// native JH Labs textures read a fixed table instead, so their seed changes nothing.
  /// `environment` is the image that lights a raymarch scene in place of the sky. Other presets
  /// ignore it. Returns nil when either size is not positive.
  public static func render(
    _ preset: TexturePreset,
    seed: UInt64,
    width: Int,
    height: Int,
    environment: RasterImage? = nil
  ) -> RasterImage? {
    guard width > 0, height > 0 else { return nil }
    switch preset.source {
    case .fastNoise:
      return FastNoiseRenderer.render(preset, seed: seed, width: width, height: height)
    case .pattern(let kind):
      return PatternRenderer.render(
        preset, kind: kind, seed: seed, width: width, height: height)
    case .raymarch(let scene):
      return RaymarchRenderer.render(
        preset, scene: scene, width: width, height: height, environment: environment)
    case .classic(let kind):
      return ClassicRenderer.render(
        preset, kind: kind, seed: seed, width: width, height: height)
    }
  }
}
