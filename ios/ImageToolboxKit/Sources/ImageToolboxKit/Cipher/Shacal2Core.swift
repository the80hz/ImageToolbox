import Foundation

/// SHACAL-2 (Handschuh and Naccache, NESSIE): the SHA-256 compression function as a block cipher.
/// 256-bit block, key of 16 to 64 bytes (shorter keys are zero padded to 64 bytes).
final class Shacal2Core: BlockCore {
  let blockSize = 32

  private var schedule = [UInt32](repeating: 0, count: 64)

  private static let constants: [UInt32] = [
    0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4,
    0xAB1C_5ED5, 0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE,
    0x9BDC_06A7, 0xC19B_F174, 0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F,
    0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA, 0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7,
    0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967, 0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC,
    0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85, 0xA2BF_E8A1, 0xA81A_664B,
    0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070, 0x19A4_C116,
    0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
    0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7,
    0xC671_78F2,
  ]

  /// Returns `nil` unless the key is 16 to 64 bytes long.
  init?(key: [UInt8]) {
    guard (16...64).contains(key.count) else { return nil }
    var padded = key
    while padded.count < 64 { padded.append(0) }
    let words = words32(padded, bigEndian: true)
    for index in 0..<16 { schedule[index] = words[index] }
    for index in 16..<64 {
      let w15 = schedule[index - 15]
      let w2 = schedule[index - 2]
      let s0 = rotateRight(w15, 7) ^ rotateRight(w15, 18) ^ (w15 >> 3)
      let s1 = rotateRight(w2, 17) ^ rotateRight(w2, 19) ^ (w2 >> 10)
      schedule[index] = s1 &+ schedule[index - 7] &+ s0 &+ schedule[index - 16]
    }
    for index in 0..<64 { schedule[index] = schedule[index] &+ Shacal2Core.constants[index] }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadBigEndian32(block)
    var b = loadBigEndian32(block + 4)
    var c = loadBigEndian32(block + 8)
    var d = loadBigEndian32(block + 12)
    var e = loadBigEndian32(block + 16)
    var f = loadBigEndian32(block + 20)
    var g = loadBigEndian32(block + 24)
    var h = loadBigEndian32(block + 28)
    for round in 0..<64 {
      let sigma1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
      let choose = (e & f) ^ (~e & g)
      let t1 = h &+ sigma1 &+ choose &+ schedule[round]
      let sigma0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let t2 = sigma0 &+ majority
      h = g
      g = f
      f = e
      e = d &+ t1
      d = c
      c = b
      b = a
      a = t1 &+ t2
    }
    storeBigEndian32(a, block)
    storeBigEndian32(b, block + 4)
    storeBigEndian32(c, block + 8)
    storeBigEndian32(d, block + 12)
    storeBigEndian32(e, block + 16)
    storeBigEndian32(f, block + 20)
    storeBigEndian32(g, block + 24)
    storeBigEndian32(h, block + 28)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    var a = loadBigEndian32(block)
    var b = loadBigEndian32(block + 4)
    var c = loadBigEndian32(block + 8)
    var d = loadBigEndian32(block + 12)
    var e = loadBigEndian32(block + 16)
    var f = loadBigEndian32(block + 20)
    var g = loadBigEndian32(block + 24)
    var h = loadBigEndian32(block + 28)
    for round in (0..<64).reversed() {
      // Undo the shift of the working variables; a' = t1 + t2, e' = d + t1.
      let previousA = b
      let previousB = c
      let previousC = d
      let previousE = f
      let previousF = g
      let previousG = h
      let sigma0 =
        rotateRight(previousA, 2) ^ rotateRight(previousA, 13)
        ^ rotateRight(previousA, 22)
      let majority = (previousA & previousB) ^ (previousA & previousC) ^ (previousB & previousC)
      let t2 = sigma0 &+ majority
      let t1 = a &- t2
      let previousD = e &- t1
      let sigma1 =
        rotateRight(previousE, 6) ^ rotateRight(previousE, 11)
        ^ rotateRight(previousE, 25)
      let choose = (previousE & previousF) ^ (~previousE & previousG)
      let previousH = t1 &- sigma1 &- choose &- schedule[round]
      (a, b, c, d, e, f, g, h) = (
        previousA, previousB, previousC, previousD, previousE, previousF, previousG, previousH
      )
    }
    storeBigEndian32(a, block)
    storeBigEndian32(b, block + 4)
    storeBigEndian32(c, block + 8)
    storeBigEndian32(d, block + 12)
    storeBigEndian32(e, block + 16)
    storeBigEndian32(f, block + 20)
    storeBigEndian32(g, block + 24)
    storeBigEndian32(h, block + 28)
  }
}
