import Foundation

/// Draws the classic presets of the Android app. The JH Labs filters, Check and Cellular follow
/// the native code of the Android fork (see `ClassicJHLabs` and `ClassicCellularFilter`). The three
/// GMIC textures (OrganicFibers, GmicReactionDiffusion and Truchet) are rebuilt from their
/// parameters, because GMIC is licensed under CeCILL and its source was not read.
enum ClassicRenderer {
  static func render(
    _ preset: TexturePreset,
    kind: ClassicKind,
    seed: UInt64,
    width: Int,
    height: Int
  ) -> RasterImage {
    switch kind {
    case .brushedMetal, .caustics, .cellular, .check, .fbm, .marble, .plasma, .quilt, .wood:
      let argb = ClassicJHLabs.render(preset, kind: kind, width: width, height: height)
      return raster(argb, width: width, height: height)
    case .organicFibers, .gmicReactionDiffusion, .truchet:
      let context = ClassicContext(preset: preset, seed: seed, width: width, height: height)
      var pixels = [UInt8](repeating: 255, count: width * height * 4)
      for y in 0..<height {
        for x in 0..<width {
          let colour = context.shade(kind, x: x, y: y)
          let index = (y * width + x) * 4
          pixels[index] = byte(colour.x)
          pixels[index + 1] = byte(colour.y)
          pixels[index + 2] = byte(colour.z)
        }
      }
      return RasterImage(width: width, height: height, pixels: pixels)
    }
  }

  /// Packs ARGB pixels into the RGBA bytes of a `RasterImage`, alpha included.
  private static func raster(_ argb: [Int], width: Int, height: Int) -> RasterImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for (index, colour) in argb.enumerated() {
      pixels[index * 4] = UInt8(truncatingIfNeeded: ClassicMath.red(colour))
      pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: ClassicMath.green(colour))
      pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: ClassicMath.blue(colour))
      pixels[index * 4 + 3] = UInt8(truncatingIfNeeded: ClassicMath.alpha(colour))
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func byte(_ channel: Double) -> UInt8 {
    UInt8((min(max(channel, 0), 1) * 255).rounded())
  }
}

/// The per-preset inputs of the GMIC reconstructions, which draw one pixel at a time.
private struct ClassicContext {
  let preset: TexturePreset
  let noise: FractalNoise
  let cells: CellularNoise2D
  let colours: [SIMD3<Double>]
  let size: Double

  init(preset: TexturePreset, seed: UInt64, width: Int, height: Int) {
    self.preset = preset
    noise = FractalNoise(seed: seed, basis: .perlin)
    cells = CellularNoise2D(seed: seed)
    colours = Self.palette(preset.colours.map(FastNoiseRenderer.colour))
    size = preset.scale > 1 ? preset.scale : Double(max(width, height)) / 8
  }

  /// At least two colours, so that the picture varies. A preset with no colour, or a black one,
  /// gets black to white. Any other single colour gets a shade from a quarter of it up to itself.
  static func palette(_ given: [SIMD3<Double>]) -> [SIMD3<Double>] {
    switch given.count {
    case 0: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)]
    case 1 where given[0] == .zero: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)]
    case 1: [given[0] * 0.25, given[0]]
    default: given
    }
  }

  func shade(_ kind: ClassicKind, x: Int, y: Int) -> SIMD3<Double> {
    let u = (Double(x) + 0.5) / size
    let v = (Double(y) + 0.5) / size
    switch kind {
    case .organicFibers:
      let angle = 3 * noise.fractal(x: u * 0.5, y: v * 0.5, octaves: 2)
      let fibre = 0.5 + 0.5 * sin((u * cos(angle) + v * sin(angle)) * 6)
      return ramp(fibre)
    case .gmicReactionDiffusion:
      let iterations = preset.value("iterations", fallback: 5)
      let pattern = noise.fractal(x: u * 0.6, y: v * 0.6, octaves: Int(iterations / 2) + 1)
      return ramp(smooth(0.5 + 0.5 * pattern))
    case .truchet:
      return truchet(u: u, v: v)
    case .brushedMetal, .caustics, .cellular, .check, .fbm, .marble, .plasma, .quilt, .wood:
      preconditionFailure("\(kind) is drawn as a whole picture by ClassicJHLabs")
    }
  }

  private func ramp(_ t: Double) -> SIMD3<Double> {
    FastNoiseRenderer.ramp(colours, at: t)
  }

  private func smooth(_ t: Double) -> Double {
    let clamped = min(max(t, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
  }

  /// Wedges of a square lattice: each cell draws two quarter arcs, and a hash flips the cell.
  private func truchet(u: Double, v: Double) -> SIMD3<Double> {
    let radius = max(preset.value("radius", fallback: 5), 1)
    let smoothness = preset.value("smoothness", fallback: 1)
    let cell = SIMD2(u.rounded(.down), v.rounded(.down))
    var local = SIMD2(u - cell.x, v - cell.y)
    if cells.cellValue(x: cell.x, y: cell.y) > 0.5 {
      local.x = 1 - local.x
    }
    let a = abs((local * local).sum().squareRoot() - 0.5)
    let b = abs(((local - 1) * (local - 1)).sum().squareRoot() - 0.5)
    let width = 0.5 / radius
    let line = min(a, b)
    let weight = 1 - min(max((line - width) / max(0.02 * smoothness, 0.001), 0), 1)
    return SIMD3(repeating: weight)
  }
}
