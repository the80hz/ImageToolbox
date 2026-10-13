import Foundation

/// A control point of a tone curve. Both coordinates are in 0...1.
public struct CurvePoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A tone curve from input level to output level, both in 0...1. The curve passes through its
/// control points as a monotone cubic (Fritsch–Carlson): it never overshoots a point and never
/// turns back. The first point is at x = 0 and the last at x = 1, so every input has an output.
public struct ToneCurve: Equatable, Sendable {
  /// Smallest horizontal distance between two control points.
  public static let minimumGap = 0.01

  /// Control points sorted by x, with unique x values.
  public private(set) var points: [CurvePoint]

  public static let identity = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)])

  /// Clamps coordinates to 0...1, sorts by x and merges points that share an x. The curve is
  /// extended to x = 0 and x = 1 at the height of the nearest point. Empty input gives the identity.
  public init(points input: [CurvePoint]) {
    var sorted: [CurvePoint] = []
    for point in input.sorted(by: { $0.x < $1.x }) {
      let clamped = CurvePoint(x: clampedUnit(point.x), y: clampedUnit(point.y))
      if let last = sorted.last, last.x == clamped.x {
        sorted[sorted.count - 1] = clamped
      } else {
        sorted.append(clamped)
      }
    }
    guard let first = sorted.first, let last = sorted.last else {
      self = .identity
      return
    }
    if first.x > 0 {
      sorted.insert(CurvePoint(x: 0, y: first.y), at: 0)
    }
    if last.x < 1 {
      sorted.append(CurvePoint(x: 1, y: last.y))
    }
    points = sorted
  }

  /// Output level for input `x`, both in 0...1.
  public func value(at x: Double) -> Double {
    Self.evaluate(points, Self.tangents(of: points), at: clampedUnit(x))
  }

  /// Output byte for each of the 256 input bytes.
  public func lookupTable() -> [UInt8] {
    let tangents = Self.tangents(of: points)
    return (0..<256).map { input in
      let output = Self.evaluate(points, tangents, at: Double(input) / 255)
      return UInt8((clampedUnit(output) * 255).rounded())
    }
  }

  /// The curve with the point at `index` moved to `point`. Endpoints keep their x, and the other
  /// points stay between their neighbours.
  public func movingPoint(at index: Int, to point: CurvePoint) -> ToneCurve {
    guard points.indices.contains(index) else { return self }
    let isEdge = index == 0 || index == points.count - 1
    let lower = index > 0 ? points[index - 1].x + Self.minimumGap : 0
    let upper = index < points.count - 1 ? points[index + 1].x - Self.minimumGap : 1
    var moved = points
    moved[index] = CurvePoint(
      x: isEdge ? points[index].x : min(max(clampedUnit(point.x), lower), upper),
      y: clampedUnit(point.y))
    return ToneCurve(points: moved)
  }

  /// The curve with a new point at (x, y). Nothing changes if a point already sits within
  /// `minimumGap` of x.
  public func addingPoint(x: Double, y: Double) -> ToneCurve {
    let x = clampedUnit(x)
    guard !points.contains(where: { abs($0.x - x) < Self.minimumGap }) else { return self }
    return ToneCurve(points: points + [CurvePoint(x: x, y: clampedUnit(y))])
  }

  /// The curve without the point at `index`. The two endpoints cannot be removed.
  public func removingPoint(at index: Int) -> ToneCurve {
    guard points.indices.contains(index), index > 0, index < points.count - 1 else { return self }
    var reduced = points
    reduced.remove(at: index)
    return ToneCurve(points: reduced)
  }

  /// Slope at each control point, limited so that the cubic on each segment stays monotone.
  private static func tangents(of points: [CurvePoint]) -> [Double] {
    let count = points.count
    guard count > 1 else { return [0] }
    let slopes = (0..<count - 1).map { index in
      (points[index + 1].y - points[index].y) / (points[index + 1].x - points[index].x)
    }

    var tangents = [Double](repeating: 0, count: count)
    tangents[0] = slopes[0]
    tangents[count - 1] = slopes[count - 2]
    if count > 2 {
      for index in 1..<(count - 1) {
        let before = slopes[index - 1]
        let after = slopes[index]
        tangents[index] = before * after <= 0 ? 0 : (before + after) / 2
      }
    }

    for index in 0..<(count - 1) {
      let slope = slopes[index]
      guard slope != 0 else {
        tangents[index] = 0
        tangents[index + 1] = 0
        continue
      }
      let alpha = tangents[index] / slope
      let beta = tangents[index + 1] / slope
      let magnitude = alpha * alpha + beta * beta
      if magnitude > 9 {
        let scale = 3 / magnitude.squareRoot()
        tangents[index] = scale * alpha * slope
        tangents[index + 1] = scale * beta * slope
      }
    }
    return tangents
  }

  /// Cubic Hermite evaluation on the segment that contains `x`.
  private static func evaluate(_ points: [CurvePoint], _ tangents: [Double], at x: Double) -> Double
  {
    var index = 0
    while index < points.count - 2 && x > points[index + 1].x {
      index += 1
    }
    let left = points[index]
    let right = points[index + 1]
    let width = right.x - left.x
    let t = (x - left.x) / width
    let t2 = t * t
    let t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * left.y
      + (t3 - 2 * t2 + t) * width * tangents[index]
      + (-2 * t3 + 3 * t2) * right.y
      + (t3 - t2) * width * tangents[index + 1]
  }
}

/// The curves of the tool: one per colour channel and a master curve. The master curve is applied
/// after the channel's own curve, so it affects all three channels.
public struct CurveSet: Equatable, Sendable {
  public enum Channel: CaseIterable, Sendable {
    case master
    case red
    case green
    case blue
  }

  public var master: ToneCurve
  public var red: ToneCurve
  public var green: ToneCurve
  public var blue: ToneCurve

  public static let identity = CurveSet()

  public init(
    master: ToneCurve = .identity,
    red: ToneCurve = .identity,
    green: ToneCurve = .identity,
    blue: ToneCurve = .identity
  ) {
    self.master = master
    self.red = red
    self.green = green
    self.blue = blue
  }

  public subscript(channel: Channel) -> ToneCurve {
    get {
      switch channel {
      case .master: master
      case .red: red
      case .green: green
      case .blue: blue
      }
    }
    set {
      switch channel {
      case .master: master = newValue
      case .red: red = newValue
      case .green: green = newValue
      case .blue: blue = newValue
      }
    }
  }

  /// Output tables for red, green and blue. Each maps an input byte to an output byte: the
  /// channel's own curve first, then the master curve.
  public func lookupTables() -> (red: [UInt8], green: [UInt8], blue: [UInt8]) {
    let masterTable = master.lookupTable()
    func compose(_ channel: ToneCurve) -> [UInt8] {
      channel.lookupTable().map { masterTable[Int($0)] }
    }
    return (compose(red), compose(green), compose(blue))
  }
}

/// Clamps to 0...1. Shared by the curve types in this file.
private func clampedUnit(_ value: Double) -> Double {
  min(max(value, 0), 1)
}
