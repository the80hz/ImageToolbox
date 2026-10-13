import CommonCrypto
import Foundation

/// A block cipher with its key schedule already run. Blocks are processed in place, one or many at
/// a time. An instance is used for one file and one thread, so it needs no locking.
protocol BlockCore: AnyObject {
  /// The block size in bytes.
  var blockSize: Int { get }
  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>)
  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>)
  /// Encrypts `count` consecutive independent blocks in place.
  func encryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int)
  /// Decrypts `count` consecutive independent blocks in place.
  func decryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int)
}

extension BlockCore {
  func encryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int) {
    for index in 0..<count { encryptBlock(buffer + index * blockSize) }
  }

  func decryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int) {
    for index in 0..<count { decryptBlock(buffer + index * blockSize) }
  }
}

/// A block cipher from CommonCrypto, used in single-block ECB mode as the primitive that the
/// modes below build on.
final class CommonCryptoCore: BlockCore {

  enum Kind {
    case aes, des, tripleDES, blowfish, cast5, rc2

    fileprivate var algorithm: Int {
      switch self {
      case .aes: kCCAlgorithmAES
      case .des: kCCAlgorithmDES
      case .tripleDES: kCCAlgorithm3DES
      case .blowfish: kCCAlgorithmBlowfish
      case .cast5: kCCAlgorithmCAST
      case .rc2: kCCAlgorithmRC2
      }
    }

    fileprivate var size: Int {
      switch self {
      case .aes: kCCBlockSizeAES128
      case .des: kCCBlockSizeDES
      case .tripleDES: kCCBlockSize3DES
      case .blowfish: kCCBlockSizeBlowfish
      case .cast5: kCCBlockSizeCAST
      case .rc2: kCCBlockSizeRC2
      }
    }
  }

  let blockSize: Int
  private var encryptor: CCCryptorRef?
  private var decryptor: CCCryptorRef?

  /// Returns `nil` when CommonCrypto rejects the key length.
  init?(_ kind: Kind, key: [UInt8]) {
    blockSize = kind.size
    let options = CCOptions(kCCOptionECBMode)
    let encryptStatus = CCCryptorCreate(
      CCOperation(kCCEncrypt), CCAlgorithm(kind.algorithm), options, key, key.count, nil,
      &encryptor)
    let decryptStatus = CCCryptorCreate(
      CCOperation(kCCDecrypt), CCAlgorithm(kind.algorithm), options, key, key.count, nil,
      &decryptor)
    guard encryptStatus == kCCSuccess, decryptStatus == kCCSuccess else {
      if let encryptor { CCCryptorRelease(encryptor) }
      if let decryptor { CCCryptorRelease(decryptor) }
      return nil
    }
  }

  deinit {
    if let encryptor { CCCryptorRelease(encryptor) }
    if let decryptor { CCCryptorRelease(decryptor) }
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    process(encryptor, block, count: 1)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    process(decryptor, block, count: 1)
  }

  func encryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int) {
    process(encryptor, buffer, count: count)
  }

  func decryptBlocks(_ buffer: UnsafeMutablePointer<UInt8>, count: Int) {
    process(decryptor, buffer, count: count)
  }

  private func process(_ cryptor: CCCryptorRef?, _ buffer: UnsafeMutablePointer<UInt8>, count: Int)
  {
    guard count > 0 else { return }
    let length = count * blockSize
    var moved = 0
    let status = CCCryptorUpdate(cryptor, buffer, length, buffer, length, &moved)
    precondition(status == kCCSuccess && moved == length, "CommonCrypto ECB update failed")
  }
}

/// Block modes over a ``BlockCore``: CBC with PKCS#7 padding, CTR and GCM.
enum BlockModes {

  // MARK: CBC

