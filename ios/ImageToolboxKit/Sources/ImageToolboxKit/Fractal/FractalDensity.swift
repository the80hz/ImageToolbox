import Foundation

/// The kinds drawn by hits rather than per pixel. Many orbits, or one long orbit, are counted in a
/// histogram of the view, which is shown on a log scale. The two-dimensional attractors are in
/// `FractalAttractors`, the iterated systems and the recursive shapes in `FractalIFS`, and the
/// three-dimensional attractors in `Fractal3DAttractors`. The Buddhabrot is here. The number of steps
/// and samples follows the engine's work plan.
enum FractalDensity {

  /// The engine's work budget, in units of one pixel or one step.
  static let workBudget = 500_000_000

  /// The pixel count of the engine's reference picture, 640 x 480, which sets the resolution multiplier.
  private static let referencePixels = 640 * 480

  static func render(
    _ settings: EscapeTimeFractal.Settings, width: Int, height: Int
  ) -> RasterImage {
    var canvas = DensityCanvas(width: width, height: height, settings: settings)
    let pixels = width * height
    let maxIterations = settings.maxIterations
    // The supersampling of a density kind is not drawn: it lengthens the work plan only.
    let supersampling = settings.supersampling
    switch settings.kind {
    case .buddhabrot:
      plotBuddhabrot(
        into: &canvas,
        samples: buddhabrotSamples(
          pixels: pixels, maxIterations: maxIterations, supersampling: supersampling),
        maxIterations: maxIterations)
    case .barnsleyFern, .vicsekCross, .ifsDragon, .ifsTwig, .christmasTree:
      FractalIFS.plotSystem(settings.kind, into: &canvas)
    case .heighwayDragon:
      FractalIFS.plotHeighwayDragon(into: &canvas)
    case .kochSnowflake:
      FractalIFS.plotKochSnowflake(into: &canvas)
    case .pythagorasTree:
      FractalIFS.plotPythagorasTree(into: &canvas)
    case .hTree:
      FractalIFS.plotHTree(into: &canvas)
    case .hilbertCurve:
      FractalIFS.plotHilbertCurve(into: &canvas)
    case .pickover, .lorenz, .rossler:
      let base = min(max(maxIterations * 32, 12_000), 240_000)
      let steps = budgetedSteps(
        base: base, pixels: pixels, costPerStep: 9, supersampling: supersampling)
      Fractal3DAttractors.plot(settings, into: &canvas, steps: steps)
    default:
      let base = min(max(maxIterations * 128, 24_000), 1_000_000)
      let steps = budgetedSteps(
        base: base, pixels: pixels, costPerStep: 25, supersampling: supersampling)
      FractalAttractors.plot(
        settings.kind, settings.resolvedCoefficients, into: &canvas, steps: steps)
    }
    return canvas.image()
  }

  /// The steps of a density kind: the base for its iteration count, times the resolution multiplier of
  /// its sampled pixels, cut to what the work budget affords at the given cost per step. The budget is
  /// taken from the pixels alone, and the sampled pixels set only the multiplier, as the engine does.
  static func budgetedSteps(
    base: Int, pixels: Int, costPerStep: Int, supersampling: Int = 1
  ) -> Int {
    let desired = base * resolutionMultiplier(pixels: pixels * supersampling * supersampling)
    let affordable = max(workBudget - pixels, 0) / costPerStep
    return min(desired, affordable)
  }

  /// The engine's multiplier for a picture: the square root, rounded up, of the picture's pixels in
  /// units of the reference picture. It is at least 1.
  static func resolutionMultiplier(pixels: Int) -> Int {
    let ratio = (pixels + referencePixels - 1) / referencePixels
    var root = 1
    while root * root < ratio {
      root += 1
    }
    return max(root, 1)
  }

  /// The Buddhabrot samples: half the sampled pixels, and at least 8 192, cut to the budget of the orbit
  /// length, which is taken from the pixels alone.
  static func buddhabrotSamples(pixels: Int, maxIterations: Int, supersampling: Int = 1) -> Int {
    let desired = max(pixels * supersampling * supersampling / 2, 8_192)
    let affordable = max(workBudget - pixels, 0) / max(maxIterations, 32)
    return min(desired, affordable)
  }

