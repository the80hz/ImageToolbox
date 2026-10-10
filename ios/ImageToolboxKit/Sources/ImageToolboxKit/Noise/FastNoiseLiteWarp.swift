import Foundation

/// The 2D domain warp of FastNoiseLite: the three warp kernels and the octave loops that apply
/// them. Each kernel adds an offset to the output point, so the caller passes the original
/// point as the starting value.
extension FastNoiseLite {
  /// Warp of a single octave, for the settings' domain warp type.
  func warpSingle(_ x: inout Float, _ y: inout Float) {
    let seed = self.seed
    let amplitude = domainWarpAmp * fractalBounding
    let freq = frequency
    var xs = x
    var ys = y
    transformDomainWarpCoordinate(&xs, &ys)
    doSingleDomainWarp(seed, amplitude, freq, xs, ys, &x, &y)
  }

  /// Progressive warp: every octave warps the result of the octave before.
  func warpProgressive(_ x: inout Float, _ y: inout Float) {
    var seed = self.seed
    var amplitude = domainWarpAmp * fractalBounding
    var freq = frequency
    for _ in 0..<max(0, octaves) {
      var xs = x
      var ys = y
      transformDomainWarpCoordinate(&xs, &ys)
      doSingleDomainWarp(seed, amplitude, freq, xs, ys, &x, &y)
      seed = seed &+ 1
      amplitude *= gain
      freq *= lacunarity
    }
  }

  /// Independent warp: every octave warps from the same starting point and adds its offset.
  func warpIndependent(_ x: inout Float, _ y: inout Float) {
    var xs = x
    var ys = y
    transformDomainWarpCoordinate(&xs, &ys)
    var seed = self.seed
    var amplitude = domainWarpAmp * fractalBounding
    var freq = frequency
    for _ in 0..<max(0, octaves) {
      doSingleDomainWarp(seed, amplitude, freq, xs, ys, &x, &y)
      seed = seed &+ 1
      amplitude *= gain
      freq *= lacunarity
    }
  }

  /// Skews the input onto the simplex grid for the simplex warps. The basic grid warp needs no
  /// skew.
  func transformDomainWarpCoordinate(_ x: inout Float, _ y: inout Float) {
    switch domainWarpType {
    case .openSimplex2, .openSimplex2Reduced:
      let sqrt3: Float = 1.7320508075688772935274463415059
      let f2: Float = 0.5 * (sqrt3 - 1)
      let t = (x + y) * f2
      x += t
      y += t
    case .basicGrid:
      break
    }
  }

  func doSingleDomainWarp(
    _ seed: Int32,
    _ amplitude: Float,
    _ freq: Float,
    _ x: Float,
    _ y: Float,
    _ xr: inout Float,
    _ yr: inout Float
  ) {
    switch domainWarpType {
    case .openSimplex2:
      simplexGradientWarp(
        seed, amplitude * 38.283687591552734375, freq, x, y, &xr, &yr, gradientOnly: false)
    case .openSimplex2Reduced:
      simplexGradientWarp(seed, amplitude * 16, freq, x, y, &xr, &yr, gradientOnly: true)
    case .basicGrid:
      basicGridWarp(seed, amplitude, freq, x, y, &xr, &yr)
    }
  }

