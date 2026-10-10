import Foundation

/// Tnepres, Serpent with its byte order reversed (Anderson, Biham and Knudsen), 128-bit block,
/// 128, 192 or 256-bit key.
///
/// The Bouncy Castle TnepresEngine reads the block as four big-endian words in reverse order and
/// the key as big-endian words from its last four bytes backwards, and it pads a short key the way
/// Serpent does. Reversing the bytes of the block and of the key gives the same words, so Tnepres
/// is ``SerpentCore`` on the reversed key, with the block reversed before and after each call.
final class TnepresCore: BlockCore {
  let blockSize = 16

  private let serpent: SerpentCore

  /// Returns `nil` unless the key is 16, 24 or 32 bytes long.
  init?(key: [UInt8]) {
    guard let serpent = SerpentCore(key: Array(key.reversed())) else { return nil }
    self.serpent = serpent
  }

  func encryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    TnepresCore.reverse(block)
    serpent.encryptBlock(block)
    TnepresCore.reverse(block)
  }

  func decryptBlock(_ block: UnsafeMutablePointer<UInt8>) {
    TnepresCore.reverse(block)
    serpent.decryptBlock(block)
    TnepresCore.reverse(block)
  }

  private static func reverse(_ block: UnsafeMutablePointer<UInt8>) {
    for index in 0..<8 {
      let byte = block[index]
      block[index] = block[15 - index]
      block[15 - index] = byte
    }
  }
}