  /// Pads with PKCS#7 and encrypts in CBC mode. `iv` must be one block long.
  static func cbcEncrypt(_ core: some BlockCore, iv: [UInt8], plaintext: [UInt8]) -> [UInt8] {
    let size = core.blockSize
    let padding = size - plaintext.count % size
    var buffer = plaintext
    buffer.append(contentsOf: repeatElement(UInt8(padding), count: padding))
    buffer.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      var offset = 0
      while offset < storage.count {
        if offset == 0 {
          for index in 0..<size { base[index] ^= iv[index] }
        } else {
          for index in 0..<size { base[offset + index] ^= base[offset - size + index] }
        }
        core.encryptBlock(base + offset)
        offset += size
      }
    }
    return buffer
  }

  /// Decrypts CBC data and removes the PKCS#7 padding. Returns `nil` when the length or the padding
  /// is not valid.
  static func cbcDecrypt(_ core: some BlockCore, iv: [UInt8], ciphertext: [UInt8]) -> [UInt8]? {
    let size = core.blockSize
    guard !ciphertext.isEmpty, ciphertext.count % size == 0 else { return nil }
    var buffer = ciphertext
    buffer.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      core.decryptBlocks(base, count: storage.count / size)
    }
    for index in 0..<buffer.count {
      buffer[index] ^= index < size ? iv[index] : ciphertext[index - size]
    }
    guard let last = buffer.last, last >= 1, Int(last) <= size, Int(last) <= buffer.count else {
      return nil
    }
    let padding = Int(last)
    var difference: UInt8 = 0
    for index in (buffer.count - padding)..<buffer.count { difference |= buffer[index] ^ last }
    guard difference == 0 else { return nil }
    buffer.removeLast(padding)
    return buffer
  }

  // MARK: CTR

  /// Encrypts or decrypts (the two are the same) in CTR mode. The counter block is `iv`, taken as a
  /// big-endian number over the whole block and incremented once per block.
  static func ctr(_ core: some BlockCore, iv: [UInt8], data: [UInt8]) -> [UInt8] {
    let size = core.blockSize
    var counter = iv
    var output = data
    let chunkBlocks = 512
    var keystream = [UInt8](repeating: 0, count: chunkBlocks * size)
    var offset = 0
    while offset < output.count {
      let remaining = output.count - offset
      let blocks = min(chunkBlocks, (remaining + size - 1) / size)
      for block in 0..<blocks {
        for index in 0..<size { keystream[block * size + index] = counter[index] }
        incrementBigEndian(&counter)
      }
      keystream.withUnsafeMutableBufferPointer { storage in
        guard let base = storage.baseAddress else { return }
        core.encryptBlocks(base, count: blocks)
      }
      let used = min(remaining, blocks * size)
      for index in 0..<used { output[offset + index] ^= keystream[index] }
      offset += used
    }
    return output
  }

  private static func incrementBigEndian(_ counter: inout [UInt8]) {
    var index = counter.count - 1
    while index >= 0 {
      counter[index] &+= 1
      if counter[index] != 0 { break }
      index -= 1
    }
  }

  // MARK: CFB and OFB (full-block feedback)

  /// Full-block CFB. The feedback register is the previous ciphertext block, starting from `iv`.
  /// A partial last block is allowed and uses the first bytes of the keystream.
  static func cfb(
    _ core: some BlockCore, iv: [UInt8], data: [UInt8], encrypt: Bool
  ) -> [UInt8] {
    let size = core.blockSize
    precondition(iv.count == size)
    var register = iv
    var output = data
    var offset = 0
    while offset < data.count {
      var keystream = register
      keystream.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
      let count = min(size, data.count - offset)
      for index in 0..<count { output[offset + index] = data[offset + index] ^ keystream[index] }
      if count == size {
        // The next block is keyed by the ciphertext: the output when encrypting, the input when
        // decrypting.
        register =
          encrypt ? Array(output[offset..<(offset + size)]) : Array(data[offset..<(offset + size)])
      }
      offset += count
    }
    return output
  }

  /// CFB with an 8-bit feedback segment (CFB8, NIST SP 800-38A F.3.7). Each byte is XORed with the
  /// first byte of the cipher applied to the register. The register then shifts left by one byte and
  /// takes in the ciphertext byte. `iv` is one block long.
  static func cfb8(
    _ core: some BlockCore, iv: [UInt8], data: [UInt8], encrypt: Bool
  ) -> [UInt8] {
    let size = core.blockSize
    precondition(iv.count == size)
    var register = iv
    var scratch = [UInt8](repeating: 0, count: size)
    var output = data
    for index in 0..<data.count {
      for position in 0..<size { scratch[position] = register[position] }
      scratch.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
      let result = data[index] ^ scratch[0]
      output[index] = result
      let feedback = encrypt ? result : data[index]
      for position in 0..<(size - 1) { register[position] = register[position + 1] }
      register[size - 1] = feedback
    }
    return output
  }

  /// Full-block OFB. The keystream is the block cipher applied again and again to `iv`, so it does
  /// not depend on the data. Encryption and decryption are the same operation.
  static func ofb(_ core: some BlockCore, iv: [UInt8], data: [UInt8]) -> [UInt8] {
    let size = core.blockSize
    precondition(iv.count == size)
    var state = iv
    var output = data
    var offset = 0
    while offset < output.count {
      state.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
      let count = min(size, output.count - offset)
      for index in 0..<count { output[offset + index] ^= state[index] }
      offset += count
    }
    return output
  }

  // MARK: CTS

  /// CBC with ciphertext stealing, variant CBC-CS3 of NIST SP 800-38A addendum (October 2010). The
  /// output has the length of the input, so no padding is added. The input must be at least one
  /// block, and `iv` is one block. A single block is encrypted as CBC encrypts it. For two blocks
  /// or more, the final partial block is padded with zeros, CBC runs over all blocks, and then the
  /// last two output blocks are swapped and the penultimate block is cut to the length of the final
  /// one. CBC-CS3 swaps unconditionally, so for a whole last block it differs from CBC. Returns
  /// `nil` when the input is shorter than one block.
  static func ctsEncrypt(_ core: some BlockCore, iv: [UInt8], plaintext: [UInt8]) -> [UInt8]? {
    let size = core.blockSize
    guard plaintext.count >= size, iv.count == size else { return nil }
    let blocks = (plaintext.count + size - 1) / size
    guard blocks > 1 else { return cbcChainEncrypt(core, iv: iv, data: plaintext) }
    let tail = plaintext.count - (blocks - 1) * size
    var padded = plaintext
    padded.append(contentsOf: repeatElement(0, count: blocks * size - plaintext.count))
    let chained = cbcChainEncrypt(core, iv: iv, data: padded)
    // C_1 ... C_{n-2}, then C_n in full, then the first `tail` bytes of C_{n-1}.
    let penultimate = (blocks - 2) * size
    let last = (blocks - 1) * size
    return Array(chained[0..<penultimate]) + Array(chained[last..<(last + size)])
      + Array(chained[penultimate..<(penultimate + tail)])
  }

  /// Decrypts CBC-CS3 data made by ``ctsEncrypt``. Returns `nil` when the input is shorter than one
  /// block or `iv` is not one block long.
  static func ctsDecrypt(_ core: some BlockCore, iv: [UInt8], ciphertext: [UInt8]) -> [UInt8]? {
    let size = core.blockSize
    guard ciphertext.count >= size, iv.count == size else { return nil }
    let blocks = (ciphertext.count + size - 1) / size
    guard blocks > 1 else { return cbcChainDecrypt(core, iv: iv, data: ciphertext) }
    // The encrypted output holds C_n in full, then the `tail` bytes of C_{n-1}. CBC-CS1 wants the
    // cut block first, so the two are swapped back before the CBC-CS1 steps run.
    let penultimate = (blocks - 2) * size
    let leading = Array(ciphertext[0..<penultimate])
    let last = Array(ciphertext[penultimate..<(penultimate + size)])
    let cut = Array(ciphertext[(penultimate + size)..<ciphertext.count])
    var decrypted = last
    decrypted.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      core.decryptBlock(base)
    }
    // Z* is the first `tail` bytes of D(C_n) and Z** the rest. C_{n-1} is the cut block followed by
    // Z**, and the final plaintext block is the cut block XOR Z*.
    let tail = cut.count
    let penultimateBlock = cut + decrypted[tail..<size]
    let head = cbcChainDecrypt(core, iv: iv, data: leading + penultimateBlock)
    let finalBlock = (0..<tail).map { cut[$0] ^ decrypted[$0] }
    return head + finalBlock
  }

  /// CBC over whole blocks with no padding. `data` is a multiple of the block size.
  private static func cbcChainEncrypt(
    _ core: some BlockCore, iv: [UInt8], data: [UInt8]
  ) -> [UInt8] {
    let size = core.blockSize
    var buffer = data
    buffer.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      var offset = 0
      while offset < storage.count {
        if offset == 0 {
          for index in 0..<size { base[index] ^= iv[index] }
        } else {
          for index in 0..<size { base[offset + index] ^= base[offset - size + index] }
        }
        core.encryptBlock(base + offset)
        offset += size
      }
    }
    return buffer
  }

  /// CBC decryption of whole blocks, with no padding. `data` is a multiple of the block size.
  private static func cbcChainDecrypt(
    _ core: some BlockCore, iv: [UInt8], data: [UInt8]
  ) -> [UInt8] {
    let size = core.blockSize
    var buffer = data
    buffer.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      core.decryptBlocks(base, count: storage.count / size)
    }
    for index in 0..<buffer.count {
      buffer[index] ^= index < size ? iv[index] : data[index - size]
    }
    return buffer
  }

  // MARK: CCM

  /// Counter with CBC-MAC (RFC 3610) for 128-bit block ciphers. `nonce` is 7 to 13 bytes and
  /// `tagLength` is an even number from 4 to 16. The message may be at most 2^(8q) - 1 bytes, where
  /// q = 15 - nonce length.
  static func ccmSeal(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], plaintext: [UInt8], tagLength: Int
  ) -> (ciphertext: [UInt8], tag: [UInt8])? {
    guard isValidCCM(core, nonce: nonce, tagLength: tagLength, length: plaintext.count) else {
      return nil
    }
    let mac = ccmMAC(
      core, nonce: nonce, aad: aad, message: plaintext, tagLength: tagLength)
    let stream = ccmKeystream(core, nonce: nonce, blocks: (plaintext.count + 15) / 16)
    let ciphertext = zip(plaintext, stream).map { $0 ^ $1 }
    let s0 = ccmBlock(core, nonce: nonce, counter: 0)
    let tag = (0..<tagLength).map { mac[$0] ^ s0[$0] }
    return (ciphertext, tag)
  }

  /// Verifies the CCM tag and decrypts. Returns `nil` when the tag does not match.
  static func ccmOpen(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8], tag: [UInt8]
  ) -> [UInt8]? {
    guard isValidCCM(core, nonce: nonce, tagLength: tag.count, length: ciphertext.count) else {
      return nil
    }
    let stream = ccmKeystream(core, nonce: nonce, blocks: (ciphertext.count + 15) / 16)
    let plaintext = zip(ciphertext, stream).map { $0 ^ $1 }
    let mac = ccmMAC(core, nonce: nonce, aad: aad, message: plaintext, tagLength: tag.count)
    let s0 = ccmBlock(core, nonce: nonce, counter: 0)
    let expected = (0..<tag.count).map { mac[$0] ^ s0[$0] }
    guard constantTimeEqual(expected, tag) else { return nil }
    return plaintext
  }

  private static func isValidCCM(
    _ core: some BlockCore, nonce: [UInt8], tagLength: Int, length: Int
  ) -> Bool {
    guard core.blockSize == 16, (7...13).contains(nonce.count) else { return false }
    guard (4...16).contains(tagLength), tagLength % 2 == 0 else { return false }
    let q = 15 - nonce.count
    return q >= 8 || length < 1 << (8 * q)
  }

  /// The flags byte of a CCM block: `adata` set when there is associated data, the tag length
  /// field, and the length field size q - 1.
  private static func ccmFlags(nonce: [UInt8], tagLength: Int, adata: Bool) -> UInt8 {
    let q = 15 - nonce.count
    return (adata ? 0x40 : 0) | UInt8((tagLength - 2) / 2) << 3 | UInt8(q - 1)
  }

  private static func ccmMAC(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], message: [UInt8], tagLength: Int
  ) -> [UInt8] {
    let q = 15 - nonce.count
    var first = [ccmFlags(nonce: nonce, tagLength: tagLength, adata: !aad.isEmpty)] + nonce
    for shift in stride(from: 8 * (q - 1), through: 0, by: -8) {
      first.append(UInt8(truncatingIfNeeded: message.count >> shift))
    }
    var state = [UInt8](repeating: 0, count: 16)
    ccmAbsorb(core, &state, first)
    if !aad.isEmpty {
      var header: [UInt8] = []
      if aad.count < 0xFF00 {
        header = [UInt8(aad.count >> 8), UInt8(aad.count & 0xFF)]
      } else {
        header =
          [0xFF, 0xFE] + (0..<4).map { UInt8(truncatingIfNeeded: aad.count >> (24 - 8 * $0)) }
      }
      ccmAbsorb(core, &state, header + aad)
    }
    ccmAbsorb(core, &state, message)
    return Array(state.prefix(tagLength))
  }

  /// Runs CBC-MAC over `data`, zero padded to whole blocks.
  private static func ccmAbsorb(_ core: some BlockCore, _ state: inout [UInt8], _ data: [UInt8]) {
    var offset = 0
    while offset < data.count {
      for index in 0..<16 {
        state[index] ^= offset + index < data.count ? data[offset + index] : 0
      }
      state.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
      offset += 16
    }
  }

  /// The counter block A_i of CCM: flags, nonce, and the counter in q bytes.
  private static func ccmBlock(_ core: some BlockCore, nonce: [UInt8], counter: Int) -> [UInt8] {
    let q = 15 - nonce.count
    var block = [UInt8(q - 1)] + nonce
    for shift in stride(from: 8 * (q - 1), through: 0, by: -8) {
      block.append(UInt8(truncatingIfNeeded: counter >> shift))
    }
    block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    return block
  }

  /// The keystream blocks S_1 ... S_blocks used to encrypt the message.
  private static func ccmKeystream(
    _ core: some BlockCore, nonce: [UInt8], blocks: Int
  ) -> [UInt8] {
    (0..<blocks).flatMap { ccmBlock(core, nonce: nonce, counter: $0 + 1) }
  }

  // MARK: GCM

  /// Galois/Counter Mode for 128-bit block ciphers with a 96-bit nonce and a 128-bit tag, as in
  /// NIST SP 800-38D.
  static func gcmSeal(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]
  ) -> (ciphertext: [UInt8], tag: [UInt8]) {
    precondition(core.blockSize == 16 && nonce.count == 12)
    let hasher = GHash(core: core)
    let ciphertext = gcmCounter(core, nonce: nonce, data: plaintext)
    let tag = gcmTag(core, hasher: hasher, nonce: nonce, aad: aad, ciphertext: ciphertext)
    return (ciphertext, tag)
  }

  /// Verifies the tag and decrypts. Returns `nil` when the tag does not match.
  static func gcmOpen(
    _ core: some BlockCore, nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8], tag: [UInt8]
  ) -> [UInt8]? {
    precondition(core.blockSize == 16 && nonce.count == 12)
    let hasher = GHash(core: core)
    let expected = gcmTag(core, hasher: hasher, nonce: nonce, aad: aad, ciphertext: ciphertext)
    guard constantTimeEqual(expected, tag) else { return nil }
    return gcmCounter(core, nonce: nonce, data: ciphertext)
  }

  /// CTR with the 32-bit counter of GCM, starting from block 2 (block 1 masks the tag).
  private static func gcmCounter(_ core: some BlockCore, nonce: [UInt8], data: [UInt8]) -> [UInt8] {
    var output = data
    var counter = UInt32(2)
    let chunkBlocks = 512
    var keystream = [UInt8](repeating: 0, count: chunkBlocks * 16)
    var offset = 0
    while offset < output.count {
      let remaining = output.count - offset
      let blocks = min(chunkBlocks, (remaining + 15) / 16)
      for block in 0..<blocks {
        for index in 0..<12 { keystream[block * 16 + index] = nonce[index] }
        keystream[block * 16 + 12] = UInt8(truncatingIfNeeded: counter >> 24)
        keystream[block * 16 + 13] = UInt8(truncatingIfNeeded: counter >> 16)
        keystream[block * 16 + 14] = UInt8(truncatingIfNeeded: counter >> 8)
        keystream[block * 16 + 15] = UInt8(truncatingIfNeeded: counter)
        counter &+= 1
      }
      keystream.withUnsafeMutableBufferPointer { storage in
        guard let base = storage.baseAddress else { return }
        core.encryptBlocks(base, count: blocks)
      }
      let used = min(remaining, blocks * 16)
      for index in 0..<used { output[offset + index] ^= keystream[index] }
      offset += used
    }
    return output
  }

  private static func gcmTag(
    _ core: some BlockCore, hasher: GHash, nonce: [UInt8], aad: [UInt8], ciphertext: [UInt8]
  ) -> [UInt8] {
    var state = hasher
    state.absorb(aad)
    state.absorb(ciphertext)
    state.absorbLengths(aadBytes: aad.count, dataBytes: ciphertext.count)
    var mask = nonce + [0, 0, 0, 1]
    mask.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      core.encryptBlock(base)
    }
    return zip(state.digest, mask).map { $0 ^ $1 }
  }

  /// Compares two byte strings without stopping at the first difference.
  static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for index in 0..<lhs.count { difference |= lhs[index] ^ rhs[index] }
    return difference == 0
  }
}

