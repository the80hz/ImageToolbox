import Foundation

extension EscapeTimeFractal {

  /// A view of the complex plane: its centre and its width.
  public struct View: Equatable, Sendable {
    public var centreReal: Double
    public var centreImaginary: Double
    public var span: Double

    public init(centreReal: Double, centreImaginary: Double, span: Double) {
      self.centreReal = centreReal
      self.centreImaginary = centreImaginary
      self.span = span
    }
  }

  /// The kinds of the Android engine's catalogue: 62 two-dimensional and 15 three-dimensional. The
  /// defaults of each kind are in `FractalKindDefaults.swift` and `Fractal3DCamera.swift`.
  public enum Kind: CaseIterable, Sendable {
    // Polynomial maps: z -> f(z) + c, with f a power or a fold of z.
    /// z -> z^2 + c, with z starting at 0 and c the pixel.
    case mandelbrot
    /// z -> z^2 + c, with c fixed and z starting at the pixel.
    case julia
    /// z -> (|re z| + i|im z|)^2 + c.
    case burningShip
    /// z -> (|re z| + i|im z|)^2 + c, with c fixed and z starting at the pixel.
    case burningShipJulia
    /// z -> (re z - i|im z|)^2 + c.
    case perpendicularBurningShip
    /// z -> conj(z)^2 + c.
    case tricorn
    /// z -> z^power + c, for power 2 to 16.
    case multibrot
    /// z -> conj(z)^power + c, for power 2 to 16.
    case multicorn
    /// z -> |re(z^2)| + i*im(z^2) + c, the Celtic fold of the Mandelbrot map.
    case celtic
    /// The Celtic map with c fixed and z starting at the pixel.
    case celticJulia
    /// z -> z^2 + c + p*z_prev, with z and z_prev starting at 0 and c the pixel.
    case phoenix
    /// z -> z^2 + c_n and c_{n+1} = c_n / 2 + z_{n+1}, with z and c starting at the pixel.
    case spider
    /// z -> z^2 + z_prev + c, with z and z_prev starting at 0 and c the pixel.
    case manOWar
    /// z -> lambda*z*(1 - z), with z starting at 1/2 and lambda the pixel.
    case lambda
    /// Buddhabrot: the orbits of sampled points that escape, drawn as hit counts.
    case buddhabrot
    /// Buffalo: z -> (|re z| + i|im z|)^power, with the parts made positive again, plus c.
    case buffalo
    /// z -> s + (s + c)^2 + c with s = z^2, z and c starting at 0 and the pixel.
    case alphaMandelbrot
    /// The Alpha Mandelbrot map with c fixed and z starting at the pixel.
    case alphaMandelbrotJulia
    /// z -> z^2 + c/z, with z and c starting at the pixel.
    case zubieta
    /// z -> z*z^2 + (c - 1)*z - c, with z starting at 0 and c the pixel.
    case cactus

    // Barnsley's maps, which switch by the sign of a part of z.
    /// z -> (z -/+ 1)*c, with z and c starting at the pixel. Barnsley's first Mandelbrot map.
    case barnsleyMandelbrot
    /// The first Barnsley map with c fixed and z starting at the pixel.
    case barnsleyJulia
    /// The second Barnsley map, switching by the sign of the imaginary part of z*c.
    case barnsleyII
    /// The third Barnsley map, z^2 - 1 with c*Re z added when Re z is not positive.
    case barnsleyIII

    // Transcendental maps.
    /// z -> c*sin z, with z starting at 1 and c the pixel.
    case sine
    /// z -> cos z + c, with z starting at 0 and c the pixel.
    case cosine
    /// z -> c*sin z, with c fixed and z starting at the pixel.
    case juliaSine
    /// z -> cos z + c, with c fixed and z starting at the pixel.
    case juliaCosine
    /// z -> sinh z + c, with z starting at 0 and c the pixel.
    case sinh
    /// z -> sinh z + c, with c fixed and z starting at the pixel.
    case juliaSinh
    /// z -> c^z, the power tower, with z starting at 1 and c the pixel.
    case tetration
    /// Thorn: z -> Re z / cos(Im z) + a and Im z / sin(Re z) + b, with z starting at the pixel.
    case thorn

