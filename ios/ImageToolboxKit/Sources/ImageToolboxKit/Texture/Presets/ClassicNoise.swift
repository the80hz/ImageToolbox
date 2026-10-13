import Foundation

/// The gradient noise of the JH Labs filters, as the native code of the Android fork computes it
/// (`PerlinNoise` in `lib.rs`). The lattice tables are drawn from a seed with the same steps in the
/// same order as `PerlinNoise::new`. The Android app always draws them from `ClassicNative.tableSeed`.
struct ClassicNoise: Sendable {
  private static let latticeSize = 0x100
  private static let mask = 0xff
  private static let offset: Float = 0x1000

  /// The permutation of the lattice, doubled so that indices may run past 255.
  private let permutation: [Int]
  private let gradients2: [SIMD2<Float>]
  private let gradients3: [SIMD3<Float>]

  init(seed: Int64) {
    var random = ClassicRandom(seed: seed)
    let size = 2 * Self.latticeSize + 2
    var permutation = [Int](repeating: 0, count: size)
    var gradients2 = [SIMD2<Float>](repeating: .zero, count: size)
    var gradients3 = [SIMD3<Float>](repeating: .zero, count: size)
    for i in 0..<Self.latticeSize {
      permutation[i] = i
      // The reference also draws a one-dimensional gradient here, which these filters never
      // read. The draw keeps the sequence in step with the reference.
      _ = Self.lattice(&random)
      // Each component is drawn in turn, so the draws stay in the reference order.
      let pairX = Self.lattice(&random)
      let pairY = Self.lattice(&random)
      var pair = SIMD2<Float>(pairX, pairY)
      Self.normalise(&pair)
      gradients2[i] = pair
      let tripleX = Self.lattice(&random)
      let tripleY = Self.lattice(&random)
      let tripleZ = Self.lattice(&random)
      var triple = SIMD3<Float>(tripleX, tripleY, tripleZ)
      Self.normalise(&triple)
      gradients3[i] = triple
    }
    for i in stride(from: Self.latticeSize - 1, through: 0, by: -1) {
      let swapped = permutation[i]
      let j = Self.randomBits(&random) % Self.latticeSize
      permutation[i] = permutation[j]
      permutation[j] = swapped
    }
    for i in 0..<(Self.latticeSize + 2) {
      permutation[Self.latticeSize + i] = permutation[i]
      gradients2[Self.latticeSize + i] = gradients2[i]
      gradients3[Self.latticeSize + i] = gradients3[i]
    }
    self.permutation = permutation
    self.gradients2 = gradients2
    self.gradients3 = gradients3
  }

  /// `random() & 0x7fffffff`, the non-negative draw of the reference.
  private static func randomBits(_ random: inout ClassicRandom) -> Int {
    Int(random.nextInt() & 0x7fff_ffff)
  }

  /// One lattice component: `(random() % 512 - 256) / 256`, in -1...1.
  private static func lattice(_ random: inout ClassicRandom) -> Float {
    Float(randomBits(&random) % (2 * latticeSize) - latticeSize) / Float(latticeSize)
  }

  private static func normalise(_ v: inout SIMD2<Float>) {
    let length = (v[0] * v[0] + v[1] * v[1]).squareRoot()
    v[0] = v[0] / length
    v[1] = v[1] / length
  }

  private static func normalise(_ v: inout SIMD3<Float>) {
    let length = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot()
    v[0] = v[0] / length
    v[1] = v[1] / length
    v[2] = v[2] / length
  }

  private static func sCurve(_ t: Float) -> Float {
    t * t * (3 - 2 * t)
  }

