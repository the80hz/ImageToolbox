import Compression
import Foundation

extension SevenZipArchive {

  // MARK: - Decoding a folder

  /// The bytes of one folder, decoded from its packed streams and checked against its CRC. An
  /// encrypted folder needs `password`.
  static func unpack(
    folder index: Int, of streams: StreamsInfo, archive: [UInt8], password: String?,
    budget: inout Int
  ) throws -> [UInt8] {
    let folder = streams.folders[index]
    guard let main = folder.mainOutput, let size = folder.unpackSize else {
      throw ArchiveCodecError.malformed
    }
    guard size <= UInt64(budget) else { throw ArchiveCodecError.tooLarge }

    // Where this folder's packed streams start: after those of the folders before it.
    var firstPackedStream = 0
    for earlier in streams.folders[..<index] { firstPackedStream += earlier.packedStreams.count }
    var packedRanges: [Range<Int>] = []
    var offset = streams.packPosition
    for stream in 0..<firstPackedStream {
      guard stream < streams.packSizes.count else { throw ArchiveCodecError.malformed }
      offset = offset &+ streams.packSizes[stream]
    }
    for stream in firstPackedStream..<(firstPackedStream + folder.packedStreams.count) {
      guard stream < streams.packSizes.count else { throw ArchiveCodecError.malformed }
      let packedSize = streams.packSizes[stream]
      guard offset <= UInt64(archive.count - 32), packedSize <= UInt64(archive.count - 32) - offset
      else { throw ArchiveCodecError.malformed }
      packedRanges.append((32 + Int(offset))..<(32 + Int(offset + packedSize)))
      offset += packedSize
    }

    let result: [UInt8]
    do {
      result = try decodeOutput(
        main, folder: folder, archive: archive, packedRanges: packedRanges, password: password,
        limit: budget, depth: 0)
    } catch ArchiveCodecError.malformed where folder.isEncrypted {
      // Under a wrong key the data is noise, which the coders reject.
      throw PasswordFailure.wrongPassword
    }
    guard UInt64(result.count) == size else { throw ArchiveCodecError.malformed }
    if let crc = folder.crc, crc != ArchiveChecksum.crc32(result) {
      if folder.isEncrypted { throw PasswordFailure.wrongPassword }
      throw ArchiveCodecError.checksumMismatch
    }
    budget -= result.count
    return result
  }

  /// The bytes of one output stream of a folder, decoded from its coder and, recursively, from
  /// the coders that feed it.
  private static func decodeOutput(
    _ output: Int, folder: Folder, archive: [UInt8], packedRanges: [Range<Int>],
    password: String?, limit: Int, depth: Int
  ) throws -> [UInt8] {
    guard depth <= folder.coders.count else { throw ArchiveCodecError.malformed }
    var firstOutput = 0
    var firstInput = 0
    for coder in folder.coders {
      if output < firstOutput + coder.outputs {
        guard coder.inputs == 1, coder.outputs == 1 else { throw ArchiveCodecError.unsupported }
        let input: [UInt8]
        if let pair = folder.bindPairs.first(where: { $0.input == firstInput }) {
          input = try decodeOutput(
            pair.output, folder: folder, archive: archive, packedRanges: packedRanges,
            password: password, limit: limit, depth: depth + 1)
        } else if let packed = folder.packedStreams.firstIndex(of: firstInput),
          packed < packedRanges.count
        {
          input = Array(archive[packedRanges[packed]])
        } else {
          throw ArchiveCodecError.malformed
        }
        let size = folder.unpackSizes[output]
        guard size <= UInt64(limit) else { throw ArchiveCodecError.tooLarge }
        return try run(coder, input: input, size: Int(size), limit: limit, password: password)
      }
      firstOutput += coder.outputs
      firstInput += coder.inputs
    }
    throw ArchiveCodecError.malformed
  }

  /// One coder applied to its input. PPMd and the other coders not listed here are unsupported.
  private static func run(
    _ coder: Coder, input: [UInt8], size: Int, limit: Int, password: String?
  ) throws -> [UInt8] {
    switch coder.method {
    case SevenZipAES.method:
      guard let password else { throw PasswordFailure.passwordRequired }
      let plain = try SevenZipAES.decrypt(input, properties: coder.properties, password: password)
      guard size <= plain.count else { throw ArchiveCodecError.malformed }
      return Array(plain[0..<size])
    case [0x00]:
      guard input.count >= size else { throw ArchiveCodecError.malformed }
      return Array(input[0..<size])
    case [0x21]:
      let result = try LZMACodec.decodeLZMA2(input, maximumOutputSize: limit)
      guard result.count == size else { throw ArchiveCodecError.malformed }
      return result
    case [0x03, 0x01, 0x01]:
      return try LZMACodec.decodeRaw(
        input, properties: coder.properties, size: size, maximumOutputSize: limit)
    case [0x04, 0x01, 0x08]:
      return try inflate(input, size: size)
    case [0x04, 0x02, 0x02]:
      let result = [UInt8](try BZip2Codec.decompress(Data(input), maximumOutputSize: limit))
      guard result.count == size else { throw ArchiveCodecError.malformed }
      return result
    case [0x03]:
      // Delta. The one property byte holds the distance minus one.
      guard coder.properties.count == 1, input.count == size else {
        throw ArchiveCodecError.malformed
      }
      var output = input
      SevenZipFilters.deltaDecode(&output, distance: Int(coder.properties[0]) + 1)
      return output
    case [0x03, 0x03, 0x01, 0x03]:
      // BCJ for x86. A start offset given as a property is not read, so such an archive is refused.
      guard coder.properties.isEmpty else { throw ArchiveCodecError.unsupported }
      guard input.count == size else { throw ArchiveCodecError.malformed }
      var output = input
      SevenZipFilters.x86Convert(&output)
      return output
    default:
      throw ArchiveCodecError.unsupported
    }
  }

  private static func inflate(_ input: [UInt8], size: Int) throws -> [UInt8] {
    guard size > 0 else { return [] }
    guard !input.isEmpty else { throw ArchiveCodecError.malformed }
    var output = [UInt8](repeating: 0, count: size)
    let written = input.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        compression_decode_buffer(
          destination.baseAddress!, size, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard written == size else { throw ArchiveCodecError.malformed }
    return output
  }

}
