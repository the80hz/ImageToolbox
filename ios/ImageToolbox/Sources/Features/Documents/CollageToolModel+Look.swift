import ImageToolboxKit
import SwiftUI

/// The look and the export settings of the collage tool, as bindings for the controls. Each change is stored by
/// `CollageToolModel.settings`, which keeps them between launches.
extension CollageToolModel {

  /// Gap between neighbouring cells in pixels, from 0 to 40.
  var gap: Double {
    get { settings.gap }
    set { settings.gap = newValue }
  }

  /// Margin between the cells and the edge of the canvas in pixels, from 0 to 60.
  var margin: Double {
    get { settings.margin }
    set { settings.margin = newValue }
  }

  /// The aspect ratio of the export, one of the Android presets.
  var aspect: CollageExportSize.Aspect {
    get { settings.aspect }
    set {
      settings.aspectWidth = newValue.width
      settings.aspectHeight = newValue.height
    }
  }

  /// The output scale of the export, from 0.1 to 1 of the largest picture.
  var exportScale: Double {
    get { settings.exportScale }
    set { settings.exportScale = newValue }
  }

  var fill: CollageSettings.Fill {
    get { settings.fill }
    set { settings.fill = newValue }
  }

  /// The solid colour, or the start of a gradient.
  var startColor: Color {
    get { Self.color(settings.startColour) }
    set { settings.startColour = ColorConversion.rgba(newValue).hexString }
  }

  /// The end of a gradient.
  var endColor: Color {
    get { Self.color(settings.endColour) }
    set { settings.endColour = ColorConversion.rgba(newValue).hexString }
  }

  /// Direction of a linear gradient in degrees. 0 runs left to right and 90 top to bottom.
  var gradientAngle: Double {
    get { settings.gradientAngle }
    set { settings.gradientAngle = newValue }
  }

  /// Width of the line around every cell in pixels, from 0 to 30. Zero draws no border.
  var borderWidth: Double {
    get { settings.borderWidth }
    set { settings.borderWidth = newValue }
  }

  var borderColor: Color {
    get { Self.color(settings.borderColour) }
    set { settings.borderColour = ColorConversion.rgba(newValue).hexString }
  }

  private static func color(_ hex: String) -> Color {
    RGBA(hex: hex).map(ColorConversion.color) ?? .white
  }
}
