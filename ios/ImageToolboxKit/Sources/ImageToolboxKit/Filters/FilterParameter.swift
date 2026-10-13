import Foundation

/// One setting of a filter, described as data so the app can build its controls from it.
public struct FilterParameter: Equatable, Sendable {
  /// Key in `FilterStep.values`. Camel case, English.
  public let key: String
  /// Localization key of the label. It is the Android string resource name, so the translations match.
  public let titleKey: String
  public let kind: Kind

  public enum Kind: Equatable, Sendable {
    /// A number in `range`. `step` is the granularity a slider snaps to.
    case number(range: ClosedRange<Double>, step: Double, defaultValue: Double)
    case flag(defaultValue: Bool)
    case choice(options: [String], defaultValue: String)
    case color(defaultValue: FilterColor)
    case point(defaultValue: FilterPoint)
    /// A square matrix of `size` x `size` numbers, stored row by row. Android edits it as text.
    /// No range: Android does not limit the cells.
    case matrix(size: Int, defaultValue: [Double])
  }

  public init(key: String, titleKey: String, kind: Kind) {
    self.key = key
    self.titleKey = titleKey
    self.kind = kind
  }

  /// The value a new filter starts with.
  public var defaultValue: FilterValue {
    switch kind {
    case .number(_, _, let value): .number(value)
    case .flag(let value): .flag(value)
    case .choice(_, let value): .choice(value)
    case .color(let value): .color(value)
    case .point(let value): .point(value)
    case .matrix(_, let value): .matrix(value)
    }
  }

  /// Brings a stored value into the parameter's range. A missing value, a value of another kind,
  /// or a choice that is not an option gives the default. A number outside the range is clamped.
  func normalized(_ stored: FilterValue?) -> FilterValue {
    guard let stored else { return defaultValue }
    switch (kind, stored) {
    case (.number(let range, _, let fallback), .number(let number)):
      guard number.isFinite else { return .number(fallback) }
      return .number(min(max(number, range.lowerBound), range.upperBound))
    case (.flag, .flag):
      return stored
    case (.choice(let options, _), .choice(let option)) where options.contains(option):
      return stored
    case (.color, .color(let color)):
      return .color(
        FilterColor(
          red: Self.unit(color.red), green: Self.unit(color.green),
          blue: Self.unit(color.blue), alpha: Self.unit(color.alpha)))
    case (.point, .point(let point)):
      return .point(FilterPoint(x: Self.unit(point.x), y: Self.unit(point.y)))
    case (.matrix(let size, let fallback), .matrix(let values)):
      // A matrix of another size gives the default. A cell that is not finite gives the default cell.
      guard values.count == size * size, fallback.count == size * size else {
        return .matrix(fallback)
      }
      return .matrix(zip(values, fallback).map { $0.isFinite ? $0 : $1 })
    default:
      return defaultValue
    }
  }

  /// Clamps to 0...1. NaN becomes 0.
  private static func unit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}
