import CommonCrypto
import CryptoKit
import Foundation

/// Password-based file encryption. The key comes from the password with PBKDF2-HMAC-SHA256 and a
/// random salt. An algorithm is a cipher family and a mode. The AEAD modes (GCM, CCM, EAX, OCB3,
/// GCM-SIV and ChaCha20-Poly1305) authenticate the header and the ciphertext with their own tag. The
/// other modes (CBC, CTS, CTR, CFB, CFB8, OFB and RC4) get an HMAC-SHA256 over the header and
/// the ciphertext, made with a second key from the same PBKDF2 output (encrypt then MAC).
///
/// Container format, all integers big endian:
/// - 4 bytes: "ITCF".
/// - 1 byte: format version. Version 3 is written for the algorithms added after version 2, and
///   version 2 for the others. Version 1 files (AES-256-GCM and ChaCha20-Poly1305 only) are still read.
/// - the algorithm: 1 byte in versions 1 and 2, see ``Algorithm/legacyByte``; 2 bytes in version 3, the
///   family number and then the mode number, see ``Algorithm/id``.
/// - 4 bytes: PBKDF2 iteration count.
/// - 16 bytes: salt.
/// - the IV or nonce, ``Algorithm/ivLength`` bytes.
/// - the ciphertext, then a 16-byte tag (AEAD) or a 32-byte HMAC-SHA256 (other modes).
///
/// The header is authenticated: it is the AAD of the AEAD modes and the first part of the MAC input,
/// so changing any header field makes decryption fail. CBC uses PKCS#7 padding, and CTS none.
/// The format is this package's own; the Android app's files are not read.
public enum FileCipher {

  /// The cipher behind an algorithm. Block families differ in block size and key length, and a
  /// block family takes the modes listed in ``modes``.
  public enum Family: UInt8, CaseIterable, Sendable {
    case aes = 1
    case rijndael = 25
    case aria = 2
    case camellia = 3
    case sm4 = 4
    case seed = 5
    case serpent = 6
    case tnepres = 28
    case twofish = 7
    case cast256 = 8
    case rc6 = 9
    case lea = 10
    case noekeon = 11
    case shacal2 = 12
    case threefish256 = 13
    case threefish512 = 26
    case threefish1024 = 27
    case idea = 14
    case blowfish = 15
    case tripleDES = 16
    case rc2 = 17
    case rc5 = 18
    case skipjack = 19
    case tea = 20
    case xtea = 21
    case gost28147 = 22
    case rc4 = 23
    case chaCha20 = 24

    /// The name shown to the user, with the key size.
    public var title: String {
      switch self {
      case .aes: "AES-256"
      case .rijndael: "Rijndael-256"
      case .aria: "ARIA-256"
      case .camellia: "Camellia-256"
      case .sm4: "SM4-128"
      case .seed: "SEED-128"
      case .serpent: "Serpent-256"
      case .tnepres: "Tnepres-256"
      case .twofish: "Twofish-256"
      case .cast256: "CAST-256"
      case .rc6: "RC6-256"
      case .lea: "LEA-256"
      case .noekeon: "Noekeon-128"
      case .shacal2: "SHACAL-2-256"
      case .threefish256: "Threefish-256"
      case .threefish512: "Threefish-512"
      case .threefish1024: "Threefish-1024"
      case .idea: "IDEA-128"
      case .blowfish: "Blowfish-256"
      case .tripleDES: "DESede-192"
      case .rc2: "RC2-256"
      case .rc5: "RC5-32/12-256"
      case .skipjack: "Skipjack-80"
      case .tea: "TEA-128"
      case .xtea: "XTEA-128"
      case .gost28147: "GOST 28147-89"
      case .rc4: "RC4-256"
      case .chaCha20: "ChaCha20"
      }
    }

    /// The modes this family supports. GCM is offered for the 128-bit block ciphers the Android app
    /// offers it for, CCM and GCM-SIV for AES only (Rijndael with a 128-bit block is AES). EAX, OCB3
    /// and CFB8 are offered for every 128-bit block cipher, since they need only the block cipher.
    /// CTS is offered for the same ciphers, because a file must hold at least one block for it.
    public var modes: [Mode] {
      switch self {
      case .aes, .rijndael:
        [.cbc, .cts, .ctr, .cfb, .cfb8, .ofb, .gcm, .ccm, .gcmSIV, .eax, .ocb3]
      case .aria, .sm4, .lea: [.cbc, .cts, .ctr, .cfb, .cfb8, .ofb, .gcm, .eax, .ocb3]
      case .rc4: [.stream]
      case .chaCha20: [.chaCha20Poly1305]
      default:
        blockSize == 16
          ? [.cbc, .cts, .ctr, .cfb, .cfb8, .ofb, .eax, .ocb3] : [.cbc, .ctr, .cfb, .ofb]
      }
    }

