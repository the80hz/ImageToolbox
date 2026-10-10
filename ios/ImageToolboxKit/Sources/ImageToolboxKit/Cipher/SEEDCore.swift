import Foundation

/// SEED (RFC 4269), 128-bit block, 128-bit key.
final class SEEDCore: BlockCore {
  let blockSize = 16

  /// Two words for each of the 16 rounds.
  private var roundKeys = [UInt32](repeating: 0, count: 32)

  private static let tables = CipherTables.words(CipherTables.seedSS)
  private static let constants: [UInt32] = (0..<16).map { rotateLeft(0x9E37_79B9, UInt32($0)) }

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    let words = words32(key, bigEndian: true)
    var a = words[0]
    var b = words[1]
    var c = words[2]
    var d = words[3]
    for round in 0..<16 {
      roundKeys[round * 2] = SEEDCore.g(a &+ c &- SEEDCore.constants[round])
      roundKeys[round * 2 + 1] = SEEDCore.g(b &- d &+ SEEDCore.constants[round])
      if round % 2 == 0 {
        let high = a
        a = a >> 8 | b << 24
        b = b >> 8 | high << 24
      } else {
        let high = c
        c = c << 8 | d >> 24
        d = d << 8 | high >> 24
      }
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, reversed: false)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, reversed: true)
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, reversed: Bool) {
    var left0 = loadBigEndian32(block)
    var left1 = loadBigEndian32(block + 4)
    var right0 = loadBigEndian32(block + 8)
    var right1 = loadBigEndian32(block + 12)
    for round in 0..<16 {
      let index = reversed ? 15 - round : round
      var t0 = right0 ^ roundKeys[index * 2]
      var t1 = right1 ^ roundKeys[index * 2 + 1]
      t1 ^= t0
      t1 = SEEDCore.g(t1)
      t0 = t0 &+ t1
      t0 = SEEDCore.g(t0)
      t1 = t1 &+ t0
      t1 = SEEDCore.g(t1)
      t0 = t0 &+ t1
      let nextRight0 = left0 ^ t0
      let nextRight1 = left1 ^ t1
      left0 = right0
      left1 = right1
      right0 = nextRight0
      right1 = nextRight1
    }
    storeBigEndian32(right0, block)
    storeBigEndian32(right1, block + 4)
    storeBigEndian32(left0, block + 8)
    storeBigEndian32(left1, block + 12)
  }

  private static func g(_ word: UInt32) -> UInt32 {
    tables[Int(word & 0xFF)] ^ tables[256 + Int((word >> 8) & 0xFF)]
      ^ tables[512 + Int((word >> 16) & 0xFF)] ^ tables[768 + Int(word >> 24)]
  }
}
