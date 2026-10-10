import Foundation
import Testing

@testable import ImageToolboxKit

/// The Skein 1.3 hash built on Threefish. It is test code, used only to check ``ThreefishCore`` with
/// the known answers of Skein 1.3, Appendix C (the simple hash of section 3.5.4). The messages are
/// the bytes 0xFF, 0xFE, ... as the specification prints them. The file cipher itself uses only the
/// block cipher with a zero tweak.
private enum SkeinReference {

  /// Skein-(state bits)-(output bits): configuration, message and output stages.
  static func hash(_ message: [UInt8], stateBytes: Int, outputBits: Int) -> [UInt8] {
    var configuration = [UInt8](repeating: 0, count: 32)
    configuration.replaceSubrange(0..<4, with: [0x53, 0x48, 0x41, 0x33])
    configuration[4] = 1
    for byte in 0..<8 {
      configuration[8 + byte] = UInt8(truncatingIfNeeded: UInt64(outputBits) >> (8 * UInt64(byte)))
    }
    let chaining = ubi([UInt8](repeating: 0, count: stateBytes), configuration, type: 4)
    let state = ubi(chaining, message, type: 48)
    var output: [UInt8] = []
    var counter: UInt64 = 0
    while output.count < outputBits / 8 {
      let counterBytes = (0..<8).map { UInt8(truncatingIfNeeded: counter >> (8 * UInt64($0))) }
      output += ubi(state, counterBytes, type: 63)
      counter += 1
    }
    return Array(output.prefix(outputBits / 8))
  }

  /// UBI (section 3.4): each block is encrypted with the chaining value as the key and a tweak that
  /// holds the byte position, the block type and the first and last flags, then XORed with the block.
  static func ubi(_ chaining: [UInt8], _ message: [UInt8], type: UInt64) -> [UInt8] {
    let size = chaining.count
    let blocks = max(1, (message.count + size - 1) / size)
    var padded = message
    padded += [UInt8](repeating: 0, count: blocks * size - message.count)
    var value = chaining
    for index in 0..<blocks {
      let block = Array(padded[(index * size)..<((index + 1) * size)])
      let position = index == blocks - 1 ? UInt64(message.count) : UInt64((index + 1) * size)
      var high = type << 56
      if index == 0 { high |= 1 << 62 }
      if index == blocks - 1 { high |= 1 << 63 }
      guard let cipher = ThreefishCore(key: value, tweak: (position, high)) else {
        preconditionFailure("the chaining value has a Threefish key size")
      }
      var encrypted = block
      encrypted.withUnsafeMutableBufferPointer { cipher.encryptBlock($0.baseAddress!) }
      value = zip(encrypted, block).map { $0 ^ $1 }
    }
    return value
  }
}

/// The messages of Appendix C: the byte at position i is 255 - i.
private func descendingBytes(_ count: Int) -> [UInt8] {
  (0..<count).map { UInt8(255 - $0) }
}

@Suite("Threefish with the Skein 1.3 known answers")
struct ThreefishSkeinTests {