    /// The key length in bytes: the cipher's own key size, or 256 bits where the cipher takes any
    /// length. SEED, Noekeon, SM4 and TEA use 128-bit keys, as in the Android app's MD5 list.
    var keyLength: Int {
      switch self {
      case .sm4, .seed, .noekeon, .idea, .tea, .xtea: 16
      case .skipjack: 10
      case .tripleDES: 24
      case .threefish512: 64
      case .threefish1024: 128
      case .chaCha20, .aes, .rijndael, .aria, .camellia, .serpent, .tnepres, .twofish, .cast256,
        .rc6, .lea:
        32
      case .threefish256, .shacal2, .blowfish, .rc2, .rc5, .gost28147, .rc4: 32
      }
    }

    /// The block size in bytes. A stream cipher has none and returns 0.
    var blockSize: Int {
      switch self {
      case .threefish1024: 128
      case .threefish512: 64
      case .shacal2, .threefish256: 32
      case .idea, .blowfish, .tripleDES, .rc2, .rc5, .skipjack, .tea, .xtea, .gost28147: 8
      case .rc4, .chaCha20: 0
      default: 16
      }
    }

    /// The block cipher with the key already scheduled, or `nil` when the key length is wrong.
    /// RC4 and ChaCha20 are not block ciphers and return `nil`.
    func makeCore(key: [UInt8]) -> (any BlockCore)? {
      switch self {
      case .aes, .rijndael: CommonCryptoCore(.aes, key: key)
      case .aria: ARIACore(key: key)
      case .camellia: CamelliaCore(key: key)
      case .sm4: SM4Core(key: key)
      case .seed: SEEDCore(key: key)
      case .serpent: SerpentCore(key: key)
      case .tnepres: TnepresCore(key: key)
      case .twofish: TwofishCore(key: key)
      case .cast256: CAST256Core(key: key)
      case .rc6: RC6Core(key: key)
      case .lea: LEACore(key: key)
      case .noekeon: NoekeonCore(key: key)
      case .shacal2: Shacal2Core(key: key)
      case .threefish256, .threefish512, .threefish1024: ThreefishCore(key: key)
      case .idea: IDEACore(key: key)
      case .blowfish: CommonCryptoCore(.blowfish, key: key)
      case .tripleDES: CommonCryptoCore(.tripleDES, key: key)
      case .rc2: CommonCryptoCore(.rc2, key: key)
      case .rc5: RC5Core(key: key)
      case .skipjack: SkipjackCore(key: key)
      case .tea: TEACore(key: key)
      case .xtea: XTEACore(key: key)
      case .gost28147: GOST28147Core(key: key)
      case .rc4, .chaCha20: nil
      }
    }
  }

  /// How the family's cipher is run over the data.
  public enum Mode: UInt8, CaseIterable, Sendable {
    /// Cipher block chaining with PKCS#7 padding. Followed by an HMAC-SHA256 tag.
    case cbc
    /// Counter mode. Followed by an HMAC-SHA256 tag.
    case ctr
    /// Full-block cipher feedback. Followed by an HMAC-SHA256 tag.
    case cfb
    /// Full-block output feedback. Followed by an HMAC-SHA256 tag.
    case ofb
    /// Galois/Counter Mode with a 96-bit nonce and a 128-bit tag (NIST SP 800-38D).
    case gcm
    /// Counter with CBC-MAC (RFC 3610) with a 56-bit nonce and a 128-bit tag. AES only.
    case ccm
    /// The RC4 keystream. Followed by an HMAC-SHA256 tag.
    case stream
    /// ChaCha20-Poly1305 (RFC 8439).
    case chaCha20Poly1305
    /// CFB with an 8-bit feedback segment (NIST SP 800-38A). Followed by an HMAC-SHA256 tag.
    case cfb8 = 8
    /// EAX (Bellare, Rogaway and Wagner) with a 128-bit nonce and a 128-bit tag.
    case eax = 9
    /// OCB3 (RFC 7253) with a 96-bit nonce and a 128-bit tag.
    case ocb3 = 10
    /// AES-GCM-SIV (RFC 8452) with a 96-bit nonce and a 128-bit tag. AES only.
    case gcmSIV = 11
    /// CBC with ciphertext stealing, variant CBC-CS3 (NIST SP 800-38A addendum, 2010). The file
    /// keeps its length, so it must hold at least one block. Followed by an HMAC-SHA256 tag.
    case cts = 12
  }

