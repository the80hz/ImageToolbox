import Foundation

/// Authenticated modes: EAX (Bellare, Rogaway and Wagner, 2004) and OCB3 (RFC 7253) for 128-bit
/// block ciphers, and AES-GCM-SIV (RFC 8452). Every seal function returns the ciphertext and a 16-byte
/// tag. Every open function returns `nil` when the tag does not match.
enum BlockAEAD {

  // MARK: - Helpers

  private static func zeros(_ count: Int) -> [UInt8] {
    [UInt8](repeating: 0, count: count)
  }

  private static func xor(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
    zip(lhs, rhs).map { $0 ^ $1 }
  }

  private static func encrypted(_ core: some BlockCore, _ block: [UInt8]) -> [UInt8] {
    var buffer = block
    buffer.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    return buffer
  }

  private static func decrypted(_ core: some BlockCore, _ block: [UInt8]) -> [UInt8] {
    var buffer = block
    buffer.withUnsafeMutableBufferPointer { core.decryptBlock($0.baseAddress!) }
    return buffer
  }

  /// Multiplication by x in GF(2^128) with the polynomial x^128 + x^7 + x^2 + x + 1, the doubling of
  /// CMAC and OCB. The block is big-endian.
  private static func double(_ block: [UInt8]) -> [UInt8] {
    var result = zeros(16)
    var carry: UInt8 = 0
    for index in stride(from: 15, through: 0, by: -1) {
      result[index] = block[index] << 1 | carry
      carry = block[index] >> 7
    }
    if carry == 1 { result[15] ^= 0x87 }
    return result
  }

  /// The 16 bytes `x` padded with a one bit and zeros, as a block. `x` is shorter than 16 bytes.
  private static func oneZeroPadded(_ x: [UInt8]) -> [UInt8] {
    x + [0x80] + zeros(15 - x.count)
  }

  // MARK: - CMAC and EAX

  /// AES-CMAC (NIST SP 800-38B, RFC 4493) of `message`, with the subkeys K1 = double(E(0)) and
  /// K2 = double(K1).
  private static func cmac(_ core: some BlockCore, _ message: [UInt8]) -> [UInt8] {
    let k1 = double(encrypted(core, zeros(16)))
    let k2 = double(k1)
    let blocks = max(1, (message.count + 15) / 16)
    let tail = Array(message[((blocks - 1) * 16)...])
    let last: [UInt8]
    if !message.isEmpty && message.count % 16 == 0 {
      last = xor(tail, k1)
    } else {
      last = xor(oneZeroPadded(tail), k2)
    }
    var state = zeros(16)
    for block in 0..<(blocks - 1) {
      state = encrypted(core, xor(state, Array(message[(block * 16)..<(block * 16 + 16)])))
    }
    return encrypted(core, xor(state, last))
  }

  /// OMAC^t of EAX: CMAC over the block [t]_n followed by `data`.
  private static func omac(_ core: some BlockCore, type: UInt8, _ data: [UInt8]) -> [UInt8] {
    var prefix = zeros(16)
    prefix[15] = type
    return cmac(core, prefix + data)
  }

