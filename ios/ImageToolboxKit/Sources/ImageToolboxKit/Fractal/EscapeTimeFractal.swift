import Foundation

/// Fractals computed on the CPU. Escape-time kinds colour each pixel by the smoothed iteration at
/// which its orbit leaves the escape radius, and points that never leave are black. Newton's method
/// colours by its convergence count and the root it reaches. Density kinds (attractors, iterated
/// systems and the Buddhabrot) are drawn by the hits of many orbits, see `FractalDensity`. Every
/// formula, start point, escape radius and colouring input follows the Android engine's Rust
/// renderer, which is the reference here.
///
/// The kinds are grouped in `FractalKind.swift`, and each family's maps are in its own file:
/// `FractalPolynomial`, `FractalSpecial`, `FractalTranscendental`, `FractalRational`,
/// `FractalGeometric`, `FractalAttractors` and `FractalIFS`. The three-dimensional kinds are in
/// `Fractal3D`, `Fractal3DBulb`, `Fractal3DFolds` and `Fractal3DAttractors`, and their camera is in
/// `Fractal3DCamera`.
public enum EscapeTimeFractal {

  /// The constants of the attractors and of the three-dimensional kinds. Each kind uses the ones
  /// its `coefficientCount` names, counted from a.
  public struct Coefficients: Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double

