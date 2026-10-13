import CryptoKit
import Foundation
import Testing

@testable import ImageToolboxKit

private func hex(_ bytes: [UInt8]) -> String {
  bytes.map { String(format: "%02x", $0) }.joined()
}

private func bytes(hex text: String) -> [UInt8] {
  stride(from: 0, to: text.count, by: 2).map { index in
    let start = text.index(text.startIndex, offsetBy: index)
    return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
  }
}

@Suite("WinZip AES primitives")
struct ZipAESPrimitiveTests {

  @Test(
    "PBKDF2-HMAC-SHA1 gives the RFC 6070 test vectors",
    arguments: [
      ("password", "salt", 1, 20, "0c60c80f961f0e71f3a9b524af6012062fe037a6"),
      ("password", "salt", 2, 20, "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"),
      ("password", "salt", 4096, 20, "4b007901b765489abead49d926f721d065a429c1"),
      (
        "passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 25,
        "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038"
      ),
    ])
  func rfc6070(password: String, salt: String, iterations: Int, length: Int, expected: String) {
    let key = PBKDF2.deriveKey(
      password: Array(password.utf8), salt: Array(salt.utf8), iterations: iterations,
      length: length)
    #expect(key.map(hex) == expected)
  }

  @Test("PBKDF2 keeps NUL bytes of the password and the salt")
  func rfc6070NulBytes() {
    let key = PBKDF2.deriveKey(
      password: Array("pass\0word".utf8), salt: Array("sa\0lt".utf8), iterations: 4096,
      length: 16)
    #expect(key.map(hex) == "56fa6aa75548099dcc37d7f03425e0c3")
  }

  @Test("PBKDF2 refuses an empty request")
  func pbkdf2Parameters() {
    #expect(PBKDF2.deriveKey(password: [1], salt: [1], iterations: 0, length: 16) == nil)
    #expect(PBKDF2.deriveKey(password: [1], salt: [1], iterations: 1, length: 0) == nil)
  }

  @Test(
    "the AES block function gives the FIPS-197 example vectors",
    arguments: [
      (16, "69c4e0d86a7b0430d8cdb78070b4c55a"),
      (24, "dda97ca4864cdfe06eaf70a0ec0d7191"),
      (32, "8ea2b7ca516745bfeafc49904b496089"),
    ])
  func fips197(keyLength: Int, expected: String) throws {
    let key = (0..<keyLength).map { UInt8($0) }
    let plain = bytes(hex: "00112233445566778899aabbccddeeff")
    #expect(hex(try ZipAES.encryptBlock(plain, key: key)) == expected)
  }

  @Test("the authentication code is the first 10 bytes of HMAC-SHA1 (RFC 2202 vectors)")
  func authenticationCodeVectors() {
    let vectors: [([UInt8], [UInt8], String)] = [
      ([UInt8](repeating: 0x0B, count: 20), Array("Hi There".utf8), "b617318655057264e28b"),
      (Array("Jefe".utf8), Array("what do ya want for nothing?".utf8), "effcdf6ae5eb2fa2d274"),
      (
        [UInt8](repeating: 0xAA, count: 20), [UInt8](repeating: 0xDD, count: 50),
        "125d7342b9ac11cd91a3"
      ),
    ]
    for (key, message, expected) in vectors {
      let code = message.withUnsafeBytes { ZipAES.authenticationCode(key, $0) }
      #expect(hex(code) == expected)
    }
  }

