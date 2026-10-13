import Foundation

extension EscapeTimeFractal {

  /// The camera of the three-dimensional kinds. The eye sits `distance` from the origin, at the
  /// given yaw and pitch, and looks at the origin. Yaw turns about the vertical axis, and pitch lifts
  /// the eye toward it. The ranges are the Android app's: pitch from -89 deg to 89 deg, distance from 0.5
  /// to 20, and yaw wrapped into [-180 deg, 180 deg).
  public struct Camera: Equatable, Sendable {
    /// Rotation about the vertical axis, in degrees.
    public var yaw: Double
    /// Elevation of the eye above the horizontal plane, in degrees.
    public var pitch: Double
    /// Distance from the eye to the origin.
    public var distance: Double

    /// The defaults are the engine's yaw of 0.65 and pitch of 0.3 radians, in degrees.
    public init(
      yaw: Double = 0.65 * 180 / .pi, pitch: Double = 0.3 * 180 / .pi, distance: Double = 3.5
    ) {
      self.yaw = yaw
      self.pitch = pitch
      self.distance = distance
    }

    /// The same camera with each value inside its range. A value that is not finite takes the
    /// fallback's, so a bad number never reaches the renderer.
    public func normalized(fallback: Camera = Camera()) -> Camera {
      Camera(
        yaw: yaw.isFinite ? Self.wrappedDegrees(yaw) : fallback.yaw,
        pitch: pitch.isFinite ? min(max(pitch, -89), 89) : fallback.pitch,
        distance: distance.isFinite ? min(max(distance, 0.5), 20) : fallback.distance)
    }

    /// The angle wrapped into [-180, 180). The value 180 itself stays at 180 when it is positive.
    private static func wrappedDegrees(_ degrees: Double) -> Double {
      var wrapped = (degrees + 180).truncatingRemainder(dividingBy: 360)
      if wrapped < 0 { wrapped += 360 }
      wrapped -= 180
      return wrapped == -180 && degrees > 0 ? 180 : wrapped
    }

    /// The eye and the view's axes. Forward points from the eye toward the origin. Right is
    /// forward crossed with the world's up axis, and up is right crossed with forward.
    struct Basis: Sendable {
      let eye: FractalVector
      let forward: FractalVector
      let right: FractalVector
      let up: FractalVector
    }

    var basis: Basis {
      let yawRadians = yaw * .pi / 180
      // The engine keeps the pitch within 0.49pi, short of the poles.
      let pitchRadians = min(max(pitch * .pi / 180, -0.49 * .pi), 0.49 * .pi)
      let eye =
        FractalVector(
          cos(pitchRadians) * cos(yawRadians),
          sin(pitchRadians),
          cos(pitchRadians) * sin(yawRadians)) * distance
      let forward = (FractalVector.zero - eye).normalized
      var right = forward.cross(FractalVector(0, 1, 0))
      if right.length < 1e-10 {
        right = FractalVector(1, 0, 0)
      } else {
        right = right.normalized
      }
      let up = right.cross(forward).normalized
      return Basis(eye: eye, forward: forward, right: right, up: up)
    }
  }
}

extension EscapeTimeFractal.Kind {

  /// The camera the kind opens with, from the Android app's `FractalType.kt`. The catalogue gives the yaw
  /// and the pitch in radians, and they are converted here to the camera's degrees. The two-dimensional
  /// kinds, and the kinds that keep the standard camera, get the engine's default of yaw 0.65, pitch 0.3
  /// and distance 3.5.
  public var defaultCamera: EscapeTimeFractal.Camera {
    func camera(
      yaw: Double = 0.65, pitch: Double = 0.3, distance: Double
    ) -> EscapeTimeFractal.Camera {
      EscapeTimeFractal.Camera(yaw: yaw * 180 / .pi, pitch: pitch * 180 / .pi, distance: distance)
    }
    switch self {
    case .mandelbulb: return camera(distance: 3.2)
    case .mandelbox: return camera(yaw: 0.7, pitch: 0.35, distance: 4.5)
    case .mengerSponge: return camera(yaw: 0.7, pitch: 0.45, distance: 3.6)
    case .sierpinskiPyramid: return camera(pitch: 0.35, distance: 3.8)
    case .quaternionJulia: return camera(pitch: 0.25, distance: 3.4)
    case .quaternionCubic: return camera(distance: 3.5)
    case .hybridMandelbulbJulia: return camera(distance: 4)
    case .sierpinskiGasket: return camera(pitch: 0.35, distance: 5)
    case .octahedralIFS, .icosahedralIFS: return camera(pitch: 0.35, distance: 9)
    case .apollonianGasket: return camera(pitch: 0.35, distance: 8)
    case .kleinian: return camera(distance: 5)
    case .pickover: return camera(distance: 3)
    case .lorenz: return camera(pitch: 0.25, distance: 5)
    case .rossler: return camera(distance: 5)
    default: return EscapeTimeFractal.Camera()
    }
  }
}
