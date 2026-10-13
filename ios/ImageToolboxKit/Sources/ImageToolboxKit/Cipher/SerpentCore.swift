import Foundation

/// Serpent (Anderson, Biham and Knudsen, AES finalist), 128-bit block, 128, 192 or 256-bit key.
///
/// This is the bitslice form: the block is four little-endian words, and an S-box acts on one bit of
/// each word at a time. Each S-box is evaluated as a truth table over the 16 minterms of its four
/// input words, so the code needs no data-dependent branch or table lookup.
final class SerpentCore: BlockCore {
  let blockSize = 16

  private var subkeys = [UInt32](repeating: 0, count: 132)

  /// The eight S-boxes, as given in the Serpent specification.
  private static let boxes: [[UInt8]] = [
    [3, 8, 15, 1, 10, 6, 5, 11, 14, 13, 4, 2, 7, 0, 9, 12],
    [15, 12, 2, 7, 9, 0, 5, 10, 1, 11, 14, 8, 6, 13, 3, 4],
    [8, 6, 7, 9, 3, 12, 10, 15, 13, 1, 14, 4, 0, 11, 5, 2],
    [0, 15, 11, 8, 12, 9, 6, 3, 13, 1, 2, 4, 10, 7, 5, 14],
    [1, 15, 8, 3, 12, 0, 11, 6, 2, 5, 4, 10, 9, 14, 7, 13],
    [15, 5, 2, 11, 4, 10, 9, 12, 0, 3, 14, 8, 13, 6, 7, 1],
    [7, 2, 12, 5, 8, 4, 6, 11, 14, 9, 1, 15, 13, 3, 10, 0],
    [1, 13, 15, 0, 14, 8, 2, 11, 7, 4, 12, 10, 9, 3, 5, 6],
  ]

  /// For every S-box and its inverse, four masks: bit k of mask j says that output bit j is set for
  /// the input nibble k. Entries 0...7 are the S-boxes, 8...15 their inverses; the masks of table t
  /// are at 4 * t ..< 4 * t + 4.
  private static let masks: [UInt16] = {
    var result: [UInt16] = []
    for table in boxes + boxes.map(invert) {
      var outputs = [UInt16](repeating: 0, count: 4)
      for input in 0..<16 {
        for bit in 0..<4 where (table[input] >> UInt8(bit)) & 1 == 1 {
          outputs[bit] |= UInt16(1) << UInt16(input)
        }
      }
      result.append(contentsOf: outputs)
    }
    return result
  }()

