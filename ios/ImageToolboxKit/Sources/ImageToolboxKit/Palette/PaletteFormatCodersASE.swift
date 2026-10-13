import Foundation

// MARK: - Adobe Swatch Exchange

/// The Adobe Swatch Exchange (.ase) format: a list of blocks, each holding a colour or a group.
///
/// Colours outside groups are the global colours, and a group block starts and ends the colours
/// inside it. The name and the type of each colour are kept, and so are the group names. The
/// format has no palette name, so `PaletteDocument.name` is always nil when reading and is not
/// written. Colours are written as RGB entries. A group that is still open at the end of the file
/// is read as a group, as in the Android coder.
public enum ASEPaletteCoder: PaletteDocumentCoder {

  private static let signature = Array("ASEF".utf8)

  public static func decodeDocument(_ data: Data) throws -> PaletteDocument {
    var reader = BinaryReader(data)
    guard try reader.take(4) == signature else { throw PaletteFormatError.invalidHeader }
    // The version is not checked, as in the Android coder.
    _ = try reader.uint16()
    _ = try reader.uint16()
    let blockCount = try reader.uint32()

    var colours: [PaletteColour] = []
    var groups: [PaletteColourGroup] = []
    var openGroup: (name: String, colours: [PaletteColour])?
    for _ in 0..<blockCount {
      let type = try reader.uint16()
      // The block length is not needed because the blocks are read in sequence.
      _ = try reader.uint32()
      switch type {
      case 0xC001:
        guard openGroup == nil else { throw PaletteFormatError.invalidFormat }
        _ = try reader.uint16()
        openGroup = (try reader.nullTerminatedUTF16(), [])
      case 0xC002:
        guard let group = openGroup else { throw PaletteFormatError.invalidFormat }
        groups.append(PaletteColourGroup(name: group.name, colours: group.colours))
        openGroup = nil
      case 0x0001:
        let colour = try readColour(&reader)
        if openGroup != nil {
          openGroup?.colours.append(colour)
        } else {
          colours.append(colour)
        }
      default:
        throw PaletteFormatError.unknownBlockType(type)
      }
    }
    if let group = openGroup {
      groups.append(PaletteColourGroup(name: group.name, colours: group.colours))
    }
    return PaletteDocument(colours: colours, groups: groups)
  }

  /// The header, the global colours, then each group as a start block, its colours and an end
  /// block. The block count includes the group blocks, as the Android coder counts them.
  public static func encodeDocument(_ document: PaletteDocument) -> Data {
    var writer = BinaryWriter()
    writer.append(signature)
    writer.uint16(1)
    writer.uint16(0)
    let blockCount =
      document.colours.count + document.groups.count * 2
      + document.groups.reduce(0) { $0 + $1.colours.count }
    writer.uint32(UInt32(blockCount))
    for colour in document.colours {
      writeColour(colour, to: &writer)
    }
    for group in document.groups {
      var body = BinaryWriter()
      body.nullTerminatedUTF16(group.name)
      writer.uint16(0xC001)
      writer.uint32(UInt32(body.bytes.count))
      writer.append(body.bytes)
      for colour in group.colours {
        writeColour(colour, to: &writer)
      }
      writer.uint16(0xC002)
      writer.uint32(0)
    }
    return writer.data
  }

  private static func writeColour(_ colour: PaletteColour, to writer: inout BinaryWriter) {
    var body = BinaryWriter()
    body.nullTerminatedUTF16(colour.name ?? "")
    body.append(Array("RGB ".utf8))
    for channel in [colour.red, colour.green, colour.blue] {
      body.float32(PaletteMath.unit(channel))
    }
    body.uint16(colourTypeCode(colour.colourType))
    writer.uint16(0x0001)
    writer.uint32(UInt32(body.bytes.count))
    writer.append(body.bytes)
  }

  /// The code of a colour type in the file: 0 global, 1 spot and 2 normal, as in the Android coder.
  private static func colourTypeCode(_ type: PaletteColourType) -> UInt16 {
    switch type {
    case .global: 0
    case .spot: 1
    case .normal: 2
    }
  }