  /// Samples the points c of the Halton sequence over [-2.5, 1) x [-1.5, 1.5). A point in the main
  /// cardioid or the period-2 bulb is skipped, since its orbit never escapes. The orbit of z from 0
  /// is kept if it escapes the radius 2 and lasts at least max(20, limit/10) steps, where limit is
  /// at least 32. Its points are plotted rotated, at (im z, -re z), as the Android engine does.
  private static func plotBuddhabrot(
    into canvas: inout DensityCanvas, samples: Int, maxIterations: Int
  ) {
    let limit = max(maxIterations, 32)
    let shortest = max(20, limit / 10)
    var orbit: [FractalComplex] = []
    orbit.reserveCapacity(limit)
    for index in 1...max(samples, 1) {
      let c = FractalComplex(
        -2.5 + 3.5 * halton(index, base: 2), -1.5 + 3.0 * halton(index, base: 3))
      guard !insideMainBulbs(c) else { continue }

      orbit.removeAll(keepingCapacity: true)
      var z = FractalComplex.zero
      var escaped = false
      while orbit.count < limit {
        z = z * z + c
        orbit.append(z)
        // NaN fails the comparison, so an overflow also counts as an escape.
        if !(z.squaredMagnitude <= 4) {
          escaped = true
          break
        }
      }
      guard escaped, orbit.count >= shortest else { continue }
      for point in orbit {
        canvas.add(real: point.im, imaginary: -point.re)
      }
    }
  }

  /// Whether c lies in the main cardioid or in the period-2 bulb of the Mandelbrot set.
  static func insideMainBulbs(_ c: FractalComplex) -> Bool {
    let x = c.re
    let y = c.im
    let q = (x - 0.25) * (x - 0.25) + y * y
    let cardioid = q * (q + (x - 0.25)) <= 0.25 * y * y
    let bulb = (x + 1) * (x + 1) + y * y <= 0.0625
    return cardioid || bulb
  }

  /// The radical inverse of the index in the given base, which lies in [0, 1).
  static func halton(_ index: Int, base: Int) -> Double {
    var fraction = 1.0
    var result = 0.0
    var remaining = index
    while remaining > 0 {
      fraction /= Double(base)
      result += fraction * Double(remaining % base)
      remaining /= base
    }
    return result
  }
}

/// A square-pixel histogram of the view. A hit adds one to each pixel of a disc about its point, of the
/// radius the engine uses for the kind, and a projected point adds the engine's 3 x 3 brush. Points
/// outside the view are dropped.
struct DensityCanvas {
  let width: Int
  let height: Int
  /// The vertical span of the view in the complex plane. The horizontal span is this times the aspect.
  let span: Double
  let centreReal: Double
  let centreImaginary: Double
  /// The number of hits in each pixel, row by row from the top.
  private(set) var hits: [UInt32]

  init(width: Int, height: Int, settings: EscapeTimeFractal.Settings) {
    self.width = width
    self.height = height
    span = settings.span
    centreReal = settings.centreReal
    centreImaginary = settings.centreImaginary
    hits = [UInt32](repeating: 0, count: width * height)
  }

  /// The horizontal span of the view: the vertical span times the picture's aspect ratio.
  private var horizontalSpan: Double {
    span * Double(width) / Double(height)
  }

  /// Pixels per unit of the complex plane. The pixels are square, so it is the same on both axes.
  var pixelsPerUnit: Double {
    Double(height) / span
  }

  /// Whether a disc of the given radius about the centre may reach the view.
  func mayContainCircle(centre: FractalComplex, radius: Double) -> Bool {
    let dx = max(abs(centre.re - centreReal) - horizontalSpan / 2, 0)
    let dy = max(abs(centre.im - centreImaginary) - span / 2, 0)
    return dx * dx + dy * dy <= radius * radius
  }

  /// Whether a box of the plane meets the view.
  func overlaps(_ box: FractalIFS.Box) -> Bool {
    let halfWidth = horizontalSpan / 2
    let halfHeight = span / 2
    return box.x1 >= centreReal - halfWidth && box.x0 <= centreReal + halfWidth
      && box.y1 >= centreImaginary - halfHeight && box.y0 <= centreImaginary + halfHeight
  }

