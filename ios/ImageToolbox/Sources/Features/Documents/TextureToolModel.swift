import CoreGraphics
import ImageToolboxKit
import Observation
import SwiftUI

/// What the tool draws: one of the basic kinds, or a preset of the catalogue.
enum TextureChoice: Hashable, Sendable {
  case kind(TextureKind)
  case preset(String)
}

/// Draws a basic texture or a catalogue preset and encodes it as PNG. Safe to run off the main
/// actor.
enum TextureRenderer {
  struct Settings: Sendable {
    enum Source: Sendable {
      case basic(TextureSettings)
      case preset(id: String, seed: UInt64)
    }

    let source: Source
    /// Width and height of the square picture in pixels.
    let size: Int
  }

  struct Output: Sendable {
    let raster: RasterImage
    let png: Data
  }

  static func render(_ settings: Settings) -> Output? {
    let raster: RasterImage?
    switch settings.source {
    case .basic(let texture):
      raster = ProceduralTexture.render(texture, width: settings.size, height: settings.size)
    case .preset(let id, let seed):
      guard let preset = TexturePresets.preset(id: id) else { return nil }
      raster = TexturePresetRenderer.render(
        preset, seed: seed, width: settings.size, height: settings.size)
    }
    guard
      let raster,
      let image = raster.toCGImage(),
      let png = ExportEncoding.encode(image, as: .png, source: nil)
    else { return nil }
    return Output(raster: raster, png: png)
  }
}

/// Holds the texture tool's settings and the last rendered picture.
@MainActor
@Observable
final class TextureToolModel {
  /// Width and height of the picture in pixels, for both the preview and the export.
  static let size = 1024

  /// The picture to draw: a basic kind or a catalogue preset.
  var choice = TextureChoice.kind(.noise) {
    didSet {
      if case .kind(let kind) = choice { basicKind = kind }
      changed()
    }
  }

  /// The last basic kind chosen, so that switching back to it keeps the tool's other settings.
  private var basicKind = TextureKind.noise

  /// The same seed and settings always give the same picture.
  var seed: UInt64 = 42 {
    didSet { changed() }
  }

  var colourA = Color.black {
    didSet { changed() }
  }

  var colourB = Color.white {
    didSet { changed() }
  }

  /// Characteristic size in pixels, from 4 to 512.
  var scale = 64.0 {
    didSet { changed() }
  }

  /// Noise octaves, from 1 to 8. Only some kinds use them, see `usesOctaves`.
  var octaves = 4.0 {
    didSet { changed() }
  }

  /// Rotation of the pattern in degrees, from -180 to 180.
  var angle = 0.0 {
    didSet { changed() }
  }

  private(set) var image: CGImage?
  private(set) var pngData: Data?
  private(set) var pngFileName = "texture.png"
  private(set) var isGenerating = false
  private(set) var generationFailed = false
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  /// The revision that the current picture was drawn for.
  private var renderedRevision: Int?

  /// Whether the picture is a catalogue preset. Presets set their own colours and parameters, so
  /// the colour, scale and angle controls do not apply to them.
  var isPreset: Bool {
    if case .preset = choice { true } else { false }
  }

  /// Whether `octaves` changes the picture. Stripes, checkerboard, dots and voronoi ignore it,
  /// and so do presets.
  var usesOctaves: Bool {
    switch choice {
    case .kind(let kind):
      switch kind {
      case .noise, .turbulence, .marble, .wood: true
      case .voronoi, .stripes, .checkerboard, .dots: false
      }
    case .preset: false
    }
  }

  func shuffleSeed() {
    seed = UInt64.random(in: UInt64.min...UInt64.max)
  }

  /// Draws the picture for the current settings. A result that belongs to settings which changed
  /// while it was drawn is dropped, because the newer change starts its own refresh.
  func refresh() async {
    guard renderedRevision != revision else { return }
    let requested = revision
    let settings = TextureRenderer.Settings(source: renderSource, size: Self.size)
    isGenerating = true
    let output = await Task.detached(priority: .userInitiated) {
      TextureRenderer.render(settings)
    }.value
    guard requested == revision else { return }
    isGenerating = false
    renderedRevision = requested

    guard let output, let cgImage = output.raster.toCGImage() else {
      image = nil
      pngData = nil
      generationFailed = true
      return
    }
    generationFailed = false
    image = cgImage
    pngData = output.png
    pngFileName = ExportNaming.fileName(stem: "texture", fileExtension: "png", data: output.png)
  }

  private var renderSource: TextureRenderer.Settings.Source {
    switch choice {
    case .kind:
      .basic(
        TextureSettings(
          kind: basicKind,
          seed: seed,
          scale: scale,
          octaves: Int(octaves.rounded()),
          colourA: Self.components(colourA),
          colourB: Self.components(colourB),
          angle: angle * Double.pi / 180))
    case .preset(let id):
      .preset(id: id, seed: seed)
    }
  }

  /// Clears the export at once, so a share never sends a picture for older settings.
  private func changed() {
    pngData = nil
    revision += 1
  }

  /// Red, green and blue in 0...1, as `TextureSettings` expects.
  private static func components(_ colour: Color) -> SIMD3<Double> {
    let rgba = ColorConversion.rgba(colour)
    return SIMD3(
      Double(rgba.red) / 255,
      Double(rgba.green) / 255,
      Double(rgba.blue) / 255)
  }
}
