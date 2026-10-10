import CryptoKit
import Foundation
import Testing

@testable import ImageToolboxKit

/// Known-answer tests for the block ciphers and the modes built on them. Each vector is from the
/// standard or the paper named beside it. Where a vector was produced with OpenSSL 3.6.5 (an
/// independent implementation) instead, the comment says so.
@Suite("Block ciphers and modes")
struct BlockCipherVectorTests {

  /// Encrypts one block with ``core`` and checks both directions.
  private func check(
    _ core: (some BlockCore)?, plaintext: String, ciphertext: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard let core else {
      Issue.record("The cipher rejected its key.", sourceLocation: sourceLocation)
      return
    }
    var block = hexBytes(plaintext)
    block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    #expect(block == hexBytes(ciphertext), "encrypt", sourceLocation: sourceLocation)
    block.withUnsafeMutableBufferPointer { core.decryptBlock($0.baseAddress!) }
    #expect(block == hexBytes(plaintext), "decrypt", sourceLocation: sourceLocation)
  }

  // MARK: AES through CommonCrypto

  @Test("AES, FIPS 197 appendix C")
  func aesFIPS197() {
    let plaintext = "00112233445566778899aabbccddeeff"
    check(
      CommonCryptoCore(.aes, key: hexBytes("000102030405060708090a0b0c0d0e0f")),
      plaintext: plaintext, ciphertext: "69c4e0d86a7b0430d8cdb78070b4c55a")
    check(
      CommonCryptoCore(.aes, key: hexBytes("000102030405060708090a0b0c0d0e0f1011121314151617")),
      plaintext: plaintext, ciphertext: "dda97ca4864cdfe06eaf70a0ec0d7191")
    check(
      CommonCryptoCore(
        .aes,
        key: hexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")),
      plaintext: plaintext, ciphertext: "8ea2b7ca516745bfeafc49904b496089")
  }

  // MARK: Modes

  @Test("CBC, NIST SP 800-38A F.2.1 and F.2.5 (the padding block comes after them)")
  func cbcSP80038A() throws {
    let plaintext = hexBytes(
      "6bc1bee22e409f96e93d7e117393172a" + "ae2d8a571e03ac9c9eb76fac45af8e51"
        + "30c81c46a35ce411e5fbc1191a0a52ef" + "f69f2445df4f9b17ad2b417be66c3710")
    let iv = hexBytes("000102030405060708090a0b0c0d0e0f")

    let core128 = try #require(
      CommonCryptoCore(.aes, key: hexBytes("2b7e151628aed2a6abf7158809cf4f3c")))
    let sealed128 = BlockModes.cbcEncrypt(core128, iv: iv, plaintext: plaintext)
    #expect(
      Array(sealed128.prefix(64))
        == hexBytes(
          "7649abac8119b246cee98e9b12e9197d" + "5086cb9b507219ee95db113a917678b2"
            + "73bed6b8e3c1743b7116e69e22229516" + "3ff1caa1681fac09120eca307586e1a7"))
    #expect(BlockModes.cbcDecrypt(core128, iv: iv, ciphertext: sealed128) == plaintext)

