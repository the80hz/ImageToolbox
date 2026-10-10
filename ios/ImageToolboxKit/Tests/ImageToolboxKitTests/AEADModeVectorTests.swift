import Foundation
import Testing

@testable import ImageToolboxKit

/// Known answers for EAX, OCB3 and AES-GCM-SIV.
///
/// - OCB3: RFC 7253, appendix A, AEAD_AES_128_OCB_TAGLEN128. The associated data and the plaintext of
///   each case are the bytes 0, 1, 2, ... of the stated length.
/// - GCM-SIV: RFC 8452, appendix C.2, AEAD_AES_256_GCM_SIV: the empty case, the 8-byte case and the
///   8-byte case with one byte of associated data.
/// - EAX: the paper of Bellare, Rogaway and Wagner prints no vectors. The vectors are cases 1 to 4
///   and 6 of LibTomCrypt's eax_test.c, as copied in Dropbear. That file gives no source for cases 1
///   to 4 and attributes case 6 to Brian Gladman. The tags of cases 2 and 3 also appear in a search
///   result that quotes the same file.
@Suite("Authenticated modes: EAX, OCB3 and AES-GCM-SIV")
struct AEADModeVectorTests {

  /// The bytes 0, 1, ... of `count` bytes, as the RFC 7253 vectors use them.
  private func sequence(_ count: Int) -> [UInt8] {
    (0..<count).map { UInt8($0) }
  }

  private struct EAXVector {
    let number: Int
    let key: String
    let nonce: String
    let header: String
    let message: String
    let ciphertext: String
    let tag: String
  }

  private static let eaxVectors: [EAXVector] = [
    EAXVector(
      number: 1, key: "000102030405060708090a0b0c0d0e0f", nonce: "", header: "", message: "",
      ciphertext: "", tag: "9ad07e7dbff301f505de596b9615dfff"),
    EAXVector(
      number: 2, key: "000102030405060708090a0b0c0d0e0f",
      nonce: "000102030405060708090a0b0c0d0e0f", header: "", message: "", ciphertext: "",
      tag: "1ce10d3effd4cadbe2e44b58d60ab9ec"),
    EAXVector(
      number: 3, key: "000102030405060708090a0b0c0d0e0f", nonce: "",
      header: "000102030405060708090a0b0c0d0e0f", message: "", ciphertext: "",
      tag: "3a698f7a270e51b0f65b3d3e47193cff"),
    EAXVector(
      number: 4, key: "000102030405060708090a0b0c0d0e0f",
      nonce: "000102030405060708090a0b0c0d0e0f",
      header: "000102030405060708090a0b0c0d0e0f",
      message: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
      ciphertext: "29d878d1a3be857b6fb8c8ea5950a778331fbf2ccf33986f35e8cf121dcb30bc",
      tag: "4fbe0338be1c8c7e1d7ae7e45b92c587"),
    EAXVector(
      number: 6, key: "233952dee4d5ed5f9b9c6d6ff80ff478", nonce: "62ec67f9c3a4a407fcb2a8c49031a8b3",
      header: "6bfb914fd07eae6b", message: "", ciphertext: "",
      tag: "e037830e8389f27b025a2d6527e79d01"),
  ]

