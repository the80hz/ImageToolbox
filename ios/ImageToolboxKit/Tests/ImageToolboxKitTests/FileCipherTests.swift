import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Password-based file encryption")
struct FileCipherTests {

  private static let secret = Data("the picture bytes, or any file".utf8)
  private static let iterations = 1_000

  /// A version 1 file for AES-256-GCM, written by a separate implementation (hashlib PBKDF2 and the
  /// cryptography package) in the layout of the earlier release. The plaintext is
  /// "Version 1 fixture: the bytes of a file written by the earlier release.", the password
  /// "correct horse".
  private static let version1AES =
    "495443460101000003e8101112131415161718191a1b1c1d1e1fa0a1a2a3a4a5a6a7a8a9aaab1f2a79906a665b0391e6"
    + "6d7ff78472a56b327249727da7b62078f0bc86f1fdb955d55442159b623ac62a2679448e8464fcb1b6eb3da8cc527526"
    + "d01bcb3650b3af768042cec39a44d4aad26b4ce2750ef56494ac75f1"

  /// The same plaintext and password, ChaCha20-Poly1305, version 1.
  private static let version1ChaCha =
    "495443460102000003e8101112131415161718191a1b1c1d1e1fa0a1a2a3a4a5a6a7a8a9aaab66aaec7d39facb503982"
    + "9e49737a50dfb90e19da356fe3b4af2ccce63a120bbfd9271e26e90af71dca437fae23ee64fa2d167aea1612f121c03b"
    + "6da402b3d8f584ad4cc85fc169d7a57290a286da04d8691ee8ba8832"

  private static let version1Plaintext =
    "Version 1 fixture: the bytes of a file written by the earlier release."

  /// The offset of the salt. The header is magic (4), version (1), algorithm (1 in version 2, 2 in
  /// version 3), iterations (4) and then the salt.
  private static func saltOffset(_ file: [UInt8]) -> Int {
    file[4] == 3 ? 11 : 10
  }

  private func encrypted(
    _ algorithm: FileCipher.Algorithm = .aes256GCM,
    of data: Data = Self.secret
  ) throws -> Data {
    try FileCipher.encrypt(
      data, password: "correct horse", algorithm: algorithm, iterations: Self.iterations)
  }

  @Test("every algorithm decrypts what it encrypted", arguments: FileCipher.Algorithm.allCases)
  func roundTrip(algorithm: FileCipher.Algorithm) throws {
    let file = try encrypted(algorithm)
    #expect(try FileCipher.decrypt(file, password: "correct horse") == Self.secret)
  }

  @Test(
    "empty input round-trips with every algorithm but CTS, which needs one block of data",
    arguments: FileCipher.Algorithm.allCases.filter { $0.mode != .cts })
  func emptyInput(algorithm: FileCipher.Algorithm) throws {
    let file = try encrypted(algorithm, of: Data())
    #expect(try FileCipher.decrypt(file, password: "correct horse").isEmpty)
  }

  @Test(
    "the header holds the magic, the version, the algorithm id and the IV",
    arguments: FileCipher.Algorithm.allCases)
  func header(algorithm: FileCipher.Algorithm) throws {
    let file = [UInt8](try encrypted(algorithm))
    #expect(Array(file.prefix(4)) == Array("ITCF".utf8))
    let algorithmBytes: [UInt8]
    if let legacy = algorithm.legacyByte {
      #expect(file[4] == 2)
      algorithmBytes = [legacy]
    } else {
      #expect(file[4] == 3)
      algorithmBytes = [UInt8(algorithm.id >> 8), UInt8(algorithm.id & 0xFF)]
    }
    #expect(Array(file[5..<(5 + algorithmBytes.count)]) == algorithmBytes)
    let ivEnd = Self.saltOffset(file) + 16 + algorithm.ivLength
    #expect(file.count >= ivEnd + algorithm.trailerLength)
  }

  @Test("the algorithms added in version 3 are the ones with no one-byte id")
  func versionThreeAlgorithms() {
    for algorithm in FileCipher.Algorithm.allCases {
      let needsVersionThree = algorithm.family.rawValue > 24 || algorithm.mode.rawValue > 7
      #expect((algorithm.legacyByte == nil) == needsVersionThree, "\(algorithm.title)")
    }
    #expect(FileCipher.Algorithm(family: .aes, mode: .cfb8).legacyByte == nil)
    #expect(FileCipher.Algorithm(family: .aes, mode: .cbc).legacyByte == 0x08)
  }