  /// The simplex gradient warp: a weighted sum of the gradients at the three corners of the
  /// simplex that contains the point. `gradientOnly` drops the dot product with the offset.
  func simplexGradientWarp(
    _ seed: Int32,
    _ warpAmp: Float,
    _ frequency: Float,
    _ inputX: Float,
    _ inputY: Float,
    _ xr: inout Float,
    _ yr: inout Float,
    gradientOnly: Bool
  ) {
    let sqrt3: Float = 1.7320508075688772935274463415059
    let g2: Float = (3 - sqrt3) / 6
    let x = inputX * frequency
    let y = inputY * frequency
    var i = Self.fastFloor(x)
    var j = Self.fastFloor(y)
    let xi = x - Float(i)
    let yi = y - Float(j)
    let t = (xi + yi) * g2
    let x0 = xi - t
    let y0 = yi - t
    i = i &* Self.primeX
    j = j &* Self.primeY
    var vx: Float = 0
    var vy: Float = 0
    let a = 0.5 - x0 * x0 - y0 * y0
    if a > 0 {
      let aaaa = (a * a) * (a * a)
      let (xo, yo) =
        gradientOnly
        ? gradCoordOut(seed, i, j)
        : gradCoordDual(seed, i, j, x0, y0)
      vx += aaaa * xo
      vy += aaaa * yo
    }
    let c =
      Float(2 * (1 - 2 * g2) * (1 / g2 - 2)) * t
      + (Float(-2 * (1 - 2 * g2) * (1 - 2 * g2)) + a)
    if c > 0 {
      let x2 = x0 + (2 * g2 - 1)
      let y2 = y0 + (2 * g2 - 1)
      let cccc = (c * c) * (c * c)
      let (xo, yo) =
        gradientOnly
        ? gradCoordOut(seed, i &+ Self.primeX, j &+ Self.primeY)
        : gradCoordDual(seed, i &+ Self.primeX, j &+ Self.primeY, x2, y2)
      vx += cccc * xo
      vy += cccc * yo
    }
    if y0 > x0 {
      let x1 = x0 + g2
      let y1 = y0 + (g2 - 1)
      let b = 0.5 - x1 * x1 - y1 * y1
      if b > 0 {
        let bbbb = (b * b) * (b * b)
        let (xo, yo) =
          gradientOnly
          ? gradCoordOut(seed, i, j &+ Self.primeY)
          : gradCoordDual(seed, i, j &+ Self.primeY, x1, y1)
        vx += bbbb * xo
        vy += bbbb * yo
      }
    } else {
      let x1 = x0 + (g2 - 1)
      let y1 = y0 + g2
      let b = 0.5 - x1 * x1 - y1 * y1
      if b > 0 {
        let bbbb = (b * b) * (b * b)
        let (xo, yo) =
          gradientOnly
          ? gradCoordOut(seed, i &+ Self.primeX, j)
          : gradCoordDual(seed, i &+ Self.primeX, j, x1, y1)
        vx += bbbb * xo
        vy += bbbb * yo
      }
    }
    xr += vx * warpAmp
    yr += vy * warpAmp
  }

  /// The basic grid warp: bilinear interpolation of random vectors on the integer grid, with
  /// Hermite weights.
  func basicGridWarp(
    _ seed: Int32,
    _ warpAmp: Float,
    _ frequency: Float,
    _ inputX: Float,
    _ inputY: Float,
    _ xr: inout Float,
    _ yr: inout Float
  ) {
    let xf = inputX * frequency
    let yf = inputY * frequency
    var x0 = Self.fastFloor(xf)
    var y0 = Self.fastFloor(yf)
    let xs = Self.interpHermite(xf - Float(x0))
    let ys = Self.interpHermite(yf - Float(y0))
    x0 = x0 &* Self.primeX
    y0 = y0 &* Self.primeY
    let x1 = x0 &+ Self.primeX
    let y1 = y0 &+ Self.primeY
    let vectors = FastNoiseLiteTables.randVecs2D
    var hash0 = Int(Self.primedHash(seed, x0, y0) & (255 << 1))
    var hash1 = Int(Self.primedHash(seed, x1, y0) & (255 << 1))
    let lx0x = Self.lerp(vectors[hash0], vectors[hash1], xs)
    let ly0x = Self.lerp(vectors[hash0 | 1], vectors[hash1 | 1], xs)
    hash0 = Int(Self.primedHash(seed, x0, y1) & (255 << 1))
    hash1 = Int(Self.primedHash(seed, x1, y1) & (255 << 1))
    let lx1x = Self.lerp(vectors[hash0], vectors[hash1], xs)
    let ly1x = Self.lerp(vectors[hash0 | 1], vectors[hash1 | 1], xs)
    xr += Self.lerp(lx0x, lx1x, ys) * warpAmp
    yr += Self.lerp(ly0x, ly1x, ys) * warpAmp
  }

  /// A unit vector picked by the hash of one lattice point.
  func gradCoordOut(_ seed: Int32, _ xPrimed: Int32, _ yPrimed: Int32) -> (Float, Float) {
    let index = Int(Self.primedHash(seed, xPrimed, yPrimed) & (255 << 1))
    return (FastNoiseLiteTables.randVecs2D[index], FastNoiseLiteTables.randVecs2D[index | 1])
  }

  /// A unit vector picked by the hash, scaled by the dot product of the offset with a gradient.
  func gradCoordDual(
    _ seed: Int32, _ xPrimed: Int32, _ yPrimed: Int32, _ xd: Float, _ yd: Float
  ) -> (Float, Float) {
    let hash = Self.primedHash(seed, xPrimed, yPrimed)
    let index1 = Int(hash & (127 << 1))
    let index2 = Int((hash >> 7) & (255 << 1))
    let xg = FastNoiseLiteTables.gradients2D[index1]
    let yg = FastNoiseLiteTables.gradients2D[index1 | 1]
    let value = xd * xg + yd * yg
    let xgo = FastNoiseLiteTables.randVecs2D[index2]
    let ygo = FastNoiseLiteTables.randVecs2D[index2 | 1]
    return (value * xgo, value * ygo)
  }
}
