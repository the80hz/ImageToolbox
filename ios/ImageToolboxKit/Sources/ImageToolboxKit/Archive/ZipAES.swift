import CommonCrypto
import CryptoKit
import Foundation

/// WinZip AES encryption of zip entries (AE-1 and AE-2), as 7-Zip, WinZip and libarchive write it.
///
/// An encrypted entry has the compression method 99. The method actually used for the data sits in
/// the extra field 0x9901 (version, vendor "AE", strength, method). The entry data is:
///
///     salt | 2-byte password verifier | AES-CTR ciphertext | 10-byte authentication code
///
/// PBKDF2-HMAC-SHA1 with 1,000 iterations turns the password and the salt into an AES key, an
/// HMAC key of the same size and the verifier. The salt is 8, 12 or 16 bytes for AES-128, 192 or
/// 256. The cipher is AES in counter mode with a 16-byte little-endian counter that starts at 1,
/// which is built here from the AES block function in ECB mode. The authentication code is the
/// first 10 bytes of HMAC-SHA1 over the ciphertext.
public enum ZipAES {

  /// The AES key size, which also sets the salt size.
  public enum Strength: UInt8, CaseIterable, Sendable {
    case aes128 = 1
    case aes192 = 2
    case aes256 = 3

    /// Bytes in the AES key, and in the HMAC key.
    var keyLength: Int {
      switch self {
      case .aes128: 16
      case .aes192: 24
      case .aes256: 32
      }
    }

    /// 8, 12 or 16 bytes.
    var saltLength: Int { keyLength / 2 }
  }

  /// AE-1 keeps the CRC-32 of the plain data in the entry. AE-2 stores zero there, so the CRC
  /// does not reveal anything about a small file. Both are read and written.
  public enum Version: UInt16, CaseIterable, Sendable {
    case ae1 = 1
    case ae2 = 2
  }

  // MARK: - Format constants

  /// The compression method that marks a WinZip AES entry.
  static let methodMarker: UInt16 = 99
  static let extraFieldID: UInt16 = 0x9901
  static let iterations = 1000
  static let verifierLength = 2
  static let authenticationLength = 10
  /// Version 5.1 is the first to know AES encryption.
  static let versionNeeded: UInt16 = 51

  private static let vendor: [UInt8] = Array("AE".utf8)
  private static let blockLength = 16
  private static let blocksPerBatch = 4096

  /// The content of the 0x9901 extra field.
  struct Header: Equatable {
    var version: Version
    var strength: Strength
    /// The compression method of the data under the encryption.
    var method: UInt16

    /// The extra field with its id and size.
    var extraField: [UInt8] {
      var field: [UInt8] = []
      field.appendZipInteger(extraFieldID)
      field.appendZipInteger(UInt16(7))
      field.appendZipInteger(version.rawValue)
      field.append(contentsOf: vendor)
      field.append(strength.rawValue)
      field.appendZipInteger(method)
      return field
    }

    /// The header from the data of a 0x9901 field, or nil when it is not a known layout.
    init?(fieldData data: UnsafeRawBufferPointer) {
      guard data.count == 7 else { return nil }
      let reader = ZipByteReader(bytes: data)
      guard let rawVersion = try? reader.uint16(0), let version = Version(rawValue: rawVersion),
        data[2] == vendor[0], data[3] == vendor[1],
        let strength = Strength(rawValue: data[4]), let method = try? reader.uint16(5)
      else { return nil }
      self.version = version
      self.strength = strength
      self.method = method
    }

    init(version: Version, strength: Strength, method: UInt16) {
      self.version = version
      self.strength = strength
      self.method = method
    }
  }

  enum KeyFailure: Error {
    case derivationFailed
    case cipherFailed
  }

  // MARK: - Encryption

  /// `salt | verifier | ciphertext | authentication code` for the plain bytes.
  static func seal(
    _ plain: UnsafeRawBufferPointer, password: [UInt8], strength: Strength, salt: [UInt8]
  ) throws -> [UInt8] {
    precondition(salt.count == strength.saltLength, "The salt size must match the strength")
    let keys = try deriveKeys(password: password, salt: salt, strength: strength)
    let ciphertext = try applyKeyStream(key: keys.encryptionKey, to: plain)
    let code = ciphertext.withUnsafeBytes { authenticationCode(keys.authenticationKey, $0) }

    var output = salt
    output.reserveCapacity(salt.count + verifierLength + ciphertext.count + authenticationLength)
    output.append(contentsOf: keys.verifier)
    output.append(contentsOf: ciphertext)
    output.append(contentsOf: code)
    return output
  }

