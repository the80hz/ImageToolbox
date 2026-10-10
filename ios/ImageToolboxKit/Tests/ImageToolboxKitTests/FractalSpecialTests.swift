import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Special escape-time maps: Buffalo, Alpha Mandelbrot, Cactus, Zubieta, Feather and Barnsley")
struct FractalSpecialTests {

  private static func settings(_ kind: EscapeTimeFractal.Kind) -> EscapeTimeFractal.Settings {
    EscapeTimeFractal.Settings(kind: kind, maxIterations: 200)
  }

  @Test("Buffalo keeps the origin inside, and lets c = 2 escape its radius 4")
  func buffalo() {
    let settings = Self.settings(.buffalo)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, settings) != nil)
  }

  @Test("Cactus keeps the origin inside, and lets c = 3 escape its radius 100")
  func cactus() {
    let settings = Self.settings(.cactus)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 3, imaginary: 0, settings) != nil)
  }

  @Test("Alpha Mandelbrot keeps the origin inside, and lets c = 1 escape at the second step")
  func alphaMandelbrot() {
    let settings = Self.settings(.alphaMandelbrot)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
    // z goes 0, 2 and then 30, which is past the radius 4.
    #expect(EscapeTimeFractal.escapeValue(real: 1, imaginary: 0, settings) != nil)
  }

  @Test("Barnsley's first Mandelbrot map keeps the origin inside, and lets c = 3 escape")
  func barnsleyMandelbrot() {
    let settings = Self.settings(.barnsleyMandelbrot)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 3, imaginary: 0, settings) != nil)
  }

  @Test("Feather keeps the origin inside, and lets c = 3 escape")
  func feather() {
    let settings = Self.settings(.feather)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 3, imaginary: 0, settings) != nil)
  }

  @Test("Zubieta escapes its radius 100 from c = 3 in two steps")
  func zubieta() {
    let settings = Self.settings(.zubieta)
    #expect(EscapeTimeFractal.escapeValue(real: 3, imaginary: 0, settings) != nil)
  }

  @Test("Thorn escapes at the origin, where its sine vanishes and the map is infinite")
  func thorn() {
    let settings = Self.settings(.thorn)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) != nil)
  }

  @Test("the Barnsley Julia kinds take the Android constants by default")
  func barnsleyConstants() {
    let julia = EscapeTimeFractal.Kind.barnsleyJulia.defaultJuliaConstant
    #expect(julia.real == 1.1 && julia.imaginary == 0.6)
    let third = EscapeTimeFractal.Kind.barnsleyIII.defaultJuliaConstant
    #expect(third.real == -0.75 && third.imaginary == -0.2)
    #expect(EscapeTimeFractal.Kind.mandelbrot.defaultJuliaConstant.real == 0)
  }
}
