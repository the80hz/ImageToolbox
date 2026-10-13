extension SevenZipArchive {

  struct HeaderCursor {
    let bytes: [UInt8]
    var position = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func readByte() throws -> UInt8 {
      guard position < bytes.count else { throw ArchiveCodecError.malformed }
      position += 1
      return bytes[position - 1]
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
      guard count >= 0, count <= bytes.count - position else { throw ArchiveCodecError.malformed }
      position += count
      return Array(bytes[(position - count)..<position])
    }

    mutating func skip(_ count: UInt64) throws {
      guard count <= UInt64(bytes.count - position) else { throw ArchiveCodecError.malformed }
      position += Int(count)
    }

    mutating func readUInt32() throws -> UInt32 {
      LittleEndian.uint32(try readBytes(4), 0)
    }

    /// A 7z number: the leading one bits of the first byte count the extra bytes.
    mutating func readNumber() throws -> UInt64 {
      let first = try readByte()
      var mask: UInt8 = 0x80
      var value: UInt64 = 0
      for index in 0..<8 {
        if first & mask == 0 {
          let high = UInt64(first & (mask &- 1))
          return value | high << UInt64(8 * index)
        }
        value |= UInt64(try readByte()) << UInt64(8 * index)
        mask >>= 1
      }
      return value
    }

    /// A number that is used as a count or an index.
    mutating func readCount(limit: Int = 1 << 24) throws -> Int {
      let value = try readNumber()
      guard value <= UInt64(limit) else { throw ArchiveCodecError.malformed }
      return Int(value)
    }

    /// A vector of flags, most significant bit first.
    mutating func readBits(_ count: Int) throws -> [Bool] {
      var result: [Bool] = []
      result.reserveCapacity(count)
      var current: UInt8 = 0
      var mask: UInt8 = 0
      for _ in 0..<count {
        if mask == 0 {
          current = try readByte()
          mask = 0x80
        }
        result.append(current & mask != 0)
        mask >>= 1
      }
      return result
    }

    /// Flags that may be abbreviated to "all set" by a leading byte.
    mutating func readOptionalBits(_ count: Int) throws -> [Bool] {
      let allDefined = try readByte()
      if allDefined != 0 { return [Bool](repeating: true, count: count) }
      return try readBits(count)
    }

    mutating func readDigests(_ count: Int) throws -> [UInt32?] {
      let defined = try readOptionalBits(count)
      return try defined.map { $0 ? try readUInt32() : nil }
    }
  }

}
