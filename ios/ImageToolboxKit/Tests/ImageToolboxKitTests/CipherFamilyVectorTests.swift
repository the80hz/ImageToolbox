import Foundation
import Testing

@testable import ImageToolboxKit

/// Known answers for CFB8, for the Rijndael name of AES, and for Tnepres.
///
/// - CFB8: NIST SP 800-38A, F.3.7 (CFB8-AES128.Encrypt). The example prints 64 segments; the
///   18 segments read here are the ones whose bytes the extracted text gives in full, with the
///   cipher outputs (Output Block) of segments 1 and 2.
/// - Rijndael: FIPS 197 appendix C.3 (AES-256), as the family reads it.
/// - Tnepres: the single-block rows of Bouncy Castle's TnepresTest, and its Monte Carlo rows (the
///   block encrypted 100 and 10000 times in place under one key), as read through WebFetch. The
///   Monte Carlo procedure is that of BlockCipherMonteCarloTest, also read through WebFetch.
@Suite("CFB8, Rijndael and Tnepres")
struct CipherFamilyVectorTests {

  @Test("CFB8, NIST SP 800-38A F.3.7 (AES-128), the first 18 segments and two cipher outputs")
  func cfb8SP80038A() throws {
    let key = hexBytes("2b7e151628aed2a6abf7158809cf4f3c")
    let iv = hexBytes("000102030405060708090a0b0c0d0e0f")
    let core = try #require(CommonCryptoCore(.aes, key: key))

    // The Output Block of segment 1 is the cipher applied to the IV, and that of segment 2 the cipher
    // applied to the IV shifted by one byte, with the first ciphertext byte at its end.
    var first = iv
    first.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    #expect(first == hexBytes("50fe67cc996d32b6da0937e99bafec60"))
    var second = hexBytes("0102030405060708090a0b0c0d0e0f3b")
    second.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    #expect(second == hexBytes("b8eb865a2b026381abb1d6560ed20f68"))

    let plaintext = hexBytes("6bc1bee22e409f96e93d7e117393172aae2d")
    let ciphertext = hexBytes("3b79424c9c0dd436bace9e0ed4586a4f32b9")
    #expect(BlockModes.cfb8(core, iv: iv, data: plaintext, encrypt: true) == ciphertext)
    #expect(BlockModes.cfb8(core, iv: iv, data: ciphertext, encrypt: false) == plaintext)
  }

  @Test("CFB8 decrypts what it encrypted, for every length from 0 to 40 bytes")
  func cfb8RoundTrip() throws {
    let core = try #require(CommonCryptoCore(.aes, key: [UInt8](repeating: 0x5A, count: 32)))
    let iv = (0..<16).map { UInt8($0 * 3) }
    for length in 0...40 {
      let plaintext = (0..<length).map { UInt8(($0 * 29 + 7) % 256) }
      let encrypted = BlockModes.cfb8(core, iv: iv, data: plaintext, encrypt: true)
      #expect(encrypted.count == length)
      #expect(BlockModes.cfb8(core, iv: iv, data: encrypted, encrypt: false) == plaintext)
    }
  }

  @Test("Rijndael with a 128-bit block is AES: FIPS 197 appendix C.3 through the family")
  func rijndaelIsAES() throws {
    let key = hexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let core = try #require(FileCipher.Family.rijndael.makeCore(key: key))
    var block = hexBytes("00112233445566778899aabbccddeeff")
    block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    #expect(block == hexBytes("8ea2b7ca516745bfeafc49904b496089"))
    #expect(FileCipher.Family.rijndael.blockSize == 16)
    #expect(FileCipher.Algorithm(family: .rijndael, mode: .gcm).title == "Rijndael-256-GCM")
  }

