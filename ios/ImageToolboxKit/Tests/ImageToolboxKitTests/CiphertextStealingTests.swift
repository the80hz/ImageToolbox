import Foundation
import Testing

@testable import ImageToolboxKit

/// CBC-CS3 (NIST SP 800-38A addendum, October 2010). The addendum prints no example vectors, so
/// these tests check the structure its steps define. For a whole last block, the output is CBC
/// with the last two blocks swapped. For a partial last block, it is CBC of the zero-padded input,
/// with the penultimate block cut to the length of the last one and the same swap. CBC itself is
/// covered by the SP 800-38A tests in BlockCipherVectorTests. The file tests go through FileCipher.
@Suite("CBC ciphertext stealing, CBC-CS3")
struct CiphertextStealingTests {

  private static let key128: [UInt8] = (0..<16).map { UInt8(0x20 &+ $0) }
  private static let key256: [UInt8] = (0..<32).map { UInt8(0x60 &+ $0) }
  private static let iv: [UInt8] = (0..<16).map { UInt8(0x10 &+ $0) }

  private static func bytes(_ count: Int) -> [UInt8] {
    (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
  }

  @Test("a single block is encrypted as CBC encrypts it")
  func singleBlock() throws {
    let core = try #require(CommonCryptoCore(.aes, key: Self.key128))
    let plaintext = Self.bytes(16)
    let cbc = BlockModes.cbcEncrypt(core, iv: Self.iv, plaintext: plaintext)
    #expect(BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: plaintext) == Array(cbc.prefix(16)))
  }

  @Test("whole blocks give CBC with the last two blocks swapped, for two to six blocks")
  func wholeBlocks() throws {
    let core = try #require(CommonCryptoCore(.aes, key: Self.key256))
    for blocks in 2...6 {
      let plaintext = Self.bytes(blocks * 16)
      let cbc = Array(
        BlockModes.cbcEncrypt(core, iv: Self.iv, plaintext: plaintext).prefix(blocks * 16))
      let penultimate = (blocks - 2) * 16
      let last = (blocks - 1) * 16
      let expected =
        Array(cbc[0..<penultimate]) + Array(cbc[last..<(last + 16)])
        + Array(cbc[penultimate..<last])
      #expect(BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: plaintext) == expected)
    }
  }

  @Test("a partial last block gives CBC of the padded input, cut and swapped")
  func partialBlock() throws {
    let core = try #require(CommonCryptoCore(.aes, key: Self.key128))
    for length in [17, 20, 31, 33, 47, 49, 63, 65, 100] {
      let blocks = (length + 15) / 16
      let tail = length - (blocks - 1) * 16
      let padded = Self.bytes(length) + [UInt8](repeating: 0, count: blocks * 16 - length)
      let cbc = Array(
        BlockModes.cbcEncrypt(core, iv: Self.iv, plaintext: padded).prefix(blocks * 16))
      let penultimate = (blocks - 2) * 16
      let last = (blocks - 1) * 16
      let expected =
        Array(cbc[0..<penultimate]) + Array(cbc[last..<(last + 16)])
        + Array(cbc[penultimate..<(penultimate + tail)])
      let actual = BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: Self.bytes(length))
      #expect(actual == expected, "length \(length)")
    }
  }

  @Test("every length from one block to 200 bytes decrypts to its input, with AES-128 and AES-256")
  func roundTrip() throws {
    for key in [Self.key128, Self.key256] {
      let core = try #require(CommonCryptoCore(.aes, key: key))
      for length in 16...200 {
        let plaintext = Self.bytes(length)
        let encrypted = try #require(
          BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: plaintext))
        #expect(encrypted.count == length, "length \(length)")
        let decrypted = BlockModes.ctsDecrypt(core, iv: Self.iv, ciphertext: encrypted)
        #expect(decrypted == plaintext, "length \(length)")
      }
    }
  }

  @Test("the structure is not tied to 16-byte blocks: triple DES with 8-byte blocks round-trips")
  func otherBlockSize() throws {
    let key = (0..<24).map { UInt8(0x30 &+ $0) }
    let core = try #require(CommonCryptoCore(.tripleDES, key: key))
    let iv = [UInt8](repeating: 0x5A, count: 8)
    for length in 8...40 {
      let plaintext = Self.bytes(length)
      let encrypted = try #require(BlockModes.ctsEncrypt(core, iv: iv, plaintext: plaintext))
      #expect(encrypted.count == length, "length \(length)")
      #expect(BlockModes.ctsDecrypt(core, iv: iv, ciphertext: encrypted) == plaintext)
    }
  }

  @Test("input shorter than one block, and an IV of the wrong size, are refused")
  func refusals() throws {
    let core = try #require(CommonCryptoCore(.aes, key: Self.key128))
    #expect(BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: []) == nil)
    #expect(BlockModes.ctsEncrypt(core, iv: Self.iv, plaintext: Self.bytes(15)) == nil)
    #expect(BlockModes.ctsDecrypt(core, iv: Self.iv, ciphertext: []) == nil)
    #expect(BlockModes.ctsDecrypt(core, iv: Self.iv, ciphertext: Self.bytes(15)) == nil)
    let shortIV = Array(Self.iv.prefix(15))
    #expect(BlockModes.ctsEncrypt(core, iv: shortIV, plaintext: Self.bytes(16)) == nil)
  }

  @Test("CTS is offered for the 128-bit block ciphers, AES among them, with id 0x010C")
  func offeredFamilies() {
    for family in FileCipher.Family.allCases where family.blockSize == 16 {
      #expect(family.modes.contains(.cts), "\(family.title)")
    }
    for family in FileCipher.Family.allCases where family.modes.contains(.cts) {
      #expect(family.blockSize == 16, "\(family.title)")
    }
    let aes = FileCipher.Algorithm(family: .aes, mode: .cts)
    #expect(aes.title == "AES-256-CTS")
    #expect(aes.id == 0x010C)
    #expect(aes.legacyByte == nil)
    #expect(aes.ivLength == 16)
  }

  @Test("a CTS file keeps the length of its input, with a 32-byte HMAC after it")
  func fileLength() throws {
    let algorithm = FileCipher.Algorithm(family: .aes, mode: .cts)
    for length in [16, 17, 30, 100] {
      let data = Data(Self.bytes(length))
      let file = try FileCipher.encrypt(
        data, password: "correct horse", algorithm: algorithm, iterations: 1_000)
      // Magic 4, version 1, algorithm 2, iterations 4, salt 16 and IV 16 make the 43-byte header.
      #expect(file.count == 43 + length + 32, "length \(length)")
      #expect(try FileCipher.decrypt(file, password: "correct horse") == data)
    }
  }

  @Test("a file shorter than one block is refused with tooShort, for every CTS algorithm")
  func shortFile() {
    for family in FileCipher.Family.allCases where family.modes.contains(.cts) {
      let algorithm = FileCipher.Algorithm(family: family, mode: .cts)
      #expect(throws: FileCipher.Failure.tooShort) {
        try FileCipher.encrypt(
          Data(Self.bytes(family.blockSize - 1)), password: "correct horse",
          algorithm: algorithm, iterations: 1_000)
      }
    }
  }
}
