import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Fractal density kinds: attractors, iterated systems and the Buddhabrot")
struct FractalDensityTests {

  private static let attractors: [EscapeTimeFractal.Kind] = [
    .hopalong, .martin, .gingerbreadman, .clifford, .deJong, .ikeda, .tinkerbell, .gumowskiMira,
    .chip, .quadruptwo, .threeply,
  ]

  private static let systems: [EscapeTimeFractal.Kind] = [
    .barnsleyFern, .vicsekCross, .heighwayDragon, .kochSnowflake, .pythagorasTree,
    .ifsDragon, .ifsTwig, .christmasTree,
  ]

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

  /// The box of the complex plane that the lit pixels cover, for a square picture of the settings.
  private static func litExtent(
    _ image: RasterImage, centre: (Double, Double), span: Double
  ) -> (x0: Double, x1: Double, y0: Double, y1: Double)? {
    var extent: (x0: Double, x1: Double, y0: Double, y1: Double)?
    let scale = span / Double(image.width)
    for y in 0..<image.height {
      for x in 0..<image.width {
        let pixel = image.pixel(x: x, y: y)
        guard pixel.red > 0 || pixel.green > 0 || pixel.blue > 0 else { continue }
        let real = centre.0 + (Double(x) + 0.5 - Double(image.width) / 2) * scale
        let imaginary = centre.1 - (Double(y) + 0.5 - Double(image.height) / 2) * scale
        if let current = extent {
          extent = (
            min(current.x0, real), max(current.x1, real),
            min(current.y0, imaginary), max(current.y1, imaginary)
          )
        } else {
          extent = (real, real, imaginary, imaginary)
        }
      }
    }
    return extent
  }

  private static func settings(_ kind: EscapeTimeFractal.Kind, iterations: Int = 64)
    -> EscapeTimeFractal.Settings
  {
    let view = kind.defaultView
    return EscapeTimeFractal.Settings(
      kind: kind, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
      span: view.span, maxIterations: iterations)
  }

  @Test("the attractor maps take the textbook values at the origin")
  func attractorFormulas() {
    let defaults = { (kind: EscapeTimeFractal.Kind) in kind.defaultCoefficients }
    let origin = (0.0, 0.0)
    let hopalong = FractalAttractors.step(.hopalong, origin.0, origin.1, defaults(.hopalong))
    #expect(hopalong == (0, 0.4))
    let martin = FractalAttractors.step(.martin, origin.0, origin.1, defaults(.martin))
    #expect(martin == (0, Double.pi))
    let gingerbreadman = FractalAttractors.step(
      .gingerbreadman, origin.0, origin.1, defaults(.gingerbreadman))
    #expect(gingerbreadman == (1, 0))
    let clifford = FractalAttractors.step(.clifford, origin.0, origin.1, defaults(.clifford))
    #expect(clifford == (1, 0.7))
    let deJong = FractalAttractors.step(.deJong, origin.0, origin.1, defaults(.deJong))
    #expect(deJong == (-1, -1))
    let ikeda = FractalAttractors.step(.ikeda, origin.0, origin.1, defaults(.ikeda))
    #expect(ikeda == (0.85, 0))
    let tinkerbell = FractalAttractors.step(.tinkerbell, origin.0, origin.1, defaults(.tinkerbell))
    #expect(tinkerbell == (0, 0))
    let gumowski = FractalAttractors.step(
      .gumowskiMira, origin.0, origin.1, defaults(.gumowskiMira))
    #expect(gumowski == (0, 0))
    // Threeply: x' = -|c| = -42 and y' = a = -55 at the origin.
    let threeply = FractalAttractors.step(.threeply, origin.0, origin.1, defaults(.threeply))
    #expect(threeply == (-42, -55))
    // Quadruptwo: x' = -sin(ln 5)*atan(1) and y' = a = 34 at the origin.
    let quadruptwo = FractalAttractors.step(
      .quadruptwo, origin.0, origin.1, defaults(.quadruptwo))
    #expect(abs(quadruptwo.0 + sin(log(5.0)) * Double.pi / 4) < 1e-12)
    #expect(quadruptwo.1 == 34)
  }

