import Foundation
import Testing

@testable import ImageToolboxKit

// The vectors were made outside the code under test: the key with Python's hashlib, the data with
// the lzma module (raw LZMA2) and the AES encryption with the openssl command line, and the 7z
// headers by a script of the same kind. Each archive holds `secret.txt` in one folder, LZMA2 fed by
// 7zAES, under the password "p\u{e4}ssword" with 2^6 rounds of the key derivation. The second
// vector also packs its header with 7zAES, so the names are hidden until the password is given.
@Suite("7z archives encrypted with 7zAES")
struct SevenZipAESTests {

  private typealias Entry = SevenZipArchive.Entry
  private typealias PasswordFailure = SevenZipArchive.PasswordFailure

  private static let password = "p\u{e4}ssword"
  private static let secret = Data(
    ("The 7zAES vector was made with Python hashlib, lzma and OpenSSL, "
      + "not with the code under test.\n").utf8)

  /// The archive with a plain header.
  private static let plainHeader = archiveVector(
    """
    N3q8ryccAAQZGYf3cAAAAAAAAABjAAAAAAAAAI42iD/W4vVxtH4m9qb28tyGhoyg0ybrZwF5i1/D
    ziGL+yR1kZKSe46MddrdoS04vUtpv73F8Q/la7GAj9SpX/rNIoPy0+WnY8p5ms5UIztZ5ByGna6q
    2dmOQm+d700lPVMaWNldpQCuqUha308GBtz+Xa85AQQGAAEJcAAHCwEAAiEhARgkBvEHASLG/wAB
    AgMEBQYHCAkKCwwNDg+goaKjpKWmp6ipqqusra6vAAEMX2MKAZX9TzgAAAUBERcAcwBlAGMAcgBl
    AHQALgB0AHgAdAAAAAAA
    """)

  /// The archive whose header is encrypted too.
  private static let encryptedHeader = archiveVector(
    """
    N3q8ryccAAQ2m+ez4AAAAAAAAABFAAAAAAAAAP31oOPW4vVxtH4m9qb28tyGhoyg0ybrZwF5i1/D
    ziGL+yR1kZKSe46MddrdoS04vUtpv73F8Q/la7GAj9SpX/rNIoPy0+WnY8p5ms5UIztZ5ByGna6q
    2dmOQm+d700lPVMaWNldpQCuqUha308GBtz+Xa85TA8myGL8C5h0r5wLrnX37IQT8KNQL6DpaRQ4
    nayu7LDKBPME5Mtugv6QayAHFfn4yX/Amhlu34sD69RqK0C9ikDEcc6PPbU15etlR/cmqw23yrBf
    sCVVzb5IyZtBMjPB+Itbgekq1F0/Jkgv+a9XnxcGcAEJcAAHCwEAAiEhARgkBvEHASLG/wABAgME
    BQYHCAkKCwwNDg+goaKjpKWmp6ipqqusra6vAAEMY2UKAY42iD8AAA==
    """)

  /// The key for the salt 0...15 and the password, from Python with 2^6 rounds.
  private static let referenceKey =
    "b53d5060a5652113b7090652e28b2bd3605c0fa6bbbca1734cb15bfb1085a199"

  private static func hexBytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map { offset in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
  }

  @Test("the key is the SHA-256 chain that 7-Zip computes")
  func keyDerivation() throws {
    let salt = (0..<16).map { UInt8($0) }
    let key = try SevenZipAES.deriveKey(
      salt: salt, password: SevenZipAES.utf16LE(Self.password), cyclesPower: 6)
    #expect(key == Self.hexBytes(Self.referenceKey))
  }

  @Test("a cycle power of 0x3F takes the salt and the password as the key, padded to 32 bytes")
  func directKey() throws {
    let key = try SevenZipAES.deriveKey(salt: [1, 2], password: [3, 4], cyclesPower: 0x3F)
    #expect(key == [1, 2, 3, 4] + [UInt8](repeating: 0, count: 28))
  }

  @Test("the password is hashed as UTF-16LE")
  func passwordEncoding() {
    #expect(SevenZipAES.utf16LE("A\u{e4}") == [0x41, 0x00, 0xE4, 0x00])
  }

  @Test("an archive with an encrypted folder is read with its password")
  func decryptsFolder() throws {
    let entries = try SevenZipArchive.entries(in: Self.plainHeader, password: Self.password)
    #expect(entries == [Entry(name: "secret.txt", data: Self.secret)])
  }

  @Test("an archive with an encrypted header is read with its password")
  func decryptsHeader() throws {
    let entries = try SevenZipArchive.entries(in: Self.encryptedHeader, password: Self.password)
    #expect(entries == [Entry(name: "secret.txt", data: Self.secret)])
  }

  @Test("without a password, encrypted data and an encrypted header are refused as such")
  func passwordRequired() {
    for archive in [Self.plainHeader, Self.encryptedHeader] {
      #expect(throws: PasswordFailure.passwordRequired) {
        try SevenZipArchive.entries(in: archive)
      }
      // An empty password is no password.
      #expect(throws: PasswordFailure.passwordRequired) {
        try SevenZipArchive.entries(in: archive, password: "")
      }
    }
  }

  @Test("a wrong password fails the checksum and is refused")
  func wrongPassword() {
    for archive in [Self.plainHeader, Self.encryptedHeader] {
      #expect(throws: PasswordFailure.wrongPassword) {
        try SevenZipArchive.entries(in: archive, password: "password")
      }
    }
  }

  @Test("damaged encrypted data is refused with the same message as a wrong password")
  func damagedData() throws {
    var copy = [UInt8](Self.plainHeader)
    copy[40] ^= 0x04
    #expect(throws: PasswordFailure.wrongPassword) {
      try SevenZipArchive.entries(in: Data(copy), password: Self.password)
    }
  }

  @Test("properties and input that do not fit the coder are refused as malformed")
  func malformedCoder() throws {
    let salt = [UInt8](repeating: 1, count: 16)
    let iv = [UInt8](repeating: 2, count: 16)
    let properties = [0xC6, 0xFF] + salt + iv
    let block = [UInt8](repeating: 0, count: 32)
    // A properties block that is cut short.
    #expect(throws: ArchiveCodecError.malformed) {
      try SevenZipAES.decrypt(block, properties: [0xC6], password: "x")
    }
    // Input that is not a whole number of AES blocks.
    #expect(throws: ArchiveCodecError.malformed) {
      try SevenZipAES.decrypt(
        [UInt8](repeating: 0, count: 31), properties: properties, password: "x")
    }
    // Rounds beyond the limit are refused before any hashing.
    #expect(throws: ArchiveCodecError.unsupported) {
      try SevenZipAES.decrypt(block, properties: [0xC0 | 25, 0xFF] + salt + iv, password: "x")
    }
  }
}