  /// One algorithm: a family with one of its modes. The id is what the container stores.
  public struct Algorithm: Hashable, Identifiable, Sendable {

    public let family: Family
    public let mode: Mode

    /// The id stored in version 3 containers: the family number in the high byte and the mode number
    /// in the low byte.
    public var id: UInt16 { UInt16(family.rawValue) << 8 | UInt16(mode.rawValue) }

    /// The one-byte id of version 2 containers, which were written before the modes 8 and up and
    /// the families 25 and up existed: the family number shifted left by three bits, plus the mode
    /// number. `nil` for the algorithms that need version 3.
    var legacyByte: UInt8? {
      family.rawValue <= 24 && mode.rawValue <= 7 ? family.rawValue << 3 | mode.rawValue : nil
    }

    /// AES-256 in GCM mode. This is the default.
    public static let aes256GCM = Algorithm(family: .aes, mode: .gcm)

    /// ChaCha20-Poly1305.
    public static let chaCha20Poly1305 = Algorithm(family: .chaCha20, mode: .chaCha20Poly1305)

    /// Every algorithm, grouped by family in the order of ``Family``.
    public static let allCases: [Algorithm] = Family.allCases.flatMap { family in
      family.modes.map { Algorithm(family: family, mode: $0) }
    }

    /// The algorithm with this id, or `nil` when no algorithm has it.
    public init?(id: UInt16) {
      guard let family = Family(rawValue: UInt8(truncatingIfNeeded: id >> 8)),
        let mode = Mode(rawValue: UInt8(truncatingIfNeeded: id & 0xFF)),
        family.modes.contains(mode)
      else { return nil }
      self.init(family: family, mode: mode)
    }

    /// The algorithm with a version 2 id, or `nil`. Only the families and modes of that registry are
    /// accepted, so a version 2 file cannot name an algorithm added later.
    init?(legacyByte byte: UInt8) {
      guard let family = Family(rawValue: byte >> 3), family.rawValue <= 24,
        let mode = Mode(rawValue: byte & 7),
        family.modes.contains(mode)
      else { return nil }
      self.init(family: family, mode: mode)
    }

    /// The mode must be one the family supports; an unsupported pair is a programming error.
    init(family: Family, mode: Mode) {
      precondition(family.modes.contains(mode), "\(family) has no \(mode) mode")
      self.family = family
      self.mode = mode
    }

    /// The name shown to the user, such as "AES-256-GCM" or "Serpent-256-CFB". CBC, CTR, CFB and
    /// OFB do not name their padding or MAC here: CBC uses PKCS#7 and every non-AEAD mode has an
    /// HMAC-SHA256.
    public var title: String {
      switch mode {
      case .stream: family.title
      case .chaCha20Poly1305: "\(family.title)-Poly1305"
      default: "\(family.title)-\(modeTitle)"
      }
    }

    private var modeTitle: String {
      switch mode {
      case .cbc: "CBC"
      case .ctr: "CTR"
      case .cfb: "CFB"
      case .ofb: "OFB"
      case .gcm: "GCM"
      case .ccm: "CCM"
      case .stream: ""
      case .chaCha20Poly1305: "Poly1305"
      case .cfb8: "CFB8"
      case .eax: "EAX"
      case .ocb3: "OCB3"
      case .gcmSIV: "GCM-SIV"
      case .cts: "CTS"
      }
    }

    /// The length of the IV or nonce stored in the header.
    public var ivLength: Int {
      switch mode {
      case .cbc, .cts, .ctr, .cfb, .cfb8, .ofb: family.blockSize
      case .gcm, .chaCha20Poly1305, .ocb3, .gcmSIV: 12
      case .eax: 16
      case .ccm: 7
      case .stream: 0
      }
    }

    /// The length of the authenticator after the ciphertext: 16 bytes for the AEAD modes, 32 for
    /// HMAC-SHA256.
    public var trailerLength: Int { isAEAD ? 16 : 32 }

