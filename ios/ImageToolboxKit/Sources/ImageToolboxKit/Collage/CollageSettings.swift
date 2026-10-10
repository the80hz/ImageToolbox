import Foundation

/// The look and export settings of the collage tool, kept between launches as JSON in UserDefaults. The Android
/// collage keeps its parameters the same way: the spacing, the corners, the output scale and the rotation switch. The
/// pictures, the template, the moved dividers and the cell shapes are not kept, since a picture picked from the library
/// does not outlive the session on Android either. A stored value that does not decode is replaced by the defaults.
public struct CollageSettings: Codable, Equatable, Sendable {
  public static let defaultsKey = "collage.settings"

  /// What is drawn behind the cells.
  public enum Fill: String, Codable, CaseIterable, Sendable {
    case solid
    case linear
    case radial
  }

  /// The aspect ratio of the export: the width and height parts of an Android preset.
  public var aspectWidth: Double
  public var aspectHeight: Double
  /// The output scale of the export, from 0.1 to 1.
  public var exportScale: Double
  /// The gap between cells and the margin around them, in pixels of the design canvas.
  public var gap: Double
  public var margin: Double
  public var fill: Fill
  /// The solid colour, or the start of a gradient, as a hex code such as `#FFFFFF`.
  public var startColour: String
  /// The end of a gradient, as a hex code.
  public var endColour: String
  /// The direction of a linear gradient in degrees, from 0 to 360.
  public var gradientAngle: Double
  /// The width of the line around each cell in pixels. Zero draws none.
  public var borderWidth: Double
  /// The colour of that line, as a hex code.
  public var borderColour: String

  public init(
    aspectWidth: Double = CollageExportSize.defaultAspect.width,
    aspectHeight: Double = CollageExportSize.defaultAspect.height,
    exportScale: Double = CollageExportSize.defaultScale, gap: Double = 8, margin: Double = 8,
    fill: Fill = .solid, startColour: String = "#FFFFFF", endColour: String = "#6B59E6",
    gradientAngle: Double = 45, borderWidth: Double = 0, borderColour: String = "#000000"
  ) {
    self.aspectWidth = aspectWidth
    self.aspectHeight = aspectHeight
    self.exportScale = exportScale
    self.gap = gap
    self.margin = margin
    self.fill = fill
    self.startColour = startColour
    self.endColour = endColour
    self.gradientAngle = gradientAngle
    self.borderWidth = borderWidth
    self.borderColour = borderColour
  }

  /// The aspect ratio of the export as an Android preset.
  public var aspect: CollageExportSize.Aspect {
    CollageExportSize.Aspect(width: aspectWidth, height: aspectHeight)
  }

  /// The background as the collage draws it.
  public var background: CollageBackground {
    let start = Self.colour(startColour, default: RGBA(red: 255, green: 255, blue: 255))
    let end = Self.colour(endColour, default: RGBA(red: 107, green: 89, blue: 230))
    switch fill {
    case .solid: return .solid(start)
    case .linear: return .linearGradient(from: start, to: end, angle: gradientAngle)
    case .radial: return .radialGradient(from: start, to: end)
    }
  }

  /// The line around each cell as the collage draws it.
  public var border: CollageBorder {
    CollageBorder(
      width: borderWidth,
      color: Self.colour(borderColour, default: RGBA(red: 0, green: 0, blue: 0)))
  }

  /// The same settings with every value inside the range the tool offers. A colour that is not a hex code is replaced
  /// by its default, and an aspect part that is not a positive number by 1.
  public var clamped: CollageSettings {
    var copy = self
    copy.aspectWidth = Self.positive(aspectWidth)
    copy.aspectHeight = Self.positive(aspectHeight)
    copy.exportScale = min(
      max(exportScale.isFinite ? exportScale : CollageExportSize.defaultScale, 0.1), 1)
    copy.gap = min(max(gap.isFinite ? gap : 8, 0), 40)
    copy.margin = min(max(margin.isFinite ? margin : 8, 0), 60)
    copy.gradientAngle = min(max(gradientAngle.isFinite ? gradientAngle : 45, 0), 360)
    copy.borderWidth = min(max(borderWidth.isFinite ? borderWidth : 0, 0), 30)
    copy.startColour = Self.hex(startColour, default: "#FFFFFF")
    copy.endColour = Self.hex(endColour, default: "#6B59E6")
    copy.borderColour = Self.hex(borderColour, default: "#000000")
    return copy
  }

  /// The stored settings, or the defaults when nothing is stored or the stored value is unreadable. The result is
  /// clamped.
  public static func load(from defaults: UserDefaults, key: String = defaultsKey) -> CollageSettings
  {
    guard let data = defaults.data(forKey: key),
      let stored = try? JSONDecoder().decode(CollageSettings.self, from: data)
    else { return CollageSettings() }
    return stored.clamped
  }

  public func save(to defaults: UserDefaults, key: String = defaultsKey) {
    guard let data = try? JSONEncoder().encode(clamped) else { return }
    defaults.set(data, forKey: key)
  }

  // MARK: - Helpers

  private static func colour(_ hex: String, default fallback: RGBA) -> RGBA {
    RGBA(hex: hex) ?? fallback
  }

  private static func hex(_ value: String, default fallback: String) -> String {
    RGBA(hex: value)?.hexString ?? fallback
  }

  private static func positive(_ value: Double) -> Double {
    value.isFinite && value > 0 ? value : 1
  }
}
