import Compression
import Foundation

/// Writes zip archives in memory. An entry is deflated with the Compression framework when that
/// makes it smaller, and stored otherwise. An archive that outgrows the classic format, with 65,535
/// or more entries or 4 GiB of data, is written with the Zip64 extensions, and a classic archive is
/// written otherwise. With a password every entry is encrypted with WinZip AES.
public enum ZipWriter {

  public struct Entry: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
      self.name = name
      self.data = data
    }
  }

  /// How an archive is written. The defaults give a plain archive that uses Zip64 only when needed.
  public struct Options: Equatable, Sendable {

    public enum Zip64Mode: Equatable, Sendable {
      /// Zip64 records and extra fields where the classic fields are too small, and not otherwise.
      case automatic
      /// Zip64 records and extra fields for every entry, whatever the size.
      case always
      /// Never. An archive that needs Zip64 is refused with `Failure.tooManyEntries` or
      /// `Failure.tooLarge`.
      case never
    }

    public enum Method: Equatable, Sendable {
      /// Deflate the data when that makes it smaller, and store it otherwise.
      case automatic
      /// Store every entry as it is.
      case stored
    }

    public var zip64: Zip64Mode
    public var method: Method
    /// Encrypts every entry with WinZip AES. Nil and the empty string write a plain archive, as
    /// the Android app does.
    public var password: String?
    public var strength: ZipAES.Strength
    /// Nil picks AE-2 for entries under 20 bytes, where a CRC-32 would give the content away, and
    /// AE-1 for the others, as WinZip and libarchive do.
    public var aesVersion: ZipAES.Version?

    /// The size and offset from which a field needs Zip64. It is `0xFFFFFFFF` for real archives and
    /// smaller in tests, so the Zip64 paths run on small data.
    var sizeThreshold: UInt64 = UInt64(Zip64.marker32)
    /// The entry count from which the end record needs Zip64: `0xFFFF` for real archives.
    var entryThreshold = Int(Zip64.marker16)

    public init(
      zip64: Zip64Mode = .automatic,
      method: Method = .automatic,
      password: String? = nil,
      strength: ZipAES.Strength = .aes256,
      aesVersion: ZipAES.Version? = nil
    ) {
      self.zip64 = zip64
      self.method = method
      self.password = password
      self.strength = strength
      self.aesVersion = aesVersion
    }
  }

  public enum Failure: Error, Equatable {
    /// More entries than the classic format holds, with `Options.Zip64Mode.never`. The classic
    /// count field holds up to 65,534 entries, since 65,535 is the Zip64 marker.
    case tooManyEntries
    /// An entry or the archive is larger than the classic format holds, with
    /// `Options.Zip64Mode.never`.
    case tooLarge
    /// The name is not safe to store (`ZipEntryPath`): it is empty, absolute, contains ".." or
    /// "." segments, a NUL character, or is longer than the Android app accepts.
    case unsafeName(String)
    /// The key could not be derived or the cipher failed.
    case encryptionFailed
  }

  private static let localHeader: UInt32 = 0x0403_4B50
  private static let centralHeader: UInt32 = 0x0201_4B50
  private static let endHeader: UInt32 = 0x0605_4B50
  private static let storedMethod: UInt16 = 0
  private static let deflateMethod: UInt16 = 8
  /// Version 2.0 is needed for deflate, and the value is also written for stored entries.
  private static let versionNeeded: UInt16 = 20
  /// Bit 0: the entry is encrypted.
  private static let encryptedFlag: UInt16 = 0x0001
  /// Bit 11: the names are UTF-8.
  private static let utf8NamesFlag: UInt16 = 0x0800
  /// 1980-01-01 00:00, the earliest time a zip entry can carry.
  private static let fixedDate: UInt16 = 0x0021
  private static let fixedTime: UInt16 = 0

  public static func archive(_ entries: [Entry], options: Options = Options()) throws -> Data {
    let forced = options.zip64 == .always
    let classic = options.zip64 == .never
    let threshold = options.sizeThreshold
    if classic && entries.count >= Int(Zip64.marker16) { throw Failure.tooManyEntries }
    let password = options.password.flatMap { $0.isEmpty ? nil : Array($0.utf8) }

    var output = Data()
    var central: [UInt8] = []
    for entry in entries {
      guard var name = ZipEntryPath.safeName(entry.name) else {
        throw Failure.unsafeName(entry.name)
      }
      if entry.name.hasSuffix("/") || entry.name.hasSuffix("\\") { name += "/" }
      let nameBytes = Array(name.utf8)

      let checksum = CRC32.checksum(entry.data)
      var (method, body) = compressed(entry.data, deflate: options.method == .automatic)
      var flags = utf8NamesFlag
      var neededVersion = versionNeeded
      var crcField = checksum
      var aesExtra: [UInt8] = []
      if let password {
        let version = options.aesVersion ?? (entry.data.count < 20 ? .ae2 : .ae1)
        let header = ZipAES.Header(
          version: version, strength: options.strength, method: method)
        body = try encrypted(body, password: password, header: header)
        aesExtra = header.extraField
        method = ZipAES.methodMarker
        flags |= encryptedFlag
        neededVersion = ZipAES.versionNeeded
        // AE-2 keeps the CRC-32 out of the entry, and the authentication code protects the data.
        if version == .ae2 { crcField = 0 }
      }

      let uncompressedSize = UInt64(entry.data.count)
      let compressedSize = UInt64(body.count)
      let offset = UInt64(output.count)
      let needsSizes = forced || uncompressedSize >= threshold || compressedSize >= threshold
      let needsOffset = forced || offset >= threshold
      if classic && (needsSizes || needsOffset) { throw Failure.tooLarge }
      if needsSizes || needsOffset { neededVersion = max(neededVersion, Zip64.versionNeeded) }
      let marker = Zip64.marker32
      let compressed32 = needsSizes ? marker : UInt32(truncatingIfNeeded: compressedSize)
      let uncompressed32 = needsSizes ? marker : UInt32(truncatingIfNeeded: uncompressedSize)

      // The local header carries both sizes in its Zip64 field, or none.
      let localExtra =
        (needsSizes ? Zip64.extraField([uncompressedSize, compressedSize]) : []) + aesExtra
      var local: [UInt8] = []
      local.reserveCapacity(30 + nameBytes.count + localExtra.count)
      local.appendZipInteger(localHeader)
      local.appendZipInteger(neededVersion)
      local.appendZipInteger(flags)
      local.appendZipInteger(method)
      local.appendZipInteger(fixedTime)
      local.appendZipInteger(fixedDate)
      local.appendZipInteger(crcField)
      local.appendZipInteger(compressed32)
      local.appendZipInteger(uncompressed32)
      local.appendZipInteger(UInt16(nameBytes.count))
      local.appendZipInteger(UInt16(localExtra.count))
      local.append(contentsOf: nameBytes)
      local.append(contentsOf: localExtra)
      output.append(contentsOf: local)
      output.append(body)

      // The central record lists only the fields that hold the marker, in a fixed order.
      var replaced: [UInt64] = []
      if needsSizes { replaced += [uncompressedSize, compressedSize] }
      if needsOffset { replaced.append(offset) }
      let centralExtra = (replaced.isEmpty ? [] : Zip64.extraField(replaced)) + aesExtra
      central.appendZipInteger(centralHeader)
      central.appendZipInteger(neededVersion)  // version made by
      central.appendZipInteger(neededVersion)
      central.appendZipInteger(flags)
      central.appendZipInteger(method)
      central.appendZipInteger(fixedTime)
      central.appendZipInteger(fixedDate)
      central.appendZipInteger(crcField)
      central.appendZipInteger(compressed32)
      central.appendZipInteger(uncompressed32)
      central.appendZipInteger(UInt16(nameBytes.count))
      central.appendZipInteger(UInt16(centralExtra.count))
      central.appendZipInteger(UInt16(0))  // comment length
      central.appendZipInteger(UInt16(0))  // disk number
      central.appendZipInteger(UInt16(0))  // internal attributes
      central.appendZipInteger(UInt32(0))  // external attributes
      central.appendZipInteger(needsOffset ? marker : UInt32(truncatingIfNeeded: offset))
      central.append(contentsOf: nameBytes)
      central.append(contentsOf: centralExtra)
    }

    let directoryOffset = UInt64(output.count)
    let directorySize = UInt64(central.count)
    let count = UInt64(entries.count)
    let countOverflows = entries.count >= options.entryThreshold
    let needsZip64End =
      forced || countOverflows || directorySize >= threshold || directoryOffset >= threshold
    if classic && (directorySize >= threshold || directoryOffset >= threshold) {
      throw Failure.tooLarge
    }
    output.append(contentsOf: central)

    // A field is replaced by its marker only when its own value overflows.
    var end: [UInt8] = []
    let marked = needsZip64End && !classic
    if marked {
      output.append(
        contentsOf: Zip64.endRecords(
          entryCount: count, directorySize: directorySize, directoryOffset: directoryOffset,
          recordOffset: UInt64(output.count)))
    }
    let count16 = marked && countOverflows ? Zip64.marker16 : UInt16(truncatingIfNeeded: count)
    end.appendZipInteger(endHeader)
    end.appendZipInteger(UInt16(0))  // number of this disk
    end.appendZipInteger(UInt16(0))  // disk with the central directory
    end.appendZipInteger(count16)
    end.appendZipInteger(count16)
    end.appendZipInteger(
      marked && directorySize >= threshold
        ? Zip64.marker32 : UInt32(truncatingIfNeeded: directorySize))
    end.appendZipInteger(
      marked && directoryOffset >= threshold
        ? Zip64.marker32 : UInt32(truncatingIfNeeded: directoryOffset))
    end.appendZipInteger(UInt16(0))  // comment length
    output.append(contentsOf: end)
    return output
  }

  /// The deflated payload when it is smaller than the data, otherwise the data stored as it is.
  private static func compressed(
    _ data: Data, deflate: Bool
  ) -> (method: UInt16, payload: Data) {
    guard deflate, !data.isEmpty else { return (storedMethod, data) }
    let capacity = data.count + data.count / 100 + 64
    var buffer = [UInt8](repeating: 0, count: capacity)
    let size = data.withUnsafeBytes { source -> Int in
      guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
      return compression_encode_buffer(&buffer, capacity, base, data.count, nil, COMPRESSION_ZLIB)
    }
    guard size > 0, size < data.count else { return (storedMethod, data) }
    return (deflateMethod, Data(buffer[0..<size]))
  }

  private static func encrypted(
    _ data: Data, password: [UInt8], header: ZipAES.Header
  ) throws -> Data {
    let salt = ZipAES.randomSalt(strength: header.strength)
    do {
      let sealed = try data.withUnsafeBytes {
        try ZipAES.seal($0, password: password, strength: header.strength, salt: salt)
      }
      return Data(sealed)
    } catch is ZipAES.KeyFailure {
      throw Failure.encryptionFailed
    }
  }
}
