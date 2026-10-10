import Foundation

/// SM4 (GB/T 32907-2016), 128-bit block, 128-bit key.
final class SM4Core: BlockCore {
  let blockSize = 16

  private var roundKeys = [UInt32](repeating: 0, count: 32)

  private static let sbox = CipherTables.bytes(CipherTables.sm4SBox)
  private static let systemParameters: [UInt32] = [
    0xA3B1_BAC6, 0x56AA_3350, 0x677D_9197, 0xB270_22DC,
  ]
  /// The round constants: byte j of constant i is (4i + j) * 7 modulo 256.
  private static let constants: [UInt32] = (0..<32).map { index in
    var word: UInt32 = 0
    for offset in 0..<4 { word = word << 8 | UInt32(((4 * index + offset) * 7) & 0xFF) }
    return word
  }

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    let words = words32(key, bigEndian: true)
    var state = (0..<4).map { words[$0] ^ SM4Core.systemParameters[$0] }
    for round in 0..<32 {
      let input = state[1] ^ state[2] ^ state[3] ^ SM4Core.constants[round]
      let substituted = SM4Core.substitute(input)
      let mixed = substituted ^ rotateLeft(substituted, 13) ^ rotateLeft(substituted, 23)
      let next = state[0] ^ mixed
      roundKeys[round] = next
      state = [state[1], state[2], state[3], next]
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, reversed: false)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, reversed: true)
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, reversed: Bool) {
    var x0 = loadBigEndian32(block)
    var x1 = loadBigEndian32(block + 4)
    var x2 = loadBigEndian32(block + 8)
    var x3 = loadBigEndian32(block + 12)
    for round in 0..<32 {
      let key = roundKeys[reversed ? 31 - round : round]
      let substituted = SM4Core.substitute(x1 ^ x2 ^ x3 ^ key)
      var mixed = substituted ^ rotateLeft(substituted, 2) ^ rotateLeft(substituted, 10)
      mixed ^= rotateLeft(substituted, 18) ^ rotateLeft(substituted, 24)
      let next = x0 ^ mixed
      x0 = x1
      x1 = x2
      x2 = x3
      x3 = next
    }
    storeBigEndian32(x3, block)
    storeBigEndian32(x2, block + 4)
    storeBigEndian32(x1, block + 8)
    storeBigEndian32(x0, block + 12)
  }

  private static func substitute(_ word: UInt32) -> UInt32 {
    var result = UInt32(sbox[Int(word >> 24)])
    result = result << 8 | UInt32(sbox[Int((word >> 16) & 0xFF)])
    result = result << 8 | UInt32(sbox[Int((word >> 8) & 0xFF)])
    result = result << 8 | UInt32(sbox[Int(word & 0xFF)])
    return result
  }
}
