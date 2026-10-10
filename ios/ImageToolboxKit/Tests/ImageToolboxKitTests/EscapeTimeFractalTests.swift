import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Escape-time fractals")
struct EscapeTimeFractalTests {

  private static func settings(_ kind: EscapeTimeFractal.Kind, power: Int = 2)
    -> EscapeTimeFractal.Settings
  {
    EscapeTimeFractal.Settings(kind: kind, maxIterations: 200, power: power)
  }

  @Test("the origin of the Mandelbrot set never escapes, and a point far away escapes at once")
  func mandelbrotPoints() {
    let inside = EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.mandelbrot))
    #expect(inside == nil)
    let outside = EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, Self.settings(.mandelbrot))
    #expect(outside != nil && outside! < 3)
  }

  @Test("a Julia set with the constant 0 keeps the origin inside")
  func juliaOrigin() {
    var settings = Self.settings(.julia)
    settings.juliaReal = 0
    settings.juliaImaginary = 0
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
  }

  @Test("the power-2 multibrot is the Mandelbrot set")
  func multibrotPowerTwo() {
    for (real, imaginary) in [(-1.0, 0.0), (0.3, 0.5), (1.0, 0.0), (-0.75, 0.1)] {
      let mandelbrot = EscapeTimeFractal.escapeValue(
        real: real, imaginary: imaginary, Self.settings(.mandelbrot))
      let multibrot = EscapeTimeFractal.escapeValue(
        real: real, imaginary: imaginary, Self.settings(.multibrot, power: 2))
      #expect((mandelbrot == nil) == (multibrot == nil))
    }
  }

  @Test("the burning ship and tricorn have their own inside points")
  func otherFamilies() {
    #expect(
      EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.burningShip)) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.tricorn)) == nil)
    #expect(
      EscapeTimeFractal.escapeValue(real: 1.5, imaginary: 1.5, Self.settings(.burningShip)) != nil)
  }

  @Test("a rendered picture has the requested size, and points inside the set are black")
  func renderSizeAndColour() throws {
    var settings = Self.settings(.mandelbrot)
    settings.centreReal = 0
    settings.centreImaginary = 0
    settings.span = 0.5
    let image = try #require(EscapeTimeFractal.render(settings, width: 32, height: 16))
    #expect(image.width == 32 && image.height == 16)
    let centre = image.pixel(x: 16, y: 8)
    #expect(centre.red == 0 && centre.green == 0 && centre.blue == 0)
  }

  @Test("Newton: the root 1 converges at the first step, z = 0 has no step, 2 is not black")
  func newtonPoints() {
    // The engine's count at convergence is 1 for the root 1, and the root's own offset is 0.
    let root = EscapeTimeFractal.escapeValue(real: 1, imaginary: 0, Self.settings(.newton))
    #expect(root == 1)
    let outside = EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, Self.settings(.newton))
    #expect(outside != nil)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.newton)) == nil)
  }

  @Test("the phoenix keeps c = 0 inside and lets c = 2 escape")
  func phoenixPoints() {
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.phoenix)) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, Self.settings(.phoenix)) != nil)
  }

  @Test("the Celtic map keeps c = -1 inside, where the orbit has period 2, and lets c = 2 escape")
  func celticPoints() {
    #expect(EscapeTimeFractal.escapeValue(real: -1, imaginary: 0, Self.settings(.celtic)) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, Self.settings(.celtic)) != nil)
  }

  @Test("the sine map keeps c = 0 inside, and lets c = 5 escape the radius 4 at the first step")
  func sinePoints() {
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.sine)) == nil)
    // The engine's sine map is c*sin z from z = 1, so z1 = 5 sin 1, with |z1| > 4, smoothed.
    let value = EscapeTimeFractal.escapeValue(real: 5, imaginary: 0, Self.settings(.sine))
    #expect(abs((value ?? 0) - (2 - log(log(5 * sin(1.0))) / log(2.0))) < 1e-12)
  }

  @Test("the cosine map keeps c = 0 inside, and c = 60 escapes its radius 50 at once")
  func cosinePoints() {
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, Self.settings(.cosine)) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 60, imaginary: 0, Self.settings(.cosine)) != nil)
  }
}
