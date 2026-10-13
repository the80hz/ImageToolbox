import Foundation

/// RC5-32/12 (Rivest), 64-bit block, key of 1 to 255 bytes.
final class RC5Core: BlockCore {
  let blockSize = 8

  private var schedule = [UInt32](repeating: 0, count: 26)

  /// Returns `nil` unless the key is 1 to 255 bytes long.
  init?(key: [UInt8]) {
    guard (1...255).contains(key.count) else { return nil }
    var words = words32(key, bigEndian: false)
    let count = words.count
    schedule[0] = 0xB7E1_5163
    for index in 1..<26 { schedule[index] = schedule[index - 1] &+ 0x9E37_79B9 }
    var a: UInt32 = 0
    var b: UInt32 = 0
    var i = 0
    var j = 0
    for _ in 0..<(3 * max(count, 26)) {
      a = rotateLeft(schedule[i] &+ a &+ b, 3)
      schedule[i] = a
      b = rotateLeft(words[j] &+ a &+ b, a &+ b)
      words[j] = b
      i = (i + 1) % 26
      j = (j + 1) % count
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadLittleEndian32(block) &+ schedule[0]
    var b = loadLittleEndian32(block + 4) &+ schedule[1]
    for round in 1...12 {
      a = rotateLeft(a ^ b, b) &+ schedule[2 * round]
      b = rotateLeft(b ^ a, a) &+ schedule[2 * round + 1]
    }
    storeLittleEndian32(a, block)
    storeLittleEndian32(b, block + 4)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadLittleEndian32(block)
    var b = loadLittleEndian32(block + 4)
    for round in (1...12).reversed() {
      b = rotateRight(b &- schedule[2 * round + 1], a) ^ a
      a = rotateRight(a &- schedule[2 * round], b) ^ b
    }
    storeLittleEndian32(a &- schedule[0], block)
    storeLittleEndian32(b &- schedule[1], block + 4)
  }
}

/// TEA (Wheeler and Needham), 64-bit block, 128-bit key, 32 cycles, big-endian words.
final class TEACore: BlockCore {
  let blockSize = 8

  private let key: [UInt32]

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    self.key = words32(key, bigEndian: true)
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v0 = loadBigEndian32(block)
    var v1 = loadBigEndian32(block + 4)
    var sum: UInt32 = 0
    for _ in 0..<32 {
      sum = sum &+ 0x9E37_79B9
      v0 = v0 &+ (((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1]))
      v1 = v1 &+ (((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3]))
    }
    storeBigEndian32(v0, block)
    storeBigEndian32(v1, block + 4)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v0 = loadBigEndian32(block)
    var v1 = loadBigEndian32(block + 4)
    var sum: UInt32 = 0x9E37_79B9 &* 32
    for _ in 0..<32 {
      v1 = v1 &- (((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3]))
      v0 = v0 &- (((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1]))
      sum = sum &- 0x9E37_79B9
    }
    storeBigEndian32(v0, block)
    storeBigEndian32(v1, block + 4)
  }
}

/// XTEA (Needham and Wheeler), 64-bit block, 128-bit key, 32 cycles, big-endian words.
final class XTEACore: BlockCore {
  let blockSize = 8

  private let key: [UInt32]

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    self.key = words32(key, bigEndian: true)
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v0 = loadBigEndian32(block)
    var v1 = loadBigEndian32(block + 4)
    var sum: UInt32 = 0
    for _ in 0..<32 {
      v0 = v0 &+ ((((v1 << 4) ^ (v1 >> 5)) &+ v1) ^ (sum &+ key[Int(sum & 3)]))
      sum = sum &+ 0x9E37_79B9
      v1 = v1 &+ ((((v0 << 4) ^ (v0 >> 5)) &+ v0) ^ (sum &+ key[Int((sum >> 11) & 3)]))
    }
    storeBigEndian32(v0, block)
    storeBigEndian32(v1, block + 4)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v0 = loadBigEndian32(block)
    var v1 = loadBigEndian32(block + 4)
    var sum: UInt32 = 0x9E37_79B9 &* 32
    for _ in 0..<32 {
      v1 = v1 &- ((((v0 << 4) ^ (v0 >> 5)) &+ v0) ^ (sum &+ key[Int((sum >> 11) & 3)]))
      sum = sum &- 0x9E37_79B9
      v0 = v0 &- ((((v1 << 4) ^ (v1 >> 5)) &+ v1) ^ (sum &+ key[Int(sum & 3)]))
    }
    storeBigEndian32(v0, block)
    storeBigEndian32(v1, block + 4)
  }
}

/// Skipjack (NSA, declassified 1998), 64-bit block, 80-bit key.
final class SkipjackCore: BlockCore {
  let blockSize = 8

  private let key: [UInt8]

  private static let table = CipherTables.bytes(CipherTables.skipjackF)