  private static func readColour(_ reader: inout BinaryReader) throws -> PaletteColour {
    // The name length is not needed because the name is read up to its terminator.
    _ = try reader.uint16()
    let name = try reader.nullTerminatedUTF16()
    let model = String(decoding: try reader.take(4), as: UTF8.self)

    let colour: PaletteColour
    switch model {
    case "RGB ":
      let values = try readFloats(&reader, count: 3)
      colour = PaletteMath.colour(
        name: name, red: values[0], green: values[1], blue: values[2])
    case "CMYK":
      let values = try readFloats(&reader, count: 4)
      colour = PaletteMath.cmyk(
        name: name, cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
    case "Gray":
      let values = try readFloats(&reader, count: 1)
      colour = PaletteMath.grey(name: name, white: values[0])
    case "LAB ":
      // L is stored from 0 to 1 and multiplied by 100, as the Android coder does.
      let values = try readFloats(&reader, count: 3)
      let rgb = PaletteLab.toSRGB(l: values[0] * 100, a: values[1], b: values[2])
      colour = PaletteColour(name: name, red: rgb.red, green: rgb.green, blue: rgb.blue)
    default:
      throw PaletteFormatError.unknownColourModel(model)
    }

    let typeCode = try reader.uint16()
    let colourType: PaletteColourType
    switch typeCode {
    case 0: colourType = .global
    case 1: colourType = .spot
    case 2: colourType = .normal
    default: throw PaletteFormatError.unknownColourType(typeCode)
    }
    return colour.withColourType(colourType)
  }

  private static func readFloats(_ reader: inout BinaryReader, count: Int) throws -> [Double] {
    var values: [Double] = []
    for _ in 0..<count {
      values.append(Double(try reader.float32()))
    }
    return values
  }
}

/// Reads big-endian values from a byte array. Reads past the end throw `truncated`.
private struct BinaryReader {
  private let bytes: [UInt8]
  private var position = 0

  init(_ data: Data) {
    bytes = Array(data)
  }

  mutating func take(_ count: Int) throws -> [UInt8] {
    guard count >= 0, count <= bytes.count - position else {
      throw PaletteFormatError.truncated
    }
    let slice = Array(bytes[position..<position + count])
    position += count
    return slice
  }

  mutating func uint16() throws -> UInt16 {
    let value = try take(2)
    return UInt16(value[0]) << 8 | UInt16(value[1])
  }

  mutating func uint32() throws -> UInt32 {
    try take(4).reduce(0) { $0 << 8 | UInt32($1) }
  }

  mutating func float32() throws -> Float {
    Float(bitPattern: try uint32())
  }

  /// UTF-16 code units up to a zero unit, which ends the string.
  mutating func nullTerminatedUTF16() throws -> String {
    var units: [UInt16] = []
    while true {
      let unit = try uint16()
      if unit == 0 { break }
      units.append(unit)
    }
    return String(decoding: units, as: UTF16.self)
  }
}

/// Writes big-endian values into a byte array.
private struct BinaryWriter {
  private(set) var bytes: [UInt8] = []

  var data: Data {
    Data(bytes)
  }

  mutating func append(_ values: [UInt8]) {
    bytes += values
  }

  mutating func uint16(_ value: UInt16) {
    bytes += [UInt8(value >> 8), UInt8(value & 0xFF)]
  }

  mutating func uint32(_ value: UInt32) {
    bytes += [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  mutating func float32(_ value: Double) {
    uint32(Float(value).bitPattern)
  }

  /// The UTF-16 units of `text` with a count that includes the zero unit, then the units and the
  /// zero unit. Names longer than the 16-bit count limit are cut.
  mutating func nullTerminatedUTF16(_ text: String) {
    let units = Array(text.utf16.prefix(Int(UInt16.max) - 1))
    uint16(UInt16(units.count + 1))
    for unit in units {
      uint16(unit)
    }
    uint16(0)
  }
}