  @Test("the attractors start where the Android engine starts them")
  func attractorStarts() {
    #expect(FractalAttractors.start(.gingerbreadman) == (-0.1, 0))
    #expect(FractalAttractors.start(.gumowskiMira) == (-0.1, 0))
    #expect(FractalAttractors.start(.tinkerbell) == (-0.72, -0.64))
    #expect(FractalAttractors.start(.hopalong) == (0.1, 0))
  }

  @Test("the attractor orbits never become NaN over a long run from the default constants")
  func attractorOrbitsStayDefined() {
    for kind in Self.attractors {
      let constants = kind.defaultCoefficients
      var (x, y) = FractalAttractors.start(kind)
      for _ in 0..<5_000 {
        (x, y) = FractalAttractors.step(kind, x, y, constants)
        guard abs(x) <= 1e7 && abs(y) <= 1e7 else { break }
      }
      #expect(!x.isNaN && !y.isNaN, "\(kind)")
    }
  }

  @Test("each attractor draws a picture with lit pixels, and repeats exactly")
  func attractorsDraw() throws {
    for kind in Self.attractors {
      let settings = Self.settings(kind)
      let first = try #require(EscapeTimeFractal.render(settings, width: 48, height: 48))
      let second = try #require(EscapeTimeFractal.render(settings, width: 48, height: 48))
      #expect(Self.litPixels(first) > 0, "\(kind) draws nothing")
      #expect(first.pixels == second.pixels, "\(kind) is not repeatable")
    }
  }

  @Test("the Buddhabrot draws the escaping orbits, and repeats exactly")
  func buddhabrotDraws() throws {
    let settings = EscapeTimeFractal.Settings(
      kind: .buddhabrot, centreReal: 0.4, centreImaginary: 0, span: 4.5, maxIterations: 32)
    let first = try #require(EscapeTimeFractal.render(settings, width: 48, height: 48))
    let second = try #require(EscapeTimeFractal.render(settings, width: 48, height: 48))
    #expect(Self.litPixels(first) > 0)
    #expect(first.pixels == second.pixels)
  }

  @Test("the Halton sequence gives the radical inverses, and the bulbs are skipped")
  func haltonAndBulbs() {
    #expect(FractalDensity.halton(1, base: 2) == 0.5)
    #expect(FractalDensity.halton(2, base: 2) == 0.25)
    #expect(abs(FractalDensity.halton(1, base: 3) - 1.0 / 3) < 1e-12)
    #expect(FractalDensity.insideMainBulbs(FractalComplex(0, 0)))
    #expect(FractalDensity.insideMainBulbs(FractalComplex(-1, 0)))
    #expect(!FractalDensity.insideMainBulbs(FractalComplex(2, 0)))
  }

  @Test("each iterated system draws a picture with lit pixels")
  func systemsDraw() throws {
    for kind in Self.systems {
      let image = try #require(EscapeTimeFractal.render(Self.settings(kind), width: 64, height: 64))
      #expect(Self.litPixels(image) > 50, "\(kind) draws too little")
    }
  }

