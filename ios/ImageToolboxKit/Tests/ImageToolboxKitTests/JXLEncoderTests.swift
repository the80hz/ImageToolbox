import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import ImageToolboxKit

/// The JPEG XL writer is checked against ImageIO, which decodes `public.jpeg-xl` on this system.
/// ImageIO is the independent reference: every test that matters writes a file with the encoder,
/// lets ImageIO decode it, and compares the straight RGBA bytes with what `RasterImage` reports.
@Suite("JPEG XL encoder")
struct JXLEncoderTests {

  // MARK: Pictures and the reference decoder

  enum Content: CaseIterable, CustomStringConvertible {
    case noise, gradient, flat, edges, grey

    var description: String {
      switch self {
      case .noise: "noise"
      case .gradient: "gradient"
      case .flat: "flat"
      case .edges: "edges"
      case .grey: "grey"
      }
    }
  }

  /// A picture built from code. With `alpha` the alpha channel varies, and the colour values are
  /// premultiplied as `RasterImage` stores them.
  static func raster(
    width: Int, height: Int, content: Content, alpha: Bool, seed: UInt64 = 1
  ) -> RasterImage {
    var generator = SeededGenerator(seed: seed &+ UInt64(width * 31 + height))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        var red: Int
        var green: Int
        var blue: Int
        switch content {
        case .noise:
          red = Int.random(in: 0...255, using: &generator)
          green = Int.random(in: 0...255, using: &generator)
          blue = Int.random(in: 0...255, using: &generator)
        case .gradient:
          red = (x * 255) / max(1, width - 1)
          green = (y * 255) / max(1, height - 1)
          blue = ((x + y) * 255) / max(1, width + height - 2)
        case .flat:
          red = 200
          green = 30
          blue = 90
        case .edges:
          // Flat areas with hard edges and a few small steps: only a handful of residual sizes.
          let band = (x / 7 + y / 5) % 4
          red = [0, 255, 3, 128][band]
          green = [255, 0, 2, 129][band]
          blue = [7, 7, 250, 127][band]
        case .grey:
          red = (x * 3 + y * 5) % 256
          green = red
          blue = red
        }
        var opacity = 255
        if alpha {
          opacity = (x * 17 + y * 29) % 7 == 0 ? 0 : 1 + (x * 5 + y * 3) % 255
        }
        // Premultiply the way Core Graphics stores pixels.
        red = (red * opacity + 127) / 255
        green = (green * opacity + 127) / 255
        blue = (blue * opacity + 127) / 255
        let index = (y * width + x) * 4
        pixels[index] = UInt8(red)
        pixels[index + 1] = UInt8(green)
        pixels[index + 2] = UInt8(blue)
        pixels[index + 3] = UInt8(opacity)
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  struct Decoded {
    var width: Int
    var height: Int
    /// Straight RGBA, 4 bytes per pixel. An image without alpha reads as 255.
    var rgba: [UInt8]
    var hasAlpha: Bool
  }

  enum DecodeFailure: Error {
    case notDecoded
    case unexpectedLayout
  }

  /// Decodes with ImageIO and returns the samples as the decoder stores them, without any
  /// premultiplication or colour conversion.
  static func decode(_ data: Data) throws -> Decoded {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) as String? == "public.jpeg-xl",
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let provider = image.dataProvider,
      let raw = provider.data
    else { throw DecodeFailure.notDecoded }
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32 else {
      throw DecodeFailure.unexpectedLayout
    }
    let hasAlpha: Bool
    switch image.alphaInfo {
    case .last: hasAlpha = true
    case .noneSkipLast: hasAlpha = false
    default: throw DecodeFailure.unexpectedLayout
    }
    let bytes = [UInt8](raw as Data)
    var rgba = [UInt8](repeating: 255, count: image.width * image.height * 4)
    for y in 0..<image.height {
      for x in 0..<image.width {
        let source = y * image.bytesPerRow + x * 4
        let target = (y * image.width + x) * 4
        rgba[target] = bytes[source]
        rgba[target + 1] = bytes[source + 1]
        rgba[target + 2] = bytes[source + 2]
        if hasAlpha { rgba[target + 3] = bytes[source + 3] }
      }
    }
    return Decoded(width: image.width, height: image.height, rgba: rgba, hasAlpha: hasAlpha)
  }

