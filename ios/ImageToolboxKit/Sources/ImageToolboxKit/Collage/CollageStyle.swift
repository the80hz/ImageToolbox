import CoreGraphics
import Foundation

/// A line drawn along the inside edge of every cell. The Android collage has no borders; this is an addition.
public struct CollageBorder: Equatable, Sendable {
  /// Width in pixels. Zero draws nothing.
  public var width: Double
  public var color: RGBA

  public init(width: Double = 0, color: RGBA = RGBA(red: 0, green: 0, blue: 0)) {
    self.width = max(width, 0)
    self.color = color
  }

  /// No border.
  public static let none = CollageBorder()

  /// Whether drawing the border changes any pixel.
  public var isVisible: Bool {
    width > 0 && color.alpha > 0
  }
}

/// How a collage looks apart from where its cells are and the shape of each cell: what is behind the cells and the
/// line around them. The shape of each cell is a `CollageMask` kept per picture by `CollageComposition`.
public struct CollageStyle: Equatable, Sendable {
  public var background: CollageBackground
  public var border: CollageBorder

  public init(background: CollageBackground = .white, border: CollageBorder = .none) {
    self.background = background
    self.border = border
  }

  /// The same style drawn on a canvas `factor` times the size it was made for: the border width grows with it.
  public func scaled(by factor: Double) -> CollageStyle {
    var copy = self
    copy.border.width *= factor
    return copy
  }
}