    // Newton-type and rational maps.
    /// Newton's method for z^3 - 1, with z starting at the pixel. Coloured by the root reached.
    case newton
    /// z -> z - a*(z^3 - 1)/(3z^2) + c, with z starting at 1 and c the pixel.
    case nova
    /// z -> ((z^2 + c - 1)/(2z + c - 2))^2, with z starting at 0 and c the pixel.
    case magnetI
    /// z -> q^2, q = (z^3 + 3(c - 1)z + (c - 1)(c - 2)) / (3z^2 + 3(c - 2)z + (c - 1)(c - 2) + 1), from 0.
    case magnetII
    /// The complex Collatz map (2 + 7z - (2 + 5z)*cos piz)/4, with z starting at the pixel.
    case collatz
    /// The Lyapunov exponent of the logistic map under the sequence AB, with a = re and b = im.
    case lyapunov
    /// Feather: z -> z^3 / ((1 + Re z^2) + i*Im z^2) + c, with z starting at 0 and c the pixel.
    case feather

    // Geometric sets, found by digit tests.
    /// The Sierpinski carpet on the square [-1, 1]^2, with black holes and one colour for the rest.
    case sierpinskiCarpet
    /// The Sierpinski triangle with vertices (0, 0.96) and (+/-1, -0.78), black holes and one colour.
    case sierpinskiTriangle

    // Two-dimensional attractors, drawn by the hits of one long orbit.
    /// x -> y - sign(x)*sqrt|bx - c|, y -> a - x.
    case hopalong
    /// x -> y - sin x, y -> a - x.
    case martin
    /// x -> 1 - y + |x|, y -> x.
    case gingerbreadman
    /// x -> sin(ay) + c*cos(ax), y -> sin(bx) + d*cos(by).
    case clifford
    /// x -> sin(ay) - cos(bx), y -> sin(cx) - cos(dy).
    case deJong
    /// The Ikeda map with the constants a, b, c and d.
    case ikeda
    /// x -> x^2 - y^2 + ax + by, y -> 2xy + cx + dy.
    case tinkerbell
    /// The Gumowski-Mira map with the constants a and b.
    case gumowskiMira
    /// Chip: x -> y - sign(x)*cos(ln^2|bx - c|)*atan(ln^2|cx - b|), y -> a - x.
    case chip
    /// Quadruptwo: x -> y - sign(x)*sin(ln|bx - c|)*atan(|cx - b|^2), y -> a - x.
    case quadruptwo
    /// Threeply: x -> y - sign(x)*|sin x*cos b + c - x*sin(a + b + c)|, y -> a - x.
    case threeply

    // Iterated function systems and recursive shapes.
    /// The four-map Barnsley fern, drawn by recursive subdivision of its maps.
    case barnsleyFern
    /// The five-map Vicsek cross, drawn by recursive subdivision of its maps.
    case vicsekCross
    /// The Heighway dragon, drawn by recursive subdivision of its segment.
    case heighwayDragon
    /// The Koch snowflake outline, drawn by subdividing each side of the triangle.
    case kochSnowflake
    /// The Pythagoras tree, drawn as the outlines of its squares.
    case pythagorasTree
    /// The two-map IFS dragon, drawn by recursive subdivision of its maps.
    case ifsDragon
    /// The three-map IFS twig, drawn by recursive subdivision of its maps.
    case ifsTwig
    /// The three-map Christmas tree, drawn by recursive subdivision of its maps.
    case christmasTree
    /// The H-tree, drawn by recursive subdivision of its segments, as the engine draws it.
    case hTree
    /// The Hilbert curve of order 32, drawn by recursive subdivision of its cells.
    case hilbertCurve

