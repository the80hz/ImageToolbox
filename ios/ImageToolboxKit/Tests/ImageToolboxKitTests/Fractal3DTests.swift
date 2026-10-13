import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Three-dimensional fractals: estimators, camera, attractors and renders")
struct Fractal3DTests {

  /// The ray-marched kinds, each with a point on or inside the set and one outside it. Inside means
  /// the estimate is below the hit threshold. The folding kinds are not signed inside, so their
  /// points are fixed points of the maps, scaled by the object scale, where the estimate is about
  /// zero.
  struct KnownPoint: Sendable, CustomTestStringConvertible {
    let kind: EscapeTimeFractal.Kind
    let inside: FractalVector
    let outside: FractalVector

    var testDescription: String { "\(kind)" }
  }

  private static let knownPoints: [KnownPoint] = [
    KnownPoint(
      kind: .mandelbulb, inside: FractalVector(0.5, 0, 0), outside: FractalVector(2.5, 0, 0)),
    KnownPoint(
      kind: .hybridMandelbulbJulia, inside: FractalVector(0, 0, 0),
      outside: FractalVector(2.5, 0, 0)),
    KnownPoint(kind: .mandelbox, inside: FractalVector(0, 0, 0), outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .mengerSponge, inside: FractalVector(0.95, 0.95, 0.95),
      outside: FractalVector(1.5, 0, 0)),
    KnownPoint(
      kind: .quaternionJulia, inside: FractalVector(-0.3, 0.1, 0.1),
      outside: FractalVector(2.5, 0, 0)),
    KnownPoint(
      kind: .quaternionCubic, inside: FractalVector(0, 0, 0), outside: FractalVector(2.5, 0, 0)),
    // The pyramid's inside point has a negative estimate at the default 10 iterations. A vertex
    // does not, since the fold sends the origin back out. The fixed points of the three IFS maps
    // are in world units.
    KnownPoint(
      kind: .sierpinskiPyramid, inside: FractalVector(-0.75, -0.5, 0.25),
      outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .sierpinskiGasket, inside: FractalVector(1.5, 1.5, 1.5),
      outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .octahedralIFS, inside: FractalVector(2, 2, 2), outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .icosahedralIFS, inside: FractalVector(1.7, 1.7, 1.7), outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .apollonianGasket, inside: FractalVector(-0.3, -0.3, -0.3),
      outside: FractalVector(3, 0, 0)),
    KnownPoint(
      kind: .kleinian, inside: FractalVector(-1.5, 0.6, 1.2), outside: FractalVector(3, 0, 0)),
  ]

  /// The estimator of a ray-marched kind, with the kind's default constants and iterations.
  private static func field(_ kind: EscapeTimeFractal.Kind) -> Fractal3DField {
    Fractal3DField(EscapeTimeFractal.Settings(kind: kind, maxIterations: kind.defaultIterations))
  }

  @Test(
    "the inside point is below the hit threshold, and the outside point is well above it",
    arguments: knownPoints)
  func knownPointsBehave(_ known: KnownPoint) {
    let field = Self.field(known.kind)
    let inside = field.distance(known.inside)
    let outside = field.distance(known.outside)
    #expect(inside.isFinite && inside < 1e-3, "\(known.kind) inside is \(inside)")
    #expect(outside.isFinite && outside > 1e-2, "\(known.kind) outside is \(outside)")
  }

  @Test("the estimates are finite over a grid, with the default settings of each kind")
  func finiteEstimatesOverGrid() {
    for kind in EscapeTimeFractal.Kind.allCases where kind.isRayMarched {
      let field = Self.field(kind)
      for x in 0..<7 {
        for y in 0..<7 {
          for z in 0..<7 {
            let point = FractalVector(
              -1.5 + 0.5 * Double(x), -1.5 + 0.5 * Double(y), -1.5 + 0.5 * Double(z))
            #expect(field.distance(point).isFinite, "\(kind) at \(point)")
          }
        }
      }
    }
  }

  @Test("the quaternion cubic matches the engine's reference sample")
  func quaternionCubicReference() {
    let value = Fractal3DBulb.quaternionCubic(
      FractalVector(0.37, -0.21, 0.54), constant: FractalQuaternion(-0.2, 0.6, 0.3, 0),
      iterations: 16)
    #expect(abs(value - 0.021641987147598706) < 1e-12)
  }

  @Test("the attractors stay finite and bounded along their orbits")
  func attractorOrbitsStayBounded() {
    let pickover = EscapeTimeFractal.Kind.pickover.defaultCoefficients
    let lorenz = EscapeTimeFractal.Kind.lorenz.defaultCoefficients
    let rossler = EscapeTimeFractal.Kind.rossler.defaultCoefficients
    var pickoverPoint = FractalVector(0.1, 0.1, 0.1)
    var lorenzPoint = FractalVector(0.1, 0, 0)
    var rosslerPoint = FractalVector(0.1, 0, 0)
    for _ in 0..<20_000 {
      pickoverPoint = Fractal3DAttractors.pickoverStep(pickoverPoint, pickover)
      lorenzPoint = Fractal3DAttractors.lorenzStep(lorenzPoint, lorenz)
      rosslerPoint = Fractal3DAttractors.rosslerStep(rosslerPoint, rossler)
    }
    #expect(pickoverPoint.isFinite && pickoverPoint.length < 10)
    #expect(lorenzPoint.isFinite && lorenzPoint.length < 100)
    #expect(rosslerPoint.isFinite && rosslerPoint.length < 100)
  }