  /// The part of a segment inside the view, clipped as the engine clips its lines: the Liang-Barsky
  /// test against the four edges. Nil when none of the segment is inside.
  func clip(_ start: FractalComplex, _ end: FractalComplex) -> (FractalComplex, FractalComplex)? {
    let halfWidth = horizontalSpan / 2
    let halfHeight = span / 2
    let dx = end.re - start.re
    let dy = end.im - start.im
    let edges = [
      (-dx, start.re - (centreReal - halfWidth)),
      (dx, (centreReal + halfWidth) - start.re),
      (-dy, start.im - (centreImaginary - halfHeight)),
      (dy, (centreImaginary + halfHeight) - start.im),
    ]
    var near = 0.0
    var far = 1.0
    for (direction, distance) in edges {
      if abs(direction) < Double.ulpOfOne {
        // A segment parallel to an edge is either inside that edge or outside the view.
        if distance < 0 { return nil }
        continue
      }
      let ratio = distance / direction
      if direction < 0 {
        near = max(near, ratio)
      } else {
        far = min(far, ratio)
      }
      if near > far { return nil }
    }
    return (
      FractalComplex(start.re + dx * near, start.im + dy * near),
      FractalComplex(start.re + dx * far, start.im + dy * far)
    )
  }

  /// Adds one hit to each pixel of a disc of the radius about the point, if the point lies in the view.
  /// The radius is 1 for the lines and the iterated systems, and 2 for the two-dimensional attractors.
  mutating func add(real: Double, imaginary: Double, radius: Int = 1) {
    guard let position = pixel(real: real, imaginary: imaginary) else { return }
    for dy in -radius...radius {
      for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
        let column = position.column + dx
        let row = position.row + dy
        guard column >= 0, column < width, row >= 0, row < height else { continue }
        hits[row * width + column] &+= 1
      }
    }
  }

  /// Adds a projected point at its position in pixels: the pixel it falls in counts twice, and its
  /// eight neighbours once, each times the weight. Pixels outside the picture are dropped.
  mutating func addProjected(x: Double, y: Double, weight: UInt32) {
    let centreColumn = Int(floor(x))
    let centreRow = Int(floor(y))
    for dy in -1...1 {
      for dx in -1...1 {
        let column = centreColumn + dx
        let row = centreRow + dy
        guard column >= 0, column < width, row >= 0, row < height else { continue }
        let falloff: UInt32 = dx == 0 && dy == 0 ? 2 : 1
        hits[row * width + column] &+= weight &* falloff
      }
    }
  }

  /// The pixel of a point of the plane, or nil when the point is outside the view. The view's top-left
  /// corner is at (centre - half the horizontal span, centre + half the vertical span).
  private func pixel(real: Double, imaginary: Double) -> (column: Int, row: Int)? {
    let normalizedX = (real - (centreReal - horizontalSpan / 2)) / horizontalSpan
    let normalizedY = ((centreImaginary + span / 2) - imaginary) / span
    guard normalizedX >= 0, normalizedX < 1, normalizedY >= 0, normalizedY < 1 else {
      return nil
    }
    return (Int(normalizedX * Double(width)), Int(normalizedY * Double(height)))
  }

  /// The histogram as an opaque picture. Empty pixels are black. The rest are coloured by the log of
  /// their hits, with the engine's gamma of 0.58, from blue for a few to red for the most.
  func image() -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    // The engine's logarithmic maximum is at least 1, so a faint picture is not stretched.
    let logMaximum = max(log(1 + Double(hits.max() ?? 0)), 1)
    for index in 0..<hits.count {
      let offset = index * 4
      pixels[offset + 3] = 255
      guard hits[index] > 0 else { continue }
      let intensity = log(1 + Double(hits[index])) / logMaximum
      let level = pow(intensity, 0.58)
      let rgb = OklabColour.hsvToRGB(
        hue: 0.72 - 0.62 * level, saturation: 0.9, value: 0.35 + 0.65 * level)
      pixels[offset] = UInt8((rgb.red * 255).rounded())
      pixels[offset + 1] = UInt8((rgb.green * 255).rounded())
      pixels[offset + 2] = UInt8((rgb.blue * 255).rounded())
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }
}