  /// `Noise.noise2`: two-dimensional gradient noise, about -1.5...1.5.
  func noise2(_ x: Float, _ y: Float) -> Float {
    var t = x + Self.offset
    let bx0 = ClassicMath.toInt(t) & Self.mask
    let bx1 = (bx0 + 1) & Self.mask
    let rx0 = t - Float(ClassicMath.toInt(t))
    let rx1 = rx0 - 1
    t = y + Self.offset
    let by0 = ClassicMath.toInt(t) & Self.mask
    let by1 = (by0 + 1) & Self.mask
    let ry0 = t - Float(ClassicMath.toInt(t))
    let ry1 = ry0 - 1
    let i = permutation[bx0]
    let j = permutation[bx1]
    let b00 = permutation[i + by0]
    let b10 = permutation[j + by0]
    let b01 = permutation[i + by1]
    let b11 = permutation[j + by1]
    let sx = Self.sCurve(rx0)
    let sy = Self.sCurve(ry0)
    var q = gradients2[b00]
    var u = rx0 * q[0] + ry0 * q[1]
    q = gradients2[b10]
    var v = rx1 * q[0] + ry0 * q[1]
    let a = ClassicMath.lerp(sx, u, v)
    q = gradients2[b01]
    u = rx0 * q[0] + ry1 * q[1]
    q = gradients2[b11]
    v = rx1 * q[0] + ry1 * q[1]
    let b = ClassicMath.lerp(sx, u, v)
    return 1.5 * ClassicMath.lerp(sy, a, b)
  }

  /// `Noise.noise3`: three-dimensional gradient noise, about -1.5...1.5.
  func noise3(_ x: Float, _ y: Float, _ z: Float) -> Float {
    var t = x + Self.offset
    let bx0 = ClassicMath.toInt(t) & Self.mask
    let bx1 = (bx0 + 1) & Self.mask
    let rx0 = t - Float(ClassicMath.toInt(t))
    let rx1 = rx0 - 1
    t = y + Self.offset
    let by0 = ClassicMath.toInt(t) & Self.mask
    let by1 = (by0 + 1) & Self.mask
    let ry0 = t - Float(ClassicMath.toInt(t))
    let ry1 = ry0 - 1
    t = z + Self.offset
    let bz0 = ClassicMath.toInt(t) & Self.mask
    let bz1 = (bz0 + 1) & Self.mask
    let rz0 = t - Float(ClassicMath.toInt(t))
    let rz1 = rz0 - 1
    let i = permutation[bx0]
    let j = permutation[bx1]
    let b00 = permutation[i + by0]
    let b10 = permutation[j + by0]
    let b01 = permutation[i + by1]
    let b11 = permutation[j + by1]
    let sx = Self.sCurve(rx0)
    let sy = Self.sCurve(ry0)
    let sz = Self.sCurve(rz0)
    var q = gradients3[b00 + bz0]
    var u = rx0 * q[0] + ry0 * q[1] + rz0 * q[2]
    q = gradients3[b10 + bz0]
    var v = rx1 * q[0] + ry0 * q[1] + rz0 * q[2]
    var a = ClassicMath.lerp(sx, u, v)
    q = gradients3[b01 + bz0]
    u = rx0 * q[0] + ry1 * q[1] + rz0 * q[2]
    q = gradients3[b11 + bz0]
    v = rx1 * q[0] + ry1 * q[1] + rz0 * q[2]
    var b = ClassicMath.lerp(sx, u, v)
    let c = ClassicMath.lerp(sy, a, b)
    q = gradients3[b00 + bz1]
    u = rx0 * q[0] + ry0 * q[1] + rz1 * q[2]
    q = gradients3[b10 + bz1]
    v = rx1 * q[0] + ry0 * q[1] + rz1 * q[2]
    a = ClassicMath.lerp(sx, u, v)
    q = gradients3[b01 + bz1]
    u = rx0 * q[0] + ry1 * q[1] + rz1 * q[2]
    q = gradients3[b11 + bz1]
    v = rx1 * q[0] + ry1 * q[1] + rz1 * q[2]
    b = ClassicMath.lerp(sx, u, v)
    let d = ClassicMath.lerp(sy, a, b)
    return 1.5 * ClassicMath.lerp(sz, c, d)
  }

  /// `PerlinNoise.turbulence3` of the native code: `noise3` summed over octaves, each at twice the
  /// frequency and with its absolute value weighed by the inverse frequency, up to `octaves`.
  func turbulence3(_ x: Float, _ y: Float, _ z: Float, _ octaves: Float) -> Float {
    var total: Float = 0
    var frequency: Float = 1
    while frequency <= octaves {
      total += abs(noise3(frequency * x, frequency * y, frequency * z)) / frequency
      frequency *= 2
    }
    return total
  }
}

/// `LinearColormap`: blends from one ARGB colour to another as the position goes from 0 to 1.
struct ClassicLinearColormap: Sendable {
  let low: Int
  let high: Int

  func colour(_ t: Float) -> Int {
    ClassicMath.mixColours(ClassicMath.clamp(t, 0, 1), low, high)
  }
}