/// The GHASH function of GCM. Multiplication by the hash key is done with a table of the 128
/// shifted copies of that key, so there is no data-dependent branch.
struct GHash {
  /// `table[i]` is H multiplied by x^i, as (high, low) halves of the reflected bit string.
  private var table: [UInt64]
  private var high: UInt64 = 0
  private var low: UInt64 = 0

  init(core: some BlockCore) {
    var key = [UInt8](repeating: 0, count: 16)
    key.withUnsafeMutableBufferPointer { storage in
      guard let base = storage.baseAddress else { return }
      core.encryptBlock(base)
    }
    self.init(hashKey: key)
  }

  /// The table for the hash key `key`: sixteen bytes in GHASH's bit order, where the first bit is
  /// the most significant bit of the first byte.
  init(hashKey key: [UInt8]) {
    var upper = GHash.load(key, at: 0)
    var lower = GHash.load(key, at: 8)
    var table = [UInt64](repeating: 0, count: 256)
    for index in 0..<128 {
      table[index * 2] = upper
      table[index * 2 + 1] = lower
      let carry = lower & 1
      lower = lower >> 1 | upper << 63
      upper = upper >> 1
      if carry == 1 { upper ^= 0xE100_0000_0000_0000 }
    }
    self.table = table
  }

  private static func load(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<8 { value = value << 8 | UInt64(bytes[offset + index]) }
    return value
  }

