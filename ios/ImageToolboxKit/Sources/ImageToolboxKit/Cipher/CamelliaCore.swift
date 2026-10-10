import Foundation

/// Camellia (RFC 3713), 128-bit block, 128, 192 or 256-bit key.
final class CamelliaCore: BlockCore {
  let blockSize = 16

  /// Whitening keys kw1...kw4, round keys and FL keys, in the order of encryption.
  private let whitening: [UInt64]
  private let roundKeys: [UInt64]
  private let functionKeys: [UInt64]
  private let isLong: Bool

  private static let sbox1 = CipherTables.bytes(CipherTables.camelliaSBox1)
  private static let sbox2 = sbox1.map { $0 << 1 | $0 >> 7 }
  private static let sbox3 = sbox1.map { $0 << 7 | $0 >> 1 }
  private static let sbox4: [UInt8] = (0..<256).map {
    sbox1[Int((UInt8($0) << 1) | (UInt8($0) >> 7))]
  }

  private static let sigma: [UInt64] = [
    0xA09E_667F_3BCC_908B, 0xB67A_E858_4CAA_73B2, 0xC6EF_372F_E94F_82BE,
    0x54FF_53A5_F1D3_6F1C, 0x10E5_27FA_DE68_2D1D, 0xB056_88C2_B3E6_C1FD,
  ]

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 24, 32].contains(key.count) else { return nil }
    let (keyLeft, keyRight) = key.withUnsafeBufferPointer { storage -> (Pair, Pair) in
      let base = storage.baseAddress!
      let left = Pair(high: loadBigEndian64(base), low: loadBigEndian64(base + 8))
      switch key.count {
      case 16:
        return (left, Pair(high: 0, low: 0))
      case 24:
        let tail = loadBigEndian64(base + 16)
        return (left, Pair(high: tail, low: ~tail))
      default:
        return (left, Pair(high: loadBigEndian64(base + 16), low: loadBigEndian64(base + 24)))
      }
    }

    // KA from KL and KR, then KB (needed for 192 and 256-bit keys).
    var d1 = keyLeft.high ^ keyRight.high
    var d2 = keyLeft.low ^ keyRight.low
    d2 ^= CamelliaCore.f(d1, CamelliaCore.sigma[0])
    d1 ^= CamelliaCore.f(d2, CamelliaCore.sigma[1])
    d1 ^= keyLeft.high
    d2 ^= keyLeft.low
    d2 ^= CamelliaCore.f(d1, CamelliaCore.sigma[2])
    d1 ^= CamelliaCore.f(d2, CamelliaCore.sigma[3])
    let keyA = Pair(high: d1, low: d2)
    d1 = keyA.high ^ keyRight.high
    d2 = keyA.low ^ keyRight.low
    d2 ^= CamelliaCore.f(d1, CamelliaCore.sigma[4])
    d1 ^= CamelliaCore.f(d2, CamelliaCore.sigma[5])
    let keyB = Pair(high: d1, low: d2)

    let kl = keyLeft
    let kr = keyRight
    let ka = keyA
    let kb = keyB
    if key.count == 16 {
      isLong = false
      whitening = [
        kl.rotated(0).high, kl.rotated(0).low, ka.rotated(111).high, ka.rotated(111).low,
      ]
      roundKeys = [
        ka.rotated(0).high, ka.rotated(0).low,
        kl.rotated(15).high, kl.rotated(15).low,
        ka.rotated(15).high, ka.rotated(15).low,
        kl.rotated(45).high, kl.rotated(45).low,
        ka.rotated(45).high, kl.rotated(60).low,
        ka.rotated(60).high, ka.rotated(60).low,
        kl.rotated(94).high, kl.rotated(94).low,
        ka.rotated(94).high, ka.rotated(94).low,
        kl.rotated(111).high, kl.rotated(111).low,
      ]
      functionKeys = [
        ka.rotated(30).high, ka.rotated(30).low, kl.rotated(77).high, kl.rotated(77).low,
      ]
    } else {
      isLong = true
      whitening = [
        kl.rotated(0).high, kl.rotated(0).low, kb.rotated(111).high, kb.rotated(111).low,
      ]
      roundKeys = [
        kb.rotated(0).high, kb.rotated(0).low,
        kr.rotated(15).high, kr.rotated(15).low,
        ka.rotated(15).high, ka.rotated(15).low,
        kb.rotated(30).high, kb.rotated(30).low,
        kl.rotated(45).high, kl.rotated(45).low,
        ka.rotated(45).high, ka.rotated(45).low,
        kr.rotated(60).high, kr.rotated(60).low,
        kb.rotated(60).high, kb.rotated(60).low,
        kl.rotated(77).high, kl.rotated(77).low,
        kr.rotated(94).high, kr.rotated(94).low,
        ka.rotated(94).high, ka.rotated(94).low,
        kl.rotated(111).high, kl.rotated(111).low,
      ]
      functionKeys = [
        kr.rotated(30).high, kr.rotated(30).low,
        kl.rotated(60).high, kl.rotated(60).low,
        ka.rotated(77).high, ka.rotated(77).low,
      ]
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, decrypt: false)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, decrypt: true)
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, decrypt: Bool) {
    let roundCount = isLong ? 24 : 18
    let groupCount = roundCount / 6
    var d1 = loadBigEndian64(block)
    var d2 = loadBigEndian64(block + 8)
    d1 ^= decrypt ? whitening[2] : whitening[0]
    d2 ^= decrypt ? whitening[3] : whitening[1]
    for group in 0..<groupCount {
      for step in 0..<3 {
        let first = decrypt ? roundCount - 1 - (group * 6 + step * 2) : group * 6 + step * 2
        let second = decrypt ? first - 1 : first + 1
        d2 ^= CamelliaCore.f(d1, roundKeys[first])
        d1 ^= CamelliaCore.f(d2, roundKeys[second])
      }
      if group < groupCount - 1 {
        let index = group * 2
        let last = functionKeys.count - 1
        let flKey = decrypt ? functionKeys[last - index] : functionKeys[index]
        let flInverseKey = decrypt ? functionKeys[last - index - 1] : functionKeys[index + 1]
        d1 = CamelliaCore.fl(d1, flKey)
        d2 = CamelliaCore.flInverse(d2, flInverseKey)
      }
    }
    d2 ^= decrypt ? whitening[0] : whitening[2]
    d1 ^= decrypt ? whitening[1] : whitening[3]
    storeBigEndian64(d2, block)
    storeBigEndian64(d1, block + 8)
  }

  // MARK: Functions

  private struct Pair {
    var high: UInt64
    var low: UInt64

    /// The 128-bit value rotated left by `bits`.
    func rotated(_ bits: Int) -> Pair {
      let amount = bits % 128
      guard amount != 0 else { return self }
      var first = high
      var second = low
      var shift = amount
      if shift >= 64 {
        swap(&first, &second)
        shift -= 64
      }
      guard shift != 0 else { return Pair(high: first, low: second) }
      let shiftCount = UInt64(shift)
      let newHigh = first << shiftCount | second >> (64 - shiftCount)
      let newLow = second << shiftCount | first >> (64 - shiftCount)
      return Pair(high: newHigh, low: newLow)
    }
  }

  private static func f(_ input: UInt64, _ key: UInt64) -> UInt64 {
    let x = input ^ key
    let t1 = sbox1[Int(x >> 56)]
    let t2 = sbox2[Int((x >> 48) & 0xFF)]
    let t3 = sbox3[Int((x >> 40) & 0xFF)]
    let t4 = sbox4[Int((x >> 32) & 0xFF)]
    let t5 = sbox2[Int((x >> 24) & 0xFF)]
    let t6 = sbox3[Int((x >> 16) & 0xFF)]
    let t7 = sbox4[Int((x >> 8) & 0xFF)]
    let t8 = sbox1[Int(x & 0xFF)]
    let y1 = t1 ^ t3 ^ t4 ^ t6 ^ t7 ^ t8
    let y2 = t1 ^ t2 ^ t4 ^ t5 ^ t7 ^ t8
    let y3 = t1 ^ t2 ^ t3 ^ t5 ^ t6 ^ t8
    let y4 = t2 ^ t3 ^ t4 ^ t5 ^ t6 ^ t7
    let y5 = t1 ^ t2 ^ t6 ^ t7 ^ t8
    let y6 = t2 ^ t3 ^ t5 ^ t7 ^ t8
    let y7 = t3 ^ t4 ^ t5 ^ t6 ^ t8
    let y8 = t1 ^ t4 ^ t5 ^ t6 ^ t7
    var result = UInt64(y1)
    for byte in [y2, y3, y4, y5, y6, y7, y8] { result = result << 8 | UInt64(byte) }
    return result
  }

  private static func fl(_ input: UInt64, _ key: UInt64) -> UInt64 {
    var x1 = UInt32(truncatingIfNeeded: input >> 32)
    var x2 = UInt32(truncatingIfNeeded: input)
    let k1 = UInt32(truncatingIfNeeded: key >> 32)
    let k2 = UInt32(truncatingIfNeeded: key)
    x2 ^= rotateLeft(x1 & k1, 1)
    x1 ^= x2 | k2
    return UInt64(x1) << 32 | UInt64(x2)
  }

  private static func flInverse(_ input: UInt64, _ key: UInt64) -> UInt64 {
    var y1 = UInt32(truncatingIfNeeded: input >> 32)
    var y2 = UInt32(truncatingIfNeeded: input)
    let k1 = UInt32(truncatingIfNeeded: key >> 32)
    let k2 = UInt32(truncatingIfNeeded: key)
    y1 ^= y2 | k2
    y2 ^= rotateLeft(y1 & k1, 1)
    return UInt64(y1) << 32 | UInt64(y2)
  }
}