  /// Encodes, decodes with ImageIO and checks every byte. Returns the file size.
  @discardableResult
  static func expectRoundTrip(
    _ raster: RasterImage, options: JXLEncoder.Options = .init(),
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws -> (size: Int, report: JXLEncoder.Report) {
    let result = try JXLEncoder.encode(raster, options: options)
    let decoded = try decode(result.data)
    #expect(decoded.width == raster.width, sourceLocation: sourceLocation)
    #expect(decoded.height == raster.height, sourceLocation: sourceLocation)
    #expect(decoded.hasAlpha == result.report.hasAlpha, sourceLocation: sourceLocation)
    let expected = raster.straightRGBA()
    if decoded.rgba != expected {
      let first = zip(decoded.rgba, expected).enumerated().first { $0.element.0 != $0.element.1 }
      Issue.record(
        "pixels differ, first at byte \(first?.offset ?? -1) of \(expected.count)",
        sourceLocation: sourceLocation)
    }
    return (result.data.count, result.report)
  }

  // MARK: Round trips

  @Test(
    "ImageIO reads back every pixel of RGB and RGBA pictures",
    arguments: [(1, 1), (3, 5), (64, 48), (257, 129)], [false, true])
  func roundTripSizes(size: (Int, Int), alpha: Bool) throws {
    for content in Content.allCases {
      let raster = Self.raster(width: size.0, height: size.1, content: content, alpha: alpha)
      try Self.expectRoundTrip(raster)
    }
  }

  @Test("every colour transform and histogram grouping decodes to the same pixels")
  func optionCombinations() throws {
    let transforms: [JXLEncoder.Options.ColourTransform] = [.automatic, .none, .yCoCg]
    let groupings: [JXLEncoder.Options.Clustering] = [
      .automatic, .shared, .perChannel, .colourAndAlpha,
    ]
    for (width, height) in [(1, 1), (3, 5), (64, 48), (257, 20)] {
      for alpha in [false, true] {
        for content in [Content.noise, .gradient, .edges] {
          let raster = Self.raster(width: width, height: height, content: content, alpha: alpha)
          for transform in transforms {
            for grouping in groupings {
              var options = JXLEncoder.Options()
              options.colourTransform = transform
              options.clustering = grouping
              let report = try Self.expectRoundTrip(raster, options: options).report
              if transform == .yCoCg { #expect(report.yCoCg) }
              if transform == .none { #expect(!report.yCoCg) }
              if grouping == .shared { #expect(Set(report.clusterOfChannel).count == 1) }
              if grouping == .perChannel {
                #expect(Set(report.clusterOfChannel).count == (alpha ? 4 : 3))
              }
            }
          }
        }
      }
    }
  }

  @Test("pictures that fill several 256 x 256 groups decode exactly")
  func multipleGroups() throws {
    let sizes = [(256, 256), (256, 257), (257, 256), (300, 40), (40, 300), (513, 260), (1, 600)]
    for (width, height) in sizes {
      for alpha in [false, true] {
        let raster = Self.raster(
          width: width, height: height, content: .gradient, alpha: alpha)
        let outcome = try Self.expectRoundTrip(raster)
        let across = (width + 255) / 256
        let down = (height + 255) / 256
        #expect(outcome.report.groupCount == across * down)
      }
    }
    // Noise in several groups, with each grouping, so the per-group streams use every code.
    let noisy = Self.raster(width: 300, height: 270, content: .noise, alpha: true)
    for grouping in [
      JXLEncoder.Options.Clustering.shared, .perChannel, .colourAndAlpha,
    ] {
      var options = JXLEncoder.Options()
      options.clustering = grouping
      try Self.expectRoundTrip(noisy, options: options)
    }
  }

  @Test("a picture judged on a sample of its groups still decodes exactly")
  func sampledDecision() throws {
    // More than eight groups, so the transform and grouping are chosen from a sample.
    let raster = Self.raster(width: 513, height: 513, content: .gradient, alpha: true)
    let outcome = try Self.expectRoundTrip(raster)
    #expect(outcome.report.groupCount == 9)
  }

  @Test("a fully transparent picture and one with a single opaque pixel decode exactly")
  func transparentPictures() throws {
    let clear = RasterImage(width: 9, height: 7, pixels: [UInt8](repeating: 0, count: 9 * 7 * 4))
    let outcome = try Self.expectRoundTrip(clear)
    #expect(outcome.report.hasAlpha)

    var pixels = [UInt8](repeating: 0, count: 9 * 7 * 4)
    let index = (3 * 9 + 4) * 4
    pixels[index] = 40
    pixels[index + 1] = 80
    pixels[index + 2] = 120
    pixels[index + 3] = 255
    try Self.expectRoundTrip(RasterImage(width: 9, height: 7, pixels: pixels))
  }

  @Test("premultiplied input is written as straight colour")
  func straightColour() throws {
    // Premultiplied (50, 25, 10) at alpha 100 is about (127, 64, 26) straight.
    let raster = RasterImage(width: 1, height: 1, pixels: [50, 25, 10, 100])
    let result = try JXLEncoder.encode(raster, options: .init())
    let decoded = try Self.decode(result.data)
    #expect(decoded.rgba == raster.straightRGBA())
    #expect(decoded.rgba[3] == 100)
    #expect(abs(Int(decoded.rgba[0]) - 127) <= 1)
  }

  // MARK: Choices the encoder makes

  @Test("a picture without transparency is written without an alpha channel")
  func opaqueHasNoAlpha() throws {
    let opaque = Self.raster(width: 32, height: 32, content: .gradient, alpha: false)
    let result = try JXLEncoder.encode(opaque, options: .init())
    #expect(!result.report.hasAlpha)
    #expect(result.report.clusterOfChannel.count == 3)
    #expect(try Self.decode(result.data).hasAlpha == false)

    let translucent = Self.raster(width: 32, height: 32, content: .gradient, alpha: true)
    let other = try JXLEncoder.encode(translucent, options: .init())
    #expect(other.report.hasAlpha)
    #expect(other.report.clusterOfChannel.count == 4)
  }

  @Test("the colour transform is chosen where it helps")
  func transformChoice() throws {
    // Grey pictures have equal channels, which YCoCg turns into two empty ones.
    let grey = try JXLEncoder.encode(
      Self.raster(width: 64, height: 64, content: .grey, alpha: false), options: .init())
    #expect(grey.report.yCoCg)

    var withoutTransform = JXLEncoder.Options()
    withoutTransform.colourTransform = .none
    let plain = try JXLEncoder.encode(
      Self.raster(width: 64, height: 64, content: .grey, alpha: false),
      options: withoutTransform)
    #expect(grey.data.count < plain.data.count)
  }

  @Test("the automatic choice is never larger than a forced one")
  func automaticIsSmallest() throws {
    for content in [Content.noise, .gradient, .edges, .grey] {
      let raster = Self.raster(width: 96, height: 64, content: content, alpha: true)
      let automatic = try JXLEncoder.encode(raster, options: .init()).data.count
      for transform in [
        JXLEncoder.Options.ColourTransform.none, .yCoCg,
      ] {
        for grouping in [
          JXLEncoder.Options.Clustering.shared, .perChannel, .colourAndAlpha,
        ] {
          var options = JXLEncoder.Options()
          options.colourTransform = transform
          options.clustering = grouping
          let forced = try JXLEncoder.encode(raster, options: options).data.count
          // The choice is made on an estimate, so allow a few bytes.
          #expect(automatic <= forced + 8, "\(content) \(transform) \(grouping)")
        }
      }
    }
  }

  @Test("smooth and flat pictures are far smaller than their raw pixels")
  func compression() throws {
    // Only the first sample of a flat picture differs from the rest, so the two symbols of its
    // residual code cost one bit per sample. Runs of zeros would need LZ77, which is not written.
    let flat = try JXLEncoder.encode(
      Self.raster(width: 256, height: 256, content: .flat, alpha: false))
    #expect(flat.count < 256 * 256 * 3 / 4)

    let gradient = try JXLEncoder.encode(
      Self.raster(width: 257, height: 129, content: .gradient, alpha: false))
    #expect(gradient.count < 257 * 129 * 3 / 4)

    // Noise cannot shrink; it must not blow up either.
    let noise = try JXLEncoder.encode(
      Self.raster(width: 64, height: 64, content: .noise, alpha: false))
    #expect(noise.count < 64 * 64 * 3 * 12 / 10)
  }

  @Test("pictures wider or taller than one 2048-sample LF group decode exactly")
  func multipleLFGroups() throws {
    // Two LF groups across or down: the table of contents then lists several LF sections.
    for (width, height) in [(2049, 2), (2, 2049), (2100, 260)] {
      for alpha in [false, true] {
        let raster = Self.raster(width: width, height: height, content: .gradient, alpha: alpha)
        let outcome = try Self.expectRoundTrip(raster)
        let groups = ((width + 255) / 256) * ((height + 255) / 256)
        #expect(outcome.report.groupCount == groups)
      }
    }
  }

  @Test("the output is a bare codestream and is reproducible")
  func codestreamMarker() throws {
    let raster = Self.raster(width: 20, height: 10, content: .gradient, alpha: true)
    let first = try JXLEncoder.encode(raster)
    let second = try JXLEncoder.encode(raster)
    #expect(first.prefix(2) == Data([0xFF, 0x0A]))
    #expect(first == second)
  }

  @Test("the header of a 1 x 1 RGB picture is exactly the fields of the specification")
  func headerLayout() throws {
    let data = try JXLEncoder.encode(RasterImage(width: 1, height: 1, pixels: [9, 8, 7, 255]))
    // Fields in order, each as "value:bits" written least-significant bit first.
    let fields: [(Int, Int)] = [
      (0, 1),  // SizeHeader: not the small form
      (0, 2), (0, 9),  // height - 1, in the 9-bit form
      (0, 3),  // aspect ratio 0: the width follows
      (0, 2), (0, 9),  // width - 1
      (0, 1),  // ImageMetadata.all_default = false
      (0, 1),  // extra_fields
      (0, 1), (0, 2),  // integer samples, 8 bits
      (1, 1),  // modular_16_bit_buffer_sufficient
      (0, 2),  // no extra channels
      (0, 1),  // xyb_encoded
      (1, 1),  // sRGB colour encoding, all default
      (0, 2),  // extensions
      (1, 1),  // CustomTransformData all default
    ]
    var writer = JXLBitWriter()
    writer.write(0xFF, bits: 8)
    writer.write(0x0A, bits: 8)
    for (value, bits) in fields { writer.write(value, bits: bits) }
    writer.padToByte()
    #expect(Array(data.prefix(writer.bytes.count)) == writer.bytes)
    // The frame header that follows begins with all_default = 0, regular frame, Modular.
    let next = data[data.startIndex + writer.bytes.count]
    #expect(next & 0b1111 == 0b1000)
  }

  @Test("an empty picture is refused")
  func emptyRefused() {
    let empty = RasterImage(width: 0, height: 0, pixels: [])
    #expect(throws: JXLEncoder.Failure.emptyImage) { try JXLEncoder.encode(empty) }
  }

  @Test("cancelling the task stops the encoder")
  func cancellation() async {
    let raster = Self.raster(width: 1024, height: 1024, content: .noise, alpha: true)
    let task = Task { try JXLEncoder.encode(raster) }
    task.cancel()
    let outcome = await task.result
    if case .failure(let error) = outcome {
      #expect(error is CancellationError)
    } else {
      Issue.record("the encoder ignored the cancellation")
    }
  }

  // MARK: Bit writer

  @Test("bits are packed least-significant first and padded with zeros")
  func bitWriter() {
    var writer = JXLBitWriter()
    writer.write(1, bits: 1)
    writer.write(0b101, bits: 3)
    writer.write(0b1100, bits: 4)  // completes byte 0: 1 + 101<<1 + 1100<<4
    writer.write(0x2B, bits: 6)
    writer.padToByte()
    writer.write(0x1_0000_0001, bits: 32)  // only the low 32 bits count
    #expect(writer.bytes == [0b1100_1011, 0x2B, 0x01, 0x00, 0x00, 0x00])
    #expect(writer.bitCount == 48)
  }
}

// MARK: - Prefix codes

/// The prefix-code header is read back with a reader that follows the decoding procedure of the
/// format (the Brotli style used by JPEG XL), then compared with the lengths that were meant.
@Suite("JPEG XL prefix codes")
struct JXLPrefixCodeTests {

  struct Reader {
    let bytes: [UInt8]
    var position = 0

    mutating func read(_ count: Int) -> Int {
      var value = 0
      for bit in 0..<count {
        let byte = bytes[position >> 3]
        value |= Int((byte >> UInt8(position & 7)) & 1) << bit
        position += 1
      }
      return value
    }
  }

  /// The decoder's view of a header: the code length of every symbol.
  static func readLengths(_ reader: inout Reader, alphabetSize: Int) -> [Int] {
    var lengths = [Int](repeating: 0, count: alphabetSize)
    // An alphabet of one symbol has no code to read.
    if alphabetSize == 1 { return lengths }
    let selector = reader.read(2)
    if selector == 1 {
      let symbolBits = JXLPrefixCode.bitLength(alphabetSize - 1)
      let count = reader.read(2) + 1
      let symbols = (0..<count).map { _ in reader.read(symbolBits) % alphabetSize }
      switch count {
      case 1:
        lengths[symbols[0]] = 0
      case 2:
        lengths[symbols[0]] = 1
        lengths[symbols[1]] = 1
      case 3:
        lengths[symbols[0]] = 1
        lengths[symbols[1]] = 2
        lengths[symbols[2]] = 2
      default:
        if reader.read(1) == 1 {
          for (index, length) in [1, 2, 3, 3].enumerated() { lengths[symbols[index]] = length }
        } else {
          for symbol in symbols { lengths[symbol] = 2 }
        }
      }
      return lengths
    }

    // Complex: the code length code lengths, in their fixed order and fixed variable-length code.
    let order = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    var codeLengthLengths = [Int](repeating: 0, count: 18)
    var space = 32
    for index in selector..<18 {
      let peek = reader.read(2)
      var value: Int
      switch peek {
      case 0: value = 0
      case 1: value = 4
      case 2: value = 3
      default:
        if reader.read(1) == 0 {
          value = 2
        } else {
          value = reader.read(1) == 0 ? 1 : 5
        }
      }
      codeLengthLengths[order[index]] = value
      if value != 0 {
        space -= 32 >> value
        if space <= 0 { break }
      }
    }
    // The code-length alphabet as a canonical code, decoded bit by bit, first bit most significant.
    let codes = JXLPrefixCode.canonicalCodes(lengths: codeLengthLengths)
    func readCodeLengthSymbol(_ reader: inout Reader) -> Int {
      var code = 0
      for length in 1...5 {
        code |= reader.read(1) << (length - 1)  // reversed codes are stored LSB first
        for symbol in 0..<18 where codeLengthLengths[symbol] == length && codes[symbol] == code {
          return symbol
        }
      }
      return -1
    }

    var symbol = 0
    var previous = 8
    var repeatCount = 0
    var repeatLength = 0
    var remaining = 32768
    while symbol < alphabetSize && remaining > 0 {
      let code = readCodeLengthSymbol(&reader)
      if code < 16 {
        repeatCount = 0
        lengths[symbol] = code
        symbol += 1
        if code != 0 {
          previous = code
          remaining -= 32768 >> code
        }
      } else {
        let extraBits = code - 14
        let newLength = code == 16 ? previous : 0
        if repeatLength != newLength {
          repeatCount = 0
          repeatLength = newLength
        }
        let old = repeatCount
        if repeatCount > 0 {
          repeatCount -= 2
          repeatCount <<= extraBits
        }
        repeatCount += reader.read(extraBits) + 3
        let delta = repeatCount - old
        guard symbol + delta <= alphabetSize else {
          Issue.record("a repeat code runs past the alphabet")
          return lengths
        }
        for offset in 0..<delta { lengths[symbol + offset] = newLength }
        symbol += delta
        if newLength != 0 { remaining -= delta << (15 - newLength) }
      }
    }
    #expect(remaining == 0, "the code is complete")
    return lengths
  }

  static func kraftSum(_ lengths: [Int]) -> Int {
    lengths.reduce(0) { $0 + ($1 > 0 ? 32768 >> $1 : 0) }
  }

  /// Total cost and height of an unrestricted Huffman tree, by repeatedly merging the two
  /// lightest weights.
  static func referenceHuffman(_ frequencies: [Int]) -> (cost: Int, height: Int) {
    var nodes = frequencies.filter { $0 > 0 }.sorted().map { (weight: $0, height: 0) }
    var cost = 0
    while nodes.count > 1 {
      let merged = (
        weight: nodes[0].weight + nodes[1].weight, height: max(nodes[0].height, nodes[1].height) + 1
      )
      cost += merged.weight
      nodes.removeFirst(2)
      let position = nodes.firstIndex { $0.weight >= merged.weight } ?? nodes.count
      nodes.insert(merged, at: position)
    }
    return (cost, nodes.first?.height ?? 0)
  }

  static func check(_ counts: [Int], alphabetSize: Int) {
    let frequencies = counts + [Int](repeating: 0, count: max(0, alphabetSize - counts.count))
    let code = JXLPrefixCode(frequencies: frequencies, alphabetSize: alphabetSize)
    var writer = JXLBitWriter()
    code.writeHeader(to: &writer)
    writer.padToByte()
    var reader = Reader(bytes: writer.bytes + [0, 0])
    let lengths = readLengths(&reader, alphabetSize: alphabetSize)
    #expect(lengths == code.lengths, "header read back: \(frequencies.prefix(alphabetSize))")
    #expect(code.headerBitCount() == reader.position, "header size is exact")

    let used = frequencies.prefix(alphabetSize).filter { $0 > 0 }.count
    if used >= 2 {
      #expect(kraftSum(code.lengths) == 32768, "the code is complete")
      #expect((code.lengths.max() ?? 0) <= JXLPrefixCode.maxLength)
    }
    // No code may be the start of another one.
    var seen = Set<String>()
    for symbol in 0..<alphabetSize where code.lengths[symbol] > 0 {
      var text = ""
      for bit in 0..<code.lengths[symbol] {
        text += (code.codes[symbol] >> bit) & 1 == 1 ? "1" : "0"
      }
      for other in seen { #expect(!text.hasPrefix(other) && !other.hasPrefix(text)) }
      seen.insert(text)
    }
  }

  @Test("headers of every shape read back to the same lengths")
  func headerRoundTrip() {
    // One to four used symbols use the simple form.
    Self.check([5], alphabetSize: 1)
    Self.check([0, 9], alphabetSize: 2)
    Self.check([4, 4], alphabetSize: 36)
    Self.check([0, 7, 0, 0, 3, 0, 0, 1], alphabetSize: 8)
    Self.check([10, 20, 30, 40], alphabetSize: 4)
    Self.check([100, 3, 2, 1], alphabetSize: 4)
    Self.check(
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 50, 0, 0, 0, 0, 3, 0, 9, 0, 0, 0, 1], alphabetSize: 23)
    // Five or more use the complex form.
    Self.check([5, 4, 3, 2, 1], alphabetSize: 5)
    Self.check([1, 1, 1, 1, 1, 1, 1, 1], alphabetSize: 8)
    Self.check(Array(repeating: 1, count: 40), alphabetSize: 40)
    // Gaps of zero lengths of every size, to exercise the repeat codes.
    for gap in 1...40 {
      var frequencies = [Int](repeating: 0, count: 60)
      for symbol in [0, 1, 2] { frequencies[symbol] = 10 + symbol }
      frequencies[3 + gap] = 7
      frequencies[4 + gap] = 5
      frequencies[5 + gap] = 1
      Self.check(frequencies, alphabetSize: 6 + gap)
    }
  }

  @Test("random histograms give complete, prefix-free, optimal codes with readable headers")
  func randomHistograms() {
    var generator = SeededGenerator(seed: 99)
    for _ in 0..<300 {
      let size = Int.random(in: 1...45, using: &generator)
      let density = Int.random(in: 1...6, using: &generator)
      var frequencies = [Int](repeating: 0, count: 64)
      for symbol in 0..<size where Int.random(in: 0...density, using: &generator) != 0 {
        frequencies[symbol] = 1 + Int(pow(Double.random(in: 0...1, using: &generator), 3) * 5000)
      }
      let last = (frequencies.lastIndex { $0 > 0 } ?? 0) + 1
      Self.check(frequencies, alphabetSize: last)

      // Without a length limit in the way, the cost equals the optimal Huffman cost.
      let code = JXLPrefixCode(frequencies: frequencies, alphabetSize: last)
      let reference = Self.referenceHuffman(frequencies)
      let spent = code.dataBitCount(frequencies: frequencies)
      if frequencies.filter({ $0 > 0 }).count >= 5 {
        if reference.height <= JXLPrefixCode.maxLength {
          #expect(spent == reference.cost)
        } else {
          #expect(spent >= reference.cost)
        }
      }
    }
  }

  @Test("a code is limited to 15 bits even when the counts ask for more")
  func lengthLimit() {
    // Fibonacci counts make an unlimited Huffman tree as deep as the alphabet is large.
    var frequencies = [Int](repeating: 0, count: 40)
    var (previous, current) = (1, 1)
    for symbol in 0..<40 {
      frequencies[symbol] = current
      (previous, current) = (current, previous + current)
    }
    let code = JXLPrefixCode(frequencies: frequencies, alphabetSize: 40)
    #expect((code.lengths.max() ?? 0) <= 15)
    #expect(Self.kraftSum(code.lengths) == 32768)
    Self.check(frequencies, alphabetSize: 40)
  }

  @Test("the alphabet size is written as a flag and a short exponent form")
  func alphabetSizeBits() {
    func bits(_ size: Int) -> (Int, Int) {
      var writer = JXLBitWriter()
      JXLPrefixCode.writeAlphabetSize(size, to: &writer)
      let count = writer.bitCount
      writer.padToByte()
      var reader = Reader(bytes: writer.bytes + [0, 0])
      var decoded = 1
      if reader.read(1) == 1 {
        let exponent = reader.read(4)
        decoded = 1 + (1 << exponent) + reader.read(exponent)
      }
      return (count, decoded)
    }
    #expect(bits(1) == (1, 1))
    #expect(bits(2) == (5, 2))
    #expect(bits(4) == (6, 4))
    for size in 1...300 { #expect(bits(size).1 == size) }
  }
}
