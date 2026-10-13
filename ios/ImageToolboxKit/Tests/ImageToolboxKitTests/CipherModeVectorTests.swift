import Foundation
import Testing

@testable import ImageToolboxKit

/// Known answers for the modes added for the file cipher: CFB, OFB, CCM and RC4. The NIST and RFC
/// vectors are printed in their standards. The other tables were computed with the Python
/// `cryptography` package, which is a separate implementation; the comments give the inputs.
@Suite("Cipher modes: CFB, OFB, CCM and RC4")
struct CipherModeVectorTests {

  /// The byte pattern the reference script used. Every key, IV and plaintext below comes from it.
  private func pattern(_ seed: Int, _ count: Int) -> [UInt8] {
    (0..<count).map { UInt8((seed * 37 + $0 * 13 + 1) % 256) }
  }

  @Test("CFB and OFB, NIST SP 800-38A F.3.13 and F.4.1 (two blocks), AES-128")
  func nistCFBAndOFB() throws {
    let key = hexBytes("2b7e151628aed2a6abf7158809cf4f3c")
    let iv = hexBytes("000102030405060708090a0b0c0d0e0f")
    let plaintext = hexBytes(
      "6bc1bee22e409f96e93d7e117393172a" + "ae2d8a571e03ac9c9eb76fac45af8e51")
    let core = try #require(CommonCryptoCore(.aes, key: key))
    #expect(
      BlockModes.cfb(core, iv: iv, data: plaintext, encrypt: true)
        == hexBytes("3b3fd92eb72dad20333449f8e83cfb4a" + "c8a64537a0b3a93fcde3cdad9f1ce58b"))
    #expect(
      BlockModes.ofb(core, iv: iv, data: plaintext)
        == hexBytes("3b3fd92eb72dad20333449f8e83cfb4a" + "7789508d16918f03f53c52dac54ed825"))
  }

  @Test("CFB decrypts what it encrypted, including a partial last block")
  func cfbRoundTrip() throws {
    let core = try #require(CommonCryptoCore(.aes, key: pattern(8, 32)))
    let iv = pattern(9, 16)
    let plaintext = pattern(10, 37)
    let encrypted = BlockModes.cfb(core, iv: iv, data: plaintext, encrypt: true)
    #expect(encrypted.count == plaintext.count)
    #expect(BlockModes.cfb(core, iv: iv, data: encrypted, encrypt: false) == plaintext)
  }

  @Test("CCM, RFC 3610 packet vector 1 (13-byte nonce, 8-byte tag)")
  func rfc3610PacketVector1() throws {
    let key = hexBytes("c0c1c2c3c4c5c6c7c8c9cacbcccdcecf")
    let nonce = hexBytes("00000003020100a0a1a2a3a4a5")
    let aad = hexBytes("0001020304050607")
    let plaintext = hexBytes("08090a0b0c0d0e0f101112131415161718191a1b1c1d1e")
    let core = try #require(CommonCryptoCore(.aes, key: key))
    let sealed = try #require(
      BlockModes.ccmSeal(core, nonce: nonce, aad: aad, plaintext: plaintext, tagLength: 8))
    #expect(sealed.ciphertext == hexBytes("588c979a61c663d2f066d0c2c0f98980" + "6d5f6b61dac384"))
    #expect(sealed.tag == hexBytes("17e8d12cfdf926e0"))
    #expect(
      BlockModes.ccmOpen(
        core, nonce: nonce, aad: aad, ciphertext: sealed.ciphertext, tag: sealed.tag)
        == plaintext)
  }

  @Test("CCM with the file cipher's sizes (7-byte nonce, 16-byte tag, 13 bytes of AAD)")
  func ccmFileSizes() throws {
    let core = try #require(CommonCryptoCore(.aes, key: pattern(5, 32)))
    let nonce = pattern(6, 7)
    let aad = pattern(7, 13)
    let plaintext = pattern(1, 37)
    let sealed = try #require(
      BlockModes.ccmSeal(core, nonce: nonce, aad: aad, plaintext: plaintext, tagLength: 16))
    #expect(
      sealed.ciphertext + sealed.tag
        == hexBytes(
          "933454d88c7d0c9a709b7f6cf498614310d4e868b3ac7388354605ed7867e5147f8e854efc9b75c1a7cdc0419140cea5e0e0d4591b"
        ))
  }

  @Test("CCM refuses a changed tag, ciphertext or associated data")
  func ccmTamper() throws {
    let core = try #require(CommonCryptoCore(.aes, key: pattern(5, 32)))
    let nonce = pattern(6, 7)
    let sealed = try #require(
      BlockModes.ccmSeal(core, nonce: nonce, aad: [1, 2], plaintext: pattern(1, 20), tagLength: 16))
    var badTag = sealed.tag
    badTag[15] ^= 0x80
    var badData = sealed.ciphertext
    badData[3] ^= 1
    #expect(
      BlockModes.ccmOpen(
        core, nonce: nonce, aad: [1, 2], ciphertext: sealed.ciphertext, tag: badTag)
        == nil)
    #expect(
      BlockModes.ccmOpen(core, nonce: nonce, aad: [1, 2], ciphertext: badData, tag: sealed.tag)
        == nil)
    #expect(
      BlockModes.ccmOpen(
        core, nonce: nonce, aad: [1, 3], ciphertext: sealed.ciphertext, tag: sealed.tag)
        == nil)
  }

  @Test("CCM refuses nonces outside 7 to 13 bytes and tags that are not 4 to 16 even bytes")
  func ccmParameters() throws {
    let core = try #require(CommonCryptoCore(.aes, key: pattern(5, 32)))
    #expect(
      BlockModes.ccmSeal(core, nonce: [0, 1, 2], aad: [], plaintext: [], tagLength: 16) == nil)
    #expect(
      BlockModes.ccmSeal(core, nonce: pattern(1, 7), aad: [], plaintext: [], tagLength: 5) == nil)
  }

  @Test("RC4, the Wikipedia examples (Key, Plaintext) and (Secret, Attack at dawn)")
  func rc4Examples() throws {
    let first = try #require(RC4Stream(key: Array("Key".utf8)))
    var plaintext = Array("Plaintext".utf8)
    first.process(&plaintext)
    #expect(plaintext == hexBytes("bbf316e8d940af0ad3"))

    let second = try #require(RC4Stream(key: Array("Secret".utf8)))
    var message = Array("Attack at dawn".utf8)
    second.process(&message)
    #expect(message == hexBytes("45a01f645fc35b383552544b9bf5"))
  }

  @Test("RC4 rejects an empty key and a key longer than 256 bytes")
  func rc4KeyLength() {
    #expect(RC4Stream(key: []) == nil)
    #expect(RC4Stream(key: [UInt8](repeating: 1, count: 257)) == nil)
  }

  /// CFB, OFB and CTR over every block size of the file cipher, with a 37-byte plaintext (so the
  /// last block is partial for 8, 16 and 32 bytes). The reference script used the keys and IVs
  /// given here.
  @Test("CFB, OFB and CTR agree with the Python cryptography package for each block size")
  func feedbackAndCounterReferences() throws {
    struct Reference {
      let name: String
      let core: (any BlockCore)?
      let iv: [UInt8]
      let cfb: String
      let ofb: String
      let ctr: String?
    }
    let aesKey = pattern(2, 32)
    let samples: [Reference] = [
      Reference(
        name: "AES-256", core: CommonCryptoCore(.aes, key: aesKey), iv: pattern(3, 16),
        cfb: "aceb0397d67e85a789a6b1139e6893bdc212ef9ee8b129d42f6ad06caa5e0104f588a98a91",
        ofb: "aceb0397d67e85a789a6b1139e6893bd89ca3aef7c5d9ec441a3a76cf5c0a36dcfd9a50745",
        ctr: "aceb0397d67e85a789a6b1139e6893bd6ac86ecf39dccb2e172ad60b530bdbd538fe19dc72"),
      Reference(
        name: "Camellia-256", core: CamelliaCore(key: aesKey), iv: pattern(3, 16),
        cfb: "5a5d91f2cb00976433b23a80b51bca34bb050851c344d3c7645a9b87a26c48066c2657ad8d",
        ofb: "5a5d91f2cb00976433b23a80b51bca34dfc969a73f3feb56427c05814ba276a577b26066f7",
        ctr: nil),
      Reference(
        name: "SM4-128", core: SM4Core(key: pattern(2, 16)), iv: pattern(3, 16),
        cfb: "38d7429b2d2420b8f4a56deece74292f23af28e26118773fa34fe2e1d41b1ff17470596fb4",
        ofb: "38d7429b2d2420b8f4a56deece74292f0654253de82203c0c37a6799140d51aa94f242d714",
        ctr: "38d7429b2d2420b8f4a56deece74292f694e6f8d62c8cc014f52212aafe68c17d4895aab71"),
      Reference(
        name: "SEED-128", core: SEEDCore(key: pattern(2, 16)), iv: pattern(3, 16),
        cfb: "f02c62fd18810c3bb3986035a4a2574cdee5973db59a04044dee3984508fefd71dd6e867ad",
        ofb: "f02c62fd18810c3bb3986035a4a2574c4215a0b2ad9a439bd7e14067c5e473c0b7dc600d4d",
        ctr: nil),
      Reference(
        name: "IDEA-128", core: IDEACore(key: pattern(2, 16)), iv: pattern(3, 8),
        cfb: "b9360e5a3158e6f593a8abee3d3afebe86169f0caae70617d39f087887adb221839400d13f",
        ofb: "b9360e5a3158e6f540a7753a906b149c714ed4209930bc0d3493626475be5232334b0e1f67",
        ctr: nil),
      Reference(
        name: "Blowfish-256", core: CommonCryptoCore(.blowfish, key: aesKey), iv: pattern(3, 8),
        cfb: "07f2b578895b3b8c812c74723f4cfb3bffac5d318fece62d8db26a9d04a74746c21e7a2d06",
        ofb: "07f2b578895b3b8c860348a66e4a10ceb2903847af8d985bf5be38e7468b7f4551109c0de7",
        ctr: nil),
      Reference(
        name: "DESede-192", core: CommonCryptoCore(.tripleDES, key: pattern(2, 24)),
        iv: pattern(3, 8),
        cfb: "849600c2b4b5cdb41e70bf3d3ddd357c493257b2689a4f00a8535a90828151007e2cabb1a7",
        ofb: "849600c2b4b5cdb4018012158b70f53115294aa270bcf102c7d75cbe1cb5e0268e243cb842",
        ctr: nil),
    ]
    let plaintext = pattern(1, 37)
    for sample in samples {
      let core = try #require(sample.core, "\(sample.name) rejected its key")
      #expect(
        BlockModes.cfb(core, iv: sample.iv, data: plaintext, encrypt: true)
          == hexBytes(sample.cfb), "\(sample.name) CFB")
      #expect(
        BlockModes.cfb(core, iv: sample.iv, data: hexBytes(sample.cfb), encrypt: false)
          == plaintext, "\(sample.name) CFB decrypt")
      #expect(
        BlockModes.ofb(core, iv: sample.iv, data: plaintext) == hexBytes(sample.ofb),
        "\(sample.name) OFB")
      if let ctr = sample.ctr {
        #expect(
          BlockModes.ctr(core, iv: sample.iv, data: plaintext) == hexBytes(ctr),
          "\(sample.name) CTR")
      }
    }
  }

  @Test("RC4 agrees with the Python cryptography package on a 37-byte message")
  func rc4Reference() throws {
    let stream = try #require(RC4Stream(key: pattern(4, 32)))
    var data = pattern(1, 37)
    stream.process(&data)
    #expect(
      data
        == hexBytes(
          "6ac3485fa4c7547d5aa1b69077431c8ad1828ec62e53cf965930d3cec1050e9b732ebc1160"))
  }
}
