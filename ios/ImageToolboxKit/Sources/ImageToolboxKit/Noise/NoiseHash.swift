import Foundation

/// Integer lattice hashing shared by the noise generators. Equal seeds and lattice points give
/// equal bits on every platform, so noise fields repeat exactly.
enum NoiseHash {
  /// 64 pseudo-random bits for one lattice point.
  static func bits(seed: UInt64, x: Int, y: Int) -> UInt64 {
    let column = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
    let row = UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
    var value = seed &+ column ^ row
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  /// A value in 0..<1 for one lattice point, from the top 53 bits.
  static func unit(seed: UInt64, x: Int, y: Int) -> Double {
    Double(bits(seed: seed, x: x, y: y) >> 11) / 9_007_199_254_740_992
  }

  /// Smoothstep-like fade used by value and gradient noise.
  static func fade(_ t: Double) -> Double {
    t * t * t * (t * (t * 6 - 15) + 10)
  }
}
