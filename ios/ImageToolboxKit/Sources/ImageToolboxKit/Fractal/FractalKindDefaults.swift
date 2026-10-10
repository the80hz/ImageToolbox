import Foundation

/// The defaults of each kind, taken from the Android app's formula catalogue: the view, the Julia
/// constant, the attractor constants, the escape radius, the exponent and the number of iterations.
extension EscapeTimeFractal.Kind {

  /// The view the kind opens on, in the complex plane.
  public var defaultView: EscapeTimeFractal.View {
    switch self {
    case .mandelbrot, .spider, .manOWar, .buffalo, .alphaMandelbrot: Self.view(-0.5, 0, 3)
    case .julia, .burningShipJulia, .celticJulia, .multibrot, .alphaMandelbrotJulia:
      Self.view(0, 0, 3)
    case .burningShip: Self.view(-0.45, -0.5, 2.4)
    case .perpendicularBurningShip: Self.view(-0.5, -0.25, 3)
    case .tricorn, .multicorn, .phoenix: Self.view(0, 0, 3.2)
    case .celtic: Self.view(-0.4, 0, 3)
    case .buddhabrot: Self.view(0.4, 0, 40.0 / 9.0)
    case .zubieta: Self.view(0, 0, 1.8)
    case .lambda, .cactus, .feather, .newton, .nova, .collatz, .sine, .juliaSine, .sinh,
      .juliaSinh, .tetration, .barnsleyMandelbrot, .barnsleyII, .clifford:
      Self.view(0, 0, 4)
    case .cosine, .juliaCosine, .barnsleyJulia: Self.view(0, 0, 6)
    case .barnsleyIII: Self.view(0, 0, 2.4)
    case .thorn: Self.view(0, 0, 3.5)
    case .magnetI, .magnetII: Self.view(0.5, 0, 4.5)
    case .lyapunov: Self.view(3, 3, 2.2)
    case .sierpinskiCarpet, .sierpinskiTriangle: Self.view(0, 0, 2.2)
    case .hopalong: Self.view(-0.1, 0.5, 4.2)
    case .martin: Self.view(Double.pi / 2, Double.pi / 2, 145)
    case .gingerbreadman: Self.view(2.5, 2.5, 12)
    case .deJong: Self.view(0, 0, 4.5)
    case .ikeda: Self.view(1, 0, 3)
    case .tinkerbell: Self.view(-0.5, -0.25, 3.5)
    case .gumowskiMira: Self.view(0, 0, 28)
    case .chip: Self.view(-7.2, -7.9, 720)
    case .quadruptwo: Self.view(16.5, 17.5, 200)
    case .threeply: Self.view(-34, -21, 5500)
    case .barnsleyFern: Self.view(0, 5, 11)
    case .ifsDragon: Self.view(0, 4, 12)
    case .ifsTwig, .christmasTree: Self.view(0.5, 0.5, 1.2)
    case .vicsekCross, .heighwayDragon, .kochSnowflake, .hTree, .hilbertCurve:
      Self.view(0, 0, 2.2)
    case .pythagorasTree: Self.view(0, 1.25, 5)
    // The camera frames the three-dimensional kinds, so their view is not used. The span is the
    // Android app's, which is 2 for all of them.
    case .mandelbulb, .mandelbox, .mengerSponge, .sierpinskiPyramid, .quaternionJulia,
      .quaternionCubic, .hybridMandelbulbJulia, .sierpinskiGasket, .octahedralIFS,
      .icosahedralIFS, .apollonianGasket, .kleinian, .pickover, .lorenz, .rossler:
      Self.view(0, 0, 2)
    }
  }

  private static func view(_ real: Double, _ imaginary: Double, _ span: Double)
    -> EscapeTimeFractal.View
  {
    EscapeTimeFractal.View(centreReal: real, centreImaginary: imaginary, span: span)
  }

  /// The constant c the Julia-type kind opens with. Kinds without one return 0 + 0i.
  public var defaultJuliaConstant: (real: Double, imaginary: Double) {
    switch self {
    case .julia, .burningShipJulia, .celticJulia: (-0.8, 0.156)
    case .alphaMandelbrotJulia: (0.36228, -0.0777)
    case .barnsleyJulia, .barnsleyII: (1.1, 0.6)
    case .barnsleyIII: (-0.75, -0.2)
    case .juliaSine: (1.0, 0.1)
    case .juliaCosine: (-0.2, 0.7)
    case .juliaSinh: (0.065, 0.122)
    case .hybridMandelbulbJulia: (-0.2, 0.8)
    default: (0, 0)
    }
  }

