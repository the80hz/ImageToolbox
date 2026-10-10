import Foundation

/// One feature point found while searching the cells around a pixel.
private final class CellularPoint {
  var distance = Float.infinity
  var dx: Float = 0
  var dy: Float = 0
  var x: Float = 0
  var y: Float = 0

  func set(distance: Float, dx: Float, dy: Float, x: Float, y: Float) {
    self.distance = distance
    self.dx = dx
    self.dy = dy
    self.x = x
    self.y = y
  }
}

/// `com.jhlabs.image.CellularFilter` as the Android app runs it: feature points on a hexagonal
/// grid, the distances to the nearest two of them, and the `useColor` blend of the source colour.
/// The feature points are drawn from a `java.util.Random` reseeded for every cell, so the picture
/// does not depend on the seed of the preset.
final class ClassicCellularFilter {
  /// The Android `CellularGridType.Hexagonal` value.
  private static let hexagonal = 2
  private static let probabilityCount = 8192

  private let scale: Float
  private let stretch: Float
  private let rotation: ClassicRotation
  private let angleCoefficient: Float
  private let gradientCoefficient: Float
  /// The weights f1...f4 of the nearest three distances.
  private let coefficients: [Float]
  private let randomness: Float
  private let distancePower: Float
  private let turbulence: Float
  /// The grid of feature points: the Android default, hexagonal.
  private let gridType = ClassicCellularFilter.hexagonal
  private let probabilities: [UInt8]
  private var random = ClassicRandom(seed: 0)
  private var results = (0..<3).map { _ in CellularPoint() }

  init(preset: TexturePreset) {
    scale = Float(preset.scale)
    stretch = Float(preset.value("stretch", fallback: 1))
    rotation = ClassicRotation(angle: Float(preset.value("angle", fallback: 0)))
    angleCoefficient = Float(preset.value("angleCoefficient", fallback: 0))
    gradientCoefficient = Float(preset.value("gradientCoefficient", fallback: 0))
    coefficients = [
      Float(preset.value("f1", fallback: 1)),
      Float(preset.value("f2", fallback: 0)),
      Float(preset.value("f3", fallback: 0)),
      Float(preset.value("f4", fallback: 0)),
    ]
    randomness = Float(preset.value("randomness", fallback: 0))
    distancePower = Float(preset.value("distancePower", fallback: 2))
    turbulence = Float(preset.value("turbulence", fallback: 1))
    probabilities = Self.poissonTable()
  }

