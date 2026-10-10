import Foundation

/// CAST-256 (RFC 2612), 128-bit block, 128 to 256-bit key. Its S-boxes are the first four of CAST-128.
final class CAST256Core: BlockCore {
  let blockSize = 16

  private var rotations = [UInt32](repeating: 0, count: 48)
  private var masks = [UInt32](repeating: 0, count: 48)

  private static let s1 = CipherTables.words(CipherTables.cast1)
  private static let s2 = CipherTables.words(CipherTables.cast2)
  private static let s3 = CipherTables.words(CipherTables.cast3)
  private static let s4 = CipherTables.words(CipherTables.cast4)

  /// Returns `nil` unless the key is 16, 20, 24, 28 or 32 bytes long.
  init?(key: [UInt8]) {
    guard [16, 20, 24, 28, 32].contains(key.count) else { return nil }
    var padded = key
    while padded.count < 32 { padded.append(0) }
    var kappa = words32(padded, bigEndian: true)

    var masksTable = [[UInt32]](repeating: [UInt32](repeating: 0, count: 8), count: 24)
    var rotationsTable = [[UInt32]](repeating: [UInt32](repeating: 0, count: 8), count: 24)
    var cm: UInt32 = 0x5A82_7999
    let mm: UInt32 = 0x6ED9_EBA1
    var cr: UInt32 = 19
    let mr: UInt32 = 17
    for row in 0..<24 {
      for column in 0..<8 {
        masksTable[row][column] = cm
        cm = cm &+ mm
        rotationsTable[row][column] = cr
        cr = (cr + mr) & 31
      }
    }

    func forward(_ row: Int) {
      let m = masksTable[row]
      let r = rotationsTable[row]
      kappa[6] ^= CAST256Core.f1(kappa[7], m[0], r[0])
      kappa[5] ^= CAST256Core.f2(kappa[6], m[1], r[1])
      kappa[4] ^= CAST256Core.f3(kappa[5], m[2], r[2])
      kappa[3] ^= CAST256Core.f1(kappa[4], m[3], r[3])
      kappa[2] ^= CAST256Core.f2(kappa[3], m[4], r[4])
      kappa[1] ^= CAST256Core.f3(kappa[2], m[5], r[5])
      kappa[0] ^= CAST256Core.f1(kappa[1], m[6], r[6])
      kappa[7] ^= CAST256Core.f2(kappa[0], m[7], r[7])
    }

    for round in 0..<12 {
      forward(2 * round)
      forward(2 * round + 1)
      rotations[round * 4] = kappa[0] & 31
      rotations[round * 4 + 1] = kappa[2] & 31
      rotations[round * 4 + 2] = kappa[4] & 31
      rotations[round * 4 + 3] = kappa[6] & 31
      masks[round * 4] = kappa[7]
      masks[round * 4 + 1] = kappa[5]
      masks[round * 4 + 2] = kappa[3]
      masks[round * 4 + 3] = kappa[1]
    }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var b = [
      loadBigEndian32(block), loadBigEndian32(block + 4), loadBigEndian32(block + 8),
      loadBigEndian32(block + 12),
    ]
    for round in 0..<6 { quad(&b, round) }
    for round in 6..<12 { quadInverse(&b, round) }
    for index in 0..<4 { storeBigEndian32(b[index], block + 4 * index) }
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var b = [
      loadBigEndian32(block), loadBigEndian32(block + 4), loadBigEndian32(block + 8),
      loadBigEndian32(block + 12),
    ]
    for round in (6..<12).reversed() { quad(&b, round) }
    for round in (0..<6).reversed() { quadInverse(&b, round) }
    for index in 0..<4 { storeBigEndian32(b[index], block + 4 * index) }
  }

  private func quad(_ b: inout [UInt32], _ round: Int) {
    let base = round * 4
    b[2] ^= CAST256Core.f1(b[3], masks[base], rotations[base])
    b[1] ^= CAST256Core.f2(b[2], masks[base + 1], rotations[base + 1])
    b[0] ^= CAST256Core.f3(b[1], masks[base + 2], rotations[base + 2])
    b[3] ^= CAST256Core.f1(b[0], masks[base + 3], rotations[base + 3])
  }

  private func quadInverse(_ b: inout [UInt32], _ round: Int) {
    let base = round * 4
    b[3] ^= CAST256Core.f1(b[0], masks[base + 3], rotations[base + 3])
    b[0] ^= CAST256Core.f3(b[1], masks[base + 2], rotations[base + 2])
    b[1] ^= CAST256Core.f2(b[2], masks[base + 1], rotations[base + 1])
    b[2] ^= CAST256Core.f1(b[3], masks[base], rotations[base])
  }

  // MARK: Round functions

  @inline(__always)
  private static func f1(_ data: UInt32, _ mask: UInt32, _ rotation: UInt32) -> UInt32 {
    let i = rotateLeft(mask &+ data, rotation)
    let a = s1[Int(i >> 24)] ^ s2[Int((i >> 16) & 0xFF)]
    return (a &- s3[Int((i >> 8) & 0xFF)]) &+ s4[Int(i & 0xFF)]
  }

  @inline(__always)
  private static func f2(_ data: UInt32, _ mask: UInt32, _ rotation: UInt32) -> UInt32 {
    let i = rotateLeft(mask ^ data, rotation)
    let a = s1[Int(i >> 24)] &- s2[Int((i >> 16) & 0xFF)]
    return (a &+ s3[Int((i >> 8) & 0xFF)]) ^ s4[Int(i & 0xFF)]
  }

  @inline(__always)
  private static func f3(_ data: UInt32, _ mask: UInt32, _ rotation: UInt32) -> UInt32 {
    let i = rotateLeft(mask &- data, rotation)
    let a = s1[Int(i >> 24)] &+ s2[Int((i >> 16) & 0xFF)]
    return (a ^ s3[Int((i >> 8) & 0xFF)]) &- s4[Int(i & 0xFF)]
  }
}
