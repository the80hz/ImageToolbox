import ImageToolboxKit
import SwiftUI

extension CollageTemplate {
  /// The template's name in the picker. Each name is a literal key in the string catalogue. A frame layout is
  /// named by its Android number, such as "Layout 3-12" for "collage_3_12".
  var title: LocalizedStringKey {
    switch self {
    case .grid: "Grid"
    case .splitSideBySide: "Two side by side"
    case .splitStacked: "Two stacked"
    case .hero: "Large picture on top"
    case .diagonal: "Diagonal"
    case .twoByTwoOffset: "Offset 2 by 2"
    case .filmstrip: "Film strip"
    case .frame(let id):
      LocalizedStringKey("Layout \(id.dropFirst("collage_".count).replacing("_", with: "-"))")
    }
  }
}

extension CollageMask.Shape {
  /// The shape's name in the picker. Each name is a literal key in the string catalogue.
  var title: LocalizedStringKey {
    switch self {
    case .rectangle: "Rectangle"
    case .ellipse: "Ellipse"
    case .circle: "Circle"
    case .hexagon: "Hexagon"
    case .heart: "Heart"
    }
  }
}

extension CollageComposition.Arrangement {
  var title: LocalizedStringKey {
    switch self {
    case .template: "Template"
    case .free: "Free"
    }
  }
}

extension CollageSettings.Fill {
  var title: LocalizedStringKey {
    switch self {
    case .solid: "Solid"
    case .linear: "Linear"
    case .radial: "Radial"
    }
  }
}
