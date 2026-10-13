import Foundation

/// The single-sample 2D noises of FastNoiseLite, in the same arithmetic order as the C++ header
/// (`Float` throughout, 32-bit integer hashing that wraps). Each function takes one point and a
/// seed; the fractal layers in `FastNoiseLite` call them once per octave.
extension FastNoiseLite {
  static let primeX: Int32 = 501_125_321
  static let primeY: Int32 = 1_136_930_381

  /// The integer hash of one lattice point.
  static func primedHash(_ seed: Int32, _ xPrimed: Int32, _ yPrimed: Int32) -> Int32 {
    var hash = seed ^ xPrimed ^ yPrimed
    hash = hash &* 0x27d4_eb2d
    return hash
  }

  /// A value in -1...1 for one lattice point, used by value noise.
  static func valCoord(_ seed: Int32, _ xPrimed: Int32, _ yPrimed: Int32) -> Float {
    var hash = primedHash(seed, xPrimed, yPrimed)
    hash = hash &* hash
    hash ^= hash << 19
    return Float(hash) * (1 / 2_147_483_648)
  }

  /// The dot product of the offset with the gradient picked by the hash of one lattice point.
  static func gradCoord(_ seed: Int32, _ xPrimed: Int32, _ yPrimed: Int32, _ xd: Float, _ yd: Float)
    -> Float
  {
    var hash = primedHash(seed, xPrimed, yPrimed)
    hash ^= hash >> 15
    hash &= 127 << 1
    let index = Int(hash)
    let xg = FastNoiseLiteTables.gradients2D[index]
    let yg = FastNoiseLiteTables.gradients2D[index | 1]
    return xd * xg + yd * yg
  }

  /// Truncating conversion used by `FastFloor`, clamped so that huge inputs do not trap.
  static func truncate(_ value: Float) -> Int32 {
    let limit: Float = 2_147_483_520
    return Int32(min(max(value, -limit), limit))
  }

  static func fastFloor(_ value: Float) -> Int32 {
    value >= 0 ? truncate(value) : truncate(value) &- 1
  }

  static func fastRound(_ value: Float) -> Int32 {
    value >= 0 ? truncate(value + 0.5) : truncate(value - 0.5)
  }

  static func fastAbs(_ value: Float) -> Float {
    value < 0 ? -value : value
  }

  static func fastMin(_ a: Float, _ b: Float) -> Float {
    a < b ? a : b
  }

  static func fastMax(_ a: Float, _ b: Float) -> Float {
    a > b ? a : b
  }

