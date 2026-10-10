import Foundation

/// The three-dimensional attractors, drawn by the hits of one long orbit like the two-dimensional ones.
/// Pickover is iterated as a map. Lorenz and Rossler are integrated by forward Euler steps. The starts,
/// transients and output scales follow the Android engine's Rust renderer. Each point is projected through
/// the camera's 45 deg field of view, with a weight that falls with its depth, and it is added to the canvas
/// at its pixel, so the view is the camera, not the centre and span.
enum Fractal3DAttractors {

  /// Plots the orbit of the kind, with `steps` points after its transient.
  static func plot(
    _ settings: EscapeTimeFractal.Settings, into canvas: inout DensityCanvas, steps: Int
  ) {
    let constants = settings.resolvedCoefficients
    let projection = Projection(
      camera: settings.resolvedCamera, width: canvas.width, height: canvas.height)
    switch settings.kind {
    case .pickover:
      var point = FractalVector(0.1, 0.1, 0.1)
      for index in 0..<(500 + steps) {
        point = pickoverStep(point, constants)
        guard point.isFinite else { break }
        if index >= 500 {
          projection.add(point * 0.3, into: &canvas)
        }
      }
    case .lorenz:
      var point = FractalVector(0.1, 0, 0)
      for index in 0..<(1_000 + steps) {
        point = lorenzStep(point, constants)
        guard point.isFinite else { break }
        if index >= 1_000 {
          projection.add(FractalVector(point.x, point.y, point.z - 25) * 0.05, into: &canvas)
        }
      }
    case .rossler:
      var point = FractalVector(0.1, 0, 0)
      for index in 0..<(2_000 + steps) {
        point = rosslerStep(point, constants)
        guard point.isFinite else { break }
        if index >= 2_000 {
          projection.add(point * 0.1, into: &canvas)
        }
      }
    default:
      preconditionFailure("\(settings.kind) is not a three-dimensional attractor")
    }
  }

  /// Pickover: x' = sin(a*y) - z*cos(b*x), y' = z*sin(c*x) - cos(d*y), z' = sin x.
  static func pickoverStep(
    _ p: FractalVector, _ constants: EscapeTimeFractal.Coefficients
  ) -> FractalVector {
    FractalVector(
      sin(constants.a * p.y) - p.z * cos(constants.b * p.x),
      p.z * sin(constants.c * p.x) - cos(constants.d * p.y),
      sin(p.x))
  }

  /// Lorenz, with sigma = a, rho = b and beta = c, by an Euler step of 0.005. All three updates use the previous
  /// point.
  static func lorenzStep(_ p: FractalVector, _ constants: EscapeTimeFractal.Coefficients)
    -> FractalVector
  {
    let dt = 0.005
    return FractalVector(
      p.x + constants.a * (p.y - p.x) * dt,
      p.y + (p.x * (constants.b - p.z) - p.y) * dt,
      p.z + (p.x * p.y - constants.c * p.z) * dt)
  }

  /// Rossler, with a, b and c, by an Euler step of 0.02.
  static func rosslerStep(_ p: FractalVector, _ constants: EscapeTimeFractal.Coefficients)
    -> FractalVector
  {
    let dt = 0.02
    return FractalVector(
      p.x + (-p.y - p.z) * dt,
      p.y + (p.x + constants.a * p.y) * dt,
      p.z + (constants.b + p.z * (p.x - constants.c)) * dt)
  }

  /// The perspective projection of the camera, as the engine computes it. The picture plane is at the
  /// tangent of half the field of view, so a point's horizontal and vertical positions are its offsets
  /// over its depth, scaled by that tangent and the aspect ratio.
  struct Projection {
    let eye: FractalVector
    let forward: FractalVector
    let right: FractalVector
    let up: FractalVector
    let tangent: Double
    let aspect: Double
    let width: Double
    let height: Double

    init(camera: EscapeTimeFractal.Camera, width: Int, height: Int) {
      let basis = camera.basis
      eye = basis.eye
      forward = basis.forward
      right = basis.right
      up = basis.up
      tangent = tan(Fractal3D.fieldOfViewDegrees * .pi / 360)
      aspect = Double(width) / Double(height)
      self.width = Double(width)
      self.height = Double(height)
    }

    /// Adds the point to the canvas at its pixel, with the weight of its depth: 24 over the depth, rounded
    /// and clamped to 1...24, with the depth at least 0.25. A point behind the eye, or outside the picture
    /// by more than a pixel, is dropped.
    func add(_ point: FractalVector, into canvas: inout DensityCanvas) {
      let relative = point - eye
      let depth = relative.dot(forward)
      guard depth.isFinite, depth > 1e-6 else { return }
      let horizontal = relative.dot(right) / (depth * tangent * aspect)
      let vertical = relative.dot(up) / (depth * tangent)
      let pixelX = (horizontal + 1) * 0.5 * width
      let pixelY = (1 - vertical) * 0.5 * height
      guard pixelX >= -1, pixelY >= -1, pixelX <= width + 1, pixelY <= height + 1 else { return }
      let scaledWeight = min(max((24 / max(depth, 0.25)).rounded(), 1), 24)
      canvas.addProjected(x: pixelX, y: pixelY, weight: UInt32(scaledWeight))
    }
  }
}