  @Test("Skein-256-256 (Appendix C.1, Threefish-256) for a one-byte and a 32-byte message")
  func skein256() {
    #expect(
      SkeinReference.hash([0xFF], stateBytes: 32, outputBits: 256)
        == hexBytes(
          "0b98dcd198ea0e50a7a244c444e25c23da30c10fc9a1f270a6637f1f34e67ed2"))
    #expect(
      SkeinReference.hash(descendingBytes(32), stateBytes: 32, outputBits: 256)
        == hexBytes(
          "8d0fa4ef777fd759dfd4044e6f6a5ac3c774aec943dcfc07927b723b5dbf408b"))
  }

  @Test("Skein-512-512 (Appendix C.2, Threefish-512) for 1, 64 and 128-byte messages")
  func skein512() {
    #expect(
      SkeinReference.hash([0xFF], stateBytes: 64, outputBits: 512)
        == hexBytes(
          "71b7bce6fe6452227b9ced6014249e5bf9a9754c3ad618ccc4e0aae16b316cc8"
            + "ca698d864307ed3e80b6ef1570812ac5272dc409b5a012df2a579102f340617a"))
    #expect(
      SkeinReference.hash(descendingBytes(64), stateBytes: 64, outputBits: 512)
        == hexBytes(
          "45863ba3be0c4dfc27e75d358496f4ac9a736a505d9313b42b2f5eada79fc17f"
            + "63861e947afb1d056aa199575ad3f8c9a3cc1780b5e5fa4cae050e989876625b"))
    #expect(
      SkeinReference.hash(descendingBytes(128), stateBytes: 64, outputBits: 512)
        == hexBytes(
          "91cca510c263c4ddd010530a33073309628631f308747e1bcbaa90e451cab92e"
            + "5188087af4188773a332303e6667a7a210856f742139000071f48e8ba2a5adb7"))
  }

  @Test("Skein-1024-1024 (Appendix C.3, Threefish-1024) for 1, 128 and 256-byte messages")
  func skein1024() {
    #expect(
      SkeinReference.hash([0xFF], stateBytes: 128, outputBits: 1024)
        == hexBytes(
          "e62c05802ea0152407cdd8787fda9e35703de862a4fbc119cff8590afe79250b"
            + "ccc8b3faf1bd2422ab5c0d263fb2f8afb3f796f048000381531b6f00d85161bc"
            + "0fff4bef2486b1ebcd3773fabf50ad4ad5639af9040e3f29c6c931301bf79832"
            + "e9da09857e831e82ef8b4691c235656515d437d2bda33bcec001c67ffde15ba8"))
    #expect(
      SkeinReference.hash(descendingBytes(128), stateBytes: 128, outputBits: 1024)
        == hexBytes(
          "1f3e02c46fb80a3fcd2dfbbc7c173800b40c60c2354af551189ebf433c3d85f9"
            + "ff1803e6d920493179ed7ae7fce69c3581a5a2f82d3e0c7a295574d0cd7d217c"
            + "484d2f6313d59a7718ead07d0729c24851d7e7d2491b902d489194e6b7d369db"
            + "0ab7aa106f0ee0a39a42efc54f18d93776080985f907574f995ec6a37153a578"))
    #expect(
      SkeinReference.hash(descendingBytes(256), stateBytes: 128, outputBits: 1024)
        == hexBytes(
          "842a53c99c12b0cf80cf69491be5e2f7515de8733b6ea9422dfd676665b5fa42"
            + "ffb3a9c48c217777950848cecdb48f640f81fb92bef6f88f7a85c1f7cd1446c9"
            + "161c0afe8f25ae444f40d3680081c35aa43f640fd5fa3c3c030bcc06abac01d0"
            + "98bcc984ebd8322712921e00b1ba07d6d01f26907050255ef2c8e24f716c52a5"))
  }

  @Test("Threefish-512 and -1024 decrypt what they encrypt, and a changed tweak changes the output")
  func roundTripAndTweak() throws {
    for size in [32, 64, 128] {
      let key = (0..<size).map { UInt8(($0 * 7 + 3) % 256) }
      let block = (0..<size).map { UInt8(($0 * 13 + 5) % 256) }
      let zeroTweak = try #require(ThreefishCore(key: key))
      let otherTweak = try #require(ThreefishCore(key: key, tweak: (1, 0)))
      var encrypted = block
      encrypted.withUnsafeMutableBufferPointer { zeroTweak.encryptBlock($0.baseAddress!) }
      #expect(encrypted != block)
      var tweaked = block
      tweaked.withUnsafeMutableBufferPointer { otherTweak.encryptBlock($0.baseAddress!) }
      #expect(tweaked != encrypted)
      encrypted.withUnsafeMutableBufferPointer { zeroTweak.decryptBlock($0.baseAddress!) }
      #expect(encrypted == block, "\(size)-byte block")
    }
  }
}
