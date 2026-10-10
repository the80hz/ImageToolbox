import Foundation

/// Failures shared by the pure Swift codecs: xz, lzma, bzip2, zstd and 7z.
public enum ArchiveCodecError: Error, Equatable, Sendable {
  /// The data is damaged, truncated or not in the format.
  case malformed
  /// The data is valid but uses a feature this implementation does not read, such as a zstd
  /// dictionary, a 7z PPMd coder or an xz filter other than LZMA2.
  case unsupported
  /// A checksum stored in the data does not match the content.
  case checksumMismatch
  /// The decoded data would be larger than the limit the caller set.
  case tooLarge
}

/// The limits applied when the caller gives none.
public enum ArchiveCodecLimits {
  /// The largest decoded size, in bytes, that the codecs produce unless asked for more.
  public static let defaultMaximumOutputSize = 1 << 30
}

/// A growing output buffer that decoders write into with raw pointers. Back references read the
/// bytes already written, so the buffer doubles as the dictionary.
final class ByteSink {
  /// Spare room that decoders may write past `limit` before the limit check runs.
  private static let slack = 1 << 12

  private(set) var base: UnsafeMutablePointer<UInt8>
  private(set) var capacity: Int
  var count = 0
  let limit: Int

  init(limit: Int) {
    self.limit = limit
    capacity = 4096
    base = malloc(capacity)!.assumingMemoryBound(to: UInt8.self)
  }

  deinit { free(base) }

  /// Makes room for `extra` more bytes after `count`.
  func reserve(_ extra: Int) throws {
    let needed = count + extra
    if needed <= capacity { return }
    guard needed - Self.slack <= limit else { throw ArchiveCodecError.tooLarge }
    let target = min(max(needed, capacity * 2), limit + Self.slack)
    guard let grown = realloc(base, max(target, needed)) else { throw ArchiveCodecError.tooLarge }
    base = grown.assumingMemoryBound(to: UInt8.self)
    capacity = max(target, needed)
  }

  /// Grows the buffer in large steps for a decoder that writes without per-byte checks. Afterwards
  /// at least 512 bytes are free, and no more than the limit plus the slack is allocated.
  func reserveForDecoding() throws {
    try checkLimit()
    try reserve(min(1 << 16, limit - count + 512))
  }

  /// Throws when more than `limit` bytes were written.
  func checkLimit() throws {
    guard count <= limit else { throw ArchiveCodecError.tooLarge }
  }

  func append(_ byte: UInt8) throws {
    try reserve(1)
    base[count] = byte
    count += 1
  }

  func append(contentsOf bytes: UnsafeBufferPointer<UInt8>) throws {
    guard let source = bytes.baseAddress, !bytes.isEmpty else { return }
    try reserve(bytes.count)
    (base + count).update(from: source, count: bytes.count)
    count += bytes.count
    try checkLimit()
  }

  func append(contentsOf bytes: [UInt8]) throws {
    try bytes.withUnsafeBufferPointer { try append(contentsOf: $0) }
  }

  /// Appends `length` bytes copied from `distance` bytes back. The ranges may overlap.
  func appendCopy(distance: Int, length: Int) throws {
    guard distance > 0, distance <= count else { throw ArchiveCodecError.malformed }
    try reserve(length)
    var source = count - distance
    var target = count
    for _ in 0..<length {
      base[target] = base[source]
      target += 1
      source += 1
    }
    count = target
  }

  func append(repeating byte: UInt8, count repeats: Int) throws {
    try reserve(repeats)
    (base + count).update(repeating: byte, count: repeats)
    count += repeats
    try checkLimit()
  }

  /// A copy of the bytes from `start` to the end.
  func data(from start: Int = 0) -> Data {
    Data(bytes: base + start, count: count - start)
  }

  func array(from start: Int = 0) -> [UInt8] {
    Array(UnsafeBufferPointer(start: base + start, count: count - start))
  }

  func buffer(from start: Int, to end: Int) -> UnsafeBufferPointer<UInt8> {
    UnsafeBufferPointer(start: base + start, count: end - start)
  }
}

/// Checksums used by the container formats, computed over raw buffers.
enum ArchiveChecksum {

