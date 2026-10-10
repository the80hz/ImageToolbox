import Foundation

/// LEA (KISA, the Korean standard TTAK.KO-12.0223), 128-bit block, 128, 192 or 256-bit key.
final class LEACore: BlockCore {
  let blockSize = 16

  private let rounds: Int
  /// Six words for each round.
  private var roundKeys: [UInt32]

  private static let delta: [UInt32] = [
    0xC3EF_E9DB, 0x4462_6B02, 0x79E2_7C8A, 0x78DF_30EC,
    0x715E_A49E, 0xC785_DA0A, 0xE04E_F22A, 0xE5C4_0957,
  ]

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 24, 32].contains(key.count) else { return nil }
    var t = words32(key, bigEndian: false)
    switch key.count {
    case 16: rounds = 24
    case 24: rounds = 28
    default: rounds = 32
    }
    roundKeys = [UInt32](repeating: 0, count: rounds * 6)
    for round in 0..<rounds {
      let r = UInt32(round)
      switch key.count {
      case 16:
        let d = LEACore.delta[round % 4]
        t[0] = rotateLeft(t[0] &+ rotateLeft(d, r), 1)
        t[1] = rotateLeft(t[1] &+ rotateLeft(d, r &+ 1), 3)
        t[2] = rotateLeft(t[2] &+ rotateLeft(d, r &+ 2), 6)
        t[3] = rotateLeft(t[3] &+ rotateLeft(d, r &+ 3), 11)
        let key = [t[0], t[1], t[2], t[1], t[3], t[1]]
        roundKeys.replaceSubrange(round * 6..<round * 6 + 6, with: key)
      case 24:
        let d = LEACore.delta[round % 6]
        t[0] = rotateLeft(t[0] &+ rotateLeft(d, r), 1)
        t[1] = rotateLeft(t[1] &+ rotateLeft(d, r &+ 1), 3)
        t[2] = rotateLeft(t[2] &+ rotateLeft(d, r &+ 2), 6)
        t[3] = rotateLeft(t[3] &+ rotateLeft(d, r &+ 3), 11)
        t[4] = rotateLeft(t[4] &+ rotateLeft(d, r &+ 4), 13)
        t[5] = rotateLeft(t[5] &+ rotateLeft(d, r &+ 5), 17)
        roundKeys.replaceSubrange(round * 6..<round * 6 + 6, with: t)
      default:
        let d = LEACore.delta[round % 8]
        let rotationsPerWord: [UInt32] = [1, 3, 6, 11, 13, 17]
        var key: [UInt32] = []
        for offset in 0..<6 {
          let slot = (6 * round + offset) % 8
          t[slot] = rotateLeft(
            t[slot] &+ rotateLeft(d, r &+ UInt32(offset)), rotationsPerWord[offset])
          key.append(t[slot])
        }
        roundKeys.replaceSubrange(round * 6..<round * 6 + 6, with: key)
      }
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var x0 = loadLittleEndian32(block)
    var x1 = loadLittleEndian32(block + 4)
    var x2 = loadLittleEndian32(block + 8)
    var x3 = loadLittleEndian32(block + 12)
    for round in 0..<rounds {
      let k = round * 6
      let n0 = rotateLeft((x0 ^ roundKeys[k]) &+ (x1 ^ roundKeys[k + 1]), 9)
      let n1 = rotateRight((x1 ^ roundKeys[k + 2]) &+ (x2 ^ roundKeys[k + 3]), 5)
      let n2 = rotateRight((x2 ^ roundKeys[k + 4]) &+ (x3 ^ roundKeys[k + 5]), 3)
      (x0, x1, x2, x3) = (n0, n1, n2, x0)
    }
    storeLittleEndian32(x0, block)
    storeLittleEndian32(x1, block + 4)
    storeLittleEndian32(x2, block + 8)
    storeLittleEndian32(x3, block + 12)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var x0 = loadLittleEndian32(block)
    var x1 = loadLittleEndian32(block + 4)
    var x2 = loadLittleEndian32(block + 8)
    var x3 = loadLittleEndian32(block + 12)
    for round in (0..<rounds).reversed() {
      let k = round * 6
      let p0 = x3
      let p1 = (rotateRight(x0, 9) &- (p0 ^ roundKeys[k])) ^ roundKeys[k + 1]
      let p2 = (rotateLeft(x1, 5) &- (p1 ^ roundKeys[k + 2])) ^ roundKeys[k + 3]
      let p3 = (rotateLeft(x2, 3) &- (p2 ^ roundKeys[k + 4])) ^ roundKeys[k + 5]
      (x0, x1, x2, x3) = (p0, p1, p2, p3)
    }
    storeLittleEndian32(x0, block)
    storeLittleEndian32(x1, block + 4)
    storeLittleEndian32(x2, block + 8)
    storeLittleEndian32(x3, block + 12)
  }
}
