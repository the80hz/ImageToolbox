import Foundation

/// A vector in three dimensions, for the ray-marched kinds and the attractors.
struct FractalVector: Equatable, Sendable {
  var x: Double
  var y: Double
  var z: Double

  init(_ x: Double, _ y: Double, _ z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  static let zero = FractalVector(0, 0, 0)

  var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite
  }

  func dot(_ other: FractalVector) -> Double {
    x * other.x + y * other.y + z * other.z
  }

  var length: Double {
    dot(self).squareRoot()
  }

  /// The unit vector in this direction. A zero vector is returned unchanged.
  var normalized: FractalVector {
    let size = length
    return size > 0 ? self * (1 / size) : self
  }

  func cross(_ other: FractalVector) -> FractalVector {
    FractalVector(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x)
  }

  var absolute: FractalVector {
    FractalVector(abs(x), abs(y), abs(z))
  }

  /// The components sorted from largest to smallest.
  var sortedDescending: FractalVector {
    var a = x
    var b = y
    var c = z
    if a < b { swap(&a, &b) }
    if a < c { swap(&a, &c) }
    if b < c { swap(&b, &c) }
    return FractalVector(a, b, c)
  }

  static func + (lhs: FractalVector, rhs: FractalVector) -> FractalVector {
    FractalVector(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
  }

  static func - (lhs: FractalVector, rhs: FractalVector) -> FractalVector {
    FractalVector(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
  }

  static func * (vector: FractalVector, scalar: Double) -> FractalVector {
    FractalVector(vector.x * scalar, vector.y * scalar, vector.z * scalar)
  }

  static func / (vector: FractalVector, scalar: Double) -> FractalVector {
    FractalVector(vector.x / scalar, vector.y / scalar, vector.z / scalar)
  }

  /// Adds the same number to each component.
  static func + (vector: FractalVector, offset: Double) -> FractalVector {
    FractalVector(vector.x + offset, vector.y + offset, vector.z + offset)
  }

  /// Subtracts the same number from each component.
  static func - (vector: FractalVector, offset: Double) -> FractalVector {
    FractalVector(vector.x - offset, vector.y - offset, vector.z - offset)
  }
}

/// A quaternion with its scalar part in w, for the quaternion Julia set and the quaternion cubic.
struct FractalQuaternion: Equatable, Sendable {
  var x: Double
  var y: Double
  var z: Double
  var w: Double

  init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) {
    self.x = x
    self.y = y
    self.z = z
    self.w = w
  }

  var normSquared: Double {
    x * x + y * y + z * z + w * w
  }

  /// The Hamilton product, which is not commutative. The Android engine writes it the same way.
  static func * (a: FractalQuaternion, b: FractalQuaternion) -> FractalQuaternion {
    FractalQuaternion(
      a.w * b.x + b.w * a.x + a.y * b.z - a.z * b.y,
      a.w * b.y + b.w * a.y + a.z * b.x - a.x * b.z,
      a.w * b.z + b.w * a.z + a.x * b.y - a.y * b.x,
      a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
  }

  static func + (lhs: FractalQuaternion, rhs: FractalQuaternion) -> FractalQuaternion {
    FractalQuaternion(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z, lhs.w + rhs.w)
  }

  static func * (quaternion: FractalQuaternion, scalar: Double) -> FractalQuaternion {
    FractalQuaternion(
      quaternion.x * scalar, quaternion.y * scalar, quaternion.z * scalar,
      quaternion.w * scalar)
  }
}