  @Test("the key stream is AES of a little-endian counter that starts at 1")
  func keyStreamCounter() throws {
    let key = (0..<16).map { UInt8($0 + 1) }
    // 300 blocks of zero bytes give the key stream itself, across a carry from byte 0 to byte 1.
    let zeros = [UInt8](repeating: 0, count: 300 * 16)
    let stream = try zeros.withUnsafeBytes { try ZipAES.applyKeyStream(key: key, to: $0) }

    func block(_ counter: Int) throws -> [UInt8] {
      var input = [UInt8](repeating: 0, count: 16)
      input[0] = UInt8(counter & 0xFF)
      input[1] = UInt8(counter >> 8)
      return try ZipAES.encryptBlock(input, key: key)
    }
    #expect(Array(stream[0..<16]) == (try block(1)))
    #expect(Array(stream[16..<32]) == (try block(2)))
    // Counter 255 is the 255th block, and counter 256 carries into the second byte.
    #expect(Array(stream[(254 * 16)..<(255 * 16)]) == (try block(255)))
    #expect(Array(stream[(255 * 16)..<(256 * 16)]) == (try block(256)))
    #expect(Array(stream[(299 * 16)...]) == (try block(300)))
  }

  @Test("a short input uses a part of the last key stream block")
  func keyStreamPartialBlock() throws {
    let key = [UInt8](repeating: 7, count: 32)
    let input: [UInt8] = Array(1...21)
    let output = try input.withUnsafeBytes { try ZipAES.applyKeyStream(key: key, to: $0) }
    let again = try output.withUnsafeBytes { try ZipAES.applyKeyStream(key: key, to: $0) }
    #expect(output.count == 21)
    #expect(output != input)
    #expect(again == input)
  }

  @Test("the strengths set the key and salt sizes")
  func strengthSizes() {
    #expect(ZipAES.Strength.aes128.keyLength == 16 && ZipAES.Strength.aes128.saltLength == 8)
    #expect(ZipAES.Strength.aes192.keyLength == 24 && ZipAES.Strength.aes192.saltLength == 12)
    #expect(ZipAES.Strength.aes256.keyLength == 32 && ZipAES.Strength.aes256.saltLength == 16)
  }

  @Test("the 0x9901 extra field has the layout of the WinZip specification")
  func extraFieldLayout() throws {
    let header = ZipAES.Header(version: .ae2, strength: .aes256, method: 8)
    #expect(
      header.extraField == [0x01, 0x99, 0x07, 0x00, 0x02, 0x00, 0x41, 0x45, 0x03, 0x08, 0x00])

    let field = Array(header.extraField.dropFirst(4))
    let parsed = field.withUnsafeBytes { ZipAES.Header(fieldData: $0) }
    #expect(parsed == header)

    let wrongVendor: [UInt8] = [0x01, 0x00, 0x41, 0x46, 0x03, 0x08, 0x00]
    #expect(wrongVendor.withUnsafeBytes { ZipAES.Header(fieldData: $0) } == nil)
    let wrongStrength: [UInt8] = [0x01, 0x00, 0x41, 0x45, 0x04, 0x08, 0x00]
    #expect(wrongStrength.withUnsafeBytes { ZipAES.Header(fieldData: $0) } == nil)
    let wrongVersion: [UInt8] = [0x03, 0x00, 0x41, 0x45, 0x03, 0x08, 0x00]
    #expect(wrongVersion.withUnsafeBytes { ZipAES.Header(fieldData: $0) } == nil)
  }
}

@Suite("WinZip AES in zip archives")
struct ZipAESArchiveTests {

  /// `bsdtar --format zip --options zip:encryption=aes256 --passphrase secret` (libarchive 3.7.4,
  /// the library the Android app uses): `a.txt` is 48 bytes, deflated, AE-1; `b.txt` is "x",
  /// deflated, AE-2. Both carry a data descriptor.
  static let libarchive256 = ZipTools.data(
    base64: """
      UEsDBBQACQBjAA9ySV0AAAAAAAAAAAAAAAAFACsAYS50eHR1eAsAAQT1AQAABAAAAAABmQcAAQBBRQMIAFVUDQAH/77I
      agC/yGr/vshqHevjPO+QS49umdYerDEzWBYjmrv5j8vrha94nN0hDcCFHt9nn2c/ugm+nI9BFtLYmwBQSwcIWtWXxjIA
      AAAwAAAAUEsDBBQACQBjAA9ySV0AAAAAAAAAAAAAAAAFACsAYi50eHR1eAsAAQT1AQAABAAAAAABmQcAAgBBRQMIAFVU
      DQAH/77IagC/yGr/vshqPu6KTORBRhs0iO2AwWtHyqWe+hQsk175iGu/vtiSPVBLBwgAAAAAHwAAAAEAAABQSwECFAMU
      AAkAYwAPckldWtWXxjIAAAAwAAAABQAjAAAAAAAAAAAApIEAAAAAYS50eHR1eAsAAQT1AQAABAAAAAABmQcAAQBBRQMI
      AFVUBQAB/77IalBLAQIUAxQACQBjAA9ySV0AAAAAHwAAAAEAAAAFACMAAAAAAAAAAACkgZAAAABiLnR4dHV4CwABBPUB
      AAAEAAAAAAGZBwACAEFFAwgAVVQFAAH/vshqUEsFBgAAAAACAAIArAAAAA0BAAAAAA==
      """)

