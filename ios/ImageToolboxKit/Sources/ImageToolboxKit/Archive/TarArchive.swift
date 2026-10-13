import Foundation

/// Reads and writes tar archives in the ustar format. Regular files are supported. Directories
/// are written as entries only when the caller gives them, and reading skips them. GNU and PAX long
/// names are not read.
public enum TarArchive {

  public struct Entry: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
      self.name = name
      self.data = data
    }
  }

  public enum Failure: Error, Equatable {
    /// The name does not fit the ustar fields, which hold 255 bytes at most.
    case nameTooLong
    /// The archive is damaged, or a header uses a feature this reader does not support.
    case malformed
  }

  private static let blockSize = 512

  public static func archive(_ entries: [Entry]) throws -> Data {
    var output = Data()
    for entry in entries {
      let header = try header(name: entry.name, size: entry.data.count)
      output.append(header)
      output.append(entry.data)
      let padding = (blockSize - entry.data.count % blockSize) % blockSize
      output.append(Data(count: padding))
    }
    output.append(Data(count: blockSize * 2))
    return output
  }

  /// The regular files of an archive, in order. Other entry types are skipped.
  public static func entries(in data: Data) throws -> [Entry] {
    let bytes = [UInt8](data)
    var result: [Entry] = []
    var position = 0
    while position + blockSize <= bytes.count {
      let header = Array(bytes[position..<(position + blockSize)])
      if header.allSatisfy({ $0 == 0 }) { break }
      guard Array(header[257..<262]) == Array("ustar".utf8) else { throw Failure.malformed }
      let size = try octal(header[124..<136])
      let type = header[156]
      let dataStart = position + blockSize
      let dataEnd = dataStart + size
      guard dataEnd <= bytes.count else { throw Failure.malformed }
      if type == UInt8(ascii: "0") || type == 0 {
        let prefix = string(header[345..<500])
        let name = string(header[0..<100])
        let fullName = prefix.isEmpty ? name : prefix + "/" + name
        result.append(Entry(name: fullName, data: Data(bytes[dataStart..<dataEnd])))
      } else if type == UInt8(ascii: "L") || type == UInt8(ascii: "x") || type == UInt8(ascii: "g")
      {
        throw Failure.malformed
      }
      position = dataStart + (size + blockSize - 1) / blockSize * blockSize
    }
    return result
  }

  // MARK: - Header

  private static func header(name: String, size: Int) throws -> Data {
    let bytes = Array(name.utf8)
    guard bytes.count <= 255 else { throw Failure.nameTooLong }
    var block = [UInt8](repeating: 0, count: blockSize)
    let (prefix, base) = try split(name: bytes)
    write(base, into: &block, at: 0, length: 100)
    writeOctal(0o644, into: &block, at: 100, length: 8)
    writeOctal(0, into: &block, at: 108, length: 8)
    writeOctal(0, into: &block, at: 116, length: 8)
    writeOctal(size, into: &block, at: 124, length: 12)
    writeOctal(0, into: &block, at: 136, length: 12)
    for index in 148..<156 { block[index] = UInt8(ascii: " ") }
    block[156] = UInt8(ascii: "0")
    write(Array("ustar".utf8) + [0], into: &block, at: 257, length: 6)
    write(Array("00".utf8), into: &block, at: 263, length: 2)
    write(prefix, into: &block, at: 345, length: 155)

    let checksum = block.reduce(0) { $0 + Int($1) }
    writeOctal(checksum, into: &block, at: 148, length: 7)
    block[155] = UInt8(ascii: " ")
    return Data(block)
  }

  /// Splits a long name at a slash so that the prefix holds the directories and the name the rest.
  /// A name with no such slash does not fit and is refused, rather than cut.
  private static func split(name: [UInt8]) throws -> (prefix: [UInt8], base: [UInt8]) {
    guard name.count > 100 else { return ([], name) }
    var index = min(name.count - 1, 155)
    while index > 0 {
      if name[index] == UInt8(ascii: "/") {
        let base = Array(name[(index + 1)...])
        if base.count <= 100 { return (Array(name[..<index]), base) }
      }
      index -= 1
    }
    throw Failure.nameTooLong
  }

  private static func write(
    _ value: [UInt8], into block: inout [UInt8], at offset: Int, length: Int
  ) {
    for (index, byte) in value.prefix(length).enumerated() {
      block[offset + index] = byte
    }
  }

  /// An octal number with a trailing NUL, zero-padded to `length` bytes.
  private static func writeOctal(
    _ value: Int, into block: inout [UInt8], at offset: Int, length: Int
  ) {
    let digits = Array(String(value, radix: 8).utf8)
    let padded =
      [UInt8](repeating: UInt8(ascii: "0"), count: max(0, length - 1 - digits.count)) + digits
    write(padded + [0], into: &block, at: offset, length: length)
  }

  private static func octal(_ field: ArraySlice<UInt8>) throws -> Int {
    var value = 0
    for byte in field {
      if byte == 0 || byte == UInt8(ascii: " ") { break }
      guard (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(byte) else { throw Failure.malformed }
      value = value * 8 + Int(byte - UInt8(ascii: "0"))
    }
    return value
  }

  private static func string(_ field: ArraySlice<UInt8>) -> String {
    let bytes = field.prefix { $0 != 0 }
    return String(decoding: bytes, as: UTF8.self)
  }
}
