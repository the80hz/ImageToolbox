import Foundation

/// The traditional PKWARE zip encryption (APPNOTE section 6.1), which `zip -e` and many tools
/// still write. It is read only: the cipher is weak, and the writer offers WinZip AES instead.
///
/// The cipher keeps three 32-bit keys, seeded by the password and updated with every plain byte.
/// An entry starts with a 12-byte header whose last byte is a check of the password.
enum ZipCrypto {

  static let headerLength = 12

  private static let crcTable: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }

  private struct Keys {
    var first: UInt32 = 0x1234_5678
    var second: UInt32 = 0x2345_6789
    var third: UInt32 = 0x3456_7890

    init(password: [UInt8]) {
      for byte in password { update(byte) }
    }

    mutating func update(_ byte: UInt8) {
      first = ZipCrypto.crc(first, byte)
      second = (second &+ (first & 0xFF)) &* 134_775_813 &+ 1
      third = ZipCrypto.crc(third, UInt8(truncatingIfNeeded: second >> 24))
    }

    /// The next byte of the key stream.
    var streamByte: UInt8 {
      let temporary = UInt16(truncatingIfNeeded: third | 2)
      return UInt8(truncatingIfNeeded: (temporary &* (temporary ^ 1)) >> 8)
    }
  }

  private static func crc(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
    crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
  }

  /// The byte the last byte of the decrypted header must equal. It is the high byte of the
  /// modification time when the entry has a data descriptor (flag bit 3), else the high byte of
  /// the CRC-32.
  static func checkByte(crc: UInt32, modifiedTime: UInt16, hasDataDescriptor: Bool) -> UInt8 {
    hasDataDescriptor ? UInt8(modifiedTime >> 8) : UInt8(truncatingIfNeeded: crc >> 24)
  }

  /// The decrypted bytes after the header. The header check is one byte, so a wrong password
  /// passes it once in 256 times; the CRC-32 of the entry is the real test.
  /// - Throws: `ZipReader.PasswordFailure.wrongPassword` when the check byte does not match.
  static func decrypt(
    _ payload: UnsafeRawBufferPointer, password: [UInt8], checkByte: UInt8
  ) throws -> [UInt8] {
    guard payload.count >= headerLength else { throw ZipReader.Failure.malformed }
    var keys = Keys(password: password)
    var output = [UInt8](repeating: 0, count: payload.count - headerLength)
    var last: UInt8 = 0
    for index in 0..<payload.count {
      let plain = payload[index] ^ keys.streamByte
      keys.update(plain)
      if index < headerLength {
        last = plain
      } else {
        output[index - headerLength] = plain
      }
    }
    guard last == checkByte else { throw ZipReader.PasswordFailure.wrongPassword }
    return output
  }

  /// Whether the password passes the check byte of the header, which is the first 12 bytes.
  static func passwordMatches(
    header: UnsafeRawBufferPointer, password: [UInt8], checkByte: UInt8
  ) -> Bool {
    guard header.count >= headerLength else { return false }
    var keys = Keys(password: password)
    var last: UInt8 = 0
    for index in 0..<headerLength {
      last = header[index] ^ keys.streamByte
      keys.update(last)
    }
    return last == checkByte
  }
}