  /// The same tool with `zip:encryption=aes128,zip:compression=store`: `c.txt` is "abc", AE-2.
  static let libarchive128 = ZipTools.data(
    base64: """
      UEsDBBQACQBjAOpzSV0AAAAAAAAAAAAAAAAFACsAYy50eHR1eAsAAQT1AQAABAAAAAABmQcAAgBBRQEAAFVUDQAHecLI
      annCyGp5wshqFocHBDb8zFHM3LzNHXZ83MkN38wxaIJQSwcIAAAAABcAAAADAAAAUEsBAhQDFAAJAGMA6nNJXQAAAAAX
      AAAAAwAAAAUAIwAAAAAAAAAAAKSBAAAAAGMudHh0dXgLAAEE9QEAAAQAAAAAAZkHAAIAQUUBAABVVAUAAXnCyGpQSwUG
      AAAAAAEAAQBWAAAAdQAAAAAA
      """)

  static let aText = Data("hello aes world hello aes world hello aes world\n".utf8)

  /// Text that deflates, noise that does not, an empty file and a short one.
  static func sampleEntries() -> [ZipWriter.Entry] {
    var generator = SeededGenerator(seed: 11)
    let noise = Data((0..<700).map { _ in UInt8.random(in: 0...255, using: &generator) })
    return [
      ZipWriter.Entry(
        name: "docs/text.txt", data: Data(String(repeating: "zip aes ", count: 200).utf8)),
      ZipWriter.Entry(name: "noise.bin", data: noise),
      ZipWriter.Entry(name: "empty.txt", data: Data()),
      ZipWriter.Entry(name: "short.txt", data: Data("tiny".utf8)),
    ]
  }

  // MARK: - Archives from libarchive

