import Foundation

/// Threefish (Ferguson et al., the tweakable block cipher of Skein 1.3) with 256, 512 or 1024-bit
/// blocks. The key is 32, 64 or 128 bytes, and the tweak is two 64-bit words. Words are
/// little-endian. The file cipher always uses an all-zero tweak.
///
/// The round counts (Table 2), the word permutations (Table 3) and the rotation constants (Table 4)
/// are those of the Skein 1.3 specification. Threefish-256 uses the same rules with four words.
final class ThreefishCore: BlockCore {
  let blockSize: Int

  private let wordCount: Int
  private let rounds: Int
  /// Output word `i` of a round is input word `permutation[i]` of the MIX functions.
  private let permutation: [Int]
  /// `rotations[round % 8][j]` is the rotation of MIX function `j`.
  private let rotations: [[UInt64]]
  /// The subkeys s = 0 ... rounds / 4, each `wordCount` words, stored one after another.
  private let subkeys: [UInt64]

  /// Returns `nil` unless the key is 32, 64 or 128 bytes long.
  init?(key: [UInt8], tweak: (UInt64, UInt64) = (0, 0)) {
    let words: Int
    switch key.count {
    case 32: words = 4
    case 64: words = 8
    case 128: words = 16
    default: return nil
    }
    let parameters = ThreefishCore.parameters(words: words)
    wordCount = words
    blockSize = words * 8
    rounds = parameters.rounds
    permutation = parameters.permutation
    rotations = parameters.rotations

    var keyWords = [UInt64](repeating: 0, count: words + 1)
    key.withUnsafeBufferPointer { storage in
      let base = storage.baseAddress!
      var parity: UInt64 = 0x1BD1_1BDA_A9FC_1A22
      for index in 0..<words {
        keyWords[index] = loadLittleEndian64(base + 8 * index)
        parity ^= keyWords[index]
      }
      keyWords[words] = parity
    }
    let tweakWords = [tweak.0, tweak.1, tweak.0 ^ tweak.1]

    var schedule = [UInt64](repeating: 0, count: (parameters.rounds / 4 + 1) * words)
    for subkey in 0...(parameters.rounds / 4) {
      for word in 0..<words {
        var value = keyWords[(subkey + word) % (words + 1)]
        if word == words - 3 { value = value &+ tweakWords[subkey % 3] }
        if word == words - 2 { value = value &+ tweakWords[(subkey + 1) % 3] }
        if word == words - 1 { value = value &+ UInt64(subkey) }
        schedule[subkey * words + word] = value
      }
    }
    subkeys = schedule
  }

  private static func parameters(words: Int) -> (
    rounds: Int, permutation: [Int], rotations: [[UInt64]]
  ) {
    switch words {
    case 4:
      (
        72, [0, 3, 2, 1],
        [
          [14, 16], [52, 57], [23, 40], [5, 37], [25, 33], [46, 12], [58, 22], [32, 32],
        ]
      )
    case 8:
      (
        72, [2, 1, 4, 7, 6, 5, 0, 3],
        [
          [46, 36, 19, 37], [33, 27, 14, 42], [17, 49, 36, 39], [44, 9, 54, 56],
          [39, 30, 34, 24], [13, 50, 10, 17], [25, 29, 39, 43], [8, 35, 56, 22],
        ]
      )
    default:
      (
        80, [0, 9, 2, 13, 6, 11, 4, 15, 10, 7, 12, 3, 14, 5, 8, 1],
        [
          [24, 13, 8, 47, 8, 17, 22, 37], [38, 19, 10, 55, 49, 18, 23, 52],
          [33, 4, 51, 13, 34, 41, 59, 17], [5, 20, 48, 41, 47, 28, 16, 25],
          [41, 9, 37, 31, 12, 47, 44, 30], [16, 34, 56, 51, 4, 53, 42, 41],
          [31, 44, 47, 46, 19, 42, 44, 25], [9, 48, 35, 52, 23, 31, 37, 20],
        ]
      )
    }
  }

  @inline(__always)
  private func subkey(_ index: Int, _ word: Int) -> UInt64 {
    subkeys[index * wordCount + word]
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v = (0..<wordCount).map { loadLittleEndian64(block + 8 * $0) }
    for round in 0..<rounds {
      if round % 4 == 0 {
        for word in 0..<wordCount { v[word] = v[word] &+ subkey(round / 4, word) }
      }
      let angles = rotations[round % 8]
      for pair in 0..<(wordCount / 2) {
        let sum = v[2 * pair] &+ v[2 * pair + 1]
        v[2 * pair] = sum
        v[2 * pair + 1] = rotateLeft(v[2 * pair + 1], angles[pair]) ^ sum
      }
      v = permutation.map { v[$0] }
    }
    for word in 0..<wordCount { v[word] = v[word] &+ subkey(rounds / 4, word) }
    for word in 0..<wordCount { storeLittleEndian64(v[word], block + 8 * word) }
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var v = (0..<wordCount).map { loadLittleEndian64(block + 8 * $0) }
    for word in 0..<wordCount { v[word] = v[word] &- subkey(rounds / 4, word) }
    for round in (0..<rounds).reversed() {
      var unpermuted = v
      for word in 0..<wordCount { unpermuted[permutation[word]] = v[word] }
      v = unpermuted
      let angles = rotations[round % 8]
      for pair in 0..<(wordCount / 2) {
        let difference = rotateRight(v[2 * pair + 1] ^ v[2 * pair], angles[pair])
        v[2 * pair + 1] = difference
        v[2 * pair] = v[2 * pair] &- difference
      }
      if round % 4 == 0 {
        for word in 0..<wordCount { v[word] = v[word] &- subkey(round / 4, word) }
      }
    }
    for word in 0..<wordCount { storeLittleEndian64(v[word], block + 8 * word) }
  }
}
