import Foundation

// Small helpers shared by the block and stream cipher implementations.

@inline(__always)
func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
  value << (count & 31) | value >> ((32 &- count) & 31)
}

@inline(__always)
func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
  value >> (count & 31) | value << ((32 &- count) & 31)
}

@inline(__always)
func rotateLeft(_ value: UInt64, _ count: UInt64) -> UInt64 {
  value << (count & 63) | value >> ((64 &- count) & 63)
}

@inline(__always)
func rotateRight(_ value: UInt64, _ count: UInt64) -> UInt64 {
  value >> (count & 63) | value << ((64 &- count) & 63)
}

@inline(__always)
func rotateLeft(_ value: UInt16, _ count: UInt16) -> UInt16 {
  value << (count & 15) | value >> ((16 &- count) & 15)
}

@inline(__always)
func loadBigEndian32(_ pointer: UnsafePointer<UInt8>) -> UInt32 {
  UInt32(pointer[0]) << 24 | UInt32(pointer[1]) << 16 | UInt32(pointer[2]) << 8
    | UInt32(pointer[3])
}

@inline(__always)
func loadLittleEndian32(_ pointer: UnsafePointer<UInt8>) -> UInt32 {
  UInt32(pointer[3]) << 24 | UInt32(pointer[2]) << 16 | UInt32(pointer[1]) << 8
    | UInt32(pointer[0])
}

@inline(__always)
func loadBigEndian64(_ pointer: UnsafePointer<UInt8>) -> UInt64 {
  var value: UInt64 = 0
  for index in 0..<8 { value = value << 8 | UInt64(pointer[index]) }
  return value
}

@inline(__always)
func loadLittleEndian64(_ pointer: UnsafePointer<UInt8>) -> UInt64 {
  var value: UInt64 = 0
  for index in (0..<8).reversed() { value = value << 8 | UInt64(pointer[index]) }
  return value
}

@inline(__always)
func storeBigEndian32(_ value: UInt32, _ pointer: UnsafeMutablePointer<UInt8>) {
  pointer[0] = UInt8(truncatingIfNeeded: value >> 24)
  pointer[1] = UInt8(truncatingIfNeeded: value >> 16)
  pointer[2] = UInt8(truncatingIfNeeded: value >> 8)
  pointer[3] = UInt8(truncatingIfNeeded: value)
}

@inline(__always)
func storeLittleEndian32(_ value: UInt32, _ pointer: UnsafeMutablePointer<UInt8>) {
  pointer[0] = UInt8(truncatingIfNeeded: value)
  pointer[1] = UInt8(truncatingIfNeeded: value >> 8)
  pointer[2] = UInt8(truncatingIfNeeded: value >> 16)
  pointer[3] = UInt8(truncatingIfNeeded: value >> 24)
}

@inline(__always)
func storeBigEndian64(_ value: UInt64, _ pointer: UnsafeMutablePointer<UInt8>) {
  for index in 0..<8 {
    pointer[index] = UInt8(truncatingIfNeeded: value >> UInt64(56 - 8 * index))
  }
}

@inline(__always)
func storeLittleEndian64(_ value: UInt64, _ pointer: UnsafeMutablePointer<UInt8>) {
  for index in 0..<8 {
    pointer[index] = UInt8(truncatingIfNeeded: value >> UInt64(8 * index))
  }
}

/// Words of `bytes` read with the given byte order. A trailing partial word is zero padded.
func words32(_ bytes: [UInt8], bigEndian: Bool) -> [UInt32] {
  var padded = bytes
  while padded.count % 4 != 0 { padded.append(0) }
  return padded.withUnsafeBufferPointer { storage in
    guard let base = storage.baseAddress else { return [] }
    return stride(from: 0, to: padded.count, by: 4).map { offset in
      bigEndian ? loadBigEndian32(base + offset) : loadLittleEndian32(base + offset)
    }
  }
}