  /// Absorbs data, padding the last partial block with zeros.
  mutating func absorb(_ data: [UInt8]) {
    var offset = 0
    var block = [UInt8](repeating: 0, count: 16)
    while offset < data.count {
      let count = min(16, data.count - offset)
      for index in 0..<16 { block[index] = index < count ? data[offset + index] : 0 }
      multiply(GHash.load(block, at: 0), GHash.load(block, at: 8))
      offset += 16
    }
  }

  mutating func absorbLengths(aadBytes: Int, dataBytes: Int) {
    multiply(UInt64(aadBytes) &* 8, UInt64(dataBytes) &* 8)
  }

  var digest: [UInt8] {
    var result = [UInt8](repeating: 0, count: 16)
    for index in 0..<8 {
      result[index] = UInt8(truncatingIfNeeded: high >> UInt64(56 - 8 * index))
      result[8 + index] = UInt8(truncatingIfNeeded: low >> UInt64(56 - 8 * index))
    }
    return result
  }

  /// Sets the state to (state xor block) times H.
  private mutating func multiply(_ blockHigh: UInt64, _ blockLow: UInt64) {
    let inputHigh = high ^ blockHigh
    let inputLow = low ^ blockLow
    var accumulatorHigh: UInt64 = 0
    var accumulatorLow: UInt64 = 0
    table.withUnsafeBufferPointer { entries in
      for bit in 0..<64 {
        let maskHigh = 0 &- (inputHigh >> UInt64(63 - bit) & 1)
        let maskLow = 0 &- (inputLow >> UInt64(63 - bit) & 1)
        accumulatorHigh ^= entries[bit * 2] & maskHigh ^ entries[(bit + 64) * 2] & maskLow
        accumulatorLow ^= entries[bit * 2 + 1] & maskHigh ^ entries[(bit + 64) * 2 + 1] & maskLow
      }
    }
    high = accumulatorHigh
    low = accumulatorLow
  }
}
