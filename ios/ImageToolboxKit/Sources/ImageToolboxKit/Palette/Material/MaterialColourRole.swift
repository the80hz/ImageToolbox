// Role names follow the Material 3 ColorScheme of the Android app (Compose Material 3).

import Foundation

/// One colour role of a Material 3 colour scheme.
public enum MaterialColourRole: String, CaseIterable, Sendable, Hashable {
  case primary, onPrimary, primaryContainer, onPrimaryContainer, inversePrimary
  case secondary, onSecondary, secondaryContainer, onSecondaryContainer
  case tertiary, onTertiary, tertiaryContainer, onTertiaryContainer
  case background, onBackground
  case surface, onSurface, surfaceVariant, onSurfaceVariant, surfaceTint
  case inverseSurface, inverseOnSurface
  case error, onError, errorContainer, onErrorContainer
  case outline, outlineVariant, scrim
  case surfaceBright, surfaceDim
  case surfaceContainer, surfaceContainerHigh, surfaceContainerHighest
  case surfaceContainerLow, surfaceContainerLowest
  case primaryFixed, primaryFixedDim, onPrimaryFixed, onPrimaryFixedVariant
  case secondaryFixed, secondaryFixedDim, onSecondaryFixed, onSecondaryFixedVariant
  case tertiaryFixed, tertiaryFixedDim, onTertiaryFixed, onTertiaryFixedVariant

  /// The label the Android Material You palette screen shows on the swatch.
  public var displayName: String {
    switch self {
    case .surfaceContainerLowest: return "Surface Lowest"
    case .surfaceContainerLow: return "Surface Low"
    case .surfaceContainerHigh: return "Surface High"
    case .surfaceContainerHighest: return "Surface Highest"
    default:
      // "onPrimaryContainer" becomes "On Primary Container".
      var words = ""
      for character in rawValue {
        if character.isUppercase { words.append(" ") }
        words.append(character)
      }
      return words.prefix(1).uppercased() + words.dropFirst()
    }
  }

  /// The role drawn on top of this one in the Android swatch grid, or nil when the swatch uses
  /// the default text colour (surface tint).
  public var contentRole: MaterialColourRole? {
    switch self {
    case .primary: return .onPrimary
    case .secondary: return .onSecondary
    case .tertiary: return .onTertiary
    case .background: return .onBackground
    case .error: return .onError
    case .primaryContainer: return .onPrimaryContainer
    case .secondaryContainer: return .onSecondaryContainer
    case .tertiaryContainer: return .onTertiaryContainer
    case .errorContainer: return .onErrorContainer
    case .inverseSurface: return .inverseOnSurface
    case .surface, .surfaceBright, .surfaceDim, .surfaceContainer, .surfaceContainerHigh,
      .surfaceContainerHighest, .surfaceContainerLow, .surfaceContainerLowest:
      return .onSurface
    case .inversePrimary: return .primary
    case .surfaceVariant: return .onSurfaceVariant
    case .onPrimary: return .primary
    case .onSecondary: return .secondary
    case .onTertiary: return .tertiary
    case .onBackground: return .background
    case .onError: return .error
    case .onPrimaryContainer: return .primaryContainer
    case .onSecondaryContainer: return .secondaryContainer
    case .onTertiaryContainer: return .tertiaryContainer
    case .onErrorContainer: return .errorContainer
    case .inverseOnSurface: return .inverseSurface
    case .onSurface: return .surface
    case .outline: return .surfaceContainerLow
    case .outlineVariant: return .onSurfaceVariant
    case .onSurfaceVariant: return .surfaceVariant
    default: return nil
    }
  }

  /// The 34 roles of the Android swatch grid in its row order, four swatches to a row.
  public static let paletteToolRows: [[MaterialColourRole]] = [
    [.primary, .onPrimary, .primaryContainer, .onPrimaryContainer],
    [.secondary, .onSecondary, .secondaryContainer, .onSecondaryContainer],
    [.tertiary, .onTertiary, .tertiaryContainer, .onTertiaryContainer],
    [.error, .onError, .errorContainer, .onErrorContainer],
    [.inversePrimary, .surfaceTint, .surfaceDim, .surfaceBright],
    [.surfaceVariant, .onSurfaceVariant, .inverseSurface, .inverseOnSurface],
    [.onSurface, .surface, .surfaceContainerLowest, .surfaceContainerLow],
    [.surfaceContainer, .surfaceContainerHigh, .surfaceContainerHighest],
    [.outline, .outlineVariant],
  ]