  /// A random salt of the size the strength needs.
  static func randomSalt(strength: Strength) -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    return (0..<strength.saltLength).map { _ in UInt8.random(in: 0...255, using: &generator) }
  }

  /// The plain bytes of `salt | verifier | ciphertext | authentication code`.
  /// - Throws: `ZipReader.PasswordFailure.wrongPassword` when the verifier does not match, and
  ///   `.authenticationFailed` when the authentication code does not match the ciphertext.
  static func open(
    _ payload: UnsafeRawBufferPointer, password: [UInt8], strength: Strength
  ) throws -> [UInt8] {
    let overhead = strength.saltLength + verifierLength + authenticationLength
    guard payload.count >= overhead else { throw ZipReader.Failure.malformed }
    let reader = ZipByteReader(bytes: payload)
    let salt = Array(try reader.slice(0, strength.saltLength))
    let verifier = Array(try reader.slice(strength.saltLength, verifierLength))
    let ciphertext = try reader.slice(
      strength.saltLength + verifierLength, payload.count - overhead)
    let code = Array(try reader.slice(payload.count - authenticationLength, authenticationLength))

    let keys = try deriveKeys(password: password, salt: salt, strength: strength)
    guard constantTimeEqual(verifier, keys.verifier) else {
      throw ZipReader.PasswordFailure.wrongPassword
    }
    guard constantTimeEqual(code, authenticationCode(keys.authenticationKey, ciphertext)) else {
      throw ZipReader.PasswordFailure.authenticationFailed
    }
    return try applyKeyStream(key: keys.encryptionKey, to: ciphertext)
  }

  // MARK: - Key derivation and authentication

  struct Keys {
    let encryptionKey: [UInt8]
    let authenticationKey: [UInt8]
    let verifier: [UInt8]
  }

  static func deriveKeys(password: [UInt8], salt: [UInt8], strength: Strength) throws -> Keys {
    let length = strength.keyLength
    guard
      let derived = PBKDF2.deriveKey(
        password: password, salt: salt, iterations: iterations,
        length: 2 * length + verifierLength)
    else { throw KeyFailure.derivationFailed }
    return Keys(
      encryptionKey: Array(derived[0..<length]),
      authenticationKey: Array(derived[length..<(2 * length)]),
      verifier: Array(derived[(2 * length)...]))
  }

  /// The first 10 bytes of HMAC-SHA1 over the ciphertext.
  static func authenticationCode(_ key: [UInt8], _ ciphertext: UnsafeRawBufferPointer) -> [UInt8] {
    var mac = HMAC<Insecure.SHA1>(key: SymmetricKey(data: key))
    mac.update(data: ciphertext)
    return Array(Data(mac.finalize()).prefix(authenticationLength))
  }

  private static func constantTimeEqual(_ first: [UInt8], _ second: [UInt8]) -> Bool {
    guard first.count == second.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(first, second) { difference |= left ^ right }
    return difference == 0
  }

  // MARK: - AES

  /// One block through AES in ECB mode. The key is 16, 24 or 32 bytes.
  static func encryptBlock(_ block: [UInt8], key: [UInt8]) throws -> [UInt8] {
    precondition(block.count == blockLength, "An AES block is 16 bytes")
    return try encryptBlocks(block, key: key)
  }

  /// A multiple of 16 bytes through AES in ECB mode, each block on its own.
  private static func encryptBlocks(_ blocks: [UInt8], key: [UInt8]) throws -> [UInt8] {
    let length = blocks.count
    var output = [UInt8](repeating: 0, count: length)
    var moved = 0
    let status = CCCrypt(
      CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
      key, key.count, nil, blocks, length, &output, length, &moved)
    guard status == kCCSuccess, moved == length else { throw KeyFailure.cipherFailed }
    return output
  }

  /// The input XOR the key stream: the AES encryptions of the counter blocks 1, 2, 3 and so on.
  /// The counter is little endian, which is where WinZip differs from the usual CTR mode.
  /// Encrypting and decrypting are the same operation.
  static func applyKeyStream(key: [UInt8], to input: UnsafeRawBufferPointer) throws -> [UInt8] {
    var output = [UInt8](repeating: 0, count: input.count)
    var counter: UInt64 = 1
    var position = 0
    while position < input.count {
      let length = min(blocksPerBatch * blockLength, input.count - position)
      let blocks = (length + blockLength - 1) / blockLength
      var counterBlocks = [UInt8](repeating: 0, count: blocks * blockLength)
      for block in 0..<blocks {
        var value = counter
        for index in 0..<8 {
          counterBlocks[block * blockLength + index] = UInt8(truncatingIfNeeded: value)
          value >>= 8
        }
        counter += 1
      }
      let keyStream = try encryptBlocks(counterBlocks, key: key)
      output.withUnsafeMutableBufferPointer { destination in
        for index in 0..<length {
          destination[position + index] = input[position + index] ^ keyStream[index]
        }
      }
      position += length
    }
    return output
  }
}