  @Test("EAX, LibTomCrypt eax_test.c cases 1 to 4 and 6 (AES-128)")
  func eaxVectors() throws {
    for vector in Self.eaxVectors {
      let core = try #require(CommonCryptoCore(.aes, key: hexBytes(vector.key)))
      let sealed = BlockAEAD.eaxSeal(
        core, nonce: hexBytes(vector.nonce), aad: hexBytes(vector.header),
        plaintext: hexBytes(vector.message))
      #expect(sealed.ciphertext == hexBytes(vector.ciphertext), "EAX case \(vector.number)")
      #expect(sealed.tag == hexBytes(vector.tag), "EAX case \(vector.number) tag")
      #expect(
        BlockAEAD.eaxOpen(
          core, nonce: hexBytes(vector.nonce), aad: hexBytes(vector.header),
          ciphertext: sealed.ciphertext, tag: sealed.tag) == hexBytes(vector.message),
        "EAX case \(vector.number) open")
    }
  }

  @Test("EAX refuses a changed tag, ciphertext, header or nonce")
  func eaxTamper() throws {
    let core = try #require(CommonCryptoCore(.aes, key: hexBytes(Self.eaxVectors[3].key)))
    let nonce = hexBytes(Self.eaxVectors[3].nonce)
    let header = hexBytes(Self.eaxVectors[3].header)
    let sealed = BlockAEAD.eaxSeal(core, nonce: nonce, aad: header, plaintext: sequence(20))
    var badTag = sealed.tag
    badTag[0] ^= 0x01
    var badBody = sealed.ciphertext
    badBody[5] ^= 0x10
    #expect(
      BlockAEAD.eaxOpen(core, nonce: nonce, aad: header, ciphertext: sealed.ciphertext, tag: badTag)
        == nil)
    #expect(
      BlockAEAD.eaxOpen(core, nonce: nonce, aad: header, ciphertext: badBody, tag: sealed.tag)
        == nil)
    #expect(
      BlockAEAD.eaxOpen(
        core, nonce: nonce, aad: [1], ciphertext: sealed.ciphertext, tag: sealed.tag) == nil)
    #expect(
      BlockAEAD.eaxOpen(
        core, nonce: [0], aad: header, ciphertext: sealed.ciphertext, tag: sealed.tag) == nil)
  }

  @Test("OCB3, RFC 7253 appendix A (AEAD_AES_128_OCB_TAGLEN128)")
  func ocbVectors() throws {
    let core = try #require(
      CommonCryptoCore(.aes, key: hexBytes("000102030405060708090A0B0C0D0E0F")))
    // (nonce, length of the associated data and of the plaintext, ciphertext and tag)
    let vectors: [(String, Int, String)] = [
      ("BBAA99887766554433221100", 0, "785407BFFFC8AD9EDCC5520AC9111EE6"),
      (
        "BBAA99887766554433221101", 8,
        "6820B3657B6F615A5725BDA0D3B4EB3A257C9AF1F8F03009"
      ),
      (
        "BBAA99887766554433221104", 16,
        "571D535B60B277188BE5147170A9A22C3AD7A4FF3835B8C5701C1CCEC8FC3358"
      ),
      (
        "BBAA99887766554433221107", 24,
        "1CA2207308C87C010756104D8840CE1952F09673A448A122C92C62241051F57356D7F3C90BB0E07F"
      ),
      (
        "BBAA9988776655443322110A", 32,
        "BD6F6C496201C69296C11EFD138A467ABD3C707924B964DEAFFC40319AF5A48540FBBA186C5553C68AD9F592A79A4240"
      ),
      (
        "BBAA9988776655443322110D", 40,
        "D5CA91748410C1751FF8A2F618255B68A0A12E093FF454606E59F9C1D0DDC54B65E8628E568BAD7AED07BA06A4A69483A7035490C5769E60"
      ),
    ]
    for (nonce, length, output) in vectors {
      let data = sequence(length)
      let sealed = try #require(
        BlockAEAD.ocbSeal(
          core, nonce: hexBytes(nonce), aad: data, plaintext: data), "OCB3 length \(length)")
      #expect(sealed.ciphertext + sealed.tag == hexBytes(output), "OCB3 length \(length)")
      #expect(
        BlockAEAD.ocbOpen(
          core, nonce: hexBytes(nonce), aad: data, ciphertext: sealed.ciphertext, tag: sealed.tag)
          == data, "OCB3 open length \(length)")
    }
  }

  @Test("OCB3 round-trips every length from 0 to 67 bytes and refuses a changed byte")
  func ocbLengths() throws {
    let core = try #require(CommonCryptoCore(.aes, key: sequence(16)))
    let nonce = sequence(12)
    for length in 0...67 {
      let plaintext = (0..<length).map { UInt8(($0 * 37 + 11) % 256) }
      let sealed = try #require(
        BlockAEAD.ocbSeal(core, nonce: nonce, aad: [7, 8, 9], plaintext: plaintext))
      #expect(sealed.ciphertext.count == length)
      #expect(
        BlockAEAD.ocbOpen(
          core, nonce: nonce, aad: [7, 8, 9], ciphertext: sealed.ciphertext, tag: sealed.tag)
          == plaintext, "length \(length)")
      if length > 0 {
        var changed = sealed.ciphertext
        changed[length - 1] ^= 0x04
        #expect(
          BlockAEAD.ocbOpen(
            core, nonce: nonce, aad: [7, 8, 9], ciphertext: changed, tag: sealed.tag) == nil,
          "length \(length) changed byte")
      }
    }
    let sealed = try #require(
      BlockAEAD.ocbSeal(core, nonce: nonce, aad: [], plaintext: [1, 2, 3]))
    #expect(
      BlockAEAD.ocbOpen(
        core, nonce: nonce, aad: [0], ciphertext: sealed.ciphertext, tag: sealed.tag)
        == nil)
  }

  @Test("AES-256-GCM-SIV, RFC 8452 appendix C.2, the empty message and the 8-byte message")
  func gcmSIVVectors() throws {
    let key = hexBytes("01" + String(repeating: "00", count: 31))
    let nonce = hexBytes("03" + String(repeating: "00", count: 11))
    let empty = BlockAEAD.gcmSIVSeal(key: key, nonce: nonce, aad: [], plaintext: [])
    #expect(empty?.ciphertext == [])
    #expect(empty?.tag == hexBytes("07f5f4169bbf55a8400cd47ea6fd400f"))

    let eightBytes = hexBytes("0100000000000000")
    let sealed = try #require(
      BlockAEAD.gcmSIVSeal(key: key, nonce: nonce, aad: [], plaintext: eightBytes))
    #expect(
      sealed.ciphertext + sealed.tag
        == hexBytes("c2ef328e5c71c83b843122130f7364b761e0b97427e3df28"))
    #expect(
      BlockAEAD.gcmSIVOpen(
        key: key, nonce: nonce, aad: [], ciphertext: sealed.ciphertext, tag: sealed.tag)
        == eightBytes)

    // The seventh case of C.2: an 8-byte message with the one-byte associated data 01.
    let withAAD = try #require(
      BlockAEAD.gcmSIVSeal(
        key: key, nonce: nonce, aad: [0x01], plaintext: hexBytes("0200000000000000")))
    #expect(
      withAAD.ciphertext + withAAD.tag
        == hexBytes("1de22967237a813291213f267e3b452f02d01ae33e4ec854"))
  }

  @Test("AES-GCM-SIV round-trips with associated data, and refuses a changed tag or byte")
  func gcmSIVTamper() throws {
    let key = sequence(16)
    let nonce = sequence(12)
    for length in [0, 1, 15, 16, 17, 40] {
      let plaintext = (0..<length).map { UInt8(($0 * 5 + 1) % 256) }
      let sealed = try #require(
        BlockAEAD.gcmSIVSeal(key: key, nonce: nonce, aad: [1, 2, 3], plaintext: plaintext))
      #expect(
        BlockAEAD.gcmSIVOpen(
          key: key, nonce: nonce, aad: [1, 2, 3], ciphertext: sealed.ciphertext, tag: sealed.tag)
          == plaintext, "length \(length)")
      var badTag = sealed.tag
      badTag[15] ^= 0x80
      #expect(
        BlockAEAD.gcmSIVOpen(
          key: key, nonce: nonce, aad: [1, 2, 3], ciphertext: sealed.ciphertext, tag: badTag)
          == nil, "length \(length) tag")
      if length > 0 {
        var changed = sealed.ciphertext
        changed[0] ^= 0x01
        #expect(
          BlockAEAD.gcmSIVOpen(
            key: key, nonce: nonce, aad: [1, 2, 3], ciphertext: changed, tag: sealed.tag) == nil,
          "length \(length) byte")
      }
    }
  }

  @Test("AES-GCM-SIV takes 16 and 32-byte keys only, and 12-byte nonces only")
  func gcmSIVParameters() {
    #expect(
      BlockAEAD.gcmSIVSeal(key: sequence(24), nonce: sequence(12), aad: [], plaintext: [1]) == nil)
    #expect(
      BlockAEAD.gcmSIVSeal(key: sequence(32), nonce: sequence(8), aad: [], plaintext: [1]) == nil)
  }

  @Test("POLYVAL of zero blocks is zero (RFC 8452 section 3)")
  func polyvalZero() {
    #expect(
      BlockAEAD.polyval(hashKey: sequence(16), blocks: [UInt8](repeating: 0, count: 32))
        == [UInt8](repeating: 0, count: 16))
  }
}
