import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Fractal families: known points, finite values and symmetry")
struct FractalFamilyTests {

  /// A point known to stay inside an escape-time kind, and one known to escape. The Julia-type
  /// kinds take their constant from `julia`, and the power kinds take an exponent.
  struct KnownPoint: Sendable, CustomTestStringConvertible {
    let kind: EscapeTimeFractal.Kind
    let inside: (Double, Double)?
    let escape: (Double, Double)
    let julia: (Double, Double)
    let power: Int

    init(
      _ kind: EscapeTimeFractal.Kind,
      inside: (Double, Double)?,
      escape: (Double, Double),
      julia: (Double, Double) = (0, 0),
      power: Int = 2
    ) {
      self.kind = kind
      self.inside = inside
      self.escape = escape
      self.julia = julia
      self.power = power
    }

    var testDescription: String { "\(kind)" }

    /// The escape radius is 2, as these points were chosen for. The Android default radius is
    /// kind-specific, and the default-radius cases are covered in `EscapeTimeFractalTests`.
    var settings: EscapeTimeFractal.Settings {
      EscapeTimeFractal.Settings(
        kind: kind, maxIterations: 200, juliaReal: julia.0, juliaImaginary: julia.1,
        power: power, bailout: 2)
    }
  }

  /// The inside point is black in the engine. It is nil for Nova, Lyapunov and Collatz, which colour
  /// every point, so only their escape point is checked. For the geometric kinds, the inside point
  /// is a hole or outside the shape, and the escape point is solid, as the engine draws them.
  private static let knownPoints: [KnownPoint] = [
    KnownPoint(.mandelbrot, inside: (0, 0), escape: (2, 0)),
    KnownPoint(.multicorn, inside: (0, 0), escape: (2, 0), power: 3),
    KnownPoint(.perpendicularBurningShip, inside: (0, 0), escape: (2, 0)),
    KnownPoint(.burningShipJulia, inside: (0, 0), escape: (2, 2)),
    KnownPoint(.celticJulia, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.spider, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.manOWar, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.lambda, inside: (0, 0), escape: (10, 0)),
    KnownPoint(.sine, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.cosine, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.juliaSine, inside: (0, 0), escape: (3, 3), julia: (1.0, 0.1)),
    KnownPoint(.juliaCosine, inside: (0, 0), escape: (3, 3)),
    KnownPoint(.sinh, inside: (0, 0), escape: (3, 0)),
    KnownPoint(.juliaSinh, inside: (0, 0), escape: (3, 3)),
    KnownPoint(.tetration, inside: (1, 0), escape: (3, 0)),
    KnownPoint(.nova, inside: nil, escape: (3, 0)),
    KnownPoint(.magnetI, inside: (1, 0), escape: (2, 0)),
    KnownPoint(.magnetII, inside: (1, 0), escape: (1.5, 1.0)),
    KnownPoint(.collatz, inside: nil, escape: (0, 2)),
    KnownPoint(.lyapunov, inside: nil, escape: (2.5, 2.5)),
    KnownPoint(.sierpinskiCarpet, inside: (0, 0), escape: (-0.8, -0.8)),
    KnownPoint(.sierpinskiTriangle, inside: (0, 1), escape: (0, 0.96)),
  ]

  @Test("the inside point stays inside, and the escape point leaves", arguments: knownPoints)
  func knownPointsBehave(_ known: KnownPoint) {
    if let inside = known.inside {
      let value = EscapeTimeFractal.escapeValue(
        real: inside.0, imaginary: inside.1, known.settings)
      #expect(value == nil, "\(known.kind) inside point")
    }
    let escape = EscapeTimeFractal.escapeValue(
      real: known.escape.0, imaginary: known.escape.1, known.settings)
    #expect(escape != nil, "\(known.kind) escape point")
    if let escape {
      #expect(escape.isFinite, "\(known.kind) escape value")
    }
  }

