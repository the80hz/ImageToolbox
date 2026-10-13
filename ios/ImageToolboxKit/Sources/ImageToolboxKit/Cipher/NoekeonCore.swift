import Foundation

/// Noekeon (Daemen, Peeters, Van Assche and Rijmen, NESSIE), 128-bit block, 128-bit key, used in
/// the direct-key mode.
final class NoekeonCore: BlockCore {
  let blockSize = 16

  private let encryptionKey: [UInt32]
  private let decryptionKey: [UInt32]

  private static let constants: [UInt32] = {
    var value: UInt32 = 0x80
    var result: [UInt32] = []
    for _ in 0...16 {
      result.append(value)
      value <<= 1
      if value & 0x100 != 0 { value ^= 0x11B }
    }
    return result
  }()

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    let words = words32(key, bigEndian: true)
    encryptionKey = words
    var transformed = words
    NoekeonCore.theta([0, 0, 0, 0], &transformed)
    decryptionKey = transformed
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var state = (0..<4).map { loadBigEndian32(block + 4 * $0) }
    for round in 0..<16 {
      state[0] ^= NoekeonCore.constants[round]
      NoekeonCore.theta(encryptionKey, &state)
      NoekeonCore.permute(&state)
    }
    state[0] ^= NoekeonCore.constants[16]
    NoekeonCore.theta(encryptionKey, &state)
    for index in 0..<4 { storeBigEndian32(state[index], block + 4 * index) }
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var state = (0..<4).map { loadBigEndian32(block + 4 * $0) }
    NoekeonCore.theta(decryptionKey, &state)
    state[0] ^= NoekeonCore.constants[16]
    for round in (0..<16).reversed() {
      NoekeonCore.permute(&state)
      NoekeonCore.theta(decryptionKey, &state)
      state[0] ^= NoekeonCore.constants[round]
    }
    for index in 0..<4 { storeBigEndian32(state[index], block + 4 * index) }
  }

  // MARK: Round pieces

  private static func theta(_ key: [UInt32], _ a: inout [UInt32]) {
    var temp = a[0] ^ a[2]
    temp ^= rotateLeft(temp, 8) ^ rotateLeft(temp, 24)
    a[1] ^= temp
    a[3] ^= temp
    for index in 0..<4 { a[index] ^= key[index] }
    temp = a[1] ^ a[3]
    temp ^= rotateLeft(temp, 8) ^ rotateLeft(temp, 24)
    a[0] ^= temp
    a[2] ^= temp
  }

  /// Pi1, Gamma and Pi2. The sequence is its own inverse, because Pi2 undoes Pi1 and Gamma is an
  /// involution.
  private static func permute(_ a: inout [UInt32]) {
    a[1] = rotateLeft(a[1], 1)
    a[2] = rotateLeft(a[2], 5)
    a[3] = rotateLeft(a[3], 2)
    gamma(&a)
    a[1] = rotateRight(a[1], 1)
    a[2] = rotateRight(a[2], 5)
    a[3] = rotateRight(a[3], 2)
  }

  private static func gamma(_ a: inout [UInt32]) {
    a[1] ^= ~a[3] & ~a[2]
    a[0] ^= a[2] & a[1]
    let temp = a[3]
    a[3] = a[0]
    a[0] = temp
    a[2] ^= a[0] ^ a[1] ^ a[3]
    a[1] ^= ~a[3] & ~a[2]
    a[0] ^= a[2] & a[1]
  }
}
