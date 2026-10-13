import Foundation

extension SevenZipArchive {

  // MARK: - Writing

  /// A 7z archive holding `entries`. File names use `/` as the separator. The data of all files
  /// is packed in one folder with LZMA2, or copied when that would not make it smaller.
  public static func archive(_ entries: [Entry]) throws -> Data {
    var names: [UInt8] = []
    var attributes: [UInt8] = []
    var emptyStream = [Bool](repeating: false, count: entries.count)
    var emptyFile: [Bool] = []
    var sizes: [UInt64] = []
    var checksums: [UInt32] = []
    var combined: [UInt8] = []
    for (index, entry) in entries.enumerated() {
      guard !entry.name.isEmpty, !entry.name.utf16.contains(0) else {
        throw ArchiveCodecError.malformed
      }
      for unit in entry.name.utf16 { names += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
      names += [0, 0]
      // Archive attribute, Unix extension flag, and a mode of rw-r--r-- in the high half.
      attributes += LittleEndian.bytes(UInt32(0x20 | 0x8000 | (0o100644 << 16)))
      if entry.data.isEmpty {
        emptyStream[index] = true
        emptyFile.append(true)
      } else {
        let content = [UInt8](entry.data)
        sizes.append(UInt64(content.count))
        checksums.append(ArchiveChecksum.crc32(content))
        combined += content
      }
    }

    // The packed stream and the coder that reads it.
    var packed = combined
    var coder: [UInt8] = [0x01, 0x00]  // idSize 1, id 0: Copy
    if !combined.isEmpty {
      let encoded = LZMA2Encoder.encode(combined)
      if encoded.stream.count < combined.count {
        packed = encoded.stream
        coder = [0x21, 0x21, 0x01, encoded.dictionaryProperty]  // has properties, id 0x21
      }
    }

    var header: [UInt8] = [UInt8(Property.header)]
    if !sizes.isEmpty {
      header.append(UInt8(Property.mainStreams))
      header += [UInt8(Property.packInfo)] + number(0) + number(1)
      header += [UInt8(Property.size)] + number(UInt64(packed.count)) + [UInt8(Property.end)]
      header += [UInt8(Property.unpackInfo), UInt8(Property.folder)] + number(1) + [0]
      header += number(1) + coder
      header += [UInt8(Property.codersUnpackSize)] + number(UInt64(combined.count))
      header += [UInt8(Property.end)]
      header += [UInt8(Property.subStreamsInfo)]
      header += [UInt8(Property.numUnpackStream)] + number(UInt64(sizes.count))
      if sizes.count > 1 {
        header.append(UInt8(Property.size))
        for size in sizes.dropLast() { header += number(size) }
      }
      header += [UInt8(Property.crc), 1]
      for checksum in checksums { header += LittleEndian.bytes(checksum) }
      header += [UInt8(Property.end), UInt8(Property.end)]
    }
    if !entries.isEmpty {
      header += [UInt8(Property.filesInfo)] + number(UInt64(entries.count))
      if emptyStream.contains(true) {
        let bits = bitVector(emptyStream)
        header += [UInt8(Property.emptyStream)] + number(UInt64(bits.count)) + bits
        let fileBits = bitVector(emptyFile)
        header += [UInt8(Property.emptyFile)] + number(UInt64(fileBits.count)) + fileBits
      }
      header += [UInt8(Property.names)] + number(UInt64(names.count + 1)) + [0] + names
      header += [UInt8(Property.attributes)] + number(UInt64(attributes.count + 2)) + [1, 0]
      header += attributes
      header.append(UInt8(Property.end))
    }
    header.append(UInt8(Property.end))

    var startHeader = LittleEndian.bytes(UInt64(packed.count))
    startHeader += LittleEndian.bytes(UInt64(header.count))
    startHeader += LittleEndian.bytes(ArchiveChecksum.crc32(header))
    var output = signature + [0, 4]
    output += LittleEndian.bytes(ArchiveChecksum.crc32(startHeader))
    output += startHeader
    output += packed
    output += header
    return Data(output)
  }

  /// A number in the 7z encoding: as many leading one bits in the first byte as extra bytes.
  private static func number(_ value: UInt64) -> [UInt8] {
    var first: UInt8 = 0
    var mask: UInt8 = 0x80
    var extra = 0
    while extra < 8 {
      if value < UInt64(1) << UInt64(7 * (extra + 1)) {
        first |= UInt8(truncatingIfNeeded: value >> UInt64(8 * extra))
        break
      }
      first |= mask
      mask >>= 1
      extra += 1
    }
    var result = [first]
    var rest = value
    for _ in 0..<extra {
      result.append(UInt8(truncatingIfNeeded: rest))
      rest >>= 8
    }
    return result
  }

  private static func bitVector(_ flags: [Bool]) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: (flags.count + 7) / 8)
    for (index, flag) in flags.enumerated() where flag {
      result[index / 8] |= 0x80 >> UInt8(index % 8)
    }
    return result
  }

}
