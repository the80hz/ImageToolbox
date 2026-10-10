import CommonCrypto
import CryptoKit

/// The 7zAES coder (method 06F10701) of encrypted 7z archives. The password turns into a 256-bit
/// key through SHA-256 over 2^cycles rounds, and the data is decrypted with AES-256 in CBC mode.
///
/// The coder's properties are a byte whose low six bits are the cycle power, a byte with the salt
/// and IV sizes, then the salt and the IV. Bit 7 of the first byte adds one to the salt size and
/// bit 6 adds one to the IV size; the high and low nibbles of the second byte hold the rest.
///
/// The key follows 7-Zip: one running SHA-256 takes, in every round, the salt, the password in
/// UTF-16LE and an 8-byte little-endian counter that counts up from zero.
enum SevenZipAES {

  /// The method id of the coder.
  static let method: [UInt8] = [0x06, 0xF1, 0x07, 0x01]

  /// The most rounds, as a power of two, that a key may take. 7-Zip writes 19 by default, and more
  /// rounds than this would take minutes on a phone, so such an archive is refused.
  private static let maximumCyclesPower: UInt8 = 24

  /// The cycle power that 7-Zip writes for a key taken straight from the salt and the password.
  private static let directKeyCyclesPower: UInt8 = 0x3F

  /// Decrypts `input` with the key that `password` gives.
  /// - Parameters:
  ///   - input: a whole number of AES blocks, as the packed stream of the coder.
  ///   - properties: the properties of the coder.
  ///   - password: the password, which is encoded as UTF-16LE before it is hashed.
  /// - Returns: the decrypted bytes, as many as `input`. The caller keeps the leading bytes it needs.
  static func decrypt(_ input: [UInt8], properties: [UInt8], password: String) throws -> [UInt8] {
    guard properties.count >= 2 else { throw ArchiveCodecError.malformed }
    let cyclesPower = properties[0] & 0x3F
    let saltSize = Int(properties[0] >> 7) + Int(properties[1] >> 4)
    let ivSize = Int((properties[0] >> 6) & 1) + Int(properties[1] & 0x0F)
    guard properties.count == 2 + saltSize + ivSize else { throw ArchiveCodecError.malformed }
    let salt = Array(properties[2..<(2 + saltSize)])
    // The IV is at most 16 bytes long, and the rest of the block is zero.
    var iv = [UInt8](repeating: 0, count: 16)
    for index in 0..<ivSize { iv[index] = properties[2 + saltSize + index] }

    guard input.count % 16 == 0 else { throw ArchiveCodecError.malformed }
    let key = try deriveKey(salt: salt, password: utf16LE(password), cyclesPower: cyclesPower)
    return try decryptCBC(input, key: key, iv: iv)
  }

  /// The 32-byte AES key for `salt` and the UTF-16LE bytes of the password.
  static func deriveKey(salt: [UInt8], password: [UInt8], cyclesPower: UInt8) throws -> [UInt8] {
    if cyclesPower == directKeyCyclesPower {
      // The salt and then the password, cut or padded with zeros to 32 bytes.
      var key = [UInt8](repeating: 0, count: 32)
      for (index, byte) in (salt + password).prefix(32).enumerated() { key[index] = byte }
      return key
    }
    guard cyclesPower <= maximumCyclesPower else { throw ArchiveCodecError.unsupported }
    // The round input is the salt, the password and the counter. Only the counter changes, so
    // one buffer holds all of it and the counter bytes are rewritten in every round.
    var block = salt + password + [UInt8](repeating: 0, count: 8)
    let counterStart = block.count - 8
    var hash = SHA256()
    for round in 0..<(1 << Int(cyclesPower)) {
      for index in 0..<8 {
        block[counterStart + index] = UInt8(truncatingIfNeeded: round >> (8 * index))
      }
      block.withUnsafeBytes { hash.update(bufferPointer: $0) }
    }
    return Array(hash.finalize())
  }

  /// The UTF-16LE bytes of `text`, which 7-Zip hashes in place of the password.
  static func utf16LE(_ text: String) -> [UInt8] {
    text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
  }

  /// AES-256 in CBC mode without padding. The input must be a whole number of blocks.
  private static func decryptCBC(_ input: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
    guard !input.isEmpty else { return [] }
    var output = [UInt8](repeating: 0, count: input.count)
    let capacity = output.count
    var moved = 0
    let status = CCCrypt(
      CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
      key, key.count, iv, input, input.count, &output, capacity, &moved)
    guard status == kCCSuccess, moved == input.count else { throw ArchiveCodecError.malformed }
    return output
  }
}
