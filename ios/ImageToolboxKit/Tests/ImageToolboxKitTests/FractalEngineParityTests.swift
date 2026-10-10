import Foundation
import Testing

@testable import ImageToolboxKit

/// Values worked out by hand from the Android engine's Rust renderer, one input point for each kind whose
/// formula, start point, radius, budget or colouring input was corrected. Each expectation is written out
/// from the formula in the engine's source, not read back from the Swift code.
@Suite("Fractal parity with the Android engine: hand-computed values")
struct FractalEngineParityTests {

  private static func settings(
    _ kind: EscapeTimeFractal.Kind, maxIterations: Int = 200, juliaReal: Double = -0.8,
    juliaImaginary: Double = 0.156
  ) -> EscapeTimeFractal.Settings {
    EscapeTimeFractal.Settings(
      kind: kind, maxIterations: maxIterations, juliaReal: juliaReal,
      juliaImaginary: juliaImaginary)
  }

  /// The engine's smoothed count for an escape at the given step, with |z|^2 = squared: the step plus one,
  /// less ln ln |z| over ln of the exponent.
  private static func smoothed(_ step: Int, squared: Double, exponent: Double = 2) -> Double {
    Double(step) + 1 - log(log(Double(squared).squareRoot())) / log(exponent)
  }

  @Test("PerpendicularBurningShip folds only the imaginary part, so c = -1 + i escapes at step 3")
  func perpendicularBurningShip() {
    // z1 = c = -1 + i. Then z2 = (-1 - i)^2 + c = -1 + 3i, and z3 = (-1 - 3i)^2 + c = -9 + 7i, with |z3|^2 = 130.
    let value = EscapeTimeFractal.escapeValue(
      real: -1, imaginary: 1, Self.settings(.perpendicularBurningShip))
    #expect(abs((value ?? 0) - Self.smoothed(3, squared: 130)) < 1e-12)
  }

