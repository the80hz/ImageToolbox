import Foundation

/// IDEA (Lai and Massey), 64-bit block, 128-bit key.
final class IDEACore: BlockCore {
  let blockSize = 8

  private var encryptionKeys = [UInt32](repeating: 0, count: 52)
  private var decryptionKeys = [UInt32](repeating: 0, count: 52)

  /// Returns `nil` unless the key is 16 bytes long.
  init?(key: [UInt8]) {
    guard key.count == 16 else { return nil }
    var high = key.withUnsafeBufferPointer { loadBigEndian64($0.baseAddress!) }
    var low = key.withUnsafeBufferPointer { loadBigEndian64($0.baseAddress! + 8) }
    var index = 0
    while index < 52 {
      let words = [high >> 48, high >> 32, high >> 16, high, low >> 48, low >> 32, low >> 16, low]
      for word in words where index < 52 {
        encryptionKeys[index] = UInt32(word & 0xFFFF)
        index += 1
      }
      // Rotate the 128-bit key left by 25 bits.
      let newHigh = high << 25 | low >> 39
      let newLow = low << 25 | high >> 39
      high = newHigh
      low = newLow
    }
    for group in 0..<9 {
      let source = 6 * (8 - group)
      let target = 6 * group
      decryptionKeys[target] = IDEACore.inverse(encryptionKeys[source])
      decryptionKeys[target + 3] = IDEACore.inverse(encryptionKeys[source + 3])
      if group == 0 || group == 8 {
        decryptionKeys[target + 1] = (0x10000 &- encryptionKeys[source + 1]) & 0xFFFF
        decryptionKeys[target + 2] = (0x10000 &- encryptionKeys[source + 2]) & 0xFFFF
      } else {
        decryptionKeys[target + 1] = (0x10000 &- encryptionKeys[source + 2]) & 0xFFFF
        decryptionKeys[target + 2] = (0x10000 &- encryptionKeys[source + 1]) & 0xFFFF
      }
      if group < 8 {
        decryptionKeys[target + 4] = encryptionKeys[source - 2]
        decryptionKeys[target + 5] = encryptionKeys[source - 1]
      }
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, keys: encryptionKeys)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    crypt(block, keys: decryptionKeys)
  }

  private func crypt(_ block: UnsafeMutablePointer<UInt8>, keys: [UInt32]) {
    var x1 = UInt32(block[0]) << 8 | UInt32(block[1])
    var x2 = UInt32(block[2]) << 8 | UInt32(block[3])
    var x3 = UInt32(block[4]) << 8 | UInt32(block[5])
    var x4 = UInt32(block[6]) << 8 | UInt32(block[7])
    for round in 0..<8 {
      let k = round * 6
      let a = IDEACore.multiply(x1, keys[k])
      let b = (x2 &+ keys[k + 1]) & 0xFFFF
      let c = (x3 &+ keys[k + 2]) & 0xFFFF
      let d = IDEACore.multiply(x4, keys[k + 3])
      let t = IDEACore.multiply(a ^ c, keys[k + 4])
      let u = IDEACore.multiply((t &+ (b ^ d)) & 0xFFFF, keys[k + 5])
      let v = (t &+ u) & 0xFFFF
      x1 = a ^ u
      x2 = c ^ u
      x3 = b ^ v
      x4 = d ^ v
    }
    let y1 = IDEACore.multiply(x1, keys[48])
    let y2 = (x3 &+ keys[49]) & 0xFFFF
    let y3 = (x2 &+ keys[50]) & 0xFFFF
    let y4 = IDEACore.multiply(x4, keys[51])
    for (index, value) in [y1, y2, y3, y4].enumerated() {
      block[2 * index] = UInt8(value >> 8)
      block[2 * index + 1] = UInt8(value & 0xFF)
    }
  }

  /// Multiplication modulo 65537, where 0 stands for 65536.
  private static func multiply(_ a: UInt32, _ b: UInt32) -> UInt32 {
    let x = UInt64(a == 0 ? 0x10000 : a)
    let y = UInt64(b == 0 ? 0x10000 : b)
    return UInt32((x * y) % 0x10001) & 0xFFFF
  }

  /// The multiplicative inverse modulo 65537 (0 stands for 65536 and is its own inverse).
  private static func inverse(_ value: UInt32) -> UInt32 {
    guard value > 1 else { return value }
    var result: UInt32 = 1
    var base = value
    var exponent: UInt32 = 0x10001 - 2
    while exponent > 0 {
      if exponent & 1 == 1 { result = multiply(result, base) }
      base = multiply(base, base)
      exponent >>= 1
    }
    return result
  }
}