  private static func invert(_ table: [UInt8]) -> [UInt8] {
    var inverse = [UInt8](repeating: 0, count: 16)
    for (index, value) in table.enumerated() { inverse[Int(value)] = UInt8(index) }
    return inverse
  }

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 24, 32].contains(key.count) else { return nil }
    var padded = key
    if padded.count < 32 {
      padded.append(1)
      while padded.count < 32 { padded.append(0) }
    }
    var words = words32(padded, bigEndian: false)
    words.reserveCapacity(140)
    for index in 8..<140 {
      let mixed = words[index - 8] ^ words[index - 5] ^ words[index - 3] ^ words[index - 1]
      let value = mixed ^ 0x9E37_79B9 ^ UInt32(index - 8)
      words.append(rotateLeft(value, 11))
    }
    for round in 0...32 {
      let boxIndex = ((3 - round) % 8 + 8) % 8
      let result = SerpentCore.substitute(
        boxIndex, words[8 + round * 4], words[9 + round * 4], words[10 + round * 4],
        words[11 + round * 4])
      subkeys[round * 4] = result.0
      subkeys[round * 4 + 1] = result.1
      subkeys[round * 4 + 2] = result.2
      subkeys[round * 4 + 3] = result.3
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var x0 = loadLittleEndian32(block)
    var x1 = loadLittleEndian32(block + 4)
    var x2 = loadLittleEndian32(block + 8)
    var x3 = loadLittleEndian32(block + 12)
    for round in 0..<32 {
      x0 ^= subkeys[round * 4]
      x1 ^= subkeys[round * 4 + 1]
      x2 ^= subkeys[round * 4 + 2]
      x3 ^= subkeys[round * 4 + 3]
      (x0, x1, x2, x3) = SerpentCore.substitute(round % 8, x0, x1, x2, x3)
      if round < 31 {
        x0 = rotateLeft(x0, 13)
        x2 = rotateLeft(x2, 3)
        x1 ^= x0 ^ x2
        x3 ^= x2 ^ (x0 << 3)
        x1 = rotateLeft(x1, 1)
        x3 = rotateLeft(x3, 7)
        x0 ^= x1 ^ x3
        x2 ^= x3 ^ (x1 << 7)
        x0 = rotateLeft(x0, 5)
        x2 = rotateLeft(x2, 22)
      }
    }
    x0 ^= subkeys[128]
    x1 ^= subkeys[129]
    x2 ^= subkeys[130]
    x3 ^= subkeys[131]
    storeLittleEndian32(x0, block)
    storeLittleEndian32(x1, block + 4)
    storeLittleEndian32(x2, block + 8)
    storeLittleEndian32(x3, block + 12)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var x0 = loadLittleEndian32(block) ^ subkeys[128]
    var x1 = loadLittleEndian32(block + 4) ^ subkeys[129]
    var x2 = loadLittleEndian32(block + 8) ^ subkeys[130]
    var x3 = loadLittleEndian32(block + 12) ^ subkeys[131]
    for round in (0..<32).reversed() {
      if round < 31 {
        x2 = rotateRight(x2, 22)
        x0 = rotateRight(x0, 5)
        x2 ^= x3 ^ (x1 << 7)
        x0 ^= x1 ^ x3
        x3 = rotateRight(x3, 7)
        x1 = rotateRight(x1, 1)
        x3 ^= x2 ^ (x0 << 3)
        x1 ^= x0 ^ x2
        x2 = rotateRight(x2, 3)
        x0 = rotateRight(x0, 13)
      }
      (x0, x1, x2, x3) = SerpentCore.substitute(8 + round % 8, x0, x1, x2, x3)
      x0 ^= subkeys[round * 4]
      x1 ^= subkeys[round * 4 + 1]
      x2 ^= subkeys[round * 4 + 2]
      x3 ^= subkeys[round * 4 + 3]
    }
    storeLittleEndian32(x0, block)
    storeLittleEndian32(x1, block + 4)
    storeLittleEndian32(x2, block + 8)
    storeLittleEndian32(x3, block + 12)
  }

  /// Applies S-box `index` (8 and up: its inverse) to all 32 bit positions at once.
  private static func substitute(
    _ index: Int, _ x0: UInt32, _ x1: UInt32, _ x2: UInt32, _ x3: UInt32
  ) -> (UInt32, UInt32, UInt32, UInt32) {
    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 8) { terms in
      terms[0] = ~x0 & ~x1
      terms[1] = x0 & ~x1
      terms[2] = ~x0 & x1
      terms[3] = x0 & x1
      terms[4] = ~x2 & ~x3
      terms[5] = x2 & ~x3
      terms[6] = ~x2 & x3
      terms[7] = x2 & x3
      var y0: UInt32 = 0
      var y1: UInt32 = 0
      var y2: UInt32 = 0
      var y3: UInt32 = 0
      let base = index * 4
      let mask0 = masks[base]
      let mask1 = masks[base + 1]
      let mask2 = masks[base + 2]
      let mask3 = masks[base + 3]
      for nibble in 0..<16 {
        let minterm = terms[nibble & 3] & terms[4 + nibble >> 2]
        let shift = UInt16(nibble)
        y0 |= minterm & (0 &- UInt32((mask0 >> shift) & 1))
        y1 |= minterm & (0 &- UInt32((mask1 >> shift) & 1))
        y2 |= minterm & (0 &- UInt32((mask2 >> shift) & 1))
        y3 |= minterm & (0 &- UInt32((mask3 >> shift) & 1))
      }
      return (y0, y1, y2, y3)
    }
  }
}
