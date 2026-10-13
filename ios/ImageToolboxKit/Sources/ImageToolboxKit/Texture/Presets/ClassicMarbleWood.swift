// Ports of the Marble and Wood textures of the JH Labs filters in the Android fork
// (ImageToolboxLibs, libs/jhlabs). Copyright 2006 Jerry Huxtable, Apache License 2.0.
import Foundation

/// The Marble and Wood textures of the Android app. The Java classes `MarbleTexFilter` and
/// `WoodFilter` of the fork hold only their parameters. The Android app draws the pictures in the
/// native code of the fork (`src/main/rust/jhlabs/src/lib.rs`, the `MarbleTexFilter` and
/// `WoodFilter` arm of `apply_filter`), which reads those parameters through their getters. These
/// functions port that code, with its float arithmetic, its Perlin table and its colour map.
enum ClassicMarbleWood {
  /// `MarbleTexFilter`: a triangle wave of the grain coordinate, pushed along by turbulent noise,
  /// read through the colour map from black to white.
  static func marble(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let field = GrainField(preset, stretchDefault: 1)
    let factor = Float(preset.value("turbulenceFactor", fallback: 0.4))
    let colours = ClassicLinearColormap(low: 0xff00_0000, high: 0xffff_ffff)
    return draw(width: width, height: height) { x, y in
      let (along, across) = field.coordinates(x, y)
      return colours.colour(triangle(along + factor * field.turbulence(along, across)))
    }
  }

  /// `WoodFilter`: rings of the distance from the origin, pushed out by turbulent noise, read
  /// through the colour map from light to dark wood. The native code does not read the gain or
  /// the bias, so neither changes the picture.
  static func wood(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let field = GrainField(preset, stretchDefault: 10)
    let rings = Float(preset.value("rings", fallback: 0.5))
    let colours = ClassicLinearColormap(low: 0xffe5_c494, high: 0xff98_7b51)
    return draw(width: width, height: height) { x, y in
      let (along, across) = field.coordinates(x, y)
      let distance = (along * along + across * across).squareRoot()
      return colours.colour(triangle(distance + rings * field.turbulence(along, across)))
    }
  }

  /// `triangle` of the native code: 0 at each whole number, 1 halfway between, and linear in
  /// between. The remainder is never negative, as with Rust's `rem_euclid`.
  static func triangle(_ value: Float) -> Float {
    var remainder = value.truncatingRemainder(dividingBy: 1)
    if remainder < 0 {
      remainder += 1
    }
    return 2 * (remainder < 0.5 ? remainder : 1 - remainder)
  }

  /// Fills a picture of ARGB pixels, row 0 first, with the colour of each pixel.
  private static func draw(width: Int, height: Int, _ shade: (Int, Int) -> Int) -> [Int] {
    var pixels = [Int](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        pixels[y * width + x] = shade(x, y)
      }
    }
    return pixels
  }
}

/// The steps that the two textures share: the pixel is turned by the angle, then divided by the
/// scale along the grain and by the scale times the stretch across it. The turbulence is summed up
/// to the octave count, which the native code never takes below one.
private struct GrainField {
  private let table = ClassicNative.table
  private let sine: Float
  private let cosine: Float
  private let scale: Float
  private let stretch: Float
  private let octaves: Float

  /// `stretchDefault` is the stretch that the Java class starts with, used only when the preset
  /// does not name one: 1 for Marble and 10 for Wood.
  init(_ preset: TexturePreset, stretchDefault: Double) {
    let angle = Float(preset.value("angle", fallback: 0))
    sine = sinf(angle)
    cosine = cosf(angle)
    scale = max(Float(preset.scale), 0.01)
    stretch = max(Float(preset.value("stretch", fallback: stretchDefault)), 0.01)
    octaves = max(Float(preset.value("turbulence", fallback: 1)), 1)
  }

  /// The grain coordinates of the pixel `(x, y)`, computed in float as the native code does.
  func coordinates(_ x: Int, _ y: Int) -> (Float, Float) {
    let column = Float(x)
    let row = Float(y)
    let along = (cosine * column + sine * row) / scale
    let across = (-sine * column + cosine * row) / (scale * stretch)
    return (along, across)
  }

  /// `PerlinNoise.turbulence3(along, across, 0, octaves)` of the native code.
  func turbulence(_ along: Float, _ across: Float) -> Float {
    table.turbulence3(along, across, 0, octaves)
  }
}
