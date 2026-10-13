import Foundation

/// Twofish (Schneier et al., AES finalist), 128-bit block, 128, 192 or 256-bit key.
final class TwofishCore: BlockCore {
  let blockSize = 16

  private var subkeys = [UInt32](repeating: 0, count: 40)
  /// The four key-dependent S-boxes with the MDS matrix folded in, 256 words each.
  private var sboxes = [UInt32](repeating: 0, count: 1024)

  private static let q0 = CipherTables.bytes(CipherTables.twofishQ0)
  private static let q1 = CipherTables.bytes(CipherTables.twofishQ1)

  /// The Reed-Solomon matrix used to derive the S-box keys.
  private static let reedSolomon: [[UInt8]] = [
    [0x01, 0xA4, 0x55, 0x87, 0x5A, 0x58, 0xDB, 0x9E],
    [0xA4, 0x56, 0x82, 0xF3, 0x1E, 0xC6, 0x68, 0xE5],
    [0x02, 0xA1, 0xFC, 0xC1, 0x47, 0xAE, 0x3D, 0x19],
    [0xA4, 0x55, 0x87, 0x5A, 0x58, 0xDB, 0x9E, 0x03],
  ]

  /// The MDS matrix of the h function.
  private static let mds: [[UInt8]] = [
    [0x01, 0xEF, 0x5B, 0x5B],
    [0x5B, 0xEF, 0xEF, 0x01],
    [0xEF, 0x5B, 0x01, 0xEF],
    [0xEF, 0x01, 0xEF, 0x5B],
  ]