  @Test("the sine map is c*sin z from z = 1, so c = 5 escapes at once with |z|^2 = 25 sin^2 1")
  func sine() {
    let value = EscapeTimeFractal.escapeValue(real: 5, imaginary: 0, Self.settings(.sine))
    #expect(abs((value ?? 0) - Self.smoothed(1, squared: 25 * pow(sin(1.0), 2))) < 1e-12)
    // From c = 0 the orbit stays at 0, which is inside.
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.sine)) == nil)
  }

  @Test("the Julia sine map is c*sin z from the pixel, so z = 5i with c = 1 + 0.1i escapes at once")
  func juliaSine() {
    // sin(5i) = i*sinh 5, so z1 = (1 + 0.1i)*i*sinh 5, and |z1|^2 = 1.01*sinh^2 5.
    let squared = 1.01 * pow(sinh(5.0), 2)
    let value = EscapeTimeFractal.escapeValue(
      real: 0, imaginary: 5, Self.settings(.juliaSine, juliaReal: 1, juliaImaginary: 0.1))
    #expect(abs((value ?? 0) - Self.smoothed(1, squared: squared)) < 1e-9)
  }

  @Test("tetration with base 0 escapes at once, smoothed on the bailout 100")
  func tetration() {
    // The engine's value is infinite, so its radius is the bailout: the count is 2 - ln(ln 100)/ln 2.
    let value = EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.tetration))
    #expect(abs((value ?? 0) - (2 - log(log(100.0)) / log(2.0))) < 1e-12)
  }

  @Test("a Julia orbit steps before its escape test: pixel 5 with c = 0 escapes at step 1")
  func juliaStepsBeforeTheTest() {
    // z0 = 5 lies outside the radius 4, but the engine first gives z1 = 25, with |z1|^2 = 625.
    let value = EscapeTimeFractal.escapeValue(
      real: 5, imaginary: 0, Self.settings(.julia, juliaReal: 0, juliaImaginary: 0))
    #expect(abs((value ?? 0) - Self.smoothed(1, squared: 625)) < 1e-12)
  }

  @Test("the Magnet quotients at z = 0 with c = -1: Magnet I is 2/3, and Magnet II is 6/7")
  func magnetQuotients() throws {
    let c = FractalComplex(-1, 0)
    let first = try #require(EscapeTimeFractal.magnetQuotient(.zero, c, doubled: false))
    #expect(abs(first.re - 2.0 / 3) < 1e-12 && abs(first.im) < 1e-12)
    let second = try #require(EscapeTimeFractal.magnetQuotient(.zero, c, doubled: true))
    #expect(abs(second.re - 6.0 / 7) < 1e-12 && abs(second.im) < 1e-12)
  }

  @Test("Collatz colours escapes by smoothed step over 50, the 1 -> 4 -> 2 cycle by distance")
  func collatz() {
    // z0 = 200 has |z|^2 = 40 000 > 100^2, so it escapes at step 0 + 1, with ln|z| = 1/2 ln 40 000.
    let logarithm = 0.5 * log(40_000.0)
    let smooth = 1 - log(logarithm / log(2.0)) / log(2.0)
    let position = smooth / 50 - floor(smooth / 50)
    let escape = EscapeTimeFractal.escapeValue(
      real: 200, imaginary: 0, Self.settings(.collatz))
    #expect(abs((escape ?? -1) - 32 * position) < 1e-9)
    // The cycle has nearest distance 1 and the position 2 * 1 mod 1 = 0. The engine never leaves it black.
    #expect(EscapeTimeFractal.escapeValue(real: 1, imaginary: 0, Self.settings(.collatz)) == 0)
  }

  @Test("Lyapunov with a = b = 2 settles on 1/2, its derivative floors at 10^-15, hue 1")
  func lyapunovSettled() {
    // The exponent is ln 10^-15 < -2.5 * 10^-1, so the position is 0.42 + 0.58 = 1, and the value 32.
    let value = EscapeTimeFractal.escapeValue(
      real: 2, imaginary: 2, Self.settings(.lyapunov, maxIterations: 100))
    #expect(abs((value ?? 0) - 32) < 1e-9)
  }

  @Test("Newton's method: z = 1 is a root, so the first step is zero, and the count is 1")
  func newtonRoot() {
    #expect(EscapeTimeFractal.escapeValue(real: 1, imaginary: 0, Self.settings(.newton)) == 1)
  }

  @Test("Nova from z = 1 with c = 0 converges at once, so its value is the plain count 1")
  func novaConverges() {
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.nova)) == 1)
  }

  @Test("the carpet and triangle: holes and the outside are black, solid points take one colour")
  func geometricColouring() {
    let carpet = Self.settings(.sierpinskiCarpet, maxIterations: 24)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, carpet) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, carpet) == nil)
    // The corner (-1, -1) has the digits 0 at every level, so it is solid: the value is 0.92 * 32.
    let solid = EscapeTimeFractal.escapeValue(real: -1, imaginary: -1, carpet)
    #expect(abs((solid ?? 0) - 0.92 * 32) < 1e-12)
    let triangle = Self.settings(.sierpinskiTriangle, maxIterations: 24)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, triangle) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: -1.5, triangle) == nil)
    // The top vertex has weights (1, 0, 0), so it stays solid at every level.
    let vertex = EscapeTimeFractal.escapeValue(real: 0, imaginary: 0.96, triangle)
    #expect(abs((vertex ?? 0) - 0.92 * 32) < 1e-12)
  }

  @Test("an attractor point stamps a disc of radius 2, 13 pixels, and a line point stamps 5 pixels")
  func attractorFootprint() {
    let view = EscapeTimeFractal.Settings(kind: .gingerbreadman, span: 9)
    var attractor = DensityCanvas(width: 9, height: 9, settings: view)
    attractor.add(real: 0, imaginary: 0, radius: 2)
    #expect(attractor.hits.reduce(0, +) == 13)
    var line = DensityCanvas(width: 9, height: 9, settings: view)
    line.add(real: 0, imaginary: 0)
    #expect(line.hits.reduce(0, +) == 5)
  }

  @Test("a projected point with weight 3 adds 6 to its pixel and 3 to each of its eight neighbours")
  func projectedBrush() {
    let view = EscapeTimeFractal.Settings(kind: .lorenz, span: 2)
    var canvas = DensityCanvas(width: 9, height: 9, settings: view)
    canvas.addProjected(x: 4.5, y: 4.5, weight: 3)
    #expect(canvas.hits.reduce(0, +) == 30)
    #expect(canvas.hits[4 * 9 + 4] == 6)
  }

  @Test("the engine's budgets at 512^2: 128 000 attractor steps, and 131 072 Buddhabrot samples")
  func densityBudgets() {
    #expect(FractalDensity.resolutionMultiplier(pixels: 512 * 512) == 1)
    #expect(FractalDensity.resolutionMultiplier(pixels: 1280 * 960) == 2)
    #expect(
      FractalDensity.budgetedSteps(base: 128_000, pixels: 512 * 512, costPerStep: 25) == 128_000)
    #expect(FractalDensity.buddhabrotSamples(pixels: 512 * 512, maxIterations: 800) == 131_072)
  }

  @Test("the ray-march plan at 512^2 and 640 x 480 trims the Mandelbulb to 9 and 8 iterations")
  func rayMarchPlan() {
    #expect(Fractal3D.desiredIterations(.mandelbulb, requested: 320) == 20)
    #expect(
      Fractal3D.rayMarchPlan(.mandelbulb, requested: 320, pixels: 512 * 512)
        == Fractal3D.RayMarchPlan(maximumSteps: 192, distanceIterations: 9))
    #expect(
      Fractal3D.rayMarchPlan(.mandelbulb, requested: 320, pixels: 640 * 480)
        == Fractal3D.RayMarchPlan(maximumSteps: 192, distanceIterations: 8))
  }

  @Test("the hybrid Mandelbulb matches the engine's reference samples, Julia constant z = 0.3")
  func hybridReference() {
    let julia = FractalVector(-0.2, 0.8, 0.3)
    let first = Fractal3DBulb.hybrid(
      FractalVector(0.37, -0.21, 0.54), power: 8, julia: julia, iterations: 12)
    #expect(abs(first - -0.016340226140528893) < 1e-12)
    let second = Fractal3DBulb.hybrid(
      FractalVector(-1.5, -1.5, -1.3), power: 8, julia: julia, iterations: 12)
    #expect(abs(second - 1.1338524354114028) < 1e-12)
  }

  @Test("Mandelbulb radius 2.5 bound: at (2.2, 0, 0) one step is 0.5 ln r * r / (8r^7 + 1)")
  func mandelbulbBailout() {
    let r = 2.2
    let expected = 0.5 * log(r) * r / (8 * pow(r, 7) + 1)
    let value = Fractal3DBulb.mandelbulb(FractalVector(r, 0, 0), power: 8, iterations: 1)
    #expect(abs(value - expected) < 1e-12)
  }

  @Test("quaternion Julia embeds the point as the engine does: one step from 0.8 + 0.1i + 0.2j")
  func quaternionJuliaStep() {
    // The scalar part is the point's x. The derivative starts at 2*sqrt0.69. Then z1 = z0^2 + c = 0.39 + 0.96i +
    // 0.32j, with |z1|^2 = 1.1761, so the estimate is 0.5 ln|z1| * |z1| / (2sqrt0.69).
    let r1 = Double(1.1761).squareRoot()
    let expected = 0.5 * log(r1) * r1 / (2 * Double(0.69).squareRoot())
    let value = Fractal3DBulb.quaternionJulia(
      FractalVector(0.8, 0.1, 0.2), constant: FractalQuaternion(-0.2, 0.8, 0, 0), iterations: 1)
    #expect(abs(value - expected) < 1e-12)
  }

  @Test("the Mandelbox scale is -1.65: one step from (0.5, 0.2, 0.3) with the sphere fold 1/0.38")
  func mandelboxStep() {
    let factor = 1 / 0.38
    let z = FractalVector(
      0.5 * factor * -1.65 + 0.5, 0.2 * factor * -1.65 + 0.2, 0.3 * factor * -1.65 + 0.3)
    let derivative = factor * 1.65 + 1
    let value = Fractal3DFolds.mandelbox(FractalVector(0.5, 0.2, 0.3), iterations: 1)
    #expect(abs(value - z.length / derivative) < 1e-12)
  }

  @Test("Menger takes the iteration count it is given: at (0.4, 0.4, 0.4), 2 steps give -0.6/9")
  func mengerIterations() {
    let point = FractalVector(0.4, 0.4, 0.4)
    #expect(abs(Fractal3DFolds.mengerSponge(point, iterations: 2) - (-0.6 / 9)) < 1e-12)
    #expect(abs(Fractal3DFolds.mengerSponge(point, iterations: 3) - (-0.2 / 27)) < 1e-12)
  }

  @Test("Sierpinski pyramid: a vertex maps to 0 in one step, so the estimate is -0.012")
  func pyramidVertex() {
    let value = Fractal3DFolds.sierpinskiPyramid(FractalVector(0.68, 0.68, 0.68), iterations: 1)
    #expect(abs(value - -0.012) < 1e-12)
  }

  @Test("the three-dimensional cameras take the catalogue's radians, converted to degrees")
  func cameraDefaults() {
    let toDegrees = 180 / Double.pi
    let lorenz = EscapeTimeFractal.Kind.lorenz.defaultCamera
    #expect(abs(lorenz.yaw - 0.65 * toDegrees) < 1e-12)
    #expect(abs(lorenz.pitch - 0.25 * toDegrees) < 1e-12)
    #expect(lorenz.distance == 5)
    let mandelbox = EscapeTimeFractal.Kind.mandelbox.defaultCamera
    #expect(abs(mandelbox.yaw - 0.7 * toDegrees) < 1e-12)
    #expect(abs(mandelbox.pitch - 0.35 * toDegrees) < 1e-12)
    #expect(mandelbox.distance == 4.5)
    #expect(abs(EscapeTimeFractal.Camera().yaw - 0.65 * toDegrees) < 1e-12)
  }

  @Test("corrected defaults: Magnet I/II at 0.5, span 4.5; Lyapunov span 2.2; Newton power 3")
  func corrected2DDefaults() {
    #expect(
      EscapeTimeFractal.Kind.magnetI.defaultView
        == EscapeTimeFractal.View(centreReal: 0.5, centreImaginary: 0, span: 4.5))
    #expect(
      EscapeTimeFractal.Kind.magnetII.defaultView
        == EscapeTimeFractal.View(centreReal: 0.5, centreImaginary: 0, span: 4.5))
    #expect(
      EscapeTimeFractal.Kind.lyapunov.defaultView
        == EscapeTimeFractal.View(centreReal: 3, centreImaginary: 3, span: 2.2))
    #expect(EscapeTimeFractal.Kind.newton.defaultPower == 3)
    #expect(EscapeTimeFractal.Kind.nova.defaultPower == 3)
  }
}