  /// The constants a to d the kind opens with, from the Android defaults.
  public var defaultCoefficients: EscapeTimeFractal.Coefficients {
    switch self {
    case .hopalong: .init(a: 0.4, b: 1, c: 0)
    case .martin: .init(a: Double.pi)
    case .clifford: .init(a: -1.4, b: 1.6, c: 1, d: 0.7)
    case .deJong: .init(a: -2.24, b: 0.43, c: -0.65, d: -2.43)
    case .ikeda: .init(a: 0.85, b: 0.9, c: 0.4, d: 7.7)
    case .tinkerbell: .init(a: 0.9, b: -0.6013, c: 2, d: 0.5)
    case .gumowskiMira: .init(a: 0.008, b: 0.05)
    case .chip: .init(a: -15, b: -19, c: 1)
    case .quadruptwo: .init(a: 34, b: 1, c: 5)
    case .threeply: .init(a: -55, b: -1, c: -42)
    case .thorn: .init(a: 0.1, b: -0.1)
    // The folding kinds take their scale, fold and minimum radius, and the quaternion kinds take
    // their constant. The attractors take their own constants, as the Android app gives them.
    case .sierpinskiGasket: .init(a: 1.5, b: 1, c: 0.5)
    case .octahedralIFS: .init(a: 2, b: 1.2)
    case .icosahedralIFS: .init(a: 1.7, b: 1.5)
    case .apollonianGasket: .init(a: 1.3, b: 1.35, c: 1.12)
    case .kleinian: .init(a: 1.5, b: 1, c: 0.5)
    case .quaternionJulia: .init(a: -0.2, b: 0.8)
    case .quaternionCubic: .init(a: -0.2, b: 0.6, c: 0.3)
    case .pickover: .init(a: 2.24, b: 0.43, c: -0.65, d: -2.43)
    case .lorenz: .init(a: 10, b: 28, c: 8.0 / 3.0)
    case .rossler: .init(a: 0.2, b: 0.2, c: 5.7)
    default: .init()
    }
  }

  /// How many of the constants a, b, c and d the kind has, counted from a.
  public var coefficientCount: Int {
    switch self {
    case .hopalong, .chip, .quadruptwo, .threeply, .sierpinskiGasket, .apollonianGasket,
      .kleinian, .lorenz, .rossler:
      3
    case .martin: 1
    case .clifford, .deJong, .ikeda, .tinkerbell, .quaternionJulia, .quaternionCubic, .pickover:
      4
    case .gumowskiMira, .thorn, .octahedralIFS, .icosahedralIFS: 2
    default: 0
    }
  }

  /// Whether the kind has a Julia constant, from `juliaReal` and `juliaImaginary`.
  public var usesJuliaConstant: Bool {
    switch self {
    case .julia, .burningShipJulia, .celticJulia, .alphaMandelbrotJulia, .barnsleyJulia,
      .barnsleyII, .barnsleyIII, .juliaSine, .juliaCosine, .juliaSinh, .hybridMandelbulbJulia:
      true
    default:
      false
    }
  }

  /// Whether the kind has an exponent, from `power`.
  public var usesPower: Bool {
    switch self {
    case .multibrot, .multicorn, .buffalo, .mandelbulb, .hybridMandelbulbJulia: true
    default: false
    }
  }

  /// The exponent the kind opens with.
  public var defaultPower: Int {
    switch self {
    case .multibrot, .multicorn, .nova, .newton: 3
    case .mandelbulb, .hybridMandelbulbJulia: 8
    default: 2
    }
  }

  /// Whether the kind has Nova's relaxation, from `novaRelaxation`.
  public var usesNovaRelaxation: Bool {
    self == .nova
  }

  /// The escape radius the kind opens with, from the Android app. A point escapes when its orbit
  /// leaves the radius, so the maps that grow slowly get a larger one.
  public var defaultBailout: Double {
    switch self {
    case .collatz, .feather, .cactus, .zubieta, .tetration: 100
    case .thorn: 10_000
    case .cosine, .juliaCosine, .sinh, .juliaSinh: 50
    case .buddhabrot: 2
    default: 4
    }
  }

  /// The number of iterations the kind opens with, from the Android app.
  public var defaultIterations: Int {
    if self == .buddhabrot { return 800 }
    if isDensity { return 1_000 }
    switch self {
    case .collatz: return 160
    case .thorn: return 500
    case .quaternionCubic: return 256
    case .hybridMandelbulbJulia, .kleinian: return 192
    case .sierpinskiGasket: return 128
    case .octahedralIFS, .icosahedralIFS, .apollonianGasket: return 160
    default: return 320
    }
  }
}
