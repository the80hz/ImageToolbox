import Foundation

/// The Quite OK Image format (QOI), 4 channels, sRGB. Written and read as specified by its authors.
/// There is no QOI support in ImageIO, so the codec lives here.
public enum QOICodec {

  public enum Failure: Error, Equatable {
    case malformed
    case tooLarge
  }

  private static let headerSize = 14
  private static let endMarker: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]
  private static let indexOp: UInt8 = 0x00
  private static let diffOp: UInt8 = 0x40
  private static let lumaOp: UInt8 = 0x80
  private static let runOp: UInt8 = 0xC0
  private static let rgbOp: UInt8 = 0xFE
  private static let rgbaOp: UInt8 = 0xFF

  /// Encodes straight RGBA bytes, 4 per pixel, row by row from the top.
  public static func encode(width: Int, height: Int, rgba pixels: [UInt8]) throws -> Data {
    guard width > 0, height > 0, pixels.count == width * height * 4 else { throw Failure.malformed }
    var output: [UInt8] = []
    output.reserveCapacity(headerSize + pixels.count / 2)
    output += Array("qoif".utf8)
    output += bigEndian(UInt32(width))
    output += bigEndian(UInt32(height))
    output += [4, 0]

    var index = [[UInt8]](repeating: [0, 0, 0, 0], count: 64)
    var previous: [UInt8] = [0, 0, 0, 255]
    var run = 0
    let count = width * height

    for pixelIndex in 0..<count {
      let offset = pixelIndex * 4
      let pixel = Array(pixels[offset..<(offset + 4)])

      if pixel == previous {
        run += 1
        if run == 62 || pixelIndex == count - 1 {
          output.append(runOp | UInt8(run - 1))
          run = 0
        }
        continue
      }
      if run > 0 {
        output.append(runOp | UInt8(run - 1))
        run = 0
      }

      let slot = hash(pixel)
      if index[slot] == pixel {
        output.append(indexOp | UInt8(slot))
      } else {
        index[slot] = pixel
        if pixel[3] == previous[3] {
          appendColour(pixel, previous: previous, to: &output)
        } else {
          output += [rgbaOp] + pixel
        }
      }
      previous = pixel
    }
    output += endMarker
    return Data(output)
  }

  /// Decodes a QOI file into straight RGBA bytes.
  public static func decode(_ data: Data) throws -> (width: Int, height: Int, rgba: [UInt8]) {
    let bytes = [UInt8](data)
    guard bytes.count >= headerSize + endMarker.count, Array(bytes[0..<4]) == Array("qoif".utf8)
    else { throw Failure.malformed }
    let width = Int(readBigEndian(bytes, 4))
    let height = Int(readBigEndian(bytes, 8))
    guard width > 0, height > 0 else { throw Failure.malformed }
    let (total, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, total <= 400_000_000 else { throw Failure.tooLarge }

    var output = [UInt8](repeating: 0, count: total * 4)
    var index = [[UInt8]](repeating: [0, 0, 0, 0], count: 64)
    var pixel: [UInt8] = [0, 0, 0, 255]
    var position = headerSize
    var run = 0
    let dataEnd = bytes.count - endMarker.count

    for pixelIndex in 0..<total {
      if run > 0 {
        run -= 1
      } else {
        guard position < dataEnd else { throw Failure.malformed }
        let byte = bytes[position]
        position += 1
        if byte == rgbOp {
          guard position + 3 <= dataEnd else { throw Failure.malformed }
          pixel = [bytes[position], bytes[position + 1], bytes[position + 2], pixel[3]]
          position += 3
        } else if byte == rgbaOp {
          guard position + 4 <= dataEnd else { throw Failure.malformed }
          pixel = Array(bytes[position..<(position + 4)])
          position += 4
        } else {
          switch byte & 0xC0 {
          case indexOp:
            pixel = index[Int(byte & 0x3F)]
          case diffOp:
            pixel = [
              pixel[0] &+ ((byte >> 4) & 0x03) &- 2,
              pixel[1] &+ ((byte >> 2) & 0x03) &- 2,
              pixel[2] &+ (byte & 0x03) &- 2,
              pixel[3],
            ]
          case lumaOp:
            guard position < dataEnd else { throw Failure.malformed }
            let second = bytes[position]
            position += 1
            let green = Int(byte & 0x3F) - 32
            let redDelta = green + Int((second >> 4) & 0x0F) - 8
            let blueDelta = green + Int(second & 0x0F) - 8
            pixel = [
              pixel[0] &+ UInt8(truncatingIfNeeded: redDelta),
              pixel[1] &+ UInt8(truncatingIfNeeded: green),
              pixel[2] &+ UInt8(truncatingIfNeeded: blueDelta),
              pixel[3],
            ]
          default:
            run = Int(byte & 0x3F)
          }
        }
        index[hash(pixel)] = pixel
      }
      let offset = pixelIndex * 4
      output[offset] = pixel[0]
      output[offset + 1] = pixel[1]
      output[offset + 2] = pixel[2]
      output[offset + 3] = pixel[3]
    }
    return (width, height, output)
  }

  // MARK: - Helpers

  /// Chooses the smallest colour operation that reproduces `pixel` from `previous`.
  private static func appendColour(_ pixel: [UInt8], previous: [UInt8], to output: inout [UInt8]) {
    let red = Int(pixel[0]) - Int(previous[0])
    let green = Int(pixel[1]) - Int(previous[1])
    let blue = Int(pixel[2]) - Int(previous[2])
    if (-2...1).contains(red), (-2...1).contains(green), (-2...1).contains(blue) {
      let packed: Int = ((red + 2) << 4) | ((green + 2) << 2) | (blue + 2)
      output.append(diffOp | UInt8(packed))
      return
    }
    let greenDifference = green
    let redGreen = red - green
    let blueGreen = blue - green
    if (-32...31).contains(greenDifference), (-8...7).contains(redGreen),
      (-8...7).contains(blueGreen)
    {
      output.append(lumaOp | UInt8(greenDifference + 32))
      let packed: Int = ((redGreen + 8) << 4) | (blueGreen + 8)
      output.append(UInt8(packed))
      return
    }
    output += [rgbOp, pixel[0], pixel[1], pixel[2]]
  }

  private static func hash(_ pixel: [UInt8]) -> Int {
    (Int(pixel[0]) * 3 + Int(pixel[1]) * 5 + Int(pixel[2]) * 7 + Int(pixel[3]) * 11) % 64
  }

  private static func bigEndian(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  private static func readBigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    var value: UInt32 = 0
    for index in 0..<4 {
      value = (value << 8) | UInt32(bytes[offset + index])
    }
    return value
  }
}