  /// Which of q0 (false) or q1 (true) each lane uses in each stage of h, from the first stage that
  /// is applied to the last. The stages are the ones before the xor with L3, L2, L1, L0 and the
  /// final one.
  private static let permutations: [[Bool]] = [
    [true, false, false, true],
    [true, true, false, false],
    [false, true, false, true],
    [false, false, true, true],
    [true, false, true, false],
  ]

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 24, 32].contains(key.count) else { return nil }
    let count = key.count / 8
    let words = words32(key, bigEndian: false)
    var even: [UInt32] = []
    var odd: [UInt32] = []
    for index in 0..<count {
      even.append(words[2 * index])
      odd.append(words[2 * index + 1])
    }

    // The S vector, in the reversed order the h function takes it.
    var sVector = [UInt32](repeating: 0, count: count)
    for index in 0..<count {
      var word: UInt32 = 0
      for row in 0..<4 {
        var accumulator: UInt8 = 0
        for column in 0..<8 {
          accumulator ^= TwofishCore.multiply(
            TwofishCore.reedSolomon[row][column], key[8 * index + column], modulus: 0x14D)
        }
        word |= UInt32(accumulator) << UInt32(8 * row)
      }
      sVector[count - 1 - index] = word
    }

    for index in 0..<20 {
      let a = TwofishCore.h(UInt32(2 * index) &* 0x0101_0101, even)
      var b = TwofishCore.h(UInt32(2 * index + 1) &* 0x0101_0101, odd)
      b = rotateLeft(b, 8)
      subkeys[2 * index] = a &+ b
      subkeys[2 * index + 1] = rotateLeft(a &+ 2 &* b, 9)
    }

    for lane in 0..<4 {
      for value in 0..<256 {
        let substituted = TwofishCore.lane(lane, UInt8(value), sVector)
        var word: UInt32 = 0
        for row in 0..<4 {
          let product = TwofishCore.multiply(
            TwofishCore.mds[row][lane], substituted, modulus: 0x169)
          word |= UInt32(product) << UInt32(8 * row)
        }
        sboxes[lane * 256 + value] = word
      }
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var r0 = loadLittleEndian32(block) ^ subkeys[0]
    var r1 = loadLittleEndian32(block + 4) ^ subkeys[1]
    var r2 = loadLittleEndian32(block + 8) ^ subkeys[2]
    var r3 = loadLittleEndian32(block + 12) ^ subkeys[3]
    for round in 0..<16 {
      let t0 = g(r0)
      let t1 = g(rotateLeft(r1, 8))
      let f0 = t0 &+ t1 &+ subkeys[2 * round + 8]
      let f1 = t0 &+ 2 &* t1 &+ subkeys[2 * round + 9]
      let next2 = rotateRight(r2 ^ f0, 1)
      let next3 = rotateLeft(r3, 1) ^ f1
      r2 = r0
      r3 = r1
      r0 = next2
      r1 = next3
    }
    storeLittleEndian32(r2 ^ subkeys[4], block)
    storeLittleEndian32(r3 ^ subkeys[5], block + 4)
    storeLittleEndian32(r0 ^ subkeys[6], block + 8)
    storeLittleEndian32(r1 ^ subkeys[7], block + 12)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var r0 = loadLittleEndian32(block + 8) ^ subkeys[6]
    var r1 = loadLittleEndian32(block + 12) ^ subkeys[7]
    var r2 = loadLittleEndian32(block) ^ subkeys[4]
    var r3 = loadLittleEndian32(block + 4) ^ subkeys[5]
    for round in (0..<16).reversed() {
      let previous0 = r2
      let previous1 = r3
      let t0 = g(previous0)
      let t1 = g(rotateLeft(previous1, 8))
      let f0 = t0 &+ t1 &+ subkeys[2 * round + 8]
      let f1 = t0 &+ 2 &* t1 &+ subkeys[2 * round + 9]
      let previous2 = rotateLeft(r0, 1) ^ f0
      let previous3 = rotateRight(r1 ^ f1, 1)
      r0 = previous0
      r1 = previous1
      r2 = previous2
      r3 = previous3
    }
    storeLittleEndian32(r0 ^ subkeys[0], block)
    storeLittleEndian32(r1 ^ subkeys[1], block + 4)
    storeLittleEndian32(r2 ^ subkeys[2], block + 8)
    storeLittleEndian32(r3 ^ subkeys[3], block + 12)
  }

  /// The g function: h with the key-dependent S-boxes.
  @inline(__always)
  private func g(_ word: UInt32) -> UInt32 {
    sboxes[Int(word & 0xFF)] ^ sboxes[256 + Int((word >> 8) & 0xFF)]
      ^ sboxes[512 + Int((word >> 16) & 0xFF)] ^ sboxes[768 + Int(word >> 24)]
  }

  // MARK: The h function

  /// The substitution part of h for one byte lane, before the MDS matrix.
  private static func lane(_ lane: Int, _ input: UInt8, _ keyWords: [UInt32]) -> UInt8 {
    var value = input
    // Stage s is followed by the xor with L(3 - s); with fewer key words the early stages are
    // skipped.
    for stage in (4 - keyWords.count)..<4 {
      value = (permutations[stage][lane] ? q1 : q0)[Int(value)]
      value ^= UInt8(truncatingIfNeeded: keyWords[3 - stage] >> UInt32(8 * lane))
    }
    return (permutations[4][lane] ? q1 : q0)[Int(value)]
  }

  private static func h(_ input: UInt32, _ keyWords: [UInt32]) -> UInt32 {
    var substituted = [UInt8](repeating: 0, count: 4)
    for lane in 0..<4 {
      substituted[lane] = TwofishCore.lane(
        lane, UInt8(truncatingIfNeeded: input >> UInt32(8 * lane)), keyWords)
    }
    var word: UInt32 = 0
    for row in 0..<4 {
      var accumulator: UInt8 = 0
      for column in 0..<4 {
        accumulator ^= multiply(mds[row][column], substituted[column], modulus: 0x169)
      }
      word |= UInt32(accumulator) << UInt32(8 * row)
    }
    return word
  }

  /// Multiplication in GF(2^8) with the given reduction polynomial (including the x^8 term).
  private static func multiply(_ a: UInt8, _ b: UInt8, modulus: UInt16) -> UInt8 {
    var result: UInt16 = 0
    var x = UInt16(a)
    var y = b
    while y != 0 {
      if y & 1 == 1 { result ^= x }
      x <<= 1
      if x & 0x100 != 0 { x ^= modulus }
      y >>= 1
    }
    return UInt8(truncatingIfNeeded: result)
  }
}
