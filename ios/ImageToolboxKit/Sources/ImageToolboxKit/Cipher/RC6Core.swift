import Foundation

/// RC6-32/20/b (Rivest et al., AES finalist), 128-bit block, key of 1 to 255 bytes.
final class RC6Core: BlockCore {
  let blockSize = 16

  private var schedule = [UInt32](repeating: 0, count: 44)

  /// Returns `nil` unless the key is 1 to 255 bytes long.
  init?(key: [UInt8]) {
    guard (1...255).contains(key.count) else { return nil }
    var words = words32(key, bigEndian: false)
    let count = words.count
    schedule[0] = 0xB7E1_5163
    for index in 1..<44 { schedule[index] = schedule[index - 1] &+ 0x9E37_79B9 }
    var a: UInt32 = 0
    var b: UInt32 = 0
    var i = 0
    var j = 0
    for _ in 0..<(3 * max(count, 44)) {
      a = rotateLeft(schedule[i] &+ a &+ b, 3)
      schedule[i] = a
      b = rotateLeft(words[j] &+ a &+ b, a &+ b)
      words[j] = b
      i = (i + 1) % 44
      j = (j + 1) % count
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadLittleEndian32(block)
    var b = loadLittleEndian32(block + 4) &+ schedule[0]
    var c = loadLittleEndian32(block + 8)
    var d = loadLittleEndian32(block + 12) &+ schedule[1]
    for round in 1...20 {
      let t = rotateLeft(b &* (2 &* b &+ 1), 5)
      let u = rotateLeft(d &* (2 &* d &+ 1), 5)
      a = rotateLeft(a ^ t, u) &+ schedule[2 * round]
      c = rotateLeft(c ^ u, t) &+ schedule[2 * round + 1]
      (a, b, c, d) = (b, c, d, a)
    }
    a = a &+ schedule[42]
    c = c &+ schedule[43]
    storeLittleEndian32(a, block)
    storeLittleEndian32(b, block + 4)
    storeLittleEndian32(c, block + 8)
    storeLittleEndian32(d, block + 12)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadLittleEndian32(block)
    var b = loadLittleEndian32(block + 4)
    var c = loadLittleEndian32(block + 8) &- schedule[43]
    var d = loadLittleEndian32(block + 12)
    a = a &- schedule[42]
    for round in (1...20).reversed() {
      (a, b, c, d) = (d, a, b, c)
      let u = rotateLeft(d &* (2 &* d &+ 1), 5)
      let t = rotateLeft(b &* (2 &* b &+ 1), 5)
      c = rotateRight(c &- schedule[2 * round + 1], t) ^ u
      a = rotateRight(a &- schedule[2 * round], u) ^ t
    }
    d = d &- schedule[1]
    b = b &- schedule[0]
    storeLittleEndian32(a, block)
    storeLittleEndian32(b, block + 4)
    storeLittleEndian32(c, block + 8)
    storeLittleEndian32(d, block + 12)
  }
}
