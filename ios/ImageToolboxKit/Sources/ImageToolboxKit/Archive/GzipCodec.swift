import Compression
import Foundation

/// The gzip container (RFC 1952) around raw deflate. The Compression framework provides the deflate
/// stream, and the header and trailer are written here. Multi-member files are not read.
public enum GzipCodec {

  public enum Failure: Error, Equatable {
    case malformed
    case checksumMismatch
    case tooLarge
  }

  private static let magic: [UInt8] = [0x1F, 0x8B, 0x08]

  /// A gzip file holding `data`. The header carries no name, time or other optional field.
  public static func compress(_ data: Data) throws -> Data {
    guard data.count <= Int(UInt32.max) else { throw Failure.tooLarge }
    let deflated = try deflate(data)
    var output = Data(magic)
    let header: [UInt8] = [0x00, 0, 0, 0, 0, 0x00, 0xFF]  // flags, mtime, xfl, OS unknown
    output.append(contentsOf: header)
    output.append(contentsOf: deflated)
    append(CRC32.checksum(data), to: &output)
    append(UInt32(data.count), to: &output)
    return output
  }

  /// The bytes of a gzip file. The checksum and the size in the trailer must match the content.
  public static func decompress(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    guard bytes.count >= 18, Array(bytes[0..<3]) == magic else { throw Failure.malformed }
    let flags = bytes[3]
    var position = 10
    if flags & 0x04 != 0 {  // FEXTRA
      guard position + 2 <= bytes.count else { throw Failure.malformed }
      position += 2 + Int(bytes[position]) + Int(bytes[position + 1]) << 8
    }
    if flags & 0x08 != 0 {  // FNAME
      position = try skipZeroTerminated(bytes, from: position)
    }
    if flags & 0x10 != 0 {  // FCOMMENT
      position = try skipZeroTerminated(bytes, from: position)
    }
    if flags & 0x02 != 0 {  // FHCRC
      position += 2
    }
    guard position <= bytes.count - 8 else { throw Failure.malformed }

    let trailer = bytes.count - 8
    let expectedCRC = readUInt32(bytes, trailer)
    let expectedSize = Int(readUInt32(bytes, trailer + 4))
    let content = try inflate(Array(bytes[position..<trailer]), size: expectedSize)
    guard CRC32.checksum(Data(content)) == expectedCRC else { throw Failure.checksumMismatch }
    return Data(content)
  }

  // MARK: - Raw deflate

  private static func deflate(_ data: Data) throws -> [UInt8] {
    guard !data.isEmpty else { return [0x03, 0x00] }  // an empty final stored block
    let capacity = data.count + data.count / 100 + 64
    var buffer = [UInt8](repeating: 0, count: capacity)
    let size = data.withUnsafeBytes { source -> Int in
      guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
      return compression_encode_buffer(&buffer, capacity, base, data.count, nil, COMPRESSION_ZLIB)
    }
    guard size > 0 else { throw Failure.malformed }
    return Array(buffer[0..<size])
  }

  private static func inflate(_ input: [UInt8], size: Int) throws -> [UInt8] {
    guard size > 0 else { return [] }
    guard !input.isEmpty else { throw Failure.malformed }
    var output = [UInt8](repeating: 0, count: size)
    let written = input.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        compression_decode_buffer(
          destination.baseAddress!, size, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard written == size else { throw Failure.malformed }
    return output
  }

  private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
    guard let end = bytes[start...].firstIndex(of: 0) else { throw Failure.malformed }
    return end + 1
  }

  private static func append(_ value: UInt32, to data: inout Data) {
    withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
  }

  private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
  }
}