  /// Roles written by "Copy as Compose code", in the order of the Android output.
  static let composeCodeOrder: [MaterialColourRole] = [
    .background, .error, .errorContainer, .inverseOnSurface, .inversePrimary, .inverseSurface,
    .onBackground, .onError, .onErrorContainer, .onPrimary, .onPrimaryContainer, .onSecondary,
    .onSecondaryContainer, .onSurface, .onSurfaceVariant, .onTertiary, .onTertiaryContainer,
    .outline, .outlineVariant, .primary, .primaryContainer, .scrim, .secondary,
    .secondaryContainer, .surface, .surfaceTint, .surfaceVariant, .tertiary, .tertiaryContainer,
    .surfaceBright, .surfaceDim, .surfaceContainer, .surfaceContainerHigh,
    .surfaceContainerHighest, .surfaceContainerLow, .surfaceContainerLowest,
  ]

  /// The dynamic-colour definition this role is computed from.
  var definition: DynamicColor {
    typealias D = MaterialDynamicColors
    switch self {
    case .primary: return D.primary
    case .onPrimary: return D.onPrimary
    case .primaryContainer: return D.primaryContainer
    case .onPrimaryContainer: return D.onPrimaryContainer
    case .inversePrimary: return D.inversePrimary
    case .secondary: return D.secondary
    case .onSecondary: return D.onSecondary
    case .secondaryContainer: return D.secondaryContainer
    case .onSecondaryContainer: return D.onSecondaryContainer
    case .tertiary: return D.tertiary
    case .onTertiary: return D.onTertiary
    case .tertiaryContainer: return D.tertiaryContainer
    case .onTertiaryContainer: return D.onTertiaryContainer
    case .background: return D.background
    case .onBackground: return D.onBackground
    case .surface: return D.surface
    case .onSurface: return D.onSurface
    case .surfaceVariant: return D.surfaceVariant
    case .onSurfaceVariant: return D.onSurfaceVariant
    case .surfaceTint: return D.surfaceTint
    case .inverseSurface: return D.inverseSurface
    case .inverseOnSurface: return D.inverseOnSurface
    case .error: return D.error
    case .onError: return D.onError
    case .errorContainer: return D.errorContainer
    case .onErrorContainer: return D.onErrorContainer
    case .outline: return D.outline
    case .outlineVariant: return D.outlineVariant
    case .scrim: return D.scrim
    case .surfaceBright: return D.surfaceBright
    case .surfaceDim: return D.surfaceDim
    case .surfaceContainer: return D.surfaceContainer
    case .surfaceContainerHigh: return D.surfaceContainerHigh
    case .surfaceContainerHighest: return D.surfaceContainerHighest
    case .surfaceContainerLow: return D.surfaceContainerLow
    case .surfaceContainerLowest: return D.surfaceContainerLowest
    case .primaryFixed: return D.primaryFixed
    case .primaryFixedDim: return D.primaryFixedDim
    case .onPrimaryFixed: return D.onPrimaryFixed
    case .onPrimaryFixedVariant: return D.onPrimaryFixedVariant
    case .secondaryFixed: return D.secondaryFixed
    case .secondaryFixedDim: return D.secondaryFixedDim
    case .onSecondaryFixed: return D.onSecondaryFixed
    case .onSecondaryFixedVariant: return D.onSecondaryFixedVariant
    case .tertiaryFixed: return D.tertiaryFixed
    case .tertiaryFixedDim: return D.tertiaryFixedDim
    case .onTertiaryFixed: return D.onTertiaryFixed
    case .onTertiaryFixedVariant: return D.onTertiaryFixedVariant
    }
  }
}