  /// Returns `nil` unless the key is 10 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 10 else { return nil }
    self.key = key
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var w1 = UInt16(block[0]) << 8 | UInt16(block[1])
    var w2 = UInt16(block[2]) << 8 | UInt16(block[3])
    var w3 = UInt16(block[4]) << 8 | UInt16(block[5])
    var w4 = UInt16(block[6]) << 8 | UInt16(block[7])
    for round in 1...32 {
      let counter = UInt16(round)
      if (round - 1) / 8 % 2 == 0 {
        // Rule A.
        let g = permutation(w1, round)
        (w1, w2, w3, w4) = (g ^ w4 ^ counter, g, w2, w3)
      } else {
        // Rule B.
        let g = permutation(w1, round)
        (w1, w2, w3, w4) = (w4, g, w1 ^ w2 ^ counter, w3)
      }
    }
    block[0] = UInt8(w1 >> 8)
    block[1] = UInt8(w1 & 0xFF)
    block[2] = UInt8(w2 >> 8)
    block[3] = UInt8(w2 & 0xFF)
    block[4] = UInt8(w3 >> 8)
    block[5] = UInt8(w3 & 0xFF)
    block[6] = UInt8(w4 >> 8)
    block[7] = UInt8(w4 & 0xFF)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var w1 = UInt16(block[0]) << 8 | UInt16(block[1])
    var w2 = UInt16(block[2]) << 8 | UInt16(block[3])
    var w3 = UInt16(block[4]) << 8 | UInt16(block[5])
    var w4 = UInt16(block[6]) << 8 | UInt16(block[7])
    for round in (1...32).reversed() {
      let counter = UInt16(round)
      if (round - 1) / 8 % 2 == 0 {
        // Undo rule A.
        let previous1 = inversePermutation(w2, round)
        (w1, w2, w3, w4) = (previous1, w3, w4, w1 ^ w2 ^ counter)
      } else {
        // Undo rule B.
        let previous1 = inversePermutation(w2, round)
        (w1, w2, w3, w4) = (previous1, w3 ^ previous1 ^ counter, w4, w1)
      }
    }
    block[0] = UInt8(w1 >> 8)
    block[1] = UInt8(w1 & 0xFF)
    block[2] = UInt8(w2 >> 8)
    block[3] = UInt8(w2 & 0xFF)
    block[4] = UInt8(w3 >> 8)
    block[5] = UInt8(w3 & 0xFF)
    block[6] = UInt8(w4 >> 8)
    block[7] = UInt8(w4 & 0xFF)
  }

  /// The four-round Feistel permutation G of round `round` (1 to 32).
  private func permutation(_ word: UInt16, _ round: Int) -> UInt16 {
    let f = SkipjackCore.table
    let g1 = UInt8(word >> 8)
    let g2 = UInt8(word & 0xFF)
    let base = 4 * (round - 1)
    let g3 = f[Int(g2 ^ key[base % 10])] ^ g1
    let g4 = f[Int(g3 ^ key[(base + 1) % 10])] ^ g2
    let g5 = f[Int(g4 ^ key[(base + 2) % 10])] ^ g3
    let g6 = f[Int(g5 ^ key[(base + 3) % 10])] ^ g4
    return UInt16(g5) << 8 | UInt16(g6)
  }

  private func inversePermutation(_ word: UInt16, _ round: Int) -> UInt16 {
    let f = SkipjackCore.table
    let g5 = UInt8(word >> 8)
    let g6 = UInt8(word & 0xFF)
    let base = 4 * (round - 1)
    let g4 = f[Int(g5 ^ key[(base + 3) % 10])] ^ g6
    let g3 = f[Int(g4 ^ key[(base + 2) % 10])] ^ g5
    let g2 = f[Int(g3 ^ key[(base + 1) % 10])] ^ g4
    let g1 = f[Int(g2 ^ key[base % 10])] ^ g3
    return UInt16(g1) << 8 | UInt16(g2)
  }
}

/// GOST 28147-89 (Magma's predecessor), 64-bit block, 256-bit key, with the S-box set
/// id-tc26-gost-28147-param-Z of RFC 7836.
final class GOST28147Core: BlockCore {
  let blockSize = 8

  private let key: [UInt32]

  /// Eight rows of 16 entries; row i substitutes the i-th nibble (least significant first).
  private static let sboxes = CipherTables.nibbles(CipherTables.gostParamZ)

  /// Returns `nil` unless the key is 32 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 32 else { return nil }
    self.key = words32(key, bigEndian: false)
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block) { round in round < 24 ? round % 8 : 7 - round % 8 }
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block) { round in round < 8 ? round : 7 - round % 8 }
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, keyIndex: (Int) -> Int) {
    var n1 = loadLittleEndian32(block)
    var n2 = loadLittleEndian32(block + 4)
    for round in 0..<32 {
      let mixed = n2 ^ roundFunction(n1, key[keyIndex(round)])
      if round < 31 {
        n2 = n1
        n1 = mixed
      } else {
        n2 = mixed
      }
    }
    storeLittleEndian32(n1, block)
    storeLittleEndian32(n2, block + 4)
  }

  private func roundFunction(_ value: UInt32, _ subkey: UInt32) -> UInt32 {
    let sum = value &+ subkey
    var result: UInt32 = 0
    for nibble in 0..<8 {
      let input = Int((sum >> UInt32(4 * nibble)) & 0xF)
      result |= UInt32(GOST28147Core.sboxes[nibble * 16 + input]) << UInt32(4 * nibble)
    }
    return rotateLeft(result, 11)
  }
}