  /// The IFS dragon is left out: its stated box is not invariant under its maps (the fixed point of
  /// the first map is at about (-3.44, 4.54), outside +/-3.1), so its picture reaches about +/-6.2,
  /// just outside the default view. The Android engine draws the same maps, so this is not checked.
  @Test("the Vicsek cross, the dragons and the other shapes stay inside their default views")
  func systemsStayInView() throws {
    for kind in Self.systems where kind != .ifsDragon {
      let view = kind.defaultView
      // Twice the default span, so a picture that leaves the default view is still drawn.
      let wide = EscapeTimeFractal.Settings(
        kind: kind, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
        span: view.span * 2, maxIterations: 64)
      let image = try #require(EscapeTimeFractal.render(wide, width: 256, height: 256))
      let extent = try #require(
        Self.litExtent(image, centre: (view.centreReal, view.centreImaginary), span: view.span * 2))
      let half = view.span / 2
      let margin = 0.1
      #expect(
        extent.x0 >= view.centreReal - half - margin
          && extent.x1 <= view.centreReal + half + margin
          && extent.y0 >= view.centreImaginary - half - margin
          && extent.y1 <= view.centreImaginary + half + margin,
        "\(kind) reaches \(extent)")
    }
  }

  @Test("the Vicsek cross and the Heighway dragon are inside the unit square and the 1.1 view")
  func vicsekAndDragonBounds() throws {
    for kind in [EscapeTimeFractal.Kind.vicsekCross, .heighwayDragon] {
      let settings = EscapeTimeFractal.Settings(
        kind: kind, centreReal: 0, span: 2.2, maxIterations: 64)
      let image = try #require(EscapeTimeFractal.render(settings, width: 256, height: 256))
      let extent = try #require(Self.litExtent(image, centre: (0, 0), span: 2.2))
      #expect(
        extent.x0 >= -1.1 && extent.x1 <= 1.1 && extent.y0 >= -1.1 && extent.y1 <= 1.1,
        "\(kind) reaches \(extent)")
    }
  }

  @Test("the fern stays within its box, from x = -2.19 to 2.66 and y = 0 to 10")
  func fernStaysInView() throws {
    let view = EscapeTimeFractal.Kind.barnsleyFern.defaultView
    let wide = EscapeTimeFractal.Settings(
      kind: .barnsleyFern, centreReal: view.centreReal, centreImaginary: view.centreImaginary,
      span: view.span * 2, maxIterations: 64)
    let image = try #require(EscapeTimeFractal.render(wide, width: 256, height: 256))
    let extent = try #require(
      Self.litExtent(image, centre: (view.centreReal, view.centreImaginary), span: view.span * 2))
    let margin = 0.25
    #expect(extent.x0 >= -2.19 - margin && extent.x1 <= 2.66 + margin)
    #expect(extent.y0 >= -margin && extent.y1 <= 10 + margin)
  }

  @Test("the Koch snowflake outline stays inside its view, and its corners are on the circle")
  func snowflakeStaysInView() throws {
    let settings = Self.settings(.kochSnowflake, iterations: 256)
    let image = try #require(EscapeTimeFractal.render(settings, width: 64, height: 64))
    // The view is 2.2 wide over 64 pixels, so a corner at radius 0.97 is about 28 pixels out.
    var farthest = 0.0
    for y in 0..<64 {
      for x in 0..<64 {
        let pixel = image.pixel(x: x, y: y)
        if pixel.red > 0 || pixel.green > 0 || pixel.blue > 0 {
          farthest = max(farthest, hypot(Double(x) - 31.5, Double(y) - 31.5))
        }
      }
    }
    #expect(farthest > 20 && farthest <= 32, "farthest lit pixel at \(farthest)")
  }

  @Test("the Vicsek maps contract by 1/3 and sit at the four corners and the centre")
  func vicsekMaps() {
    let maps = FractalIFS.system(.vicsekCross).maps
    #expect(maps.count == 5)
    for map in maps {
      #expect(abs(hypot(map.a, map.c) - 1.0 / 3) < 1e-12)
    }
    #expect(maps.contains(FractalIFS.AffineMap(1.0 / 3, 0, 0, 1.0 / 3, 0, 0)))
  }

  @Test("the fern has four maps and the IFS systems have the Android map counts")
  func systemMapCounts() {
    #expect(FractalIFS.system(.barnsleyFern).maps.count == 4)
    #expect(FractalIFS.system(.ifsDragon).maps.count == 2)
    #expect(FractalIFS.system(.ifsTwig).maps.count == 3)
    #expect(FractalIFS.system(.christmasTree).maps.count == 3)
  }
}