  static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + t * (b - a)
  }

  static func interpHermite(_ t: Float) -> Float {
    t * t * (3 - 2 * t)
  }

  static func interpQuintic(_ t: Float) -> Float {
    t * t * t * (t * (t * 6 - 15) + 10)
  }

  static func cubicLerp(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ t: Float) -> Float {
    let p = (d - c) - (a - b)
    return t * t * t * p + t * t * ((a - b) - p) + t * (c - a) + b
  }

  /// Value noise with Hermite interpolation between lattice values.
  static func singleValue(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    var x0 = fastFloor(x)
    var y0 = fastFloor(y)
    let xs = interpHermite(x - Float(x0))
    let ys = interpHermite(y - Float(y0))
    x0 = x0 &* primeX
    y0 = y0 &* primeY
    let x1 = x0 &+ primeX
    let y1 = y0 &+ primeY
    let xf0 = lerp(valCoord(seed, x0, y0), valCoord(seed, x1, y0), xs)
    let xf1 = lerp(valCoord(seed, x0, y1), valCoord(seed, x1, y1), xs)
    return lerp(xf0, xf1, ys)
  }

  /// Value noise with cubic interpolation over a 4 by 4 neighbourhood.
  static func singleValueCubic(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    var x1 = fastFloor(x)
    var y1 = fastFloor(y)
    let xs = x - Float(x1)
    let ys = y - Float(y1)
    x1 = x1 &* primeX
    y1 = y1 &* primeY
    let x0 = x1 &- primeX
    let y0 = y1 &- primeY
    let x2 = x1 &+ primeX
    let y2 = y1 &+ primeY
    let x3 = x1 &+ (primeX << 1)
    let y3 = y1 &+ (primeY << 1)
    func row(_ y: Int32) -> Float {
      cubicLerp(
        valCoord(seed, x0, y), valCoord(seed, x1, y), valCoord(seed, x2, y),
        valCoord(seed, x3, y), xs)
    }
    let column = cubicLerp(row(y0), row(y1), row(y2), row(y3), ys)
    return column * (1 / (1.5 * 1.5))
  }

  /// Perlin gradient noise with quintic interpolation.
  static func singlePerlin(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    var x0 = fastFloor(x)
    var y0 = fastFloor(y)
    let xd0 = x - Float(x0)
    let yd0 = y - Float(y0)
    let xd1 = xd0 - 1
    let yd1 = yd0 - 1
    let xs = interpQuintic(xd0)
    let ys = interpQuintic(yd0)
    x0 = x0 &* primeX
    y0 = y0 &* primeY
    let x1 = x0 &+ primeX
    let y1 = y0 &+ primeY
    let xf0 = lerp(
      gradCoord(seed, x0, y0, xd0, yd0), gradCoord(seed, x1, y0, xd1, yd0), xs)
    let xf1 = lerp(
      gradCoord(seed, x0, y1, xd0, yd1), gradCoord(seed, x1, y1, xd1, yd1), xs)
    return lerp(xf0, xf1, ys) * 1.4247691104677813
  }

  /// OpenSimplex2 on a skewed grid. The input must already be skewed by `transform`.
  static func singleSimplex(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    let sqrt3: Float = 1.7320508075688772935274463415059
    let g2: Float = (3 - sqrt3) / 6
    var i = fastFloor(x)
    var j = fastFloor(y)
    let xi = x - Float(i)
    let yi = y - Float(j)
    let t = (xi + yi) * g2
    let x0 = xi - t
    let y0 = yi - t
    i = i &* primeX
    j = j &* primeY
    var n0: Float = 0
    var n1: Float = 0
    var n2: Float = 0
    let a = 0.5 - x0 * x0 - y0 * y0
    if !(a <= 0) {
      n0 = (a * a) * (a * a) * gradCoord(seed, i, j, x0, y0)
    }
    let c =
      Float(2 * (1 - 2 * g2) * (1 / g2 - 2)) * t
      + (Float(-2 * (1 - 2 * g2) * (1 - 2 * g2)) + a)
    if !(c <= 0) {
      let x2 = x0 + (2 * g2 - 1)
      let y2 = y0 + (2 * g2 - 1)
      n2 = (c * c) * (c * c) * gradCoord(seed, i &+ primeX, j &+ primeY, x2, y2)
    }
    if y0 > x0 {
      let x1 = x0 + g2
      let y1 = y0 + (g2 - 1)
      let b = 0.5 - x1 * x1 - y1 * y1
      if !(b <= 0) {
        n1 = (b * b) * (b * b) * gradCoord(seed, i, j &+ primeY, x1, y1)
      }
    } else {
      let x1 = x0 + (g2 - 1)
      let y1 = y0 + g2
      let b = 0.5 - x1 * x1 - y1 * y1
      if !(b <= 0) {
        n1 = (b * b) * (b * b) * gradCoord(seed, i &+ primeX, j, x1, y1)
      }
    }
    return (n0 + n1 + n2) * 99.83685446303647
  }

  /// OpenSimplex2S, the smoother variant on a skewed grid with more neighbours.
  static func singleOpenSimplex2S(_ seed: Int32, _ x: Float, _ y: Float) -> Float {
    let sqrt3: Float = 1.7320508075688772935274463415059
    let g2: Float = (3 - sqrt3) / 6
    var i = fastFloor(x)
    var j = fastFloor(y)
    let xi = x - Float(i)
    let yi = y - Float(j)
    i = i &* primeX
    j = j &* primeY
    let i1 = i &+ primeX
    let j1 = j &+ primeY
    let t = (xi + yi) * g2
    let x0 = xi - t
    let y0 = yi - t
    let a0: Float = (2.0 / 3.0) - x0 * x0 - y0 * y0
    var value = (a0 * a0) * (a0 * a0) * gradCoord(seed, i, j, x0, y0)
    let a1 =
      Float(2 * (1 - 2 * g2) * (1 / g2 - 2)) * t
      + (Float(-2 * (1 - 2 * g2) * (1 - 2 * g2)) + a0)
    let x1 = x0 - (1 - 2 * g2)
    let y1 = y0 - (1 - 2 * g2)
    value += (a1 * a1) * (a1 * a1) * gradCoord(seed, i1, j1, x1, y1)
    let xmyi = xi - yi
    if t > g2 {
      if xi + xmyi > 1 {
        let x2 = x0 + (3 * g2 - 2)
        let y2 = y0 + (3 * g2 - 1)
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i &+ (primeX << 1), j &+ primeY, x2, y2)
        }
      } else {
        let x2 = x0 + g2
        let y2 = y0 + (g2 - 1)
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i, j &+ primeY, x2, y2)
        }
      }
      if yi - xmyi > 1 {
        let x3 = x0 + (3 * g2 - 1)
        let y3 = y0 + (3 * g2 - 2)
        let a3: Float = (2.0 / 3.0) - x3 * x3 - y3 * y3
        if a3 > 0 {
          value += (a3 * a3) * (a3 * a3) * gradCoord(seed, i &+ primeX, j &+ (primeY << 1), x3, y3)
        }
      } else {
        let x3 = x0 + (g2 - 1)
        let y3 = y0 + g2
        let a3: Float = (2.0 / 3.0) - x3 * x3 - y3 * y3
        if a3 > 0 {
          value += (a3 * a3) * (a3 * a3) * gradCoord(seed, i &+ primeX, j, x3, y3)
        }
      }
    } else {
      if xi + xmyi < 0 {
        let x2 = x0 + (1 - g2)
        let y2 = y0 - g2
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i &- primeX, j, x2, y2)
        }
      } else {
        let x2 = x0 + (g2 - 1)
        let y2 = y0 + g2
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i &+ primeX, j, x2, y2)
        }
      }
      if yi < xmyi {
        let x2 = x0 - g2
        let y2 = y0 - (g2 - 1)
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i, j &- primeY, x2, y2)
        }
      } else {
        let x2 = x0 + g2
        let y2 = y0 + (g2 - 1)
        let a2: Float = (2.0 / 3.0) - x2 * x2 - y2 * y2
        if a2 > 0 {
          value += (a2 * a2) * (a2 * a2) * gradCoord(seed, i, j &+ primeY, x2, y2)
        }
      }
    }
    return value * 18.24196194486065
  }

  /// Cellular (Worley) noise: the distances to the feature points of the 3 by 3 neighbourhood,
  /// combined by the return type. `jitter` is the cellular jitter modifier.
  static func singleCellular(
    _ seed: Int32,
    _ x: Float,
    _ y: Float,
    distanceFunction: CellularDistanceFunction,
    returnType: CellularReturnType,
    jitter: Float
  ) -> Float {
    let xr = fastRound(x)
    let yr = fastRound(y)
    var distance0: Float = 1e10
    var distance1: Float = 1e10
    var closestHash: Int32 = 0
    let cellularJitter = 0.43701595 * jitter
    var xPrimed = (xr &- 1) &* primeX
    let yPrimedBase = (yr &- 1) &* primeY
    for xi in (xr - 1)...(xr + 1) {
      var yPrimed = yPrimedBase
      for yi in (yr - 1)...(yr + 1) {
        let hash = primedHash(seed, xPrimed, yPrimed)
        let index = Int(hash & (255 << 1))
        let vecX = (Float(xi) - x) + FastNoiseLiteTables.randVecs2D[index] * cellularJitter
        let vecY = (Float(yi) - y) + FastNoiseLiteTables.randVecs2D[index | 1] * cellularJitter
        let newDistance: Float
        switch distanceFunction {
        case .euclidean, .euclideanSq:
          newDistance = vecX * vecX + vecY * vecY
        case .manhattan:
          newDistance = fastAbs(vecX) + fastAbs(vecY)
        case .hybrid:
          newDistance = (fastAbs(vecX) + fastAbs(vecY)) + (vecX * vecX + vecY * vecY)
        }
        distance1 = fastMax(fastMin(distance1, newDistance), distance0)
        if newDistance < distance0 {
          distance0 = newDistance
          closestHash = hash
        }
        yPrimed = yPrimed &+ primeY
      }
      xPrimed = xPrimed &+ primeX
    }
    if distanceFunction == .euclidean, returnType.rawValue >= CellularReturnType.distance.rawValue {
      distance0 = distance0.squareRoot()
      if returnType.rawValue >= CellularReturnType.distance2.rawValue {
        distance1 = distance1.squareRoot()
      }
    }
    switch returnType {
    case .cellValue: return Float(closestHash) * (1 / 2_147_483_648)
    case .distance: return distance0 - 1
    case .distance2: return distance1 - 1
    case .distance2Add: return (distance1 + distance0) * 0.5 - 1
    case .distance2Sub: return distance1 - distance0 - 1
    case .distance2Mul: return distance1 * distance0 * 0.5 - 1
    case .distance2Div: return distance0 / distance1 - 1
    }
  }
}