    var isAEAD: Bool {
      [.gcm, .ccm, .chaCha20Poly1305, .eax, .ocb3, .gcmSIV].contains(mode)
    }
  }

  public enum Failure: Error, Equatable {
    /// The data is not a file of this format, or it is shorter than the header.
    case notEncrypted
    /// The file uses a version, an algorithm or an iteration count this build does not accept.
    case unsupported
    /// The password is wrong, or the file was changed.
    case authenticationFailed
    case keyDerivationFailed
    /// The data is shorter than one block, and the CTS mode needs at least one.
    case tooShort
  }

  /// PBKDF2 iterations used for new files.
  public static let defaultIterations = 200_000

  /// The largest iteration count a file may ask for. It limits the work a damaged header can cause.
  public static let maximumIterations = 10_000_000

  private static let magic = Array("ITCF".utf8)
  private static let legacyVersion: UInt8 = 1
  private static let version2: UInt8 = 2
  private static let currentVersion: UInt8 = 3
  private static let saltSize = 16
  private static let macKeyLength = 32

  public static func encrypt(
    _ data: Data,
    password: String,
    algorithm: Algorithm = .aes256GCM,
    iterations: Int = defaultIterations
  ) throws -> Data {
    guard (1...maximumIterations).contains(iterations) else { throw Failure.unsupported }
    let salt = randomBytes(saltSize)
    let iv = randomBytes(algorithm.ivLength)
    let header = makeHeader(
      algorithm: algorithm, iterations: iterations, salt: salt, iv: iv)
    let keys = try deriveKeys(
      password: password, salt: salt, iterations: iterations, family: algorithm.family)
    let body = try seal(
      [UInt8](data), algorithm: algorithm, keys: keys, iv: iv, header: header)
    return Data(header + body)
  }

  public static func decrypt(_ input: Data, password: String) throws -> Data {
    // A copy starts at index zero, so the offsets below are plain array offsets.
    let data = [UInt8](input)
    guard data.count >= 6, Array(data.prefix(4)) == magic else {
      throw Failure.notEncrypted
    }
    let version = data[4]
    // The algorithm takes one byte in version 1 and 2, and two bytes in version 3.
    let algorithmLength: Int
    switch version {
    case legacyVersion, version2: algorithmLength = 1
    case currentVersion: algorithmLength = 2
    default: throw Failure.unsupported
    }
    let fixedHeaderSize = 4 + 1 + algorithmLength + 4 + saltSize
    guard data.count >= fixedHeaderSize else { throw Failure.notEncrypted }
    // Version 1 wrote only two algorithms, and their ids were 1 and 2. Version 2 uses the one-byte
    // registry, and version 3 the two-byte ids.
    let algorithm: Algorithm?
    switch version {
    case legacyVersion: algorithm = legacyAlgorithm(data[5])
    case version2: algorithm = Algorithm(legacyByte: data[5])
    default: algorithm = Algorithm(id: UInt16(data[5]) << 8 | UInt16(data[6]))
    }
    guard let algorithm else { throw Failure.unsupported }
    let iterationsOffset = 5 + algorithmLength
    let iterations = Int(readUInt32(data, at: iterationsOffset))
    guard (1...maximumIterations).contains(iterations) else { throw Failure.unsupported }

    let headerSize = fixedHeaderSize + algorithm.ivLength
    guard data.count >= headerSize + algorithm.trailerLength else {
      throw Failure.notEncrypted
    }
    let header = Array(data[0..<headerSize])
    let saltStart = iterationsOffset + 4
    let salt = Array(data[saltStart..<(saltStart + saltSize)])
    let iv = Array(data[fixedHeaderSize..<headerSize])
    let body = Array(data[headerSize...])
    let keys = try deriveKeys(
      password: password, salt: salt, iterations: iterations, family: algorithm.family)
    return Data(try open(body, algorithm: algorithm, keys: keys, iv: iv, header: header))
  }

  // MARK: - Sealing and opening

  private struct Keys {
    let cipher: [UInt8]
    let mac: [UInt8]
  }

