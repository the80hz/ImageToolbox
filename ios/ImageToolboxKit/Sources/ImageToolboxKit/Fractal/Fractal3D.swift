import Dispatch
import Foundation

/// The ray-marched three-dimensional kinds, rendered as the Android engine renders them. A pinhole
/// camera looks at the origin with a 45 deg vertical field of view. Each pixel's ray is marched with the
/// kind's distance estimator until it comes within a small epsilon of the surface, and a hit is shaded
/// by its normal, its step count and its fog. A miss is black. The estimators are in `Fractal3DBulb`
/// and `Fractal3DFolds`, and the attractors are in `Fractal3DAttractors`.
enum Fractal3D {

  /// The vertical field of view in degrees, as the Android engine uses it.
  static let fieldOfViewDegrees = 45.0

  /// The direction the light comes from, unit length, as the Android engine sets it. The floor shares it.
  static let light = FractalVector(-0.45, 0.8, -0.38).normalized

  /// The work plan of a picture: the steps of each march, and the iterations of each estimate.
  struct RayMarchPlan: Equatable, Sendable {
    let maximumSteps: Int
    let distanceIterations: Int
  }

  /// The estimator's iterations the request asks for, and the least the kind can use.
  static func distanceIterationRange(
    _ kind: EscapeTimeFractal.Kind, requested: Int
  ) -> (desired: Int, minimum: Int) {
    switch kind {
    case .mengerSponge: (min(max(requested / 48, 3), 7), 3)
    case .sierpinskiPyramid: (min(max(requested / 32, 6), 16), 6)
    case .octahedralIFS, .icosahedralIFS, .apollonianGasket: (min(max(requested / 16, 4), 18), 4)
    case .kleinian: (min(max(requested / 16, 10), 16), 10)
    case .hybridMandelbulbJulia, .quaternionCubic: (min(max(requested / 16, 6), 24), 6)
    case .sierpinskiGasket: (min(max(requested / 16, 5), 16), 5)
    case .mandelbulb, .mandelbox, .quaternionJulia: (min(max(requested / 16, 8), 28), 8)
    default: (0, 0)
    }
  }

  /// The estimator's iterations for the request, without the work budget of a picture.
  static func desiredIterations(_ kind: EscapeTimeFractal.Kind, requested: Int) -> Int {
    distanceIterationRange(kind, requested: requested).desired
  }

  /// The engine's plan for a kind at the requested iterations and a picture of the given pixels. The
  /// steps are the request, from 24 to 192. The estimator takes the request over the kind's divisor,
  /// within the kind's range. When the picture would exceed the work budget, the estimator's iterations
  /// come down first, and then the steps. Nil when even the smallest plan is over budget.
  static func rayMarchPlan(
    _ kind: EscapeTimeFractal.Kind, requested: Int, pixels: Int
  ) -> RayMarchPlan? {
    guard pixels > 0 else { return nil }
    let (desired, minimum) = distanceIterationRange(kind, requested: requested)
    let desiredSteps = min(max(requested, 24), 192)
    let minimumSteps = 24
    let allowance = FractalDensity.workBudget / pixels
    guard allowance >= (minimumSteps + 6) * minimum else { return nil }
    var maximumSteps = desiredSteps
    var iterations = desired
    if (desiredSteps + 6) * desired > allowance {
      iterations = max(min(allowance / (desiredSteps + 6), desired), minimum)
      if (desiredSteps + 6) * iterations > allowance {
        let affordable = max(allowance / iterations - 6, 0)
        maximumSteps = max(min(affordable, desiredSteps), minimumSteps)
      }
    }
    return RayMarchPlan(maximumSteps: maximumSteps, distanceIterations: iterations)
  }

