import Foundation

/// Bounds-checked little-endian reads from the bytes of a zip archive. Every read that would leave
/// the data throws `ZipReader.Failure.malformed`, so a damaged archive cannot cause a crash.
struct ZipByteReader {
  let bytes: UnsafeRawBufferPointer

  var count: Int { bytes.count }

  /// Whether `length` bytes starting at `offset` lie inside the data.
  func contains(offset: Int, length: Int) -> Bool {
    guard offset >= 0, length >= 0 else { return false }
    let (end, overflow) = offset.addingReportingOverflow(length)
    return !overflow && end <= bytes.count
  }

  func uint8(_ offset: Int) throws -> UInt8 {
    guard contains(offset: offset, length: 1) else { throw ZipReader.Failure.malformed }
    return bytes[offset]
  }

  func uint16(_ offset: Int) throws -> UInt16 {
    guard contains(offset: offset, length: 2) else { throw ZipReader.Failure.malformed }
    return UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
  }

  func uint32(_ offset: Int) throws -> UInt32 {
    guard contains(offset: offset, length: 4) else { throw ZipReader.Failure.malformed }
    return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
  }

  func uint64(_ offset: Int) throws -> UInt64 {
    guard contains(offset: offset, length: 8) else { throw ZipReader.Failure.malformed }
    return UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
  }

  func slice(_ offset: Int, _ length: Int) throws -> UnsafeRawBufferPointer {
    guard contains(offset: offset, length: length) else { throw ZipReader.Failure.malformed }
    return UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + length)])
  }

  /// A file offset or size from a 64-bit field as an `Int`.
  static func int(_ value: UInt64) throws -> Int {
    guard let result = Int(exactly: value) else { throw ZipReader.Failure.malformed }
    return result
  }
}

extension Array where Element == UInt8 {
  /// Appends the value in little-endian byte order, as zip stores every number.
  mutating func appendZipInteger(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value))
    append(UInt8(truncatingIfNeeded: value >> 8))
  }

  /// Appends the value in little-endian byte order, as zip stores every number.
  mutating func appendZipInteger(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 24))
  }

  /// Appends the value in little-endian byte order, as zip stores every number.
  mutating func appendZipInteger(_ value: UInt64) {
    appendZipInteger(UInt32(truncatingIfNeeded: value))
    appendZipInteger(UInt32(truncatingIfNeeded: value >> 32))
  }
}