  /// Draws the picture in row order. The source picture of the Android app is filled with the
  /// preset colour, so it is uniform and every `inPixels` lookup of the reference reads that
  /// colour.
  static func render(
    _ preset: TexturePreset,
    width: Int,
    height: Int
  ) -> [Int] {
    let filter = ClassicCellularFilter(preset: preset)
    let source = preset.colours.first.map { Int($0) } ?? 0xFFFF_FFFF
    var pixels = [Int](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        pixels[y * width + x] = filter.pixel(x: x, y: y, source: source)
      }
    }
    return pixels
  }

  /// `CellularFilter.getPixel` with `useColor`: the source colour, darkened where the two nearest
  /// feature points are close together.
  func pixel(x: Int, y: Int, source: Int) -> Int {
    var (nx, ny) = rotation.apply(x, y)
    nx /= scale
    ny /= scale * stretch
    nx += 1000
    ny += 1000
    // The reference also evaluates the field here for the points it leaves behind. Only the
    // distances of those points are read below.
    if turbulence == 1 {
      _ = evaluate(nx, ny)
    } else {
      _ = turbulence2(nx, ny, turbulence)
    }
    let nearest = results[0].distance
    let second = results[1].distance
    let blend = (second - nearest) / (second + nearest)
    let shade = ClassicMath.smoothStep(coefficients[1], coefficients[0], blend)
    return ClassicNative.mix(shade, 0xff00_0000, source)
  }

  /// `CellularFilter.evaluate`: the weighted sum of the nearest feature points' distances, with
  /// the optional angle and gradient terms.
  private func evaluate(_ x: Float, _ y: Float) -> Float {
    for point in results {
      point.distance = .infinity
    }
    let ix = ClassicMath.toInt(x)
    let iy = ClassicMath.toInt(y)
    let fx = x - Float(ix)
    let fy = y - Float(iy)
    var d = checkCube(fx, fy, ix, iy)
    if d > fy {
      d = checkCube(fx, fy + 1, ix, iy - 1)
    }
    if d > 1 - fy {
      d = checkCube(fx, fy - 1, ix, iy + 1)
    }
    if d > fx {
      _ = checkCube(fx + 1, fy, ix - 1, iy)
      if d > fy {
        d = checkCube(fx + 1, fy + 1, ix - 1, iy - 1)
      }
      if d > 1 - fy {
        d = checkCube(fx + 1, fy - 1, ix - 1, iy + 1)
      }
    }
    if d > 1 - fx {
      d = checkCube(fx - 1, fy, ix + 1, iy)
      if d > fy {
        d = checkCube(fx - 1, fy + 1, ix + 1, iy - 1)
      }
      if d > 1 - fy {
        d = checkCube(fx - 1, fy - 1, ix + 1, iy + 1)
      }
    }
    var total: Float = 0
    for i in 0..<3 {
      total += coefficients[i] * results[i].distance
    }
    if angleCoefficient != 0 {
      var angle = atan2f(y - results[0].y, x - results[0].x)
      if angle < 0 {
        angle += 2 * ClassicNative.pi
      }
      angle /= 4 * ClassicNative.pi
      total += angleCoefficient * angle
    }
    if gradientCoefficient != 0 {
      total += gradientCoefficient / (results[0].dy + results[0].dx)
    }
    return total
  }

  /// The distance to the nearest two feature points of the cell `(cubeX, cubeY)`, from the points
  /// of that cell. The result is the third nearest distance found so far, as in the reference.
  private func checkCube(_ x: Float, _ y: Float, _ cubeX: Int, _ cubeY: Int) -> Float {
    let seed =
      Int32(571) &* Int32(truncatingIfNeeded: cubeX)
      &+ Int32(23) &* Int32(truncatingIfNeeded: cubeY)
    random.setSeed(Int64(seed))
    let numPoints: Int
    switch gridType {
    case 1, 2:
      numPoints = 1
    case 3, 4:
      numPoints = 2
    default:
      numPoints = Int(probabilities[Int(random.nextInt() & 0x1fff)])
    }
    for index in 0..<numPoints {
      var px: Float = 0
      var py: Float = 0
      var weight: Float = 1
      switch gridType {
      case 0:
        px = random.nextFloat()
        py = random.nextFloat()
      case 1:
        px = 0.5
        py = 0.5
        if randomness != 0 {
          px += randomness * (random.nextFloat() - 0.5)
          py += randomness * (random.nextFloat() - 0.5)
        }
      case 2:
        px = 0.75
        py = (cubeX & 1) == 0 ? 0 : 0.5
        jitter(&px, &py, cubeX, cubeY)
      case 3:
        if index == 0 {
          px = 0.207
          py = 0.207
        } else {
          px = 0.707
          py = 0.707
          weight = 1.6
        }
        jitter(&px, &py, cubeX, cubeY)
      case 4:
        if (cubeY & 1) == 0 {
          if index == 0 {
            px = 0.25
            py = 0.35
          } else {
            px = 0.75
            py = 0.65
          }
        } else {
          if index == 0 {
            px = 0.75
            py = 0.35
          } else {
            px = 0.25
            py = 0.65
          }
        }
        jitter(&px, &py, cubeX, cubeY)
      default:
        break
      }
      let dx = abs(x - px) * weight
      let dy = abs(y - py) * weight
      let d = distance(dx, dy)
      place(d: d, dx: dx, dy: dy, x: Float(cubeX) + px, y: Float(cubeY) + py)
    }
    return results[2].distance
  }

  /// The randomness jitter of the hexagonal, octagonal and triangular grids. It reads the noise,
  /// not the cell random generator, and the second axis uses the first axis after its jitter.
  private func jitter(_ px: inout Float, _ py: inout Float, _ cubeX: Int, _ cubeY: Int) {
    guard randomness != 0 else { return }
    px +=
      randomness * ClassicNative.table.noise2(271 * (Float(cubeX) + px), 271 * (Float(cubeY) + py))
    py +=
      randomness
      * ClassicNative.table.noise2(271 * (Float(cubeX) + px) + 89, 271 * (Float(cubeY) + py) + 137)
  }

  /// The distance from a pixel to a feature point, with the power of the reference.
  private func distance(_ dx: Float, _ dy: Float) -> Float {
    if distancePower == 1 {
      return dx + dy
    }
    if distancePower == 2 {
      return (dx * dx + dy * dy).squareRoot()
    }
    let sum = powf(dx, distancePower) + powf(dy, distancePower)
    return powf(sum, 1 / distancePower)
  }

  /// Keeps the three nearest points, as `checkCube` does by swapping references.
  private func place(d: Float, dx: Float, dy: Float, x: Float, y: Float) {
    if d < results[0].distance {
      let point = results[2]
      results[2] = results[1]
      results[1] = results[0]
      results[0] = point
      point.set(distance: d, dx: dx, dy: dy, x: x, y: y)
    } else if d < results[1].distance {
      let point = results[2]
      results[2] = results[1]
      results[1] = point
      point.set(distance: d, dx: dx, dy: dy, x: x, y: y)
    } else if d < results[2].distance {
      results[2].set(distance: d, dx: dx, dy: dy, x: x, y: y)
    }
  }

  /// `CellularFilter.turbulence2`: the field summed over octaves, each at twice the frequency.
  /// This follows the description of the reference, not its listing.
  private func turbulence2(_ x: Float, _ y: Float, _ frequency: Float) -> Float {
    var total: Float = 0
    var scaleFactor: Float = 1
    while scaleFactor <= frequency {
      total += evaluate(scaleFactor * x, scaleFactor * y) / scaleFactor
      scaleFactor *= 2
    }
    return total
  }

  /// `powi` of the native code: the square-and-multiply loop of the compiler runtime.
  private static func powi(_ base: Float, _ exponent: Int) -> Float {
    var result: Float = 1
    var square = base
    var remaining = exponent
    while true {
      if remaining & 1 != 0 {
        result *= square
      }
      remaining /= 2
      if remaining == 0 {
        break
      }
      square *= square
    }
    return result
  }

  /// The table of the random grid: how many points a cell holds, for a Poisson distribution with
  /// mean 2.5 over 8192 entries, computed in float as the native code does.
  private static func poissonTable() -> [UInt8] {
    var table = [UInt8](repeating: 0, count: probabilityCount)
    var factorial: Float = 1
    var total: Float = 0
    let mean: Float = 2.5
    for i in 0..<10 {
      if i > 1 {
        factorial *= Float(i)
      }
      let probability = powi(mean, i) * expf(-mean) / factorial
      let start = ClassicMath.toInt(total * Float(probabilityCount))
      total += probability
      let end = ClassicMath.toInt(total * Float(probabilityCount))
      let low = min(max(start, 0), probabilityCount)
      let high = min(max(end, low), probabilityCount)
      for j in low..<high {
        table[j] = UInt8(i)
      }
    }
    return table
  }
}