  @Test("Tnepres, the Bouncy Castle TnepresTest rows (key, plaintext, ciphertext)")
  func tnepresVectors() throws {
    let rows: [(key: String, plaintext: String, ciphertext: String)] = [
      (
        String(repeating: "00", count: 32), String(repeating: "00", count: 16),
        "8910494504181950f98dd998a82b6749"
      ),
      (
        String(repeating: "00", count: 16), "80000000000000000000000000000000",
        "10b5ffb720b8cb9002a1142b0ba2e94a"
      ),
      (
        String(repeating: "00", count: 16), "00000000008000000000000000000000",
        "4f057a42d8d5bd9746e434680ddcd5e5"
      ),
      (
        String(repeating: "00", count: 16), "00000000000000000000400000000000",
        "99407bf8582ef12550886ef5b6f169b9"
      ),
      (
        String(repeating: "00", count: 24), "40000000000000000000000000000000",
        "d522a3b8d6d89d4d2a124fdd88f36896"
      ),
      (
        String(repeating: "00", count: 24), "00000000000200000000000000000000",
        "189b8ec3470085b3da97e82ca8964e32"
      ),
      (
        String(repeating: "00", count: 24), "00000000000000000000008000000000",
        "f77d868cf760b9143a89809510ccb099"
      ),
      (
        String(repeating: "00", count: 32), "08000000000000000000000000000000",
        "d43b7b981b829342fce0e3ec6f5f4c82"
      ),
      (
        String(repeating: "00", count: 32), "00000000000000000100000000000000",
        "0bf30e1a0c33ccf6d5293177886912a7"
      ),
      (
        String(repeating: "00", count: 32), "00000000000000000000000000000001",
        "6a7f3b805d2ddcba49b89770ade5e507"
      ),
      (
        "80" + String(repeating: "00", count: 15), String(repeating: "00", count: 16),
        "49afbfad9d5a34052cd8ffa5986bd2dd"
      ),
      (
        "000000000000000000000000004000000000000000000000",
        String(repeating: "00", count: 16), "ba8829b1de058c4b48615d851fc74f17"
      ),
      (
        "0000000000000000000000000000000000000000000000000000000100000000",
        String(repeating: "00", count: 16), "89f64377bf1e8a46c8247044e8056a98"
      ),
    ]
    for row in rows {
      let core = try #require(TnepresCore(key: hexBytes(row.key)), "key \(row.key)")
      var block = hexBytes(row.plaintext)
      block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
      #expect(block == hexBytes(row.ciphertext), "encrypt, key \(row.key)")
      block.withUnsafeMutableBufferPointer { core.decryptBlock($0.baseAddress!) }
      #expect(block == hexBytes(row.plaintext), "decrypt, key \(row.key)")
    }
  }

  @Test("Tnepres, the Bouncy Castle TnepresTest Monte Carlo rows: 100 and 10000 encryptions")
  func tnepresMonteCarlo() throws {
    // The block is encrypted in place under one fixed key, each output being the next input. The
    // rows give the key, the start block, the block after 100 steps and after 10000 steps.
    let rows: [(key: String, start: String, hundred: String, tenThousand: String)] = [
      (
        "47f5f881daab9b67b43bd1342e339c19", "7a4f7db38c52a8b711b778a38d203b6b",
        "4db75303d815c2f7cc6ca935d1c5a046", "003380e19f10065740394f48e2fe80b7"
      ),
      (
        "31fba879ebc5e80df35e6fa33eaf92d6", "70a05e12f74589009692a337f53ff614",
        "fc53a50f4d3bc9836001893d2f41742d", "afb5425426906db26b70bdf842ac5400"
      ),
      (
        "bde6dd392307984695aee80e574f9977caae9aa78eda53e8", "9cc523d034a93740a0aa4e2054bb34d8",
        "77117e6a9e80f40b2a36b7d755573c2d", "1949d506ada7de1f1344986e8ea049b2"
      ),
      (
        "60f6f8ad4290699dc50921a1bbcca92da914e7d9cf01a9317c79c0af8f2487a1",
        "ee1a61106fae2d381d686cbf854bab65", "dcd7f13ea0dcdfd0139d1a42e2ffb84b",
        "e57f45559027cb1f2ed9603d814e1c34"
      ),
    ]
    for row in rows {
      let core = try #require(TnepresCore(key: hexBytes(row.key)), "key \(row.key)")
      var block = hexBytes(row.start)
      for step in 1...10_000 {
        block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
        if step == 100 {
          #expect(block == hexBytes(row.hundred), "100 steps, key \(row.key)")
        }
      }
      #expect(block == hexBytes(row.tenThousand), "10000 steps, key \(row.key)")
    }
  }

  @Test("Tnepres is Serpent with the bytes of the block reversed, for every key size")
  func tnepresIsReversedSerpent() throws {
    for size in [16, 24, 32] {
      let key = (0..<size).map { UInt8(($0 * 11 + 1) % 256) }
      let block = (0..<16).map { UInt8(($0 * 17 + 3) % 256) }
      let tnepres = try #require(TnepresCore(key: key))
      let serpent = try #require(SerpentCore(key: Array(key.reversed())))
      var reversedBlock = Array(block.reversed())
      reversedBlock.withUnsafeMutableBufferPointer { serpent.encryptBlock($0.baseAddress!) }
      let expected = Array(reversedBlock.reversed())
      var actual = block
      actual.withUnsafeMutableBufferPointer { tnepres.encryptBlock($0.baseAddress!) }
      #expect(actual == expected, "\(size)-byte key")
    }
    #expect(TnepresCore(key: [UInt8](repeating: 0, count: 20)) == nil)
  }
}
