import Foundation

/// The categories of the texture picker, the same as the Android `TextureCategory` enum.
public enum TextureCategory: String, CaseIterable, Sendable {
  case nature
  case materials
  case space
  case patterns
  case abstract

  /// The English name of the category.
  public var title: String {
    switch self {
    case .nature: "Nature"
    case .materials: "Materials"
    case .space: "Space"
    case .patterns: "Patterns"
    case .abstract: "Abstract"
    }
  }
}

/// The part a FastNoise value plays in the recipe. The value is read as its position between the
/// bounds of its range, so every role works for any range.
public enum ParameterRole: Sendable {
  /// Multiplies the base frequency: how many features there are.
  case frequency
  /// Level at which the field is cut, for example the coverage of clouds.
  case threshold
  /// Width of the transition at a threshold or an edge.
  case softness
  /// Amount of domain warp: how far the features are pushed around.
  case warp
  /// Number of noise octaves.
  case detail
  /// Persistence of the octaves, the roughness of the fractal.
  case gain
  /// Width of lines, edges or borders.
  case width
  /// Randomness of cellular feature points.
  case jitter
  /// Strength of the highlights.
  case glow
  /// Contrast of the field.
  case contrast
  /// An angle in radians, used as is.
  case angle
  /// An aspect ratio used as is: the features are stretched along x by this factor.
  case aspect
  /// A secondary layer of noise, mixed in by its position in the range.
  case other
}

/// One parameter of a preset: the Android name, the default value, the allowed range and, for
/// FastNoise presets, the role the value plays.
public struct TextureParameter: Equatable, Sendable {
  public let name: String
  public let value: Double
  public let range: ClosedRange<Double>
  public let role: ParameterRole?

  public init(
    _ name: String,
    _ value: Double,
    _ range: ClosedRange<Double> = 0...1,
    _ role: ParameterRole? = nil
  ) {
    self.name = name
    self.value = value
    self.range = range
    self.role = role
  }

  /// The position of the value inside its range, from 0 to 1.
  public var normalized: Double {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return min(max((value - range.lowerBound) / span, 0), 1)
  }
}

/// The family of a FastNoise preset: the kind of field it draws. The native texture code of the
/// Android app draws the picture; the family is descriptive.
public enum FastNoiseFamily: Sendable {
  case fbm
  case ridged
  case turbulence
  case simplex
  case value
  case warp
  case cellular
  case edge
  case hex
  case grid
  case rings
  case bands
  case radial
  case spiral
  case mandelbrot
  case burningShip
  case julia
  case sierpinski
}

/// Which renderer draws a preset.
public enum TexturePresetSource: Equatable, Sendable {
  case fastNoise(FastNoiseFamily)
  case pattern(PatternKind)
  case raymarch(RaymarchScene)
  case classic(ClassicKind)
}

/// A texture preset of the Android catalogue, with the same id, category and parameters.
public struct TexturePreset: Identifiable, Equatable, Sendable {
  /// The Android enum name, for example "AdvancedWood". Unique in the catalogue.
  public let id: String
  public let category: TextureCategory
  public let source: TexturePresetSource
  /// The FastNoise scale (a frequency per pixel), the pattern frequency, or 1 when the preset has
  /// no size of its own.
  public let scale: Double
  /// ARGB colours, as the Android defaults store them.
  public let colours: [UInt32]
  public let parameters: [TextureParameter]

  init(
    id: String,
    category: TextureCategory,
    source: TexturePresetSource,
    scale: Double,
    colours: [UInt32],
    parameters: [TextureParameter]
  ) {
    self.id = id
    self.category = category
    self.source = source
    self.scale = scale
    self.colours = colours
    self.parameters = parameters
  }

  /// The name for people: the id with its camel case split into words, for example
  /// "Advanced Wood".
  public var title: String {
    let characters = Array(id)
    var result = ""
    for (index, character) in characters.enumerated() {
      if index > 0, character.isUppercase {
        let previous = characters[index - 1]
        let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
        if previous.isLowercase || (previous.isUppercase && nextIsLower) {
          result.append(" ")
        }
      }
      result.append(character)
    }
    return result
  }

  /// Whether the Swift renderer only approximates the Android look. FastNoise presets are exact
  /// ports of the native code of the Android fast-noise module (see `NativeTextureRenderer`).
  /// The JH Labs filters, Check and Cellular are ports of the native code of the Android fork that
  /// draws them (see `ClassicNative`). The three GMIC textures are reconstructions. Pattern and
  /// raymarch presets are not changed by this port and are not marked as approximations.
  public var isApproximation: Bool {
    switch source {
    case .fastNoise, .pattern, .raymarch: false
    case .classic(let kind):
      switch kind {
      case .brushedMetal, .caustics, .cellular, .check, .fbm, .marble, .plasma, .quilt, .wood:
        false
      case .organicFibers, .gmicReactionDiffusion, .truchet: true
      }
    }
  }

  /// The value of a named parameter, or `fallback` when the preset has no such parameter.
  public func value(_ name: String, fallback: Double = 0) -> Double {
    parameters.first { $0.name == name }?.value ?? fallback
  }

  static func fastNoise(
    _ id: String,
    _ category: TextureCategory,
    _ family: FastNoiseFamily,
    scale: Double,
    colours: [UInt32],
    _ parameters: [TextureParameter]
  ) -> TexturePreset {
    TexturePreset(
      id: id, category: category, source: .fastNoise(family), scale: scale,
      colours: colours, parameters: parameters)
  }

  static func pattern(
    _ id: String,
    _ kind: PatternKind,
    scale: Double,
    colours: [UInt32],
    _ parameters: [TextureParameter]
  ) -> TexturePreset {
    TexturePreset(
      id: id, category: .patterns, source: .pattern(kind), scale: scale,
      colours: colours, parameters: parameters)
  }

  static func raymarch(
    _ id: String,
    _ scene: RaymarchScene,
    colours: [UInt32]
  ) -> TexturePreset {
    TexturePreset(
      id: id, category: .patterns, source: .raymarch(scene), scale: 1,
      colours: colours, parameters: TexturePresets.raymarchParameters)
  }

  static func classic(
    _ id: String,
    _ category: TextureCategory,
    _ kind: ClassicKind,
    scale: Double,
    colours: [UInt32],
    _ parameters: [TextureParameter]
  ) -> TexturePreset {
    TexturePreset(
      id: id, category: category, source: .classic(kind), scale: scale,
      colours: colours, parameters: parameters)
  }
}

/// The texture catalogue: 177 presets, in the order of the Android app's groups.
public enum TexturePresets {
  /// Every preset: FastNoise, patterns, raymarch scenes, then the classic filters.
  public static let all: [TexturePreset] =
    fastNoiseFirst + fastNoiseSecond + fastNoiseThird + fastNoiseFourth + fastNoiseFifth
    + patterns + raymarch + classic

  /// The presets of one category, in catalogue order.
  public static func presets(in category: TextureCategory) -> [TexturePreset] {
    all.filter { $0.category == category }
  }

  /// The preset with the given id, or nil when there is none.
  public static func preset(id: String) -> TexturePreset? {
    all.first { $0.id == id }
  }
}