  private static func seal(
    _ plaintext: [UInt8], algorithm: Algorithm, keys: Keys, iv: [UInt8], header: [UInt8]
  ) throws -> [UInt8] {
    let family = algorithm.family
    switch algorithm.mode {
    case .chaCha20Poly1305:
      let sealed = try ChaChaPoly.seal(
        Data(plaintext), using: SymmetricKey(data: keys.cipher),
        nonce: ChaChaPoly.Nonce(data: Data(iv)), authenticating: Data(header))
      return Array(sealed.ciphertext) + Array(sealed.tag)

    case .gcm where family == .aes:
      let sealed = try AES.GCM.seal(
        Data(plaintext), using: SymmetricKey(data: keys.cipher),
        nonce: AES.GCM.Nonce(data: Data(iv)), authenticating: Data(header))
      return Array(sealed.ciphertext) + Array(sealed.tag)

    case .gcm:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      let sealed = BlockModes.gcmSeal(core, nonce: iv, aad: header, plaintext: plaintext)
      return sealed.ciphertext + sealed.tag

    case .ccm:
      guard let core = family.makeCore(key: keys.cipher),
        let sealed = BlockModes.ccmSeal(
          core, nonce: iv, aad: header, plaintext: plaintext, tagLength: 16)
      else { throw Failure.unsupported }
      return sealed.ciphertext + sealed.tag

    case .eax:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      let sealed = BlockAEAD.eaxSeal(core, nonce: iv, aad: header, plaintext: plaintext)
      return sealed.ciphertext + sealed.tag

    case .ocb3:
      guard let core = family.makeCore(key: keys.cipher),
        let sealed = BlockAEAD.ocbSeal(core, nonce: iv, aad: header, plaintext: plaintext)
      else { throw Failure.unsupported }
      return sealed.ciphertext + sealed.tag

    case .gcmSIV:
      guard
        let sealed = BlockAEAD.gcmSIVSeal(
          key: keys.cipher, nonce: iv, aad: header, plaintext: plaintext)
      else { throw Failure.unsupported }
      return sealed.ciphertext + sealed.tag

    case .stream:
      guard let stream = RC4Stream(key: keys.cipher) else { throw Failure.unsupported }
      var ciphertext = plaintext
      stream.process(&ciphertext)
      return ciphertext + macTag(header + ciphertext, key: keys.mac)

    case .cts:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard let ciphertext = BlockModes.ctsEncrypt(core, iv: iv, plaintext: plaintext) else {
        throw Failure.tooShort
      }
      return ciphertext + macTag(header + ciphertext, key: keys.mac)

    case .cbc, .ctr, .cfb, .cfb8, .ofb:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      let ciphertext: [UInt8]
      switch algorithm.mode {
      case .cbc: ciphertext = BlockModes.cbcEncrypt(core, iv: iv, plaintext: plaintext)
      case .ctr: ciphertext = BlockModes.ctr(core, iv: iv, data: plaintext)
      case .cfb: ciphertext = BlockModes.cfb(core, iv: iv, data: plaintext, encrypt: true)
      case .cfb8: ciphertext = BlockModes.cfb8(core, iv: iv, data: plaintext, encrypt: true)
      default: ciphertext = BlockModes.ofb(core, iv: iv, data: plaintext)
      }
      return ciphertext + macTag(header + ciphertext, key: keys.mac)
    }
  }

