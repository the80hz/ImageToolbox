extension SevenZipArchive {

  struct Coder {
    let method: [UInt8]
    let inputs: Int
    let outputs: Int
    let properties: [UInt8]
  }

  struct Folder {
    var coders: [Coder] = []
    var bindPairs: [(input: Int, output: Int)] = []
    var packedStreams: [Int] = []
    var unpackSizes: [UInt64] = []
    var crc: UInt32?

    /// The output stream that no bind pair consumes: the folder's result.
    var mainOutput: Int? {
      let consumed = Set(bindPairs.map { $0.output })
      return (0..<unpackSizes.count).first { !consumed.contains($0) }
    }

    var unpackSize: UInt64? { mainOutput.map { unpackSizes[$0] } }

    /// Whether a coder of the folder is 7zAES, so that the folder needs a password.
    var isEncrypted: Bool { coders.contains { $0.method == SevenZipAES.method } }
  }

  struct SubStream {
    var size: UInt64
    var crc: UInt32?
  }

  struct StreamsInfo {
    var packPosition: UInt64 = 0
    var packSizes: [UInt64] = []
    var folders: [Folder] = []
    var subStreams: [[SubStream]] = []
  }

  static func readStreamsInfo(_ cursor: inout HeaderCursor) throws -> StreamsInfo {
    var info = StreamsInfo()
    var hasSubStreams = false
    while true {
      let kind = Int(try cursor.readNumber())
      switch kind {
      case Property.end:
        if !hasSubStreams {
          info.subStreams = info.folders.map { folder in
            [SubStream(size: folder.unpackSize ?? 0, crc: folder.crc)]
          }
        }
        return info
      case Property.packInfo:
        info.packPosition = try cursor.readNumber()
        let count = try cursor.readCount()
        info.packSizes = [UInt64](repeating: 0, count: count)
        while true {
          let property = Int(try cursor.readNumber())
          if property == Property.end { break }
          if property == Property.size {
            for index in 0..<count { info.packSizes[index] = try cursor.readNumber() }
          } else if property == Property.crc {
            _ = try cursor.readDigests(count)
          } else {
            throw ArchiveCodecError.malformed
          }
        }
      case Property.unpackInfo:
        info.folders = try readUnpackInfo(&cursor)
      case Property.subStreamsInfo:
        hasSubStreams = true
        info.subStreams = try readSubStreams(&cursor, folders: info.folders)
      default:
        throw ArchiveCodecError.malformed
      }
    }
  }

  private static func readUnpackInfo(_ cursor: inout HeaderCursor) throws -> [Folder] {
    guard Int(try cursor.readNumber()) == Property.folder else { throw ArchiveCodecError.malformed }
    let count = try cursor.readCount(limit: 1 << 20)
    guard try cursor.readByte() == 0 else { throw ArchiveCodecError.unsupported }
    var folders: [Folder] = []
    for _ in 0..<count {
      var folder = Folder()
      let coderCount = try cursor.readCount(limit: 32)
      guard coderCount > 0 else { throw ArchiveCodecError.malformed }
      var totalInputs = 0
      var totalOutputs = 0
      for _ in 0..<coderCount {
        let flags = try cursor.readByte()
        guard flags & 0x80 == 0 else { throw ArchiveCodecError.unsupported }
        let method = try cursor.readBytes(Int(flags & 0x0F))
        var inputs = 1
        var outputs = 1
        if flags & 0x10 != 0 {
          inputs = try cursor.readCount(limit: 32)
          outputs = try cursor.readCount(limit: 32)
        }
        var properties: [UInt8] = []
        if flags & 0x20 != 0 {
          properties = try cursor.readBytes(try cursor.readCount(limit: 1 << 16))
        }
        folder.coders.append(
          Coder(method: method, inputs: inputs, outputs: outputs, properties: properties))
        totalInputs += inputs
        totalOutputs += outputs
      }
      guard totalOutputs > 0 else { throw ArchiveCodecError.malformed }
      for _ in 0..<(totalOutputs - 1) {
        let input = try cursor.readCount(limit: 1024)
        let output = try cursor.readCount(limit: 1024)
        guard input < totalInputs, output < totalOutputs else { throw ArchiveCodecError.malformed }
        folder.bindPairs.append((input, output))
      }
      let packedCount = totalInputs - folder.bindPairs.count
      guard packedCount >= 1 else { throw ArchiveCodecError.malformed }
      if packedCount == 1 {
        let bound = Set(folder.bindPairs.map { $0.input })
        guard let free = (0..<totalInputs).first(where: { !bound.contains($0) }) else {
          throw ArchiveCodecError.malformed
        }
        folder.packedStreams = [free]
      } else {
        for _ in 0..<packedCount {
          folder.packedStreams.append(try cursor.readCount(limit: 1024))
        }
      }
      folder.unpackSizes = [UInt64](repeating: 0, count: totalOutputs)
      folders.append(folder)
    }

    guard Int(try cursor.readNumber()) == Property.codersUnpackSize else {
      throw ArchiveCodecError.malformed
    }
    for index in folders.indices {
      for output in folders[index].unpackSizes.indices {
        folders[index].unpackSizes[output] = try cursor.readNumber()
      }
    }
    while true {
      let property = Int(try cursor.readNumber())
      if property == Property.end { return folders }
      guard property == Property.crc else { throw ArchiveCodecError.malformed }
      let digests = try cursor.readDigests(folders.count)
      for index in folders.indices { folders[index].crc = digests[index] }
    }
  }

  private static func readSubStreams(_ cursor: inout HeaderCursor, folders: [Folder]) throws
    -> [[SubStream]]
  {
    var counts = [Int](repeating: 1, count: folders.count)
    var property = Int(try cursor.readNumber())
    if property == Property.numUnpackStream {
      for index in folders.indices { counts[index] = try cursor.readCount() }
      property = Int(try cursor.readNumber())
    }
    var result: [[SubStream]] = []
    for (index, folder) in folders.enumerated() {
      guard counts[index] > 0 else {
        result.append([])
        continue
      }
      var streams: [SubStream] = []
      var sum: UInt64 = 0
      if property == Property.size {
        for _ in 0..<(counts[index] - 1) {
          let size = try cursor.readNumber()
          sum = sum &+ size
          streams.append(SubStream(size: size, crc: nil))
        }
      } else if counts[index] > 1 {
        throw ArchiveCodecError.malformed
      }
      guard let total = folder.unpackSize, sum <= total else { throw ArchiveCodecError.malformed }
      streams.append(SubStream(size: total - sum, crc: nil))
      result.append(streams)
    }
    if property == Property.size { property = Int(try cursor.readNumber()) }

    // A single stream in a folder with a checksum inherits it; the others are listed together.
    var missing = 0
    for (index, folder) in folders.enumerated() where !(counts[index] == 1 && folder.crc != nil) {
      missing += counts[index]
    }
    for (index, folder) in folders.enumerated() where counts[index] == 1 && folder.crc != nil {
      result[index][0].crc = folder.crc
    }
    while property != Property.end {
      if property == Property.crc {
        let digests = try cursor.readDigests(missing)
        var next = 0
        for (index, folder) in folders.enumerated()
        where !(counts[index] == 1 && folder.crc != nil) {
          for stream in 0..<counts[index] {
            result[index][stream].crc = digests[next]
            next += 1
          }
        }
      } else {
        try cursor.skip(try cursor.readNumber())
      }
      property = Int(try cursor.readNumber())
    }
    return result
  }

  struct FileRecord {
    var name = ""
    var hasStream = true
    var isEmptyFile = false
    var attributes: UInt32?
  }

  static func readFiles(_ cursor: inout HeaderCursor, maximumEntries: Int) throws
    -> [FileRecord]
  {
    let count = try cursor.readCount(limit: maximumEntries)
    var files = [FileRecord](repeating: FileRecord(), count: count)
    var emptyStream = [Bool](repeating: false, count: count)
    var emptyFile: [Bool] = []
    while true {
      let property = Int(try cursor.readNumber())
      if property == Property.end { break }
      let size = try cursor.readNumber()
      guard size <= UInt64(cursor.bytes.count - cursor.position) else {
        throw ArchiveCodecError.malformed
      }
      let end = cursor.position + Int(size)
      switch property {
      case Property.emptyStream:
        emptyStream = try cursor.readBits(count)
      case Property.emptyFile:
        emptyFile = try cursor.readBits(emptyStream.filter { $0 }.count)
      case Property.names:
        guard try cursor.readByte() == 0 else { throw ArchiveCodecError.unsupported }
        let raw = try cursor.readBytes(end - cursor.position)
        var units: [UInt16] = []
        var index = 0
        var file = 0
        while file < count {
          guard index + 2 <= raw.count else { throw ArchiveCodecError.malformed }
          let unit = UInt16(raw[index]) | UInt16(raw[index + 1]) << 8
          index += 2
          if unit == 0 {
            files[file].name = String(decoding: units, as: UTF16.self)
            units.removeAll(keepingCapacity: true)
            file += 1
          } else {
            units.append(unit)
          }
        }
      case Property.attributes:
        let defined = try cursor.readOptionalBits(count)
        guard try cursor.readByte() == 0 else { throw ArchiveCodecError.unsupported }
        for index in 0..<count where defined[index] {
          files[index].attributes = try cursor.readUInt32()
        }
      default:
        break
      }
      cursor.position = end
    }

    var emptyIndex = 0
    for index in 0..<count where emptyStream[index] {
      files[index].hasStream = false
      files[index].isEmptyFile = emptyIndex < emptyFile.count && emptyFile[emptyIndex]
      emptyIndex += 1
    }
    return files
  }

}
