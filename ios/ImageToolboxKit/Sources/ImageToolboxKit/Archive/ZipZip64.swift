import Foundation

/// The extra fields of a zip entry: a run of (id, size, data) blocks.
enum ZipExtra {

  struct Field {
    let id: UInt16
    let data: UnsafeRawBufferPointer
  }

  /// The fields of an extra block. A block cut short ends the list, as other readers do.
  static func fields(in block: UnsafeRawBufferPointer) -> [Field] {
    let reader = ZipByteReader(bytes: block)
    var fields: [Field] = []
    var offset = 0
    while reader.contains(offset: offset, length: 4) {
      guard let id = try? reader.uint16(offset), let size = try? reader.uint16(offset + 2),
        let data = try? reader.slice(offset + 4, Int(size))
      else { break }
      fields.append(Field(id: id, data: data))
      offset += 4 + Int(size)
    }
    return fields
  }
}

/// The Zip64 extensions (APPNOTE section 4.5.3 and 4.3.14 to 4.3.15): 64-bit sizes and offsets in
/// an extra field of the entry, and an end-of-central-directory record with a locator.
enum Zip64 {

  static let marker16: UInt16 = 0xFFFF
  static let marker32: UInt32 = 0xFFFF_FFFF
  static let extraFieldID: UInt16 = 0x0001
  /// "PK\x06\x06".
  static let endRecordSignature: UInt32 = 0x0606_4B50
  /// "PK\x06\x07".
  static let locatorSignature: UInt32 = 0x0706_4B50
  static let endRecordSize = 56
  static let locatorSize = 20
  /// Version 4.5 is the first to know Zip64.
  static let versionNeeded: UInt16 = 45

  // MARK: - Reading

  /// The sizes and offset of an entry once the Zip64 extra field has replaced the markers.
  struct EntryFields: Equatable {
    var uncompressedSize: UInt64
    var compressedSize: UInt64
    var localOffset: UInt64
  }

  /// The values of a central directory record. A field holding the marker `0xFFFFFFFF` takes its
  /// value from the Zip64 extra field, which lists the replaced fields in the order uncompressed
  /// size, compressed size, offset of the local header, disk number.
  static func resolve(
    uncompressedSize: UInt32, compressedSize: UInt32, localOffset: UInt32, disk: UInt16,
    extra: UnsafeRawBufferPointer
  ) throws -> EntryFields {
    var fields = EntryFields(
      uncompressedSize: UInt64(uncompressedSize), compressedSize: UInt64(compressedSize),
      localOffset: UInt64(localOffset))
    let replacesSize = uncompressedSize == marker32 || compressedSize == marker32
    guard replacesSize || localOffset == marker32 || disk == marker16 else { return fields }

    guard let field = ZipExtra.fields(in: extra).first(where: { $0.id == extraFieldID }) else {
      throw ZipReader.Failure.malformed
    }
    let reader = ZipByteReader(bytes: field.data)
    var offset = 0
    // Some writers list both sizes whenever one of them is replaced; the field is then 8 bytes
    // longer than the markers alone need.
    let replacedSizes =
      (uncompressedSize == marker32 ? 1 : 0) + (compressedSize == marker32 ? 1 : 0)
    let expectedLength =
      replacedSizes * 8 + (localOffset == marker32 ? 8 : 0) + (disk == marker16 ? 4 : 0)
    if replacedSizes == 1 && field.data.count == expectedLength + 8 {
      let uncompressed = try reader.uint64(0)
      let compressed = try reader.uint64(8)
      if uncompressedSize == marker32 { fields.uncompressedSize = uncompressed }
      if compressedSize == marker32 { fields.compressedSize = compressed }
      offset = 16
    } else {
      if uncompressedSize == marker32 {
        fields.uncompressedSize = try reader.uint64(offset)
        offset += 8
      }
      if compressedSize == marker32 {
        fields.compressedSize = try reader.uint64(offset)
        offset += 8
      }
    }
    if localOffset == marker32 {
      fields.localOffset = try reader.uint64(offset)
      offset += 8
    }
    if disk == marker16 {
      guard try reader.uint32(offset) == 0 else { throw ZipReader.Failure.unsupported }
    }
    return fields
  }

  /// The central directory position and entry count from the Zip64 end record that the locator
  /// before the classic end record points to.
  static func endRecord(
    in reader: ZipByteReader, classicEnd: Int
  ) throws -> (entryCount: UInt64, directorySize: UInt64, directoryOffset: UInt64)? {
    let locator = classicEnd - locatorSize
    guard locator >= 0, try reader.uint32(locator) == locatorSignature else { return nil }
    let recordOffset = try ZipByteReader.int(try reader.uint64(locator + 8))
    guard try reader.uint32(locator + 4) == 0, try reader.uint32(locator + 16) <= 1 else {
      throw ZipReader.Failure.unsupported
    }
    guard try reader.uint32(recordOffset) == endRecordSignature else {
      throw ZipReader.Failure.malformed
    }
    guard try reader.uint32(recordOffset + 16) == 0, try reader.uint32(recordOffset + 20) == 0
    else { throw ZipReader.Failure.unsupported }
    return (
      entryCount: try reader.uint64(recordOffset + 32),
      directorySize: try reader.uint64(recordOffset + 40),
      directoryOffset: try reader.uint64(recordOffset + 48)
    )
  }

  // MARK: - Writing

  /// A Zip64 extra field holding `values`, each as 8 bytes.
  static func extraField(_ values: [UInt64]) -> [UInt8] {
    var field: [UInt8] = []
    field.appendZipInteger(extraFieldID)
    field.appendZipInteger(UInt16(values.count * 8))
    for value in values { field.appendZipInteger(value) }
    return field
  }

  /// The Zip64 end-of-central-directory record followed by its locator. `recordOffset` is where
  /// the record itself is written.
  static func endRecords(
    entryCount: UInt64, directorySize: UInt64, directoryOffset: UInt64, recordOffset: UInt64
  ) -> [UInt8] {
    var data: [UInt8] = []
    data.appendZipInteger(endRecordSignature)
    data.appendZipInteger(UInt64(endRecordSize - 12))  // the size without signature and this field
    data.appendZipInteger(versionNeeded)  // version made by
    data.appendZipInteger(versionNeeded)  // version needed to extract
    data.appendZipInteger(UInt32(0))  // number of this disk
    data.appendZipInteger(UInt32(0))  // disk with the central directory
    data.appendZipInteger(entryCount)  // entries on this disk
    data.appendZipInteger(entryCount)  // entries in total
    data.appendZipInteger(directorySize)
    data.appendZipInteger(directoryOffset)

    data.appendZipInteger(locatorSignature)
    data.appendZipInteger(UInt32(0))  // disk with the Zip64 end record
    data.appendZipInteger(recordOffset)
    data.appendZipInteger(UInt32(1))  // number of disks
    return data
  }
}
