import CommonCrypto
import Foundation

/// PBKDF2 (RFC 8018) through CommonCrypto. The zip AES format needs HMAC-SHA1 with 1,000
/// iterations, which `FileCipher` does not offer, so this is a separate helper.
enum PBKDF2 {

  enum Function {
    case hmacSHA1
    case hmacSHA256

    fileprivate var algorithm: CCPseudoRandomAlgorithm {
      switch self {
      case .hmacSHA1: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
      case .hmacSHA256: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
      }
    }
  }

  /// `length` bytes derived from the password, or nil when CommonCrypto refuses the parameters.
  static func deriveKey(
    password: [UInt8], salt: [UInt8], iterations: Int, length: Int, function: Function = .hmacSHA1
  ) -> [UInt8]? {
    guard iterations > 0, iterations <= Int(UInt32.max), length > 0 else { return nil }
    var key = [UInt8](repeating: 0, count: length)
    let status = password.withUnsafeBufferPointer { passwordBuffer in
      salt.withUnsafeBufferPointer { saltBuffer in
        key.withUnsafeMutableBufferPointer { keyBuffer in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBuffer.baseAddress.map {
              UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self)
            },
            passwordBuffer.count,
            saltBuffer.baseAddress, saltBuffer.count,
            function.algorithm, UInt32(iterations),
            keyBuffer.baseAddress, keyBuffer.count)
        }
      }
    }
    return status == kCCSuccess ? key : nil
  }
}
