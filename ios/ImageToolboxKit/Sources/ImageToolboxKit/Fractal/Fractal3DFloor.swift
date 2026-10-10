import Foundation

/// The checkerboard floor under a ray-marched shape, drawn as the Android engine draws it. The plane lies
/// at y = -1.6, since the camera looks at the origin, and a ray meets it only when it goes down toward it
/// from above. The tiles are 0.8 wide in x and z. A tile is shaded like a flat surface that faces up, and
/// fades into the black background with the ray's travel. A ray that meets the floor stops there, so the
/// shape beyond the floor is not drawn.
struct Fractal3DFloor: Sendable {

  /// The height of the plane: the target's height, which is the origin, less the engine's offset of 1.6.
  static let height = -1.6

  let primary: RGBA
  let secondary: RGBA

  /// The distance along the ray to the plane, when the ray meets it within the marched range. Nil when the
  /// eye is at or below the plane, or when the ray does not go down.
  func hit(eye: FractalVector, direction: FractalVector, maxTravel: Double) -> Double? {
    guard direction.y < -1e-9, eye.y > Self.height else { return nil }
    let distance = (Self.height - eye.y) / direction.y
    guard (0...maxTravel).contains(distance) else { return nil }
    return distance
  }

  /// The colour of the floor at the point, which the ray reached after the given travel.
  func colour(
    at point: FractalVector, direction: FractalVector, travel: Double, maxTravel: Double
  ) -> (UInt8, UInt8, UInt8) {
    // The tiles alternate, so the sum of their indices decides the colour, as the engine's euclidean
    // remainder of 2 does.
    let cells = Int(floor(point.x * 1.25)) + Int(floor(point.z * 1.25))
    let tile = ((cells % 2) + 2) % 2 == 0 ? secondary : primary
    // The surface faces up, so the diffuse term is the light's height, and the highlight uses the half
    // vector with exponent 36.
    let light = Fractal3D.light
    let diffuse = max(light.y, 0)
    let halfway = (light - direction).normalized
    let specular = pow(max(halfway.y, 0), 36)
    let lit = 0.2 + 0.7 * diffuse
    let shine = 0.35 * specular
    let fog = min(max(pow(travel / maxTravel, 1.7), 0), 0.88)
    let keep = 1 - fog
    return (
      Self.channel(tile.red, lit: lit, shine: shine, keep: keep),
      Self.channel(tile.green, lit: lit, shine: shine, keep: keep),
      Self.channel(tile.blue, lit: lit, shine: shine, keep: keep)
    )
  }

  /// One channel: the tile's value under the light and the highlight, clamped, then faded to black.
  private static func channel(_ value: UInt8, lit: Double, shine: Double, keep: Double) -> UInt8 {
    let shaded = min(max(Double(value) / 255 * lit + shine, 0), 1)
    return UInt8((shaded * keep * 255).rounded())
  }
}