  /// Renders the view of the camera. The rows are split across the cores. Each pixel averages the rays
  /// through the parts of it that the supersampling divides it into. Nil when the picture is too large
  /// for the engine's work budget, which counts the sampled pixels.
  static func render(
    _ settings: EscapeTimeFractal.Settings, width: Int, height: Int
  ) -> RasterImage? {
    let supersampling = EscapeTimeFractal.effectiveSupersampling(
      settings, width: width, height: height)
    guard
      let plan = rayMarchPlan(
        settings.kind, requested: settings.maxIterations,
        pixels: width * height * supersampling * supersampling)
    else { return nil }
    let field = Fractal3DField(settings, distanceIterations: plan.distanceIterations)
    let camera = settings.resolvedCamera
    let basis = camera.basis
    let tangent = tan(fieldOfViewDegrees * .pi / 360)
    let aspect = Double(width) / Double(height)
    let maxTravel = camera.distance + 12
    let ground =
      settings.showFloor
      ? Fractal3DFloor(primary: settings.floorPrimary, secondary: settings.floorSecondary)
      : nil
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    pixels.withUnsafeMutableBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return }
      let target = SharedPixels(base: base)
      DispatchQueue.concurrentPerform(iterations: height) { row in
        for column in 0..<width {
          var average = SubsampleAverage()
          for sampleY in 0..<supersampling {
            for sampleX in 0..<supersampling {
              // Each ray goes through the centre of its part of the pixel.
              let pixelX = Double(column) + (Double(sampleX) + 0.5) / Double(supersampling)
              let pixelY = Double(row) + (Double(sampleY) + 0.5) / Double(supersampling)
              let x = (2 * pixelX / Double(width) - 1) * aspect * tangent
              let y = (1 - 2 * pixelY / Double(height)) * tangent
              let direction = (basis.forward + basis.right * x + basis.up * y).normalized
              average.add(
                march(
                  eye: basis.eye, direction: direction, field: field,
                  maxSteps: plan.maximumSteps, maxTravel: maxTravel, ground: ground))
            }
          }
          let colour = average.colour
          let offset = (row * width + column) * 4
          target.base[offset] = colour.0
          target.base[offset + 1] = colour.1
          target.base[offset + 2] = colour.2
        }
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// The pixel buffer as seen by the rows that are rendered at once. Each row writes only the
  /// offsets of its own pixels, so no two rows touch the same bytes.
  private final class SharedPixels: @unchecked Sendable {
    let base: UnsafeMutablePointer<UInt8>

    init(base: UnsafeMutablePointer<UInt8>) {
      self.base = base
    }
  }

  /// The colour of the ray from the eye: the shaded hit, or black when the ray misses. With a floor, a
  /// ray that meets the floor first stops there and takes the floor's colour, unless it hits the shape
  /// before that.
  private static func march(
    eye: FractalVector, direction: FractalVector, field: Fractal3DField, maxSteps: Int,
    maxTravel: Double, ground: Fractal3DFloor?
  ) -> (UInt8, UInt8, UInt8) {
    let floorTravel = ground?.hit(eye: eye, direction: direction, maxTravel: maxTravel)
    let limit = floorTravel ?? maxTravel
    var travel = 0.0
    for step in 0..<maxSteps {
      let point = eye + direction * travel
      let distance = field.distance(point)
      // A non-finite estimate ends the ray as a miss, so no normal is taken at a bad point.
      guard distance.isFinite else { break }
      let epsilon = field.epsilon(at: travel)
      if distance < epsilon {
        let normal = surfaceNormal(point, travel: travel, field: field)
        let shade = Shade(
          normal: normal, direction: direction, travel: travel, step: step,
          maxSteps: maxSteps, maxTravel: maxTravel)
        return shade.colour()
      }
      travel += min(max(distance, epsilon * 0.5), 0.75)
      if travel > limit { break }
    }
    guard let ground, let floorTravel else { return (0, 0, 0) }
    return ground.colour(
      at: eye + direction * floorTravel, direction: direction, travel: floorTravel,
      maxTravel: maxTravel)
  }

  /// The normal from central differences of the estimate, with an offset that grows with travel.
  private static func surfaceNormal(
    _ point: FractalVector, travel: Double, field: Fractal3DField
  ) -> FractalVector {
    let offset = 0.0009 * (1 + 0.05 * travel)
    let gradient = FractalVector(
      field.distance(point + FractalVector(offset, 0, 0))
        - field.distance(point - FractalVector(offset, 0, 0)),
      field.distance(point + FractalVector(0, offset, 0))
        - field.distance(point - FractalVector(0, offset, 0)),
      field.distance(point + FractalVector(0, 0, offset))
        - field.distance(point - FractalVector(0, 0, offset)))
    return gradient.length > 0 ? gradient.normalized : FractalVector(0, 1, 0)
  }

  /// The shading of one hit, from the Android engine's model: a diffuse term, a specular highlight
  /// with exponent 28, a rim term and the step count pick a hue, and the fog darkens distant hits.
  private struct Shade {
    let normal: FractalVector
    let direction: FractalVector
    let travel: Double
    let step: Int
    let maxSteps: Int
    let maxTravel: Double

    func colour() -> (UInt8, UInt8, UInt8) {
      let diffuse = max(normal.dot(light), 0)
      let halfway = (light - direction).normalized
      let specular = pow(max(normal.dot(halfway), 0), 28)
      // The engine's rim is the square of one minus the facing, which is squared only once.
      let facing = 1 - abs(normal.dot(direction))
      let rim = facing * facing
      let stepDetail = Double(step) / Double(maxSteps)
      let position = 0.12 + 0.52 * diffuse + 0.18 * rim + 0.18 * stepDetail
      let hue = position - position.rounded(.down)
      let base = OklabColour.hsvToRGB(hue: hue, saturation: 0.7, value: 1)
      let lit = 0.28 + 0.72 * diffuse
      let fog = min(max(pow(travel / maxTravel, 1.7), 0), 0.82)
      let keep = 1 - fog
      return (
        Self.channel((base.red * lit + 0.55 * specular) * keep),
        Self.channel((base.green * lit + 0.55 * specular) * keep),
        Self.channel((base.blue * lit + 0.55 * specular) * keep)
      )
    }

    private static func channel(_ value: Double) -> UInt8 {
      UInt8((min(max(value, 0), 1) * 255).rounded())
    }
  }
}

/// The distance estimate of a ray-marched kind, with the kind's constants resolved from the settings.
/// The coefficients a, b and c are the scale, the fold and the minimum radius for the folding kinds,
/// and a, b, c and d are the quaternion constant for the quaternion kinds.
struct Fractal3DField: Sendable {
  let kind: EscapeTimeFractal.Kind
  let power: Double
  let iterations: Int
  let julia: FractalVector
  let quaternion: FractalQuaternion
  let objectScale: Double
  let fold: Double
  let radius: Double