  private static func open(
    _ body: [UInt8], algorithm: Algorithm, keys: Keys, iv: [UInt8], header: [UInt8]
  ) throws -> [UInt8] {
    let family = algorithm.family
    let trailer = algorithm.trailerLength
    let ciphertext = Array(body.prefix(body.count - trailer))
    let tag = Array(body.suffix(trailer))

    if !algorithm.isAEAD {
      let valid = HMAC<SHA256>.isValidAuthenticationCode(
        Data(tag), authenticating: Data(header + ciphertext),
        using: SymmetricKey(data: keys.mac))
      guard valid else { throw Failure.authenticationFailed }
    }

    switch algorithm.mode {
    case .chaCha20Poly1305:
      return try authenticated {
        let box = try ChaChaPoly.SealedBox(
          nonce: ChaChaPoly.Nonce(data: Data(iv)), ciphertext: Data(ciphertext), tag: Data(tag))
        return Array(
          try ChaChaPoly.open(
            box, using: SymmetricKey(data: keys.cipher), authenticating: Data(header)))
      }

    case .gcm where family == .aes:
      return try authenticated {
        let box = try AES.GCM.SealedBox(
          nonce: AES.GCM.Nonce(data: Data(iv)), ciphertext: Data(ciphertext), tag: Data(tag))
        return Array(
          try AES.GCM.open(
            box, using: SymmetricKey(data: keys.cipher), authenticating: Data(header)))
      }

    case .gcm:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard
        let plaintext = BlockModes.gcmOpen(
          core, nonce: iv, aad: header, ciphertext: ciphertext, tag: tag)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .ccm:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard
        let plaintext = BlockModes.ccmOpen(
          core, nonce: iv, aad: header, ciphertext: ciphertext, tag: tag)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .eax:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard
        let plaintext = BlockAEAD.eaxOpen(
          core, nonce: iv, aad: header, ciphertext: ciphertext, tag: tag)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .ocb3:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard
        let plaintext = BlockAEAD.ocbOpen(
          core, nonce: iv, aad: header, ciphertext: ciphertext, tag: tag)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .gcmSIV:
      guard
        let plaintext = BlockAEAD.gcmSIVOpen(
          key: keys.cipher, nonce: iv, aad: header, ciphertext: ciphertext, tag: tag)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .stream:
      guard let stream = RC4Stream(key: keys.cipher) else { throw Failure.unsupported }
      var plaintext = ciphertext
      stream.process(&plaintext)
      return plaintext

    case .cts:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      guard let plaintext = BlockModes.ctsDecrypt(core, iv: iv, ciphertext: ciphertext)
      else { throw Failure.authenticationFailed }
      return plaintext

    case .cbc, .ctr, .cfb, .cfb8, .ofb:
      guard let core = family.makeCore(key: keys.cipher) else { throw Failure.unsupported }
      switch algorithm.mode {
      case .cbc:
        guard let plaintext = BlockModes.cbcDecrypt(core, iv: iv, ciphertext: ciphertext)
        else { throw Failure.authenticationFailed }
        return plaintext
      case .ctr: return BlockModes.ctr(core, iv: iv, data: ciphertext)
      case .cfb: return BlockModes.cfb(core, iv: iv, data: ciphertext, encrypt: false)
      case .cfb8: return BlockModes.cfb8(core, iv: iv, data: ciphertext, encrypt: false)
      default: return BlockModes.ofb(core, iv: iv, data: ciphertext)
      }
    }
  }

  /// Runs an AEAD operation and reports every failure as a wrong password or a damaged file.
  private static func authenticated(_ operation: () throws -> [UInt8]) throws -> [UInt8] {
    do {
      return try operation()
    } catch {
      throw Failure.authenticationFailed
    }
  }

  // MARK: - Helpers

  private static func legacyAlgorithm(_ byte: UInt8) -> Algorithm? {
    switch byte {
    case 1: .aes256GCM
    case 2: .chaCha20Poly1305
    default: nil
    }
  }

  private static func makeHeader(
    algorithm: Algorithm, iterations: Int, salt: [UInt8], iv: [UInt8]
  ) -> [UInt8] {
    var header = magic
    if let legacy = algorithm.legacyByte {
      header += [version2, legacy]
    } else {
      header += [currentVersion, UInt8(algorithm.id >> 8), UInt8(algorithm.id & 0xFF)]
    }
    header += bigEndianBytes(UInt32(iterations))
    header += salt
    header += iv
    return header
  }

  /// Derives the cipher key and the MAC key with one PBKDF2 run. The MAC key is always 32 bytes,
  /// and the first bytes of the output do not depend on how many bytes are asked for, so the
  /// AEAD keys of version 1 files are the same as before.
  private static func deriveKeys(
    password: String, salt: [UInt8], iterations: Int, family: Family
  ) throws -> Keys {
    let length = family.keyLength + macKeyLength
    var material = [UInt8](repeating: 0, count: length)
    let passwordBytes = Array(password.utf8)
    let status = CCKeyDerivationPBKDF(
      CCPBKDFAlgorithm(kCCPBKDF2),
      passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
      salt, salt.count,
      CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
      UInt32(iterations),
      &material, length)
    guard status == kCCSuccess else { throw Failure.keyDerivationFailed }
    return Keys(
      cipher: Array(material.prefix(family.keyLength)),
      mac: Array(material.suffix(macKeyLength)))
  }

  private static func macTag(_ message: [UInt8], key: [UInt8]) -> [UInt8] {
    Array(HMAC<SHA256>.authenticationCode(for: Data(message), using: SymmetricKey(data: key)))
  }

  private static func randomBytes(_ count: Int) -> [UInt8] {
    (0..<count).map { _ in UInt8.random(in: 0...255) }
  }

  private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  private static func readUInt32(_ data: [UInt8], at offset: Int) -> UInt32 {
    UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
      | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
  }
}