  @Test("a wrong password is refused for every algorithm", arguments: FileCipher.Algorithm.allCases)
  func wrongPassword(algorithm: FileCipher.Algorithm) throws {
    let file = try encrypted(algorithm)
    #expect(throws: FileCipher.Failure.authenticationFailed) {
      try FileCipher.decrypt(file, password: "wrong horse")
    }
  }

  @Test(
    "a changed byte in the salt, the IV, the ciphertext or the tag is refused for every algorithm",
    arguments: FileCipher.Algorithm.allCases)
  func tampering(algorithm: FileCipher.Algorithm) throws {
    let file = [UInt8](try encrypted(algorithm))
    let saltStart = Self.saltOffset(file)
    let ivEnd = saltStart + 16 + algorithm.ivLength
    let positions = [
      saltStart,
      ivEnd - 1,
      ivEnd,
      file.count - 1,
    ]
    for position in positions {
      var changed = file
      changed[position] ^= 0x01
      #expect(
        throws: FileCipher.Failure.authenticationFailed,
        "byte \(position) of \(algorithm.title)"
      ) {
        try FileCipher.decrypt(Data(changed), password: "correct horse")
      }
    }
  }

  @Test("a changed iteration count is refused, because it changes the key")
  func changedIterations() throws {
    var file = [UInt8](try encrypted())
    file[9] ^= 0x01
    #expect(throws: FileCipher.Failure.authenticationFailed) {
      try FileCipher.decrypt(Data(file), password: "correct horse")
    }
  }

  @Test("an unknown algorithm id is unsupported")
  func unknownAlgorithm() throws {
    for id: UInt8 in [0x00, 0x07, 0x0F, 0xC0, 0xFF] {
      var file = [UInt8](try encrypted())
      file[5] = id
      #expect(throws: FileCipher.Failure.unsupported) {
        try FileCipher.decrypt(Data(file), password: "correct horse")
      }
    }
  }

  @Test("an unknown format version is unsupported")
  func unknownVersion() throws {
    for version: UInt8 in [0, 4, 255] {
      var file = [UInt8](try encrypted())
      file[4] = version
      #expect(throws: FileCipher.Failure.unsupported) {
        try FileCipher.decrypt(Data(file), password: "correct horse")
      }
    }
  }

  @Test("an iteration count of zero or above the maximum is unsupported")
  func iterationBounds() throws {
    for count: UInt32 in [0, UInt32(FileCipher.maximumIterations) + 1] {
      var file = [UInt8](try encrypted())
      file[6] = UInt8(count >> 24)
      file[7] = UInt8((count >> 16) & 0xFF)
      file[8] = UInt8((count >> 8) & 0xFF)
      file[9] = UInt8(count & 0xFF)
      #expect(throws: FileCipher.Failure.unsupported) {
        try FileCipher.decrypt(Data(file), password: "correct horse")
      }
    }
  }

  @Test("a version 1 file cannot use the algorithms that only version 2 has")
  func version1RejectsNewAlgorithms() throws {
    var file = [UInt8](try encrypted(.aes256GCM))
    file[4] = 1
    file[5] = FileCipher.Algorithm(family: .serpent, mode: .cbc).legacyByte ?? 0
    #expect(throws: FileCipher.Failure.unsupported) {
      try FileCipher.decrypt(Data(file), password: "correct horse")
    }
  }

  @Test("a version 2 file cannot name a family added after version 2")
  func version2RejectsLaterAlgorithms() throws {
    // Family 25 (Rijndael) has no one-byte id in version 2: a version 2 byte of 25 << 3 is refused.
    var file = [UInt8](try encrypted(.aes256GCM))
    file[5] = 25 << 3
    #expect(throws: FileCipher.Failure.unsupported) {
      try FileCipher.decrypt(Data(file), password: "correct horse")
    }
  }

  @Test("a version 3 file with an unknown family or mode is unsupported")
  func unknownVersionThreeAlgorithm() throws {
    let file = [UInt8](try encrypted(FileCipher.Algorithm(family: .aes, mode: .cfb8)))
    #expect(file[4] == 3)
    // Mode 12 is CTS, so 13 is the unused mode number here.
    for (family, mode) in [(0x00, 0x00), (0x01, 0x0D), (0x1D, 0x00), (0x17, 0x09)] {
      var changed = file
      changed[5] = UInt8(family)
      changed[6] = UInt8(mode)
      #expect(throws: FileCipher.Failure.unsupported) {
        try FileCipher.decrypt(Data(changed), password: "correct horse")
      }
    }
  }

  @Test("data without the container magic is not decrypted")
  func notEncrypted() {
    #expect(throws: FileCipher.Failure.notEncrypted) {
      try FileCipher.decrypt(Data(repeating: 0, count: 100), password: "pw")
    }
  }

  @Test("a file shorter than its header and tag is not decrypted")
  func truncated() throws {
    let file = try encrypted()
    #expect(throws: FileCipher.Failure.notEncrypted) {
      try FileCipher.decrypt(file.prefix(30), password: "correct horse")
    }
  }

  @Test(
    "each encryption uses a new salt and IV, so the output differs",
    arguments: [
      FileCipher.Algorithm.aes256GCM,
      FileCipher.Algorithm(family: .serpent, mode: .cfb),
    ])
  func freshRandomness(algorithm: FileCipher.Algorithm) throws {
    #expect(try encrypted(algorithm) != encrypted(algorithm))
  }

  @Test("version 1 AES-256-GCM files still decrypt")
  func version1AESDecrypts() throws {
    let file = try #require(Self.hexData(Self.version1AES))
    #expect(
      try Self.plaintextString(FileCipher.decrypt(file, password: "correct horse"))
        == Self.version1Plaintext)
  }

  @Test("version 1 ChaCha20-Poly1305 files still decrypt")
  func version1ChaChaDecrypts() throws {
    let file = try #require(Self.hexData(Self.version1ChaCha))
    #expect(
      try Self.plaintextString(FileCipher.decrypt(file, password: "correct horse"))
        == Self.version1Plaintext)
  }

  @Test("version 1 files refuse a wrong password and a changed byte")
  func version1Refusals() throws {
    let aes = try #require(Self.hexData(Self.version1AES))
    #expect(throws: FileCipher.Failure.authenticationFailed) {
      try FileCipher.decrypt(aes, password: "correct hors")
    }
    var changed = [UInt8](aes)
    changed[changed.count - 1] ^= 0x01
    #expect(throws: FileCipher.Failure.authenticationFailed) {
      try FileCipher.decrypt(Data(changed), password: "correct horse")
    }
  }

  @Test("the registry ids are unique and round-trip through id")
  func registry() {
    let ids = FileCipher.Algorithm.allCases.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(FileCipher.Algorithm.allCases.count > 150)
    for algorithm in FileCipher.Algorithm.allCases {
      #expect(FileCipher.Algorithm(id: algorithm.id) == algorithm)
    }
    #expect(FileCipher.Algorithm(id: 0) == nil)
    #expect(FileCipher.Algorithm.aes256GCM.title == "AES-256-GCM")
    #expect(FileCipher.Algorithm.chaCha20Poly1305.title == "ChaCha20-Poly1305")
  }

  @Test("the families and modes added last have the names of their standards")
  func newTitles() {
    #expect(FileCipher.Algorithm(family: .rijndael, mode: .cbc).title == "Rijndael-256-CBC")
    #expect(FileCipher.Algorithm(family: .threefish512, mode: .ctr).title == "Threefish-512-CTR")
    #expect(FileCipher.Algorithm(family: .threefish1024, mode: .ofb).title == "Threefish-1024-OFB")
    #expect(FileCipher.Algorithm(family: .tnepres, mode: .eax).title == "Tnepres-256-EAX")
    #expect(FileCipher.Algorithm(family: .aes, mode: .gcmSIV).title == "AES-256-GCM-SIV")
    #expect(FileCipher.Algorithm(family: .aes, mode: .ocb3).title == "AES-256-OCB3")
    #expect(FileCipher.Algorithm(family: .serpent, mode: .cfb8).title == "Serpent-256-CFB8")
  }

  @Test("only the AEAD modes have a 16-byte trailer, the other modes a 32-byte HMAC")
  func trailers() {
    for algorithm in FileCipher.Algorithm.allCases {
      let aead = [.gcm, .ccm, .chaCha20Poly1305, .eax, .ocb3, .gcmSIV].contains(algorithm.mode)
      #expect(algorithm.trailerLength == (aead ? 16 : 32), "\(algorithm.title)")
    }
  }

  @Test("the 128-bit block families offer EAX, OCB3 and CFB8, and the others do not")
  func modesByBlockSize() {
    for family in FileCipher.Family.allCases where family.blockSize == 16 && family != .rc4 {
      #expect(family.modes.contains(.eax), "\(family.title)")
      #expect(family.modes.contains(.ocb3), "\(family.title)")
      #expect(family.modes.contains(.cfb8), "\(family.title)")
    }
    for family in [FileCipher.Family.threefish256, .threefish512, .threefish1024, .idea] {
      #expect(!family.modes.contains(.eax), "\(family.title)")
      #expect(!family.modes.contains(.cfb8), "\(family.title)")
    }
  }

  @Test("GCM-SIV and CCM are offered for AES and its Rijndael name only")
  func aesOnlyModes() {
    for family in FileCipher.Family.allCases {
      let aesOnly = family == .aes || family == .rijndael
      #expect(family.modes.contains(.gcmSIV) == aesOnly, "\(family.title)")
      #expect(family.modes.contains(.ccm) == aesOnly, "\(family.title)")
    }
  }

  // MARK: - Helpers

  private static func hexData(_ text: String) -> Data? {
    let bytes = CipherTables.bytes(text)
    return bytes.isEmpty ? nil : Data(bytes)
  }

  private static func plaintextString(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }
}
