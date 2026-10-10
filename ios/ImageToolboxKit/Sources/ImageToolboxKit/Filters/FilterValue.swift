import Foundation

/// An RGBA colour, each component in 0...1.
public struct FilterColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let black = FilterColor(red: 0, green: 0, blue: 0)
  public static let white = FilterColor(red: 1, green: 1, blue: 1)
}

/// A point, each coordinate in 0...1, measured from the top left corner.
public struct FilterPoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// One stored setting of a filter. The case must match the parameter it belongs to.
public enum FilterValue: Codable, Equatable, Sendable {
  case number(Double)
  case flag(Bool)
  case choice(String)
  case color(FilterColor)
  case point(FilterPoint)
  /// Square matrix, row by row.
  case matrix([Double])
}

/// Settings of one filter after normalisation: every parameter has a value, and each value is in range.
///
/// `FilterRegistry` builds these, so a filter never sees a missing or out-of-range setting.
public struct FilterValues: Equatable, Sendable {
  private let storage: [String: FilterValue]

  init(storage: [String: FilterValue]) {
    self.storage = storage
  }

  public func number(_ key: String) -> Double {
    guard case .number(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a number parameter")
    }
    return value
  }

  public func flag(_ key: String) -> Bool {
    guard case .flag(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a flag parameter")
    }
    return value
  }

  public func choice(_ key: String) -> String {
    guard case .choice(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a choice parameter")
    }
    return value
  }

  public func color(_ key: String) -> FilterColor {
    guard case .color(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a colour parameter")
    }
    return value
  }

  public func point(_ key: String) -> FilterPoint {
    guard case .point(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a point parameter")
    }
    return value
  }

  public func matrix(_ key: String) -> [Double] {
    guard case .matrix(let value)? = storage[key] else {
      preconditionFailure("\(key) is not a matrix parameter")
    }
    return value
  }
}