    // Three-dimensional kinds. The first twelve are ray marched, and the last three attractors are
    // drawn by hits.
    /// The Mandelbulb: z -> z^power + c in spherical coordinates, with c the point.
    case mandelbulb
    /// The Mandelbox: a box fold, a sphere fold and a scale, with c the point.
    case mandelbox
    /// The Menger sponge: the cube with square holes cut at each level the iteration budget allows.
    case mengerSponge
    /// The Sierpinski pyramid: each step moves the point to its nearest vertex and doubles the offset.
    case sierpinskiPyramid
    /// The quaternion Julia set z -> z^2 + c, with the constant c and z starting at the point.
    case quaternionJulia
    /// The quaternion cubic z -> z^3 + c, with the constant c and the point in the quaternion.
    case quaternionCubic
    /// The Mandelbulb step with c the point on even steps and the Julia constant on odd steps.
    case hybridMandelbulbJulia
    /// The Sierpinski gasket: the tetrahedral fold with a sphere fold, scaled at each step.
    case sierpinskiGasket
    /// The octahedral kaleidoscopic IFS: folds on the octahedral mirror planes, then a scale.
    case octahedralIFS
    /// The icosahedral kaleidoscopic IFS: folds on the icosahedral mirror planes, then a scale.
    case icosahedralIFS
    /// The Apollonian gasket: sphere inversions and a scale, which pack spheres.
    case apollonianGasket
    /// The Kleinian group: a box-like fold and an inversion, repeated.
    case kleinian
    /// The Pickover attractor: x -> sin(ay) - z*cos(bx), y -> z*sin(cx) - cos(dy), z -> sin x.
    case pickover
    /// The Lorenz attractor with sigma = a, rho = b and beta = c, integrated by Euler steps.
    case lorenz
    /// The Rossler attractor with a, b and c, integrated by Euler steps.
    case rossler
  }
}

extension EscapeTimeFractal.Kind {

  /// The groups the picker shows the kinds in, in this order.
  public enum Family: CaseIterable, Sendable {
    case polynomial
    case barnsley
    case transcendental
    case rational
    case geometric
    case attractor
    case iterated
    case threeDimensional
  }

  /// The group of the kind.
  public var family: Family {
    switch self {
    case .mandelbrot, .julia, .burningShip, .burningShipJulia, .perpendicularBurningShip,
      .tricorn, .multibrot, .multicorn, .celtic, .celticJulia, .phoenix, .spider, .manOWar,
      .lambda, .buddhabrot, .buffalo, .alphaMandelbrot, .alphaMandelbrotJulia, .zubieta,
      .cactus:
      .polynomial
    case .barnsleyMandelbrot, .barnsleyJulia, .barnsleyII, .barnsleyIII:
      .barnsley
    case .sine, .cosine, .juliaSine, .juliaCosine, .sinh, .juliaSinh, .tetration, .thorn:
      .transcendental
    case .newton, .nova, .magnetI, .magnetII, .collatz, .lyapunov, .feather:
      .rational
    case .sierpinskiCarpet, .sierpinskiTriangle:
      .geometric
    case .hopalong, .martin, .gingerbreadman, .clifford, .deJong, .ikeda, .tinkerbell,
      .gumowskiMira, .chip, .quadruptwo, .threeply:
      .attractor
    case .barnsleyFern, .vicsekCross, .heighwayDragon, .kochSnowflake, .pythagorasTree,
      .ifsDragon, .ifsTwig, .christmasTree, .hTree, .hilbertCurve:
      .iterated
    case .mandelbulb, .mandelbox, .mengerSponge, .sierpinskiPyramid, .quaternionJulia,
      .quaternionCubic, .hybridMandelbulbJulia, .sierpinskiGasket, .octahedralIFS,
      .icosahedralIFS, .apollonianGasket, .kleinian, .pickover, .lorenz, .rossler:
      .threeDimensional
    }
  }

  /// Whether the picture is drawn by the hits of many orbits rather than per pixel. The three
  /// three-dimensional attractors are among them.
  public var isDensity: Bool {
    switch family {
    case .attractor, .iterated: true
    case .threeDimensional: self == .pickover || self == .lorenz || self == .rossler
    default: self == .buddhabrot
    }
  }

  /// Whether the kind is three-dimensional. Its view is the camera, not the centre and span.
  public var is3D: Bool {
    family == .threeDimensional
  }

  /// Whether the kind is three-dimensional and drawn by ray marching a distance estimator.
  public var isRayMarched: Bool {
    is3D && !isDensity
  }
}
