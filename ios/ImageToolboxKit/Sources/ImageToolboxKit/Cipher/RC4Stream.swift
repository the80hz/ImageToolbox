import Foundation

/// RC4 (ARCFOUR), a stream cipher. Encryption and decryption are the same operation, so the state
/// advances with every byte processed. RC4 is kept only because the Android app offers it; it has
/// known biases and is not a choice for new files.
final class RC4Stream {

  private var state: [UInt8]
  private var i: UInt8 = 0
  private var j: UInt8 = 0

  /// Returns `nil` when the key is empty or longer than 256 bytes.
  init?(key: [UInt8]) {
    guard (1...256).contains(key.count) else { return nil }
    state = (0..<256).map { UInt8($0) }
    var j = 0
    for index in 0..<256 {
      j = (j + Int(state[index]) + Int(key[index % key.count])) & 0xFF
      state.swapAt(index, j)
    }
  }

  /// XORs the keystream into `data`, advancing the state.
  func process(_ data: inout [UInt8]) {
    for index in data.indices {
      i = i &+ 1
      j = j &+ state[Int(i)]
      state.swapAt(Int(i), Int(j))
      let keyByte = state[Int(state[Int(i)] &+ state[Int(j)])]
      data[index] ^= keyByte
    }
  }
}