  /// Points that lie off the real axis, so that the conjugate of each is a different point.
  private static let samplePoints: [(Double, Double)] = [
    (0.3, 0.4), (-0.7, 0.2), (1.2, -0.5), (0.1, 1.1), (-1.6, 0.3),
  ]

  /// Real-coefficient maps with z starting at a real value. The map commutes with conjugation, so
  /// the orbit of conj(c) is the conjugate of the orbit of c, and the counts agree.
  private static let conjugateSymmetric: [EscapeTimeFractal.Kind] = [
    .mandelbrot, .multicorn, .tricorn, .celtic, .phoenix, .spider, .manOWar, .lambda, .sine,
    .cosine, .sinh, .tetration, .nova, .magnetI, .magnetII, .collatz,
  ]

  @Test(
    "real-coefficient maps count the same at c and its conjugate", arguments: conjugateSymmetric)
  func conjugateSymmetry(_ kind: EscapeTimeFractal.Kind) {
    let settings = EscapeTimeFractal.Settings(kind: kind, maxIterations: 120, power: 3)
    for (real, imaginary) in Self.samplePoints {
      Self.expectSameCount(
        EscapeTimeFractal.escapeValue(real: real, imaginary: imaginary, settings),
        EscapeTimeFractal.escapeValue(real: real, imaginary: -imaginary, settings),
        "\(kind) at \(real), \(imaginary)")
    }
  }

  /// The Julia-type kinds. Conjugating both z and the constant leaves the count unchanged.
  private static let juliaKinds: [EscapeTimeFractal.Kind] = [
    .julia, .celticJulia, .juliaSine, .juliaCosine, .juliaSinh,
  ]

  @Test("Julia-type kinds count the same at z, c and their conjugates", arguments: juliaKinds)
  func juliaConjugateSymmetry(_ kind: EscapeTimeFractal.Kind) {
    let constant = kind.defaultJuliaConstant
    let direct = EscapeTimeFractal.Settings(
      kind: kind, maxIterations: 120, juliaReal: constant.real,
      juliaImaginary: constant.imaginary)
    let mirrored = EscapeTimeFractal.Settings(
      kind: kind, maxIterations: 120, juliaReal: constant.real,
      juliaImaginary: -constant.imaginary)
    for (real, imaginary) in Self.samplePoints {
      Self.expectSameCount(
        EscapeTimeFractal.escapeValue(real: real, imaginary: imaginary, direct),
        EscapeTimeFractal.escapeValue(real: real, imaginary: -imaginary, mirrored),
        "\(kind) at \(real), \(imaginary)")
    }
  }

  @Test(
    "the carpet and the triangle are symmetric about the vertical axis",
    arguments: [EscapeTimeFractal.Kind.sierpinskiCarpet, .sierpinskiTriangle])
  func geometricSymmetry(_ kind: EscapeTimeFractal.Kind) {
    let settings = EscapeTimeFractal.Settings(kind: kind, maxIterations: 24)
    for (real, imaginary) in Self.samplePoints {
      Self.expectSameCount(
        EscapeTimeFractal.escapeValue(real: real, imaginary: imaginary, settings),
        EscapeTimeFractal.escapeValue(real: -real, imaginary: imaginary, settings),
        "\(kind) at \(real), \(imaginary)")
    }
  }

  @Test("every escape-time kind gives finite values over a grid of its default view")
  func finiteValuesOverDefaultView() {
    for kind in EscapeTimeFractal.Kind.allCases where !kind.isDensity && !kind.is3D {
      let view = kind.defaultView
      let constant = kind.defaultJuliaConstant
      let settings = EscapeTimeFractal.Settings(
        kind: kind, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
        span: view.span, maxIterations: 128, juliaReal: constant.real,
        juliaImaginary: constant.imaginary, power: kind.usesPower ? 3 : 2
      ).normalized()
      for column in 0..<9 {
        for row in 0..<9 {
          let real = view.centreReal + (Double(column) / 8 - 0.5) * view.span
          let imaginary = view.centreImaginary + (Double(row) / 8 - 0.5) * view.span
          if let value = EscapeTimeFractal.escapeValue(
            real: real, imaginary: imaginary, settings)
          {
            #expect(value.isFinite, "\(kind) at \(real), \(imaginary)")
          }
        }
      }
    }
  }