  /// EAX (Bellare, Rogaway and Wagner) with a 16-byte tag. The nonce may have any length; the file
  /// cipher uses 16 bytes. The block cipher must have a 16-byte block.
  static func eaxSeal(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]
  ) -> (ciphertext: [UInt8], tag: [UInt8]) {
    precondition(core.blockSize == 16)
    let nonceTag = omac(core, type: 0, nonce)
    let ciphertext = BlockModes.ctr(core, iv: nonceTag, data: plaintext)
    return (ciphertext, eaxTag(core, nonceTag: nonceTag, aad: aad, ciphertext: ciphertext))
  }

  /// Verifies the EAX tag and decrypts. Returns `nil` when the tag does not match.
  static func eaxOpen(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8], tag: [UInt8]
  ) -> [UInt8]? {
    precondition(core.blockSize == 16)
    let nonceTag = omac(core, type: 0, nonce)
    let expected = eaxTag(core, nonceTag: nonceTag, aad: aad, ciphertext: ciphertext)
    guard BlockModes.constantTimeEqual(expected, tag) else { return nil }
    return BlockModes.ctr(core, iv: nonceTag, data: ciphertext)
  }

  private static func eaxTag(
    _ core: some BlockCore, nonceTag: [UInt8], aad: [UInt8], ciphertext: [UInt8]
  ) -> [UInt8] {
    xor(xor(nonceTag, omac(core, type: 1, aad)), omac(core, type: 2, ciphertext))
  }

  // MARK: - OCB3

  /// The values of OCB3 that depend only on the key and the nonce.
  private struct OCBSetup {
    /// L_* = E(0).
    let lStar: [UInt8]
    /// L_$ = double(L_*).
    let lDollar: [UInt8]
    /// `lTable[i]` is L_i. L_0 = double(L_$) and L_i = double(L_{i-1}).
    let lTable: [[UInt8]]
    /// Offset_0 of the encryption, from the nonce (RFC 7253, section 4.2, TAGLEN 128).
    let offset0: [UInt8]

    init(core: some BlockCore, nonce: [UInt8]) {
      let lStar = encrypted(core, zeros(16))
      let lDollar = double(lStar)
      var table: [[UInt8]] = []
      var current = double(lDollar)
      for _ in 0..<64 {
        table.append(current)
        current = double(current)
      }
      self.lStar = lStar
      self.lDollar = lDollar
      self.lTable = table

      // The nonce block: seven zero bits (TAGLEN mod 128), 24 zero bits, a one bit, the 96-bit nonce.
      var nonceBlock = zeros(16)
      nonceBlock[3] = 0x01
      nonceBlock.replaceSubrange(4..<16, with: nonce)
      let bottom = Int(nonceBlock[15] & 0x3F)
      nonceBlock[15] &= 0xC0
      let ktop = encrypted(core, nonceBlock)
      var stretch = ktop
      for index in 0..<8 { stretch.append(ktop[index] ^ ktop[index + 1]) }
      // Offset_0 is the 128 bits of the stretch that start at bit `bottom`.
      let byteShift = bottom / 8
      let bitShift = bottom % 8
      var offset = zeros(16)
      for index in 0..<16 {
        if bitShift == 0 {
          offset[index] = stretch[byteShift + index]
        } else {
          offset[index] =
            stretch[byteShift + index] << bitShift
            | stretch[byteShift + index + 1] >> (8 - bitShift)
        }
      }
      self.offset0 = offset
    }
  }

  /// HASH of RFC 7253, section 4.1: the associated data, with offsets of its own from zero.
  private static func ocbHash(_ core: some BlockCore, _ setup: OCBSetup, _ aad: [UInt8]) -> [UInt8]
  {
    var offset = zeros(16)
    var sum = zeros(16)
    let full = aad.count / 16
    for index in 0..<full {
      offset = xor(offset, setup.lTable[(index + 1).trailingZeroBitCount])
      let block = Array(aad[(index * 16)..<(index * 16 + 16)])
      sum = xor(sum, encrypted(core, xor(block, offset)))
    }
    // An empty final block adds nothing (RFC 7253, section 4.1).
    let rest = Array(aad[(full * 16)...])
    if !rest.isEmpty {
      offset = xor(offset, setup.lStar)
      sum = xor(sum, encrypted(core, xor(oneZeroPadded(rest), offset)))
    }
    return sum
  }

  /// OCB3 (RFC 7253) with a 96-bit nonce and a 128-bit tag. The block cipher must have a 16-byte block.
  static func ocbSeal(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]
  ) -> (ciphertext: [UInt8], tag: [UInt8])? {
    guard core.blockSize == 16, nonce.count == 12 else { return nil }
    let setup = OCBSetup(core: core, nonce: nonce)
    var offset = setup.offset0
    var checksum = zeros(16)
    var ciphertext: [UInt8] = []
    ciphertext.reserveCapacity(plaintext.count)
    let full = plaintext.count / 16
    for index in 0..<full {
      let block = Array(plaintext[(index * 16)..<(index * 16 + 16)])
      offset = xor(offset, setup.lTable[(index + 1).trailingZeroBitCount])
      ciphertext += xor(encrypted(core, xor(block, offset)), offset)
      checksum = xor(checksum, block)
    }
    // A whole number of blocks, the empty plaintext included, leaves Offset_m in `offset`.
    let rest = Array(plaintext[(full * 16)...])
    if !rest.isEmpty {
      offset = xor(offset, setup.lStar)
      let pad = encrypted(core, offset)
      ciphertext += xor(rest, Array(pad.prefix(rest.count)))
      checksum = xor(checksum, oneZeroPadded(rest))
    }
    let tag = xor(
      encrypted(core, xor(xor(checksum, offset), setup.lDollar)),
      ocbHash(core, setup, aad))
    return (ciphertext, tag)
  }

  /// Decrypts OCB3 and verifies the tag. Returns `nil` when the tag does not match.
  static func ocbOpen(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8], tag: [UInt8]
  ) -> [UInt8]? {
    guard core.blockSize == 16, nonce.count == 12 else { return nil }
    let setup = OCBSetup(core: core, nonce: nonce)
    var offset = setup.offset0
    var checksum = zeros(16)
    var plaintext: [UInt8] = []
    plaintext.reserveCapacity(ciphertext.count)
    let full = ciphertext.count / 16
    for index in 0..<full {
      let block = Array(ciphertext[(index * 16)..<(index * 16 + 16)])
      offset = xor(offset, setup.lTable[(index + 1).trailingZeroBitCount])
      let decodedBlock = xor(decrypted(core, xor(block, offset)), offset)
      plaintext += decodedBlock
      checksum = xor(checksum, decodedBlock)
    }
    // A whole number of blocks, the empty ciphertext included, leaves Offset_m in `offset`.
    let rest = Array(ciphertext[(full * 16)...])
    if !rest.isEmpty {
      offset = xor(offset, setup.lStar)
      let pad = encrypted(core, offset)
      let decodedRest = xor(rest, Array(pad.prefix(rest.count)))
      plaintext += decodedRest
      checksum = xor(checksum, oneZeroPadded(decodedRest))
    }
    let expected = xor(
      encrypted(core, xor(xor(checksum, offset), setup.lDollar)),
      ocbHash(core, setup, aad))
    guard BlockModes.constantTimeEqual(expected, tag) else { return nil }
    return plaintext
  }

  // MARK: - AES-GCM-SIV

  private struct GCMSIVKeys {
    /// The message authentication key: the first eight bytes of two derived blocks.
    let authentication: [UInt8]
    /// The AES key for encryption, which is also the key of the tag.
    let encryptor: CommonCryptoCore
  }

  /// The per-nonce keys of RFC 8452, section 4: each derived block is the AES encryption, under the
  /// key-generating key, of a little-endian 32-bit counter followed by the nonce. Its first eight bytes
  /// are kept.
  private static func gcmSIVKeys(key: [UInt8], nonce: [UInt8]) -> GCMSIVKeys? {
    guard [16, 32].contains(key.count), nonce.count == 12,
      let master = CommonCryptoCore(.aes, key: key)
    else { return nil }
    var material: [UInt8] = []
    for counter in 0..<(2 + key.count / 8) {
      var block = zeros(16)
      for byte in 0..<4 { block[byte] = UInt8(truncatingIfNeeded: counter >> (8 * byte)) }
      block.replaceSubrange(4..<16, with: nonce)
      material += encrypted(master, block).prefix(8)
    }
    guard let encryptor = CommonCryptoCore(.aes, key: Array(material[16...])) else { return nil }
    return GCMSIVKeys(authentication: Array(material[0..<16]), encryptor: encryptor)
  }

  /// POLYVAL (RFC 8452, section 3) of `blocks`, a multiple of 16 bytes, with the hash key `key`. It is
  /// GHASH with the key multiplied by x, and each block and the result are in reversed byte order.
  static func polyval(hashKey key: [UInt8], blocks: [UInt8]) -> [UInt8] {
    var hasher = GHash(hashKey: multiplyByX(Array(key.reversed())))
    var reversedBlocks = blocks
    for start in stride(from: 0, to: blocks.count, by: 16) {
      for index in 0..<16 { reversedBlocks[start + index] = blocks[start + 15 - index] }
    }
    hasher.absorb(reversedBlocks)
    return Array(hasher.digest.reversed())
  }

  /// Multiplication by x in GHASH's bit order: a one-bit shift toward the last byte, with the
  /// reduction 0xE1 when the bit shifted out was set.
  private static func multiplyByX(_ block: [UInt8]) -> [UInt8] {
    var result = zeros(16)
    var carry: UInt8 = 0
    for index in 0..<16 {
      result[index] = block[index] >> 1 | carry << 7
      carry = block[index] & 1
    }
    if carry == 1 { result[0] ^= 0xE1 }
    return result
  }

  private static func zeroPadded(_ data: [UInt8]) -> [UInt8] {
    data + zeros((16 - data.count % 16) % 16)
  }

  /// The tag of RFC 8452, section 4: POLYVAL over the padded associated data, the padded plaintext
  /// and the bit lengths, with the nonce folded in and the top bit cleared, encrypted with the key.
  private static func gcmSIVTag(
    _ keys: GCMSIVKeys, nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]
  ) -> [UInt8] {
    var input = zeroPadded(aad) + zeroPadded(plaintext)
    for value in [UInt64(aad.count) * 8, UInt64(plaintext.count) * 8] {
      input += (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }
    var state = polyval(hashKey: keys.authentication, blocks: input)
    for index in 0..<12 { state[index] ^= nonce[index] }
    state[15] &= 0x7F
    return encrypted(keys.encryptor, state)
  }

  /// The GCM-SIV encryption, which is also its decryption: the counter block is the tag with the top
  /// bit of its last byte set, and its first four bytes count up as a little-endian number.
  private static func gcmSIVCounter(
    _ encryptor: CommonCryptoCore, tag: [UInt8], data: [UInt8]
  ) -> [UInt8] {
    var counterBlock = tag
    counterBlock[15] |= 0x80
    var output = data
    for start in stride(from: 0, to: data.count, by: 16) {
      let keystream = encrypted(encryptor, counterBlock)
      for index in 0..<min(16, data.count - start) { output[start + index] ^= keystream[index] }
      var counter = UInt32(counterBlock[0]) | UInt32(counterBlock[1]) << 8
      counter |= UInt32(counterBlock[2]) << 16 | UInt32(counterBlock[3]) << 24
      counter &+= 1
      for byte in 0..<4 { counterBlock[byte] = UInt8(truncatingIfNeeded: counter >> (8 * byte)) }
    }
    return output
  }

  /// AES-GCM-SIV (RFC 8452) with a 96-bit nonce and a 16-byte tag. `key` is 16 or 32 bytes. The
  /// key is used with AES only, so the caller passes the AES key itself.
  static func gcmSIVSeal(
    key: [UInt8], nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]
  ) -> (ciphertext: [UInt8], tag: [UInt8])? {
    guard let keys = gcmSIVKeys(key: key, nonce: nonce) else { return nil }
    let tag = gcmSIVTag(keys, nonce: nonce, aad: aad, plaintext: plaintext)
    return (gcmSIVCounter(keys.encryptor, tag: tag, data: plaintext), tag)
  }

  /// Decrypts AES-GCM-SIV and verifies the tag. Returns `nil` when the tag does not match.
  static func gcmSIVOpen(
    key: [UInt8], nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8], tag: [UInt8]
  ) -> [UInt8]? {
    guard tag.count == 16, let keys = gcmSIVKeys(key: key, nonce: nonce) else { return nil }
    let plaintext = gcmSIVCounter(keys.encryptor, tag: tag, data: ciphertext)
    let expected = gcmSIVTag(keys, nonce: nonce, aad: aad, plaintext: plaintext)
    guard BlockModes.constantTimeEqual(expected, tag) else { return nil }
    return plaintext
  }
}
