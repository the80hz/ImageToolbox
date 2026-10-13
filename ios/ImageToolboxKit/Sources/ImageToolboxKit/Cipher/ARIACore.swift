import Foundation

/// ARIA (RFC 5794), 128-bit block, 128, 192 or 256-bit key.
final class ARIACore: BlockCore {
  let blockSize = 16

  private let rounds: Int
  private let encryptionKeys: [UInt8]
  private let decryptionKeys: [UInt8]
  private let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)

  private static let s1 = CipherTables.bytes(CipherTables.ariaS1)
  private static let s2 = CipherTables.bytes(CipherTables.ariaS2)
  private static let x1 = invert(s1)
  private static let x2 = invert(s2)

  /// The three key schedule constants, from the digits of pi.
  private static let constants: [[UInt8]] = [
    CipherTables.bytes("517cc1b727220a94fe13abe8fa9a6ee0"),
    CipherTables.bytes("6db14acc9e21c820ff28b1d5ef5de2b0"),
    CipherTables.bytes("db92371d2126e9700324977504e8c90e"),
  ]

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 24, 32].contains(key.count) else { return nil }
    rounds = 12 + (key.count - 16) / 4
    var padded = key
    while padded.count < 32 { padded.append(0) }
    let keyLeft = Array(padded[0..<16])
    let keyRight = Array(padded[16..<32])
    let order: [Int]
    switch key.count {
    case 16: order = [0, 1, 2]
    case 24: order = [1, 2, 0]
    default: order = [2, 0, 1]
    }
    let c = order.map { ARIACore.constants[$0] }
    let w0 = keyLeft
    let w1 = ARIACore.xor(ARIACore.oddRound(w0, c[0]), keyRight)
    let w2 = ARIACore.xor(ARIACore.evenRound(w1, c[1]), w0)
    let w3 = ARIACore.xor(ARIACore.oddRound(w2, c[2]), w1)

    // The 17 encryption round keys (only the first rounds + 1 are used).
    func mix(_ a: [UInt8], _ b: [UInt8], rotateRightBy amount: Int) -> [UInt8] {
      ARIACore.xor(a, ARIACore.rotateRight128(b, amount))
    }
    var keys: [[UInt8]] = []
    keys.append(mix(w0, w1, rotateRightBy: 19))
    keys.append(mix(w1, w2, rotateRightBy: 19))
    keys.append(mix(w2, w3, rotateRightBy: 19))
    keys.append(mix(w3, w0, rotateRightBy: 19))  // (w0 >>> 19) ^ w3
    keys.append(mix(w0, w1, rotateRightBy: 31))
    keys.append(mix(w1, w2, rotateRightBy: 31))
    keys.append(mix(w2, w3, rotateRightBy: 31))
    keys.append(mix(w3, w0, rotateRightBy: 31))  // (w0 >>> 31) ^ w3
    keys.append(mix(w0, w1, rotateRightBy: 67))  // w1 <<< 61
    keys.append(mix(w1, w2, rotateRightBy: 67))
    keys.append(mix(w2, w3, rotateRightBy: 67))
    keys.append(mix(w3, w0, rotateRightBy: 67))  // (w0 <<< 61) ^ w3
    keys.append(mix(w0, w1, rotateRightBy: 97))  // w1 <<< 31
    keys.append(mix(w1, w2, rotateRightBy: 97))
    keys.append(mix(w2, w3, rotateRightBy: 97))
    keys.append(mix(w3, w0, rotateRightBy: 97))  // (w0 <<< 31) ^ w3
    keys.append(mix(w0, w1, rotateRightBy: 109))  // w1 <<< 19

    let count = rounds + 1
    encryptionKeys = keys[0..<count].flatMap { $0 }
    var decryption: [[UInt8]] = [keys[rounds]]
    for index in 1..<rounds { decryption.append(ARIACore.diffuse(keys[rounds - index])) }
    decryption.append(keys[0])
    decryptionKeys = decryption.flatMap { $0 }
  }

  deinit { scratch.deallocate() }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, keys: encryptionKeys)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, keys: decryptionKeys)
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, keys: [UInt8]) {
    keys.withUnsafeBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      for round in 1..<rounds {
        for index in 0..<16 { block[index] ^= base[(round - 1) * 16 + index] }
        if round % 2 == 1 {
          ARIACore.substituteOdd(block)
        } else {
          ARIACore.substituteEven(block)
        }
        ARIACore.diffuse(block, into: scratch)
        for index in 0..<16 { block[index] = scratch[index] }
      }
      for index in 0..<16 { block[index] ^= base[(rounds - 1) * 16 + index] }
      ARIACore.substituteEven(block)
      for index in 0..<16 { block[index] ^= base[rounds * 16 + index] }
    }
  }

  // MARK: Building blocks

  private static func invert(_ table: [UInt8]) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: 256)
    for (index, value) in table.enumerated() { result[Int(value)] = UInt8(index) }
    return result
  }

  private static func xor(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    zip(a, b).map { $0 ^ $1 }
  }

  /// Rotates the 128-bit string right by `amount` bits (0 < amount < 128).
  private static func rotateRight128(_ bytes: [UInt8], _ amount: Int) -> [UInt8] {
    var high = bytes.withUnsafeBufferPointer { loadBigEndian64($0.baseAddress!) }
    var low = bytes.withUnsafeBufferPointer { loadBigEndian64($0.baseAddress! + 8) }
    var shift = amount % 128
    if shift >= 64 {
      swap(&high, &low)
      shift -= 64
    }
    if shift > 0 {
      let newHigh = high >> UInt64(shift) | low << UInt64(64 - shift)
      let newLow = low >> UInt64(shift) | high << UInt64(64 - shift)
      high = newHigh
      low = newLow
    }
    var result = [UInt8](repeating: 0, count: 16)
    result.withUnsafeMutableBufferPointer { storage in
      storeBigEndian64(high, storage.baseAddress!)
      storeBigEndian64(low, storage.baseAddress! + 8)
    }
    return result
  }

  private static func substituteOdd(_ block: UnsafeMutablePointer<UInt8>) {
    for index in stride(from: 0, to: 16, by: 4) {
      block[index] = s1[Int(block[index])]
      block[index + 1] = s2[Int(block[index + 1])]
      block[index + 2] = x1[Int(block[index + 2])]
      block[index + 3] = x2[Int(block[index + 3])]
    }
  }

  private static func substituteEven(_ block: UnsafeMutablePointer<UInt8>) {
    for index in stride(from: 0, to: 16, by: 4) {
      block[index] = x1[Int(block[index])]
      block[index + 1] = x2[Int(block[index + 1])]
      block[index + 2] = s1[Int(block[index + 2])]
      block[index + 3] = s2[Int(block[index + 3])]
    }
  }

  /// The diffusion layer A: a fixed 16 by 16 binary matrix.
  private static func diffuse(_ x: UnsafeMutablePointer<UInt8>, into y: UnsafeMutablePointer<UInt8>)
  {
    y[0] = x[3] ^ x[4] ^ x[6] ^ x[8] ^ x[9] ^ x[13] ^ x[14]
    y[1] = x[2] ^ x[5] ^ x[7] ^ x[8] ^ x[9] ^ x[12] ^ x[15]
    y[2] = x[1] ^ x[4] ^ x[6] ^ x[10] ^ x[11] ^ x[12] ^ x[15]
    y[3] = x[0] ^ x[5] ^ x[7] ^ x[10] ^ x[11] ^ x[13] ^ x[14]
    y[4] = x[0] ^ x[2] ^ x[5] ^ x[8] ^ x[11] ^ x[14] ^ x[15]
    y[5] = x[1] ^ x[3] ^ x[4] ^ x[9] ^ x[10] ^ x[14] ^ x[15]
    y[6] = x[0] ^ x[2] ^ x[7] ^ x[9] ^ x[10] ^ x[12] ^ x[13]
    y[7] = x[1] ^ x[3] ^ x[6] ^ x[8] ^ x[11] ^ x[12] ^ x[13]
    y[8] = x[0] ^ x[1] ^ x[4] ^ x[7] ^ x[10] ^ x[13] ^ x[15]
    y[9] = x[0] ^ x[1] ^ x[5] ^ x[6] ^ x[11] ^ x[12] ^ x[14]
    y[10] = x[2] ^ x[3] ^ x[5] ^ x[6] ^ x[8] ^ x[13] ^ x[15]
    y[11] = x[2] ^ x[3] ^ x[4] ^ x[7] ^ x[9] ^ x[12] ^ x[14]
    y[12] = x[1] ^ x[2] ^ x[6] ^ x[7] ^ x[9] ^ x[11] ^ x[12]
    y[13] = x[0] ^ x[3] ^ x[6] ^ x[7] ^ x[8] ^ x[10] ^ x[13]
    y[14] = x[0] ^ x[3] ^ x[4] ^ x[5] ^ x[9] ^ x[11] ^ x[14]
    y[15] = x[1] ^ x[2] ^ x[4] ^ x[5] ^ x[8] ^ x[10] ^ x[15]
  }

  private static func diffuse(_ bytes: [UInt8]) -> [UInt8] {
    var input = bytes
    var output = [UInt8](repeating: 0, count: 16)
    input.withUnsafeMutableBufferPointer { source in
      output.withUnsafeMutableBufferPointer { target in
        diffuse(source.baseAddress!, into: target.baseAddress!)
      }
    }
    return output
  }

  private static func oddRound(_ data: [UInt8], _ key: [UInt8]) -> [UInt8] {
    var state = xor(data, key)
    state.withUnsafeMutableBufferPointer { substituteOdd($0.baseAddress!) }
    return diffuse(state)
  }

  private static func evenRound(_ data: [UInt8], _ key: [UInt8]) -> [UInt8] {
    var state = xor(data, key)
    state.withUnsafeMutableBufferPointer { substituteEven($0.baseAddress!) }
    return diffuse(state)
  }
}