  @Test("every three-dimensional kind renders a picture that is not blank at 64 by 64")
  func rendersNotBlank() throws {
    for kind in EscapeTimeFractal.Kind.allCases where kind.is3D {
      // The attractors draw one sample per step, so they get a short budget to keep a debug run quick.
      let iterations = kind.isDensity ? 64 : kind.defaultIterations
      let settings = EscapeTimeFractal.Settings(kind: kind, maxIterations: iterations)
      let image = try #require(EscapeTimeFractal.render(settings, width: 64, height: 64))
      #expect(image.width == 64 && image.height == 64, "\(kind)")
      let lit = Self.litPixels(image)
      #expect(lit > 64 * 64 / 50, "\(kind) has \(lit) lit pixels")
    }
  }

  @Test("the three-dimensional kinds have no count per point")
  func noCountPerPoint() {
    for kind in EscapeTimeFractal.Kind.allCases where kind.is3D {
      let settings = EscapeTimeFractal.Settings(kind: kind)
      #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil, "\(kind)")
    }
  }

  @Test("the camera keeps its values in range, and a bad value takes the fallback")
  func cameraNormalises() {
    let wrapped = EscapeTimeFractal.Camera(yaw: 270, pitch: 120, distance: 0.1).normalized()
    #expect(wrapped == EscapeTimeFractal.Camera(yaw: -90, pitch: 89, distance: 0.5))
    let half = EscapeTimeFractal.Camera(yaw: 180, pitch: -95, distance: 4).normalized()
    #expect(half == EscapeTimeFractal.Camera(yaw: 180, pitch: -89, distance: 4))
    let fallback = EscapeTimeFractal.Camera(yaw: 10, pitch: 5, distance: 4)
    let bad = EscapeTimeFractal.Camera(yaw: .nan, pitch: .infinity, distance: 50)
    #expect(
      bad.normalized(fallback: fallback)
        == EscapeTimeFractal.Camera(
          yaw: 10, pitch: 5, distance: 20))
  }

  @Test("the camera basis is orthonormal, and the eye lies on the line through the origin")
  func cameraBasis() {
    let camera = EscapeTimeFractal.Camera(yaw: -35, pitch: 20, distance: 3.5)
    let basis = camera.basis
    #expect(abs(basis.forward.length - 1) < 1e-12)
    #expect(abs(basis.right.length - 1) < 1e-12)
    #expect(abs(basis.up.length - 1) < 1e-12)
    #expect(abs(basis.forward.dot(basis.right)) < 1e-12)
    #expect(abs(basis.forward.dot(basis.up)) < 1e-12)
    #expect(abs(basis.right.dot(basis.up)) < 1e-12)
    let eye = basis.eye + basis.forward * 3.5
    #expect(eye.length < 1e-12)
  }

  @Test("the three-dimensional kinds open with the Android defaults")
  func androidDefaults() {
    #expect(EscapeTimeFractal.Kind.mandelbulb.defaultPower == 8)
    #expect(EscapeTimeFractal.Kind.mandelbulb.usesPower)
    #expect(EscapeTimeFractal.Kind.hybridMandelbulbJulia.usesJuliaConstant)
    #expect(EscapeTimeFractal.Kind.quaternionJulia.coefficientCount == 4)
    #expect(EscapeTimeFractal.Kind.quaternionCubic.coefficientCount == 4)
    #expect(EscapeTimeFractal.Kind.lorenz.coefficientCount == 3)
    #expect(EscapeTimeFractal.Kind.pickover.coefficientCount == 4)
    #expect(EscapeTimeFractal.Kind.mandelbulb.defaultCamera.distance == 3.2)
    #expect(EscapeTimeFractal.Kind.octahedralIFS.defaultCamera.distance == 9)
    // The catalogue's pitch of 0.35 radians, in the camera's degrees.
    #expect(
      abs(EscapeTimeFractal.Kind.sierpinskiGasket.defaultCamera.pitch - 0.35 * 180 / Double.pi)
        < 1e-12)
    #expect(EscapeTimeFractal.Kind.mengerSponge.defaultIterations == 320)
    #expect(EscapeTimeFractal.Kind.pickover.defaultIterations == 1_000)
  }

  /// The number of pixels that are not black.
  private static func litPixels(_ image: RasterImage) -> Int {
    var count = 0
    for index in stride(from: 0, to: image.pixels.count, by: 4) {
      if image.pixels[index] | image.pixels[index + 1] | image.pixels[index + 2] != 0 {
        count += 1
      }
    }
    return count
  }
}