  /// The field of the settings, with the estimator's iterations from the work plan, or the kind's
  /// unbudgeted count when no plan is given.
  init(_ settings: EscapeTimeFractal.Settings, distanceIterations: Int? = nil) {
    kind = settings.kind
    power = Double(settings.power)
    iterations =
      distanceIterations
      ?? Fractal3D.desiredIterations(settings.kind, requested: settings.maxIterations)
    // The hybrid takes its Julia constant in the plane z = 0.3, as the engine does.
    julia = FractalVector(settings.juliaReal, settings.juliaImaginary, 0.3)
    let constants = settings.resolvedCoefficients
    quaternion = FractalQuaternion(constants.a, constants.b, constants.c, constants.d)
    objectScale = constants.a
    fold = constants.b
    radius = constants.c
  }

  /// The signed distance estimate at the point. Inside the set it is zero or negative.
  func distance(_ point: FractalVector) -> Double {
    switch kind {
    case .mandelbulb:
      return Fractal3DBulb.mandelbulb(point, power: power, iterations: iterations)
    case .hybridMandelbulbJulia:
      return Fractal3DBulb.hybrid(point, power: power, julia: julia, iterations: iterations)
    case .quaternionJulia:
      return Fractal3DBulb.quaternionJulia(point, constant: quaternion, iterations: iterations)
    case .quaternionCubic:
      return Fractal3DBulb.quaternionCubic(point, constant: quaternion, iterations: iterations)
    case .mandelbox:
      return Fractal3DFolds.mandelbox(point, iterations: iterations)
    case .mengerSponge:
      return Fractal3DFolds.mengerSponge(point, iterations: iterations)
    case .sierpinskiPyramid:
      return Fractal3DFolds.sierpinskiPyramid(point, iterations: iterations)
    case .sierpinskiGasket:
      return Fractal3DFolds.sierpinskiGasket(
        point, objectScale: objectScale, fold: fold, minimumRadius: radius, iterations: iterations)
    case .octahedralIFS:
      return Fractal3DFolds.octahedralIFS(
        point, objectScale: objectScale, fold: fold, iterations: iterations)
    case .icosahedralIFS:
      return Fractal3DFolds.icosahedralIFS(
        point, objectScale: objectScale, fold: fold, iterations: iterations)
    case .apollonianGasket:
      return Fractal3DFolds.apollonianGasket(
        point, objectScale: objectScale, fold: fold, packing: radius, iterations: iterations)
    case .kleinian:
      return Fractal3DFolds.kleinian(
        point, objectScale: objectScale, fold: fold, minimumRadius: radius, iterations: iterations)
    default:
      preconditionFailure("\(kind) is not ray marched")
    }
  }

  /// The hit threshold at the travel along the ray. The Kleinian group uses a fixed one.
  func epsilon(at travel: Double) -> Double {
    kind == .kleinian ? 3.5e-4 : 4.5e-4 * (1 + 0.08 * travel)
  }
}
