import Foundation

/// Simulated fields 96...101 of the Android native code, ported from `simulationField` in
/// `ProceduralTextures.cpp`: the three escape-time sets, the kaleidoscope, the prism and the knot.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  /// Iterates `z = z*z + c` until the point leaves the disc of radius 4 or the limit is reached,
  /// and returns the fraction of iterations used. `folded` takes the absolute values first, as
  /// the burning ship does.
  static func escapeFraction(
    zx startX: Float, zy startY: Float, cx: Float, cy: Float, maxIterations: Int, folded: Bool
  ) -> Float {
    var zx = startX
    var zy = startY
    var iteration = 0
    while iteration < maxIterations && zx * zx + zy * zy < 16 {
      if folded {
        zx = abs(zx)
        zy = abs(zy)
      }
      let nextX = zx * zx - zy * zy + cx
      zy = 2 * zx * zy + cy
      zx = nextX
      iteration += 1
    }
    return Float(iteration) / Float(maxIterations)
  }

  static func mandelbrot(_ f: NativeFieldInput) -> Float {
    let magnification = exp2(M.clamp01((f.s - 0.001) / 0.039) * 8)
    let focus = M.smoothstep(1.6, 8, magnification)
    let centerX =
      -0.5 + (-0.7436439 + 0.5) * focus + (f.distortion - 0.5) * 0.16 / magnification
    let centerY = 0.1318259 * focus + (f.distortion - 0.5) * 0.1 / magnification
    let cx = f.u / f.spatialScale * 3.1 / magnification + centerX
    let cy = f.v / f.spatialScale * 3.1 / magnification + centerY
    let maxIterations = 42 + Int(f.complexity * 104)
    return escapeFraction(
      zx: 0, zy: 0, cx: cx, cy: cy, maxIterations: maxIterations, folded: false)
  }

  static func burningShip(_ f: NativeFieldInput) -> Float {
    let magnification = exp2(M.clamp01((f.s - 0.001) / 0.039) * 7.5)
    let focus = M.smoothstep(1.7, 7, magnification)
    let centerX =
      -0.5 + (-1.7443359 + 0.5) * focus + (f.distortion - 0.5) * 0.18 / magnification
    let centerY = -0.48 + (-0.017451 + 0.48) * focus
    let cx = f.u / f.spatialScale * 3.2 / magnification + centerX
    let cy = f.v / f.spatialScale * 3.2 / magnification + centerY
    let maxIterations = 42 + Int(f.complexity * 100)
    return escapeFraction(
      zx: 0, zy: 0, cx: cx, cy: cy, maxIterations: maxIterations, folded: true)
  }

  static func juliaSet(_ f: NativeFieldInput) -> Float {
    let magnification = exp2(M.clamp01((f.s - 0.001) / 0.039) * 7)
    let focus = M.smoothstep(1.6, 6, magnification)
    let zx = f.u / f.spatialScale * 2.7 / magnification - 0.11 * focus
    let zy = f.v / f.spatialScale * 2.7 / magnification + 0.64 * focus
    let phase = f.distortion * 2 * pi
    let cx = -0.73 + cos(phase) * 0.12
    let cy = sin(phase) * 0.21
    let maxIterations = 42 + Int(f.complexity * 104)
    return escapeFraction(
      zx: zx, zy: zy, cx: cx, cy: cy, maxIterations: maxIterations, folded: false)
  }

  static func kaleidoscopeCrystal(_ f: NativeFieldInput) -> Float {
    let segments = 4 + floor(f.complexity * 12)
    let sector = 2 * pi / segments
    let folded = abs(M.fract((f.angle + pi) / sector) - 0.5) * sector
    let crystal = sin(
      f.radius * (70 + f.distortion * 90) + folded * 44 + sin(folded * segments) * 3)
    return M.clamp01(1 - abs(crystal) * 2.9)
  }

  static func spectralPrism(_ f: NativeFieldInput) -> Float {
    let facet = abs(
      M.fract((f.angle / (2 * pi) + 0.5) * (4 + floor(f.complexity * 10))) - 0.5)
    let refraction = M.fract(
      f.radius * (5 + f.distortion * 11) + facet * 3 + f.angle / (2 * pi))
    return M.clamp01(refraction * 0.75 + (1 - facet * 2) * 0.25)
  }

  static func topologicalKnot(_ f: NativeFieldInput) -> Float {
    let turns = 2 + floor(f.complexity * 6)
    let twist = 2 + floor(f.distortion * 7)
    let knotRadius = 0.27 + 0.09 * cos(f.angle * turns)
    let tube = abs(f.radius - knotRadius - 0.045 * sin(f.angle * twist))
    let crossing = 0.5 + 0.5 * sin(f.angle * turns * twist)
    return M.clamp01(1 - tube * (20 + crossing * 18))
  }
}