  @Test("Collatz point 1 is coloured by its cycle at once, and the origin too, not black")
  func collatzPoints() {
    let settings = EscapeTimeFractal.Settings(kind: .collatz, maxIterations: 200)
    #expect(EscapeTimeFractal.escapeValue(real: 1, imaginary: 0, settings) == 0)
    // The origin is a fixed point with nearest distance 0, so its position is 0, not black.
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, settings) == 0)
  }

  @Test("the centre of the carpet and of the triangle is a black hole, and the outside is black")
  func centreIsAHole() {
    let carpet = EscapeTimeFractal.Settings(kind: .sierpinskiCarpet, maxIterations: 24)
    let triangle = EscapeTimeFractal.Settings(kind: .sierpinskiTriangle, maxIterations: 24)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, carpet) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: 0, triangle) == nil)
    // Outside the square, or outside the big triangle, the point is black.
    #expect(EscapeTimeFractal.escapeValue(real: 2, imaginary: 0, carpet) == nil)
    #expect(EscapeTimeFractal.escapeValue(real: 0, imaginary: -1.5, triangle) == nil)
  }

  @Test("every kind renders a picture of the requested size, with small settings")
  func everyKindRenders() throws {
    for kind in EscapeTimeFractal.Kind.allCases {
      let view = kind.defaultView
      let constant = kind.defaultJuliaConstant
      let settings = EscapeTimeFractal.Settings(
        kind: kind, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
        span: view.span, maxIterations: 16, juliaReal: constant.real,
        juliaImaginary: constant.imaginary)
      let image = try #require(EscapeTimeFractal.render(settings, width: 24, height: 16))
      #expect(image.width == 24 && image.height == 16, "\(kind)")
      #expect(image.pixels.count == 24 * 16 * 4, "\(kind)")
    }
  }

  @Test("the catalogue has 62 two-dimensional kinds in seven families, and 15 three-dimensional")
  func catalogueSplit() {
    let kinds = EscapeTimeFractal.Kind.allCases
    #expect(kinds.count == 77)
    let counts = Dictionary(grouping: kinds, by: \.family).mapValues(\.count)
    #expect(counts[.polynomial] == 20)
    #expect(counts[.barnsley] == 4)
    #expect(counts[.transcendental] == 8)
    #expect(counts[.rational] == 7)
    #expect(counts[.geometric] == 2)
    #expect(counts[.attractor] == 11)
    #expect(counts[.iterated] == 10)
    #expect(counts[.threeDimensional] == 15)
    // 22 two-dimensional kinds (the attractors, the iterated shapes and the Buddhabrot) and 3
    // three-dimensional attractors are drawn by hits.
    #expect(kinds.filter(\.isDensity).count == 25)
    #expect(kinds.filter(\.isRayMarched).count == 12)
  }

  @Test("the parameters are normalised into their ranges, and bad numbers fall back")
  func settingsNormalise() {
    let settings = EscapeTimeFractal.Settings(
      kind: .martin, span: 5000, maxIterations: 1, novaRelaxation: 9,
      coefficients: EscapeTimeFractal.Coefficients(a: .nan, b: 500, c: -500, d: 1)
    ).normalized()
    #expect(settings.span == 1000)
    #expect(settings.maxIterations == 16)
    #expect(settings.novaRelaxation == 2)
    #expect(settings.coefficients == EscapeTimeFractal.Coefficients(a: 0, b: 100, c: -100, d: 1))
  }

  /// Both counts are nil, or both are equal within rounding.
  static func expectSameCount(_ first: Double?, _ second: Double?, _ label: String) {
    switch (first, second) {
    case (nil, nil):
      return
    case (let a?, let b?):
      #expect(abs(a - b) < 1e-9, "\(label): \(a) and \(b)")
    default:
      Issue.record("\(label): one count is nil and the other is not")
    }
  }
}
