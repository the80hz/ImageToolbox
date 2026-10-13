/// The two 7z filters that change the data of a folder: BCJ for x86 code and Delta. They work on
/// the whole output of the coder before them. The x86 converter follows the LZMA SDK's Bra86.c,
/// which the xz x86 filter matches, and Delta follows Delta.c.
enum SevenZipFilters {

  /// Undoes the Delta filter in place. Each byte was stored as its difference to the byte
  /// `distance` before it, and the bytes before the start count as zero.
  static func deltaDecode(_ bytes: inout [UInt8], distance: Int) {
    guard distance > 0, bytes.count > distance else { return }
    for index in distance..<bytes.count {
      bytes[index] &+= bytes[index - distance]
    }
  }

  /// Undoes the x86 BCJ filter in place. The filter had turned the relative targets of calls
  /// (E8) and jumps (E9) into absolute ones, so the data is converted back. With `encoding` the
  /// filter is applied instead; the tests use that for round trips.
  static func x86Convert(_ bytes: inout [UInt8], encoding: Bool = false) {
    guard bytes.count >= 5 else { return }
    // An operand needs four bytes after its opcode, so the search stops four bytes short.
    let limit = bytes.count - 4
    var position = 0
    // Bits mark recent opcode bytes that were skipped, so that an operand overlapping them is not
    // converted.
    var mask: UInt32 = 0
    while true {
      var index = position
      while index < limit, (bytes[index] & 0xFE) != 0xE8 { index += 1 }
      let skipped = index - position
      position = index
      guard index < limit else { return }

      if skipped > 2 {
        mask = 0
      } else {
        mask >>= skipped
        if mask != 0,
          mask > 4 || mask == 3 || isMostSignificantByte(bytes[index + Int(mask >> 1) + 1])
        {
          mask = (mask >> 1) | 4
          position += 1
          continue
        }
      }

      guard isMostSignificantByte(bytes[index + 4]) else {
        mask = (mask >> 1) | 4
        position += 1
        continue
      }
      var value =
        UInt32(bytes[index + 4]) << 24 | UInt32(bytes[index + 3]) << 16
        | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 1])
      // An operand is relative to the end of its five-byte instruction.
      let address = UInt32(position) &+ 5
      position += 5
      value = encoding ? value &+ address : value &- address
      if mask != 0 {
        let shift = (mask & 6) << 2
        if isMostSignificantByte(UInt8(truncatingIfNeeded: value >> shift)) {
          value ^= (UInt32(0x100) << shift) &- 1
          value = encoding ? value &+ address : value &- address
        }
        mask = 0
      }
      bytes[index + 1] = UInt8(truncatingIfNeeded: value)
      bytes[index + 2] = UInt8(truncatingIfNeeded: value >> 8)
      bytes[index + 3] = UInt8(truncatingIfNeeded: value >> 16)
      bytes[index + 4] = UInt8(truncatingIfNeeded: 0 &- ((value >> 24) & 1))
    }
  }

  /// Whether the byte is 0x00 or 0xFF, the high byte of a small signed displacement.
  private static func isMostSignificantByte(_ byte: UInt8) -> Bool {
    ((byte &+ 1) & 0xFE) == 0
  }
}