    let core256 = try #require(
      CommonCryptoCore(
        .aes,
        key: hexBytes("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")))
    let sealed256 = BlockModes.cbcEncrypt(core256, iv: iv, plaintext: plaintext)
    #expect(
      Array(sealed256.prefix(64))
        == hexBytes(
          "f58c4c04d6e5f1ba779eabfb5f7bfbd6" + "9cfc4e967edb808d679f777bc6702c7d"
            + "39f23369a9d9bacfa530e26304231461" + "b2eb05e2c39be9fcda6c19078c6a9d1b"))
    #expect(BlockModes.cbcDecrypt(core256, iv: iv, ciphertext: sealed256) == plaintext)
  }

  @Test("CBC refuses bad padding and bad lengths")
  func cbcBadInput() throws {
    let core = try #require(CommonCryptoCore(.aes, key: [UInt8](repeating: 7, count: 16)))
    let iv = [UInt8](repeating: 1, count: 16)
    #expect(BlockModes.cbcDecrypt(core, iv: iv, ciphertext: []) == nil)
    #expect(
      BlockModes.cbcDecrypt(core, iv: iv, ciphertext: [UInt8](repeating: 0, count: 15)) == nil)
    // A block of zeros decrypts to garbage whose last byte is almost never valid padding.
    var rejected = 0
    for seed in 0..<40 {
      let junk = [UInt8](repeating: UInt8(seed), count: 16)
      if BlockModes.cbcDecrypt(core, iv: iv, ciphertext: junk) == nil { rejected += 1 }
    }
    #expect(rejected > 30)
  }

  @Test("CTR, NIST SP 800-38A F.5.1 and F.5.5")
  func ctrSP80038A() throws {
    let plaintext = hexBytes(
      "6bc1bee22e409f96e93d7e117393172a" + "ae2d8a571e03ac9c9eb76fac45af8e51"
        + "30c81c46a35ce411e5fbc1191a0a52ef" + "f69f2445df4f9b17ad2b417be66c3710")
    let counter = hexBytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")

    let core128 = try #require(
      CommonCryptoCore(.aes, key: hexBytes("2b7e151628aed2a6abf7158809cf4f3c")))
    #expect(
      BlockModes.ctr(core128, iv: counter, data: plaintext)
        == hexBytes(
          "874d6191b620e3261bef6864990db6ce" + "9806f66b7970fdff8617187bb9fffdff"
            + "5ae4df3edbd5d35e5b4f09020db03eab" + "1e031dda2fbe03d1792170a0f3009cee"))

    let core256 = try #require(
      CommonCryptoCore(
        .aes,
        key: hexBytes("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")))
    let encrypted = BlockModes.ctr(core256, iv: counter, data: plaintext)
    #expect(
      encrypted
        == hexBytes(
          "601ec313775789a5b7a7f504bbf3d228" + "f443e3ca4d62b59aca84e990cacaf5c5"
            + "2b0930daa23de94ce87017ba2d84988d" + "dfc9c58db67aada613c2dd08457941a6"))
    #expect(BlockModes.ctr(core256, iv: counter, data: encrypted) == plaintext)
  }

  @Test("CTR carries across the whole block and handles a partial last block")
  func ctrCarry() throws {
    let core = try #require(CommonCryptoCore(.aes, key: [UInt8](repeating: 3, count: 32)))
    let counter = hexBytes("00000000000000000000000000ffffff")
    let data = [UInt8](repeating: 0, count: 40)
    let stream = BlockModes.ctr(core, iv: counter, data: data)
    // The second block uses the counter 00..01000000 (a carry out of the low three bytes).
    var expected = hexBytes("00000000000000000000000001000000")
    expected.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    #expect(Array(stream[16..<32]) == expected)
    #expect(stream.count == 40)
  }

  @Test("GCM, NIST test case 4 (SP 800-38D / GCM specification)")
  func gcmTestCase4() throws {
    let core = try #require(
      CommonCryptoCore(.aes, key: hexBytes("feffe9928665731c6d6a8f9467308308")))
    let nonce = hexBytes("cafebabefacedbaddecaf888")
    let aad = hexBytes("feedfacedeadbeeffeedfacedeadbeefabaddad2")
    let plaintext = hexBytes(
      "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
        + "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
    let sealed = BlockModes.gcmSeal(core, nonce: nonce, aad: aad, plaintext: plaintext)
    #expect(
      sealed.ciphertext
        == hexBytes(
          "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
            + "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091"))
    #expect(sealed.tag == hexBytes("5bc94fbc3221a5db94fae95ae7121a47"))
    let opened = BlockModes.gcmOpen(
      core, nonce: nonce, aad: aad, ciphertext: sealed.ciphertext, tag: sealed.tag)
    #expect(opened == plaintext)
  }

  @Test("generic GCM over AES equals CryptoKit AES-GCM")
  func gcmMatchesCryptoKit() throws {
    var generator = SystemRandomNumberGenerator()
    for length in [0, 1, 15, 16, 17, 31, 32, 100, 1_000, 9_999] {
      let key = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
      let nonce = (0..<12).map { _ in UInt8.random(in: 0...255, using: &generator) }
      let aad = (0..<(length % 37)).map { _ in UInt8.random(in: 0...255, using: &generator) }
      let plaintext = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
      let core = try #require(CommonCryptoCore(.aes, key: key))
      let ours = BlockModes.gcmSeal(core, nonce: nonce, aad: aad, plaintext: plaintext)
      let theirs = try AES.GCM.seal(
        plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce),
        authenticating: aad)
      #expect(ours.ciphertext == Array(theirs.ciphertext), "length \(length)")
      #expect(ours.tag == Array(theirs.tag), "length \(length)")
    }
  }

  @Test("GCM refuses a changed tag, ciphertext or associated data")
  func gcmTamper() throws {
    let core = try #require(CommonCryptoCore(.aes, key: [UInt8](repeating: 9, count: 16)))
    let nonce = [UInt8](repeating: 2, count: 12)
    let sealed = BlockModes.gcmSeal(
      core, nonce: nonce, aad: [1, 2, 3], plaintext: Array("hello world, hello".utf8))
    var badTag = sealed.tag
    badTag[0] ^= 1
    var badData = sealed.ciphertext
    badData[0] ^= 1
    #expect(
      BlockModes.gcmOpen(
        core, nonce: nonce, aad: [1, 2, 3], ciphertext: sealed.ciphertext, tag: badTag)
        == nil)
    #expect(
      BlockModes.gcmOpen(core, nonce: nonce, aad: [1, 2, 3], ciphertext: badData, tag: sealed.tag)
        == nil)
    #expect(
      BlockModes.gcmOpen(
        core, nonce: nonce, aad: [1, 2], ciphertext: sealed.ciphertext, tag: sealed.tag)
        == nil)
  }

  // MARK: ARIA

  @Test("ARIA, RFC 5794 appendix A (all three sizes also match OpenSSL)")
  func aria() {
    let plaintext = "00112233445566778899aabbccddeeff"
    check(
      ARIACore(key: hexBytes("000102030405060708090a0b0c0d0e0f")),
      plaintext: plaintext, ciphertext: "d718fbd6ab644c739da95f3be6451778")
    check(
      ARIACore(key: hexBytes("000102030405060708090a0b0c0d0e0f1011121314151617")),
      plaintext: plaintext, ciphertext: "26449c1805dbe7aa25a468ce263a9e79")
    check(
      ARIACore(
        key: hexBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")),
      plaintext: plaintext, ciphertext: "f92bd7c79fb72e2f2b8f80c1972d24fc")
  }

  // MARK: Camellia

  @Test("Camellia, RFC 3713 appendix A (also OpenSSL)")
  func camellia() {
    let plaintext = "0123456789abcdeffedcba9876543210"
    check(
      CamelliaCore(key: hexBytes("0123456789abcdeffedcba9876543210")),
      plaintext: plaintext, ciphertext: "67673138549669730857065648eabe43")
    check(
      CamelliaCore(key: hexBytes("0123456789abcdeffedcba98765432100011223344556677")),
      plaintext: plaintext, ciphertext: "b4993401b3e996f84ee5cee7d79b09b9")
    check(
      CamelliaCore(
        key: hexBytes("0123456789abcdeffedcba987654321000112233445566778899aabbccddeeff")),
      plaintext: plaintext, ciphertext: "9acc237dff16d76c20ef7c919e3a7509")
  }

  // MARK: SM4 and SEED

  @Test("SM4, GB/T 32907-2016 appendix A (also OpenSSL)")
  func sm4() {
    check(
      SM4Core(key: hexBytes("0123456789abcdeffedcba9876543210")),
      plaintext: "0123456789abcdeffedcba9876543210",
      ciphertext: "681edf34d206965e86b3e94f536e4246")
  }

  @Test("SEED, RFC 4269 appendix B (also OpenSSL)")
  func seed() {
    check(
      SEEDCore(key: hexBytes("00000000000000000000000000000000")),
      plaintext: "000102030405060708090a0b0c0d0e0f",
      ciphertext: "5ebac6e0054e166819aff1cc6d346cdb")
  }

  // MARK: AES finalists

  @Test("Serpent, the NESSIE known answers for the keys 80 00 ... 00 of the three sizes")
  func serpent() {
    check(
      SerpentCore(key: hexBytes("80000000000000000000000000000000")),
      plaintext: "00000000000000000000000000000000",
      ciphertext: "264e5481eff42a4606abda06c0bfda3d")
    check(
      SerpentCore(key: hexBytes("80" + String(repeating: "00", count: 23))),
      plaintext: "00000000000000000000000000000000",
      ciphertext: "9e274ead9b737bb21efcfca548602689")
    check(
      SerpentCore(key: hexBytes("80" + String(repeating: "00", count: 31))),
      plaintext: "00000000000000000000000000000000",
      ciphertext: "a223aa1288463c0e2be38ebd825616c0")
  }

  @Test("Twofish, the known answers of the Twofish paper (zero block)")
  func twofish() {
    let zeros = "00000000000000000000000000000000"
    check(
      TwofishCore(key: [UInt8](repeating: 0, count: 16)),
      plaintext: zeros, ciphertext: "9f589f5cf6122c32b6bfec2f2ae8c35a")
    check(
      TwofishCore(key: hexBytes("0123456789abcdeffedcba98765432100011223344556677")),
      plaintext: zeros, ciphertext: "cfd1d2e5a9be9cdf501f13b892bd2248")
    check(
      TwofishCore(
        key: hexBytes("0123456789abcdeffedcba987654321000112233445566778899aabbccddeeff")),
      plaintext: zeros, ciphertext: "37527be0052334b89f0cfccae87cfa20")
  }

  @Test("CAST-256, RFC 2612 appendix B")
  func cast256() {
    let zeros = "00000000000000000000000000000000"
    check(
      CAST256Core(key: hexBytes("2342bb9efa38542c0af75647f29f615d")),
      plaintext: zeros, ciphertext: "c842a08972b43d20836c91d1b7530f6b")
    check(
      CAST256Core(key: hexBytes("2342bb9efa38542cbed0ac83940ac298bac77a7717942863")),
      plaintext: zeros, ciphertext: "1b386c0210dcadcbdd0e41aa08a7a7e8")
    check(
      CAST256Core(
        key: hexBytes("2342bb9efa38542cbed0ac83940ac2988d7c47ce264908461cc1b5137ae6b604")),
      plaintext: zeros, ciphertext: "4f6a2038286897b9c9870136553317fa")
  }

  @Test("RC6-32/20, the known answers of the RC6 AES submission")
  func rc6() {
    check(
      RC6Core(key: [UInt8](repeating: 0, count: 16)),
      plaintext: "00000000000000000000000000000000",
      ciphertext: "8fc3a53656b1f778c129df4e9848a41e")
    check(
      RC6Core(key: hexBytes("0123456789abcdef0112233445566778")),
      plaintext: "02132435465768798a9bacbdcedfe0f1",
      ciphertext: "524e192f4715c6231f51f6367ea43f18")
  }

  // MARK: Others

  @Test("LEA, the KISA known answers for the three key sizes")
  func lea() {
    check(
      LEACore(key: hexBytes("0f1e2d3c4b5a69788796a5b4c3d2e1f0")),
      plaintext: "101112131415161718191a1b1c1d1e1f", ciphertext: "9fc84e3528c6c6185532c7a704648bfd")
    check(
      LEACore(key: hexBytes("0f1e2d3c4b5a69788796a5b4c3d2e1f0f0e1d2c3b4a59687")),
      plaintext: "202122232425262728292a2b2c2d2e2f", ciphertext: "6fb95e325aad1b878cdcf5357674c6f2")
    check(
      LEACore(key: hexBytes("0f1e2d3c4b5a69788796a5b4c3d2e1f0f0e1d2c3b4a5968778695a4b3c2d1e0f")),
      plaintext: "303132333435363738393a3b3c3d3e3f", ciphertext: "d651aff647b189c13a8900ca27f9e197")
  }

  @Test("Noekeon, the direct-key known answer of the specification")
  func noekeon() {
    check(
      NoekeonCore(key: hexBytes("b1656851699e29fa24b70148503d2dfc")),
      plaintext: "2a78421b87c7d0924f26113f1d1349b2",
      ciphertext: "e2f687e07b75660ffc372233bc47532c")
  }

  @Test("SHACAL-2 is the SHA-256 compression function (checked against CryptoKit)")
  func shacal2() throws {
    var padded = Array("abc".utf8)
    padded.append(0x80)
    while padded.count < 56 { padded.append(0) }
    padded.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 24])
    let core = try #require(Shacal2Core(key: padded))
    let initial: [UInt32] = [
      0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A, 0x510E_527F, 0x9B05_688C,
      0x1F83_D9AB, 0x5BE0_CD19,
    ]
    var block = [UInt8]()
    for word in initial {
      block.append(contentsOf: [
        UInt8(word >> 24), UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0xFF),
        UInt8(word & 0xFF),
      ])
    }
    let original = block
    block.withUnsafeMutableBufferPointer { core.encryptBlock($0.baseAddress!) }
    var digest = [UInt8]()
    for index in 0..<8 {
      let offset = index * 4
      var word = UInt32(block[offset]) << 24
      word |= UInt32(block[offset + 1]) << 16
      word |= UInt32(block[offset + 2]) << 8
      word |= UInt32(block[offset + 3])
      let sum = word &+ initial[index]
      digest.append(contentsOf: [
        UInt8(sum >> 24), UInt8((sum >> 16) & 0xFF), UInt8((sum >> 8) & 0xFF), UInt8(sum & 0xFF),
      ])
    }
    #expect(digest == Array(SHA256.hash(data: Data("abc".utf8))))
    block.withUnsafeMutableBufferPointer { core.decryptBlock($0.baseAddress!) }
    #expect(block == original)
  }

  @Test("Threefish-256, the Skein known answer for an all-zero key, tweak and block")
  func threefish256() {
    // The Skein paper prints each 64-bit word most significant byte first; the bytes of a block
    // are little-endian words.
    let words: [UInt64] = [
      0x94EE_EA8B_1F2A_DA84, 0xADF1_0331_3EAE_6670, 0x9524_19A1_F4B1_6D53, 0xD83F_13E6_3C9F_6B11,
    ]
    var expected = [UInt8]()
    for word in words {
      for index in 0..<8 { expected.append(UInt8(truncatingIfNeeded: word >> UInt64(8 * index))) }
    }
    check(
      ThreefishCore(key: [UInt8](repeating: 0, count: 32)),
      plaintext: String(repeating: "00", count: 32),
      ciphertext: expected.map { String(format: "%02x", $0) }.joined())
  }

  // MARK: 64-bit block ciphers

  @Test("IDEA, the classic known answer (also OpenSSL)")
  func idea() {
    check(
      IDEACore(key: hexBytes("00010002000300040005000600070008")),
      plaintext: "0000000100020003", ciphertext: "11fbed2b01986de5")
  }

  @Test("RC5-32/12/16, the known answers of the RC5 paper")
  func rc5() {
    check(
      RC5Core(key: [UInt8](repeating: 0, count: 16)),
      plaintext: "0000000000000000", ciphertext: "21a5dbee154b8f6d")
    check(
      RC5Core(key: hexBytes("915f4619be41b2516355a50110a9ce91")),
      plaintext: "21a5dbee154b8f6d", ciphertext: "f7c013ac5b2b8952")
  }

  @Test("TEA and XTEA, the known answers used by common test suites")
  func tea() {
    check(
      TEACore(key: [UInt8](repeating: 0, count: 16)),
      plaintext: "0000000000000000", ciphertext: "41ea3a0a94baa940")
    check(
      XTEACore(key: hexBytes("000102030405060708090a0b0c0d0e0f")),
      plaintext: "4142434445464748", ciphertext: "497df3d072612cb5")
  }

  @Test("Skipjack, the NIST known answer")
  func skipjack() {
    check(
      SkipjackCore(key: hexBytes("00998877665544332211")),
      plaintext: "33221100ddccbbaa", ciphertext: "2587cae27a12d300")
  }

  @Test("GOST 28147-89 decrypts what it encrypts and is not the identity")
  func gost() throws {
    let core = try #require(GOST28147Core(key: (0..<32).map { UInt8($0 * 7 + 1) }))
    var block = hexBytes("0123456789abcdef")
    core.encryptBlockForTest(&block)
    #expect(block != hexBytes("0123456789abcdef"))
    core.decryptBlockForTest(&block)
    #expect(block == hexBytes("0123456789abcdef"))
  }

  // MARK: CommonCrypto ciphers

  @Test("DES, Blowfish, CAST-128, 3DES and RC2 through CommonCrypto (vectors also from OpenSSL)")
  func commonCrypto() {
    check(
      CommonCryptoCore(.des, key: hexBytes("133457799bbcdff1")),
      plaintext: "0123456789abcdef", ciphertext: "85e813540f0ab405")
    check(
      CommonCryptoCore(.blowfish, key: [UInt8](repeating: 0, count: 8)),
      plaintext: "0000000000000000", ciphertext: "4ef997456198dd78")
    check(
      CommonCryptoCore(.blowfish, key: hexBytes("0123456789abcdef0123456789abcdef")),
      plaintext: "0123456789abcdef", ciphertext: "008a8314ee2b27a3")
    check(
      CommonCryptoCore(.cast5, key: hexBytes("0123456712345678234567893456789a")),
      plaintext: "0123456789abcdef", ciphertext: "238b4fe5847e44b2")
    check(
      CommonCryptoCore(
        .tripleDES, key: hexBytes("0123456789abcdef23456789abcdef01456789abcdef0123")),
      plaintext: "0123456789abcdef", ciphertext: "f2afd84ee809e2b5")
    check(
      CommonCryptoCore(.rc2, key: hexBytes("000102030405060708090a0b0c0d0e0f")),
      plaintext: "0123456789abcdef", ciphertext: "c1de66972a5efb2b")
  }
}

/// Parses a string of hexadecimal digits (white space is ignored).
func hexBytes(_ text: String) -> [UInt8] {
  CipherTables.bytes(text)
}

extension BlockCore {
  /// Encrypts one block held in an array (test helper).
  fileprivate func encryptBlockForTest(_ block: inout [UInt8]) {
    block.withUnsafeMutableBufferPointer { encryptBlock($0.baseAddress!) }
  }

  fileprivate func decryptBlockForTest(_ block: inout [UInt8]) {
    block.withUnsafeMutableBufferPointer { decryptBlock($0.baseAddress!) }
  }
}