  @Test("a libarchive AES-256 archive is decrypted, AE-1 and AE-2")
  func readsLibarchive256() throws {
    let entries = try ZipReader.entries(in: Self.libarchive256, password: "secret") { _ in true }
    #expect(
      entries == [
        ZipReader.Entry(name: "a.txt", data: Self.aText),
        ZipReader.Entry(name: "b.txt", data: Data("x".utf8)),
      ])
  }

  @Test("a libarchive AES-128 archive with stored data is decrypted")
  func readsLibarchive128() throws {
    let entries = try ZipReader.entries(in: Self.libarchive128, password: "secret") { _ in true }
    #expect(entries == [ZipReader.Entry(name: "c.txt", data: Data("abc".utf8))])
  }

  @Test("an encrypted entry needs the password, and the wrong one is told apart")
  func passwordFailures() {
    #expect(throws: ZipReader.PasswordFailure.passwordRequired) {
      try ZipReader.entries(in: Self.libarchive256) { _ in true }
    }
    #expect(throws: ZipReader.PasswordFailure.passwordRequired) {
      try ZipReader.entries(in: Self.libarchive256, password: "") { _ in true }
    }
    #expect(throws: ZipReader.PasswordFailure.wrongPassword) {
      try ZipReader.entries(in: Self.libarchive256, password: "Secret") { _ in true }
    }
    #expect(throws: ZipReader.PasswordFailure.wrongPassword) {
      try ZipReader.entries(in: Self.libarchive128, password: "secrets") { _ in true }
    }
  }

  @Test("the include filter skips encrypted entries without needing a password")
  func filterSkipsEncrypted() throws {
    let entries = try ZipReader.entries(in: Self.libarchive256) { _ in false }
    #expect(entries.isEmpty)
  }

  @Test("the encryption status, the listing and the password check read the directory")
  func statusAndListing() throws {
    #expect(try ZipReader.encryptionStatus(of: Self.libarchive256) == .passwordRequired)
    #expect(try ZipReader.encryptionStatus(of: ZipReaderTests.storedArchive) == .none)
    #expect(try ZipReader.isPasswordCorrect("secret", in: Self.libarchive256))
    #expect(try ZipReader.isPasswordCorrect("secret", in: Self.libarchive128))
    #expect(try !ZipReader.isPasswordCorrect("Secret", in: Self.libarchive256))
    #expect(try !ZipReader.isPasswordCorrect("", in: Self.libarchive256))
    #expect(try ZipReader.isPasswordCorrect("anything", in: ZipReaderTests.storedArchive))

    let list = try ZipReader.list(in: Self.libarchive256)
    #expect(list.map(\.name) == ["a.txt", "b.txt"])
    #expect(list.map(\.uncompressedSize) == [48, 1])
    #expect(list.allSatisfy { $0.isEncrypted && !$0.isDirectory })
    // 16 bytes of salt, 2 of verifier, 10 of authentication code around the deflated data.
    #expect(list[0].compressedSize == 0x32)
    #expect(try ZipReader.list(in: ZipReaderTests.storedArchive).allSatisfy { !$0.isEncrypted })
  }

  // MARK: - Round trips

  @Test(
    "every strength and version round-trips",
    arguments: ZipAES.Strength.allCases, [ZipAES.Version.ae1, .ae2, nil])
  func roundTrip(strength: ZipAES.Strength, version: ZipAES.Version?) throws {
    let entries = Self.sampleEntries()
    let options = ZipWriter.Options(
      password: "pässwörd 密码", strength: strength, aesVersion: version)
    let archive = try ZipWriter.archive(entries, options: options)
    let read = try ZipReader.entries(in: archive, password: "pässwörd 密码") { _ in true }
    #expect(read.map(\.name) == entries.map(\.name))
    #expect(read.map(\.data) == entries.map(\.data))
  }

  @Test("data longer than one key stream batch round-trips")
  func longData() throws {
    var generator = SeededGenerator(seed: 5)
    let data = Data((0..<200_003).map { _ in UInt8.random(in: 0...255, using: &generator) })
    let archive = try ZipWriter.archive(
      [ZipWriter.Entry(name: "big.bin", data: data)],
      options: ZipWriter.Options(password: "long", strength: .aes192))
    let read = try ZipReader.entries(
      in: archive, password: "long", maximumEntries: 10, maximumEntrySize: 1 << 20
    ) { _ in true }
    #expect(read.first?.data == data)
  }

  @Test("the writer keeps the entry in the layout of the WinZip specification")
  func layout() throws {
    let entries = Self.sampleEntries()
    for strength in ZipAES.Strength.allCases {
      let options = ZipWriter.Options(password: "layout", strength: strength)
      let archive = try ZipWriter.archive(entries, options: options)
      let layout = ZipLayout(archive)
      #expect(layout.records.count == entries.count)

      for (record, entry) in zip(layout.records, entries) {
        #expect(record.method == 99)
        #expect(record.flags & 0x0001 != 0)
        #expect(record.versionNeeded == 51)
        let field = try #require(record.extraFields[0x9901])
        #expect(field.count == 7)
        let version: UInt16 = entry.data.count < 20 ? 2 : 1
        #expect(field[0] == UInt8(version) && field[1] == 0)
        #expect(Array(field[2...3]) == Array("AE".utf8))
        #expect(field[4] == strength.rawValue)
        // The real method: deflate for text, stored for noise, empty and tiny data.
        let compressible = entry.name == "docs/text.txt"
        #expect(field[5] == (compressible ? 8 : 0) && field[6] == 0)
        #expect(record.crc == (version == 2 ? 0 : CRC32.checksum(entry.data)))

        // Decrypt the payload by hand: salt, verifier, ciphertext, 10-byte code.
        let payload = Self.payload(of: record, in: archive)
        let plain = try Self.decryptBySpecification(payload, password: "layout", strength: strength)
        if compressible {
          #expect(plain.count < entry.data.count)
        } else {
          #expect(Data(plain) == entry.data)
        }
      }
    }
  }

  /// The payload of an entry: found through the local header, as any reader does.
  static func payload(of record: ZipRecord, in archive: Data) -> [UInt8] {
    let bytes = [UInt8](archive)
    let offset = Int(record.localOffset32)
    let nameLength = Int(bytes[offset + 26]) | Int(bytes[offset + 27]) << 8
    let extraLength = Int(bytes[offset + 28]) | Int(bytes[offset + 29]) << 8
    let start = offset + 30 + nameLength + extraLength
    return Array(bytes[start..<(start + Int(record.compressedSize32))])
  }

  /// A second implementation of the specification, one block at a time, to check the layout the
  /// writer produces against something other than the reader.
  static func decryptBySpecification(
    _ payload: [UInt8], password: String, strength: ZipAES.Strength
  ) throws -> [UInt8] {
    let keyLength = strength.keyLength
    let saltLength = keyLength / 2
    let salt = Array(payload[0..<saltLength])
    let verifier = Array(payload[saltLength..<(saltLength + 2)])
    let ciphertext = Array(payload[(saltLength + 2)..<(payload.count - 10)])
    let code = Array(payload[(payload.count - 10)...])

    let derived = try #require(
      PBKDF2.deriveKey(
        password: Array(password.utf8), salt: salt, iterations: 1000, length: 2 * keyLength + 2))
    let aesKey = Array(derived[0..<keyLength])
    let macKey = Array(derived[keyLength..<(2 * keyLength)])
    #expect(Array(derived[(2 * keyLength)...]) == verifier)

    let mac = HMAC<Insecure.SHA1>.authenticationCode(
      for: Data(ciphertext), using: SymmetricKey(data: macKey))
    #expect(Array(Data(mac).prefix(10)) == code)

    var plain: [UInt8] = []
    for (index, start) in stride(from: 0, to: ciphertext.count, by: 16).enumerated() {
      var counter = [UInt8](repeating: 0, count: 16)
      var value = index + 1
      for position in 0..<4 {
        counter[position] = UInt8(value & 0xFF)
        value >>= 8
      }
      let stream = try ZipAES.encryptBlock(counter, key: aesKey)
      let chunk = ciphertext[start..<min(start + 16, ciphertext.count)]
      plain += zip(chunk, stream).map { $0 ^ $1 }
    }
    return plain
  }

  // MARK: - Tampering

  private static func encryptedArchive() throws -> (archive: Data, record: ZipRecord) {
    let archive = try ZipWriter.archive(
      [
        ZipWriter.Entry(
          name: "secret.txt", data: Data(String(repeating: "secret ", count: 40).utf8))
      ],
      options: ZipWriter.Options(password: "pw", strength: .aes256))
    return (archive, ZipLayout(archive).records[0])
  }

  private static func changed(_ archive: Data, at position: Int) -> Data {
    var copy = archive
    copy[copy.startIndex + position] ^= 0x01
    return copy
  }

  @Test("changed ciphertext or authentication code fails the authentication")
  func tamperedData() throws {
    let (archive, record) = try Self.encryptedArchive()
    // The local header holds the 0x9901 field of 11 bytes after the name.
    let payloadStart = Int(record.localOffset32) + 30 + record.name.utf8.count + 11
    let size = Int(record.compressedSize32)

    for position in [payloadStart + 16 + 2, payloadStart + size - 11, payloadStart + size - 1] {
      let broken = Self.changed(archive, at: position)
      #expect(throws: ZipReader.PasswordFailure.authenticationFailed) {
        try ZipReader.entries(in: broken, password: "pw") { _ in true }
      }
    }
  }

  @Test("a changed verifier reads as a wrong password, and a changed salt fails too")
  func tamperedHeader() throws {
    let (archive, record) = try Self.encryptedArchive()
    let payloadStart = Int(record.localOffset32) + 30 + record.name.utf8.count + 11

    let verifier = Self.changed(archive, at: payloadStart + 16)
    #expect(throws: ZipReader.PasswordFailure.wrongPassword) {
      try ZipReader.entries(in: verifier, password: "pw") { _ in true }
    }
    let salt = Self.changed(archive, at: payloadStart)
    do {
      _ = try ZipReader.entries(in: salt, password: "pw") { _ in true }
      Issue.record("A changed salt must not decrypt")
    } catch let failure as ZipReader.PasswordFailure {
      #expect(failure == .wrongPassword || failure == .authenticationFailed)
    }
    // The untouched archive still reads.
    let entries = try ZipReader.entries(in: archive, password: "pw") { _ in true }
    #expect(entries.count == 1)
  }

  @Test("a payload too short for its own overhead is malformed")
  func shortPayload() throws {
    let (archive, record) = try Self.encryptedArchive()
    var short = archive
    // Cut the compressed size in the central record down to 10 bytes.
    let layout = ZipLayout(archive)
    #expect(layout.records.count == 1)
    let directory = Int(layout.directoryOffset32)
    short.replaceSubrange((directory + 20)..<(directory + 24), with: [10, 0, 0, 0])
    #expect(record.compressedSize32 > 10)
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: short, password: "pw") { _ in true }
    }
  }

  // MARK: - Other tools

  @Test("libarchive reads the archives written here with the password")
  func libarchiveReadsOurArchives() throws {
    let entries = Self.sampleEntries()
    for strength in ZipAES.Strength.allCases {
      for version in [ZipAES.Version.ae1, .ae2] {
        let archive = try ZipWriter.archive(
          entries,
          options: ZipWriter.Options(
            password: "cross check", strength: strength, aesVersion: version))
        for entry in entries where !entry.name.hasSuffix("/") {
          let result = try ZipTools.bsdtarExtract(
            archive, entry: entry.name, password: "cross check")
          #expect(result.status == 0, "\(strength) \(version) \(entry.name)")
          #expect(result.data == entry.data, "\(strength) \(version) \(entry.name)")
        }
        let wrong = try ZipTools.bsdtarExtract(archive, entry: "short.txt", password: "other")
        #expect(wrong.status != 0)
      }
    }
  }

  @Test("an empty password writes a plain archive")
  func emptyPasswordIsPlain() throws {
    let entries = Self.sampleEntries()
    let plain = try ZipWriter.archive(entries)
    #expect(try ZipWriter.archive(entries, options: ZipWriter.Options(password: "")) == plain)
    #expect(try ZipReader.encryptionStatus(of: plain) == .none)
  }

  @Test("the stored option keeps the data as it is under the encryption")
  func storedOption() throws {
    let text = Data(String(repeating: "abc", count: 300).utf8)
    let deflated = try ZipWriter.archive(
      [ZipWriter.Entry(name: "a.txt", data: text)], options: ZipWriter.Options(password: "pw"))
    let stored = try ZipWriter.archive(
      [ZipWriter.Entry(name: "a.txt", data: text)],
      options: ZipWriter.Options(method: .stored, password: "pw"))
    #expect(stored.count > deflated.count + 700)
    let record = ZipLayout(stored).records[0]
    #expect(record.extraFields[0x9901]?[5] == 0)
    let entries = try ZipReader.entries(in: stored, password: "pw") { _ in true }
    #expect(entries.first?.data == text)
  }
}