  private static let crc32Table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    return value
  }

  private static let crc64Table: [UInt64] = (0..<256).map { index in
    var value = UInt64(index)
    for _ in 0..<8 { value = value & 1 == 1 ? 0xC96C_5795_D787_0F42 ^ (value >> 1) : value >> 1 }
    return value
  }

  /// The bzip2 CRC: the polynomial 0x04C11DB7 processed most significant bit first.
  private static let bzip2Table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index) << 24
    for _ in 0..<8 { value = value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1 }
    return value
  }

  static func crc32(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
    crc32Table.withUnsafeBufferPointer { table in
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
      return crc ^ 0xFFFF_FFFF
    }
  }

  static func crc32(_ bytes: [UInt8]) -> UInt32 {
    bytes.withUnsafeBufferPointer { crc32($0) }
  }

  /// CRC-64/XZ (ECMA-182, reflected), the default integrity check of xz.
  static func crc64(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
    crc64Table.withUnsafeBufferPointer { table in
      var crc: UInt64 = ~0
      for byte in bytes { crc = table[Int((crc ^ UInt64(byte)) & 0xFF)] ^ (crc >> 8) }
      return ~crc
    }
  }

  static func bzip2CRC(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
    bzip2Table.withUnsafeBufferPointer { table in
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in bytes { crc = (crc << 8) ^ table[Int((crc >> 24) ^ UInt32(byte))] }
      return ~crc
    }
  }

  // MARK: - XXH64

  /// XXH64 with seed 0, the content checksum of zstd frames (the low 32 bits are stored).
  static func xxh64(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
    let prime1: UInt64 = 0x9E37_79B1_85EB_CA87
    let prime2: UInt64 = 0xC2B2_AE3D_27D4_EB4F
    let prime3: UInt64 = 0x1656_67B1_9E37_79F9
    let prime4: UInt64 = 0x85EB_CA77_C2B2_AE63
    let prime5: UInt64 = 0x27D4_EB2F_1656_67C5

    func rotate(_ value: UInt64, _ bits: UInt64) -> UInt64 {
      (value << bits) | (value >> (64 - bits))
    }
    func round(_ accumulator: UInt64, _ input: UInt64) -> UInt64 {
      rotate(accumulator &+ input &* prime2, 31) &* prime1
    }
    func merge(_ accumulator: UInt64, _ value: UInt64) -> UInt64 {
      (accumulator ^ round(0, value)) &* prime1 &+ prime4
    }
    func read64(_ offset: Int) -> UInt64 {
      var value: UInt64 = 0
      for index in 0..<8 { value |= UInt64(bytes[offset + index]) << UInt64(8 * index) }
      return value
    }
    func read32(_ offset: Int) -> UInt64 {
      var value: UInt64 = 0
      for index in 0..<4 { value |= UInt64(bytes[offset + index]) << UInt64(8 * index) }
      return value
    }

    let length = bytes.count
    var offset = 0
    var hash: UInt64
    if length >= 32 {
      var v1 = prime1 &+ prime2
      var v2 = prime2
      var v3: UInt64 = 0
      var v4 = 0 &- prime1
      while offset + 32 <= length {
        v1 = round(v1, read64(offset))
        v2 = round(v2, read64(offset + 8))
        v3 = round(v3, read64(offset + 16))
        v4 = round(v4, read64(offset + 24))
        offset += 32
      }
      hash = rotate(v1, 1) &+ rotate(v2, 7) &+ rotate(v3, 12) &+ rotate(v4, 18)
      hash = merge(hash, v1)
      hash = merge(hash, v2)
      hash = merge(hash, v3)
      hash = merge(hash, v4)
    } else {
      hash = prime5
    }
    hash = hash &+ UInt64(length)
    while offset + 8 <= length {
      hash ^= round(0, read64(offset))
      hash = rotate(hash, 27) &* prime1 &+ prime4
      offset += 8
    }
    if offset + 4 <= length {
      hash ^= read32(offset) &* prime1
      hash = rotate(hash, 23) &* prime2 &+ prime3
      offset += 4
    }
    while offset < length {
      hash ^= UInt64(bytes[offset]) &* prime5
      hash = rotate(hash, 11) &* prime1
      offset += 1
    }
    hash ^= hash >> 33
    hash = hash &* prime2
    hash ^= hash >> 29
    hash = hash &* prime3
    hash ^= hash >> 32
    return hash
  }
}

/// Little-endian integer reads and writes on byte arrays.
enum LittleEndian {
  static func uint16(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
  }

  static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }

  static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    UInt64(uint32(bytes, offset)) | UInt64(uint32(bytes, offset + 4)) << 32
  }

  static func bytes(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(8 * $0)) }
  }

  static func bytes(_ value: UInt64) -> [UInt8] {
    (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
  }
}