    public init(a: Double = 0, b: Double = 0, c: Double = 0, d: Double = 0) {
      self.a = a
      self.b = b
      self.c = c
      self.d = d
    }
  }

  public struct Settings: Equatable, Sendable {
    public var kind: Kind
    /// Centre of the view in the complex plane.
    public var centreReal: Double
    public var centreImaginary: Double
    /// Height of the view in the complex plane, as the Android app's span. The width is this times the
    /// picture's aspect ratio.
    public var span: Double
    /// Iterations before a point counts as inside the set. From 16 to 2000. For density kinds it
    /// scales the number of orbit steps or samples.
    public var maxIterations: Int
    /// The constant for the Julia-type kinds.
    public var juliaReal: Double
    public var juliaImaginary: Double
    /// The exponent for the multibrot, multicorn and Buffalo kinds, from 2 to 16.
    public var power: Int
    /// The parameter p of the phoenix set, from -2 to 2.
    public var phoenixParameter: Double
    /// The relaxation a of Nova's step, from -2 to 2. With 1 the step is Newton's method.
    public var novaRelaxation: Double
    /// The constants of the attractors. Nil means the kind's defaults.
    public var coefficients: Coefficients?
    /// The escape radius, from 2 to 10 000. Nil means the kind's default from the Android app.
    public var bailout: Double?
    /// The camera of the three-dimensional kinds. Nil means the kind's default camera. The
    /// two-dimensional kinds ignore it.
    public var camera: Camera?
    /// The samples per side of each pixel, from 1 to 4. The escape-time and ray-marched kinds average
    /// the squared count of samples in each pixel. The density kinds use it only for their step budget.
    public var supersampling: Int
    /// Whether a ray-marched kind is drawn over a checkerboard floor. Off by default, as the engine's
    /// default is. The other kinds ignore it.
    public var showFloor: Bool
    /// The colours of the floor's two tiles, the primary and the secondary one.
    public var floorPrimary: RGBA
    public var floorSecondary: RGBA

    public init(
      kind: Kind = .mandelbrot,
      centreReal: Double = -0.5,
      centreImaginary: Double = 0,
      span: Double = 3.5,
      maxIterations: Int = 256,
      juliaReal: Double = -0.8,
      juliaImaginary: Double = 0.156,
      power: Int = 2,
      phoenixParameter: Double = -0.5,
      novaRelaxation: Double = 1,
      coefficients: Coefficients? = nil,
      bailout: Double? = nil,
      camera: Camera? = nil,
      supersampling: Int = 1,
      showFloor: Bool = false,
      floorPrimary: RGBA = RGBA(red: 255, green: 255, blue: 255),
      floorSecondary: RGBA = RGBA(red: 0, green: 0, blue: 0)
    ) {
      self.kind = kind
      self.centreReal = centreReal
      self.centreImaginary = centreImaginary
      self.span = span
      self.maxIterations = maxIterations
      self.juliaReal = juliaReal
      self.juliaImaginary = juliaImaginary
      self.power = power
      self.phoenixParameter = phoenixParameter
      self.novaRelaxation = novaRelaxation
      self.coefficients = coefficients
      self.bailout = bailout
      self.camera = camera
      self.supersampling = supersampling
      self.showFloor = showFloor
      self.floorPrimary = floorPrimary
      self.floorSecondary = floorSecondary
    }

    /// The same settings with each value inside its range. Non-finite values fall back to the
    /// kind's defaults, so a bad value never reaches a renderer.
    public func normalized() -> Settings {
      var result = self
      result.span = Self.clamped(span, 1e-12...1000, fallback: 3.5)
      result.maxIterations = min(max(maxIterations, 16), 2000)
      result.power = min(max(power, 2), 16)
      result.phoenixParameter = Self.clamped(phoenixParameter, -2...2, fallback: -0.5)
      result.novaRelaxation = Self.clamped(novaRelaxation, -2...2, fallback: 1)
      result.juliaReal = Self.clamped(juliaReal, -2...2, fallback: -0.8)
      result.juliaImaginary = Self.clamped(juliaImaginary, -2...2, fallback: 0.156)
      result.coefficients = coefficients.map { coefficients in
        Coefficients(
          a: Self.clamped(coefficients.a, -100...100, fallback: 0),
          b: Self.clamped(coefficients.b, -100...100, fallback: 0),
          c: Self.clamped(coefficients.c, -100...100, fallback: 0),
          d: Self.clamped(coefficients.d, -100...100, fallback: 0))
      }
      result.bailout = bailout.map { Self.clamped($0, 2...10_000, fallback: kind.defaultBailout) }
      result.camera = camera.map { $0.normalized(fallback: kind.defaultCamera) }
      result.supersampling = min(max(supersampling, 1), 4)
      return result
    }

    /// The attractor constants to use: the given ones, or the kind's defaults.
    var resolvedCoefficients: Coefficients {
      coefficients ?? kind.defaultCoefficients
    }

    /// The camera to use: the given one, or the kind's default.
    var resolvedCamera: Camera {
      camera ?? kind.defaultCamera
    }

    /// The escape radius to use: the given one, or the kind's default.
    var resolvedBailout: Double {
      bailout ?? kind.defaultBailout
    }

    private static func clamped(
      _ value: Double, _ range: ClosedRange<Double>, fallback: Double
    ) -> Double {
      guard value.isFinite else { return fallback }
      return min(max(value, range.lowerBound), range.upperBound)
    }
  }

  /// Renders the view as an opaque picture. Points inside the set are black, and the rest are coloured
  /// by their smoothed escape count. Each pixel is sampled on its supersampling grid, and with one sample
  /// that is its centre, as the engine samples it.
  public static func render(_ settings: Settings, width: Int, height: Int) -> RasterImage? {
    guard width > 0, height > 0 else { return nil }
    let parameters = settings.normalized()
    if parameters.kind.isDensity {
      return FractalDensity.render(parameters, width: width, height: height)
    }
    if parameters.kind.is3D {
      return Fractal3D.render(parameters, width: width, height: height)
    }
    // The vertical span covers the height, so the pixels are square.
    let scale = parameters.span / Double(height)
    let supersampling = effectiveSupersampling(parameters, width: width, height: height)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        var average = SubsampleAverage()
        for sampleY in 0..<supersampling {
          for sampleX in 0..<supersampling {
            // Each sample is at the centre of its part of the pixel.
            let column = Double(x) + (Double(sampleX) + 0.5) / Double(supersampling)
            let row = Double(y) + (Double(sampleY) + 0.5) / Double(supersampling)
            let real = parameters.centreReal + (column - Double(width) / 2) * scale
            let imaginary = parameters.centreImaginary - (row - Double(height) / 2) * scale
            average.add(
              colour(for: escapeValue(real: real, imaginary: imaginary, parameters)))
          }
        }
        let result = average.colour
        let index = (y * width + x) * 4
        pixels[index] = result.0
        pixels[index + 1] = result.1
        pixels[index + 2] = result.2
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// The state of one orbit: z, the value before it, and the constant c. Spider also updates c.
  struct Orbit {
    var z: FractalComplex
    var previous: FractalComplex
    var c: FractalComplex
  }

  /// The smoothed iteration count at which the orbit of the point leaves the escape radius, or nil
  /// when it does not leave within `maxIterations`. The orbit takes its step before the escape test, as
  /// the engine does, so a start outside the radius is not an escape. Newton's method, Nova, the Magnet
  /// sets, the Collatz map, the Lyapunov exponent and the geometric sets have their own rules.
  static func escapeValue(real: Double, imaginary: Double, _ settings: Settings) -> Double? {
    // The three-dimensional kinds have no count per point, as the density kinds have none.
    guard !settings.kind.is3D else { return nil }
    let point = FractalComplex(real, imaginary)
    switch settings.kind {
    case .newton:
      return newtonValue(real: real, imaginary: imaginary, maxIterations: settings.maxIterations)
    case .nova:
      return novaValue(
        point, relaxation: settings.novaRelaxation, bailout: settings.resolvedBailout,
        maxIterations: settings.maxIterations)
    case .magnetI, .magnetII:
      return magnetValue(
        point, doubled: settings.kind == .magnetII, bailout: settings.resolvedBailout,
        maxIterations: settings.maxIterations)
    case .collatz:
      return collatzValue(
        point, bailout: settings.resolvedBailout, maxIterations: settings.maxIterations)
    case .lyapunov:
      return lyapunovValue(a: real, b: imaginary, maxIterations: settings.maxIterations)
    case .sierpinskiCarpet:
      return carpetValue(point, maxLevels: settings.maxIterations)
    case .sierpinskiTriangle:
      return triangleValue(point, maxLevels: settings.maxIterations)
    default:
      break
    }
    guard !settings.kind.isDensity else { return nil }

    let limit = settings.resolvedBailout * settings.resolvedBailout
    var orbit = start(point, settings)
    var iterations = 0
    while iterations < settings.maxIterations {
      advance(&orbit, settings)
      iterations += 1
      let squared = orbit.z.squaredMagnitude
      // NaN fails the comparison too, so a pole or an overflow counts as an escape.
      if !(squared <= limit) {
        return smoothedCount(iterations, squared: squared, settings)
      }
    }
    return nil
  }

  /// The smoothed count of the engine: the count plus one, less ln ln|z| / ln p, where p is the exponent
  /// and at least 2. The radius is taken from the bailout when |z|^2 is not finite or not above 1. A
  /// non-finite result falls back to the whole count.
  static func smoothedCount(_ iterations: Int, squared: Double, _ settings: Settings) -> Double {
    let bailout = settings.resolvedBailout
    let safe = squared.isFinite && squared > 1 ? squared : max(bailout * bailout, 4)
    let exponent = log(Double(max(settings.power, 2)))
    let value = Double(iterations) + 1 - log(log(safe.squareRoot())) / exponent
    return value.isFinite ? value : Double(iterations)
  }

  /// The orbit before its first step. Julia-type kinds keep the constant and start at the pixel.
  static func start(_ point: FractalComplex, _ settings: Settings) -> Orbit {
    let julia = FractalComplex(settings.juliaReal, settings.juliaImaginary)
    switch settings.kind {
    case .julia, .burningShipJulia, .celticJulia, .juliaSine, .juliaCosine, .juliaSinh,
      .alphaMandelbrotJulia, .barnsleyJulia, .barnsleyII, .barnsleyIII:
      return Orbit(z: point, previous: .zero, c: julia)
    case .thorn:
      // Thorn takes its constant from the coefficients a and b, so it starts at the pixel.
      let constants = settings.resolvedCoefficients
      return Orbit(z: point, previous: .zero, c: FractalComplex(constants.a, constants.b))
    case .spider:
      return Orbit(z: point, previous: .zero, c: point)
    case .barnsleyMandelbrot, .zubieta:
      return Orbit(z: point, previous: .zero, c: point)
    case .sine, .nova, .tetration:
      return Orbit(z: FractalComplex(1, 0), previous: .zero, c: point)
    case .lambda:
      return Orbit(z: FractalComplex(0.5, 0), previous: .zero, c: point)
    default:
      return Orbit(z: .zero, previous: .zero, c: point)
    }
  }

  /// One step of the map of the orbit's kind.
  static func advance(_ orbit: inout Orbit, _ settings: Settings) {
    switch settings.kind {
    case .mandelbrot, .julia, .burningShip, .burningShipJulia, .perpendicularBurningShip,
      .tricorn, .multibrot, .multicorn, .celtic, .celticJulia, .phoenix, .spider, .manOWar,
      .lambda, .buddhabrot:
      advancePolynomial(&orbit, settings)
    case .sine, .cosine, .juliaSine, .juliaCosine, .sinh, .juliaSinh, .tetration:
      advanceTranscendental(&orbit, settings.kind)
    case .buffalo, .alphaMandelbrot, .alphaMandelbrotJulia, .cactus, .zubieta,
      .barnsleyMandelbrot, .barnsleyJulia, .barnsleyII, .barnsleyIII, .thorn, .feather:
      advanceSpecial(&orbit, settings)
    default:
      preconditionFailure("\(settings.kind) is not an orbit map")
    }
  }

  /// Black inside the set. Outside, the smoothed count moves round a hue wheel. A value that is not
  /// finite takes the first colour, as the engine's palette does for a non-finite position.
  static func colour(for value: Double?) -> (UInt8, UInt8, UInt8) {
    guard let value else { return (0, 0, 0) }
    let finite = value.isFinite ? value : 0
    let hue = (finite / 32).truncatingRemainder(dividingBy: 1)
    let rgb = OklabColour.hsvToRGB(hue: hue < 0 ? hue + 1 : hue, saturation: 0.75, value: 1)
    return (
      UInt8((rgb.red * 255).rounded()),
      UInt8((rgb.green * 255).rounded()),
      UInt8((rgb.blue * 255).rounded())
    )
  }
}
