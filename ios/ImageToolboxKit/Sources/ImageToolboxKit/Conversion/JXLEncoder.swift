import Foundation

/// A lossless JPEG XL writer, in pure Swift, with no libjxl and no ImageIO encoder behind it.
///
/// The file is a bare codestream (`FF 0A`) in Modular mode:
/// - 8 bits per channel, sRGB, straight alpha as one extra channel when any pixel is not opaque;
/// - no transform, or the reversible YCoCg transform (RCT type 6) when a sample of the picture
///   says it makes the file smaller;
/// - one MA tree whose leaves are the channels, each using the clamped Gradient predictor;
/// - residuals zig-zag packed, split into a token and raw extra bits, and the tokens written with
///   canonical prefix (Huffman) codes, shared between channels or one per channel, whichever is
///   estimated smaller;
/// - pictures larger than 256 x 256 are split into the standard 256 x 256 groups.
///
/// Only lossless coding is implemented. There is no lossy VarDCT path, so a quality setting has
/// nothing to act on and callers ignore it. No metadata, ICC profile or EXIF is written: the
/// picture is tagged sRGB.
public enum JXLEncoder {

  public enum Failure: Error, Equatable {
    /// The picture has no pixels.
    case emptyImage
    /// A side of the picture is beyond what a JPEG XL header can hold.
    case tooLarge
  }

  /// Tuning switches. Tests use them to reach each branch of the bitstream.
  struct Options {
    enum ColourTransform { case automatic, none, yCoCg }
    enum Clustering { case automatic, shared, perChannel, colourAndAlpha }

    var colourTransform = ColourTransform.automatic
    var clustering = Clustering.automatic
  }

  /// What the encoder chose for a picture. Tests read it to know which branch was taken.
  struct Report: Equatable {
    var hasAlpha: Bool
    var yCoCg: Bool
    var clusterOfChannel: [Int]
    var groupCount: Int
    /// How many of the sample histograms use the complex prefix-code header.
    var complexCodeCount: Int
  }

  /// Writes `raster` as a lossless JPEG XL codestream. The straight (non-premultiplied) RGBA
  /// values decode back exactly. A picture whose alpha is 255 everywhere is written without an
  /// alpha channel.
  public static func encode(_ raster: RasterImage) throws -> Data {
    try encode(raster, options: Options()).data
  }

  static func encode(_ raster: RasterImage, options: Options) throws -> (data: Data, report: Report)
  {
    let width = raster.width
    let height = raster.height
    guard width > 0, height > 0 else { throw Failure.emptyImage }
    guard width <= maxSide, height <= maxSide else { throw Failure.tooLarge }

    let frame = Frame(
      rgba: raster.straightRGBA(), width: width, height: height)
    let plan = try makePlan(for: frame, options: options)

    // Sections first, because the table of contents lists their sizes.
    var sections: [[UInt8]] = []
    var global = JXLBitWriter()
    writeGlobalSection(plan: plan, frame: frame, to: &global)
    if frame.groupCount == 1 {
      // The only group follows the global data in the same section, with no alignment between.
      try writeGroup(0, plan: plan, frame: frame, includeHeader: false, to: &global)
      global.padToByte()
      sections.append(global.bytes)
    } else {
      global.padToByte()
      sections.append(global.bytes)
      // One empty section per LF group, then the empty HF global section.
      sections += Array(repeating: [], count: frame.lfGroupCount + 1)
      for group in 0..<frame.groupCount {
        var writer = JXLBitWriter()
        try writeGroup(group, plan: plan, frame: frame, includeHeader: true, to: &writer)
        writer.padToByte()
        sections.append(writer.bytes)
      }
    }

    var output = JXLBitWriter()
    writeFileHeader(frame: frame, to: &output)
    writeFrameHeader(frame: frame, to: &output)
    writeTableOfContents(sizes: sections.map(\.count), to: &output)
    for section in sections { output.append(section) }
    let report = Report(
      hasAlpha: frame.hasAlpha, yCoCg: plan.yCoCg, clusterOfChannel: plan.clusterOfChannel,
      groupCount: frame.groupCount, complexCodeCount: plan.codes.filter(\.isComplex).count)
    return (Data(output.bytes), report)
  }

  // MARK: Limits and constants

  private static let maxSide = 1 << 30
  /// A group is 256 x 256 samples: `group_size_shift` 1 in the frame header.
  fileprivate static let groupSide = 256
  /// The Gradient predictor of Modular mode.
  private static let gradientPredictor = 5
  /// Room for every token the hybrid integer split can produce for 9-bit packed residuals.
  fileprivate static let tokenCapacity = 64

  // MARK: Picture and plan

  /// The picture as straight RGBA bytes with its group layout.
  fileprivate struct Frame {
    let rgba: [UInt8]
    let width: Int
    let height: Int
    let hasAlpha: Bool
    let groupsAcross: Int
    let groupCount: Int
    let lfGroupCount: Int

    init(rgba: [UInt8], width: Int, height: Int) {
      self.rgba = rgba
      self.width = width
      self.height = height
      var alpha = false
      for index in stride(from: 3, to: rgba.count, by: 4) where rgba[index] != 255 {
        alpha = true
        break
      }
      hasAlpha = alpha
      groupsAcross = (width + JXLEncoder.groupSide - 1) / JXLEncoder.groupSide
      let groupsDown = (height + JXLEncoder.groupSide - 1) / JXLEncoder.groupSide
      groupCount = groupsAcross * groupsDown
      // An LF group covers 8 x 8 groups.
      let lfSide = JXLEncoder.groupSide * 8
      lfGroupCount = ((width + lfSide - 1) / lfSide) * ((height + lfSide - 1) / lfSide)
    }

    var channelCount: Int { hasAlpha ? 4 : 3 }
  }

  /// Decisions that shape the stream: colour transform and which channels share a histogram.
  fileprivate struct Plan {
    var yCoCg: Bool
    /// Histogram index of each channel.
    var clusterOfChannel: [Int]
    var clusterCount: Int
    var codes: [JXLPrefixCode]
    /// The MA tree leaf that holds each channel, in the order the decoder numbers leaves.
    var leafOfChannel: [Int]
    var tree: [TreeNode]
  }

  fileprivate enum TreeNode {
    case split(channel: Int)
    case leaf
  }

  private static func makePlan(for frame: Frame, options: Options) throws -> Plan {
    let channels = frame.channelCount
    let all = Array(0..<frame.groupCount)
    // Large pictures are judged on up to eight groups spread over the picture.
    let sample =
      frame.groupCount <= 8
      ? all : (0..<8).map { $0 * frame.groupCount / 8 }
    let judgesAll = sample.count == frame.groupCount

    var candidates: [Bool]
    switch options.colourTransform {
    case .none: candidates = [false]
    case .yCoCg: candidates = [true]
    case .automatic: candidates = [false, true]
    }

    var best: (cost: Int, yCoCg: Bool, clusters: [Int], histograms: [[Int]])?
    for yCoCg in candidates {
      let histograms = try histogram(frame: frame, groups: sample, yCoCg: yCoCg)
      let (cost, clusters) = bestClustering(
        histograms: histograms, channelCount: channels, preference: options.clustering)
      if best == nil || cost < best!.cost {
        best = (cost, yCoCg, clusters, histograms)
      }
    }
    guard let chosen = best else { throw Failure.emptyImage }

    var histograms = chosen.histograms
    var clusters = chosen.clusters
    if !judgesAll {
      histograms = try histogram(frame: frame, groups: all, yCoCg: chosen.yCoCg)
      clusters =
        bestClustering(
          histograms: histograms, channelCount: channels, preference: options.clustering
        ).clusters
    }

    let clusterCount = (clusters.max() ?? 0) + 1
    var codes: [JXLPrefixCode] = []
    for cluster in 0..<clusterCount {
      let merged = mergedHistogram(histograms, clusters: clusters, cluster: cluster)
      codes.append(
        JXLPrefixCode(frequencies: merged, alphabetSize: alphabetSize(of: merged)))
    }
    let (tree, leafOfChannel) = makeTree(channelCount: channels)
    return Plan(
      yCoCg: chosen.yCoCg, clusterOfChannel: clusters, clusterCount: clusterCount,
      codes: codes, leafOfChannel: leafOfChannel, tree: tree)
  }

  /// Channel groupings worth trying, as the histogram index of each channel.
  private static func clusterings(channelCount: Int, preference: Options.Clustering) -> [[Int]] {
    let colour = channelCount == 4
    switch preference {
    case .shared:
      return [Array(repeating: 0, count: channelCount)]
    case .perChannel:
      return [Array(0..<channelCount)]
    case .colourAndAlpha:
      return [colour ? [0, 0, 0, 1] : [0, 0, 0]]
    case .automatic:
      var list: [[Int]] = [
        Array(repeating: 0, count: channelCount),
        Array(0..<channelCount),
      ]
      if colour {
        list += [[0, 1, 1, 2], [0, 0, 0, 1]]
      } else {
        list.append([0, 1, 1])
      }
      return list
    }
  }

  private static func bestClustering(
    histograms: [[Int]], channelCount: Int, preference: Options.Clustering
  ) -> (cost: Int, clusters: [Int]) {
    var best: (cost: Int, clusters: [Int])?
    for clusters in clusterings(channelCount: channelCount, preference: preference) {
      let cost = estimatedBits(histograms: histograms, clusters: clusters)
      if best == nil || cost < best!.cost { best = (cost, clusters) }
    }
    return best ?? (0, Array(repeating: 0, count: channelCount))
  }

  private static func mergedHistogram(_ histograms: [[Int]], clusters: [Int], cluster: Int)
    -> [Int]
  {
    var merged = [Int](repeating: 0, count: tokenCapacity)
    for (channel, histogram) in histograms.enumerated() where clusters[channel] == cluster {
      for token in 0..<tokenCapacity { merged[token] += histogram[token] }
    }
    return merged
  }

  private static func alphabetSize(of histogram: [Int]) -> Int {
    (histogram.lastIndex { $0 > 0 } ?? 0) + 1
  }

  /// Bits for the entropy-coded part of a grouping: headers, codes and extra bits.
  private static func estimatedBits(histograms: [[Int]], clusters: [Int]) -> Int {
    let clusterCount = (clusters.max() ?? 0) + 1
    var total = 3 + clusters.count * JXLPrefixCode.bitLength(clusterCount - 1)
    for cluster in 0..<clusterCount {
      let merged = mergedHistogram(histograms, clusters: clusters, cluster: cluster)
      let size = alphabetSize(of: merged)
      let code = JXLPrefixCode(frequencies: merged, alphabetSize: size)
      total += 9 + 9 + code.headerBitCount() + code.dataBitCount(frequencies: merged)
      for token in 0..<size { total += merged[token] * extraBitCount(token: token) }
    }
    return total
  }

  // MARK: Hybrid integers

  // Residuals use the hybrid integer split (split exponent 4, 2 bits of the mantissa in the
  // token, none from the low end): values below 16 are tokens, larger ones carry raw extra bits.

  private static func extraBitCount(token: Int) -> Int {
    token < 16 ? 0 : 2 + ((token - 16) >> 2)
  }

  @inline(__always)
  private static func split(_ value: Int) -> (token: Int, extra: Int, extraBits: Int) {
    if value < 16 { return (value, 0, 0) }
    let exponent = Int.bitWidth - 1 - value.leadingZeroBitCount
    let extraBits = exponent - 2
    let top = (value >> extraBits) & 3
    return (16 + ((exponent - 4) << 2) + top, value & ((1 << extraBits) - 1), extraBits)
  }

  // MARK: Residuals

  /// Reusable sample planes for one group.
  private final class GroupBuffers {
    let planes: [UnsafeMutablePointer<Int16>]
    let residuals: UnsafeMutablePointer<UInt16>

    init(channelCount: Int) {
      let size = JXLEncoder.groupSide * JXLEncoder.groupSide
      planes = (0..<channelCount).map { _ in
        let pointer = UnsafeMutablePointer<Int16>.allocate(capacity: size)
        pointer.initialize(repeating: 0, count: size)
        return pointer
      }
      residuals = .allocate(capacity: size)
      residuals.initialize(repeating: 0, count: size)
    }

    deinit {
      for plane in planes { plane.deallocate() }
      residuals.deallocate()
    }
  }

  /// Copies one group into the planes, applying the colour transform when asked.
  private static func load(
    group: Int, frame: Frame, yCoCg: Bool, into buffers: GroupBuffers
  ) -> (width: Int, height: Int) {
    let x0 = (group % frame.groupsAcross) * groupSide
    let y0 = (group / frame.groupsAcross) * groupSide
    let groupWidth = min(groupSide, frame.width - x0)
    let groupHeight = min(groupSide, frame.height - y0)
    let hasAlpha = frame.hasAlpha
    frame.rgba.withUnsafeBufferPointer { source in
      let first = buffers.planes[0]
      let second = buffers.planes[1]
      let third = buffers.planes[2]
      for y in 0..<groupHeight {
        var read = ((y0 + y) * frame.width + x0) * 4
        var write = y * groupWidth
        for _ in 0..<groupWidth {
          let red = Int(source[read])
          let green = Int(source[read + 1])
          let blue = Int(source[read + 2])
          if yCoCg {
            // YCoCg-R: exactly reversible with integer arithmetic.
            let chromaOrange = red - blue
            let temp = blue + (chromaOrange >> 1)
            let chromaGreen = green - temp
            first[write] = Int16(temp + (chromaGreen >> 1))
            second[write] = Int16(chromaOrange)
            third[write] = Int16(chromaGreen)
          } else {
            first[write] = Int16(red)
            second[write] = Int16(green)
            third[write] = Int16(blue)
          }
          if hasAlpha { buffers.planes[3][write] = Int16(source[read + 3]) }
          read += 4
          write += 1
        }
      }
    }
    return (groupWidth, groupHeight)
  }

  /// Packed Gradient-predictor residuals of one plane, row by row.
  ///
  /// West is the left sample, or the one above on the first column, or 0 at the corner. North is
  /// the sample above, or West on the first row. North-west is the diagonal one, or West.
  private static func residuals(
    of plane: UnsafeMutablePointer<Int16>, width: Int, height: Int,
    into output: UnsafeMutablePointer<UInt16>
  ) {
    for y in 0..<height {
      let row = y * width
      let above = row - width
      for x in 0..<width {
        let west: Int
        if x > 0 {
          west = Int(plane[row + x - 1])
        } else {
          west = y > 0 ? Int(plane[above]) : 0
        }
        let north = y > 0 ? Int(plane[above + x]) : west
        let northWest = (x > 0 && y > 0) ? Int(plane[above + x - 1]) : west
        let low = min(west, north)
        let high = max(west, north)
        let predicted = min(max(west + north - northWest, low), high)
        let difference = Int(plane[row + x]) - predicted
        output[row + x] = UInt16(difference >= 0 ? difference << 1 : (-difference << 1) - 1)
      }
    }
  }

  /// Token counts per channel over `groups`.
  private static func histogram(frame: Frame, groups: [Int], yCoCg: Bool) throws -> [[Int]] {
    let channels = frame.channelCount
    var counts = [[Int]](repeating: [Int](repeating: 0, count: tokenCapacity), count: channels)
    let buffers = GroupBuffers(channelCount: channels)
    for group in groups {
      try Task.checkCancellation()
      let size = load(group: group, frame: frame, yCoCg: yCoCg, into: buffers)
      for channel in 0..<channels {
        residuals(
          of: buffers.planes[channel], width: size.width, height: size.height,
          into: buffers.residuals)
        counts[channel].withUnsafeMutableBufferPointer { histogram in
          for index in 0..<(size.width * size.height) {
            histogram[split(Int(buffers.residuals[index])).token] += 1
          }
        }
      }
    }
    return counts
  }

  // MARK: MA tree

  /// The tree in the order the decoder reads it: breadth first, left child before right. A node
  /// splits on the channel index (property 0); a sample goes left when its channel is above the
  /// split value. The right child of a split holds exactly one channel, so the tree is a chain.
  private static func makeTree(channelCount: Int) -> (nodes: [TreeNode], leafOfChannel: [Int]) {
    var nodes: [TreeNode] = []
    var leafOfChannel = [Int](repeating: 0, count: channelCount)
    var queue = [(low: Int, high: Int)]([(0, channelCount - 1)])
    var head = 0
    var leaves = 0
    while head < queue.count {
      let (low, high) = queue[head]
      head += 1
      if low == high {
        nodes.append(.leaf)
        leafOfChannel[low] = leaves
        leaves += 1
      } else {
        nodes.append(.split(channel: low))
        queue.append((low + 1, high))  // channel > low
        queue.append((low, low))  // channel <= low
      }
    }
    return (nodes, leafOfChannel)
  }

  // MARK: Headers

  /// A size field: the value minus one, in one of four widths.
  private static func writeDimension(_ value: Int, to writer: inout JXLBitWriter) {
    let stored = value - 1
    if stored < 1 << 9 {
      writer.write(0, bits: 2)
      writer.write(stored, bits: 9)
    } else if stored < 1 << 13 {
      writer.write(1, bits: 2)
      writer.write(stored, bits: 13)
    } else if stored < 1 << 18 {
      writer.write(2, bits: 2)
      writer.write(stored, bits: 18)
    } else {
      writer.write(3, bits: 2)
      writer.write(stored, bits: 30)
    }
  }

  /// Signature, size header and image metadata, then padding to a byte.
  private static func writeFileHeader(frame: Frame, to writer: inout JXLBitWriter) {
    writer.write(0xFF, bits: 8)
    writer.write(0x0A, bits: 8)

    // SizeHeader: not the "small" form, explicit height and width.
    writer.write(0, bits: 1)
    writeDimension(frame.height, to: &writer)
    writer.write(0, bits: 3)  // ratio 0: the width follows
    writeDimension(frame.width, to: &writer)

    // ImageMetadata.
    writer.write(0, bits: 1)  // all_default is false: the picture is not XYB
    writer.write(0, bits: 1)  // extra_fields
    writer.write(0, bits: 1)  // integer samples
    writer.write(0, bits: 2)  // 8 bits per sample
    writer.write(1, bits: 1)  // modular_16_bit_buffer_sufficient
    if frame.hasAlpha {
      writer.write(1, bits: 2)  // one extra channel
      writer.write(1, bits: 1)  // it is alpha: 8-bit, straight, all defaults
    } else {
      writer.write(0, bits: 2)
    }
    writer.write(0, bits: 1)  // xyb_encoded
    writer.write(1, bits: 1)  // colour encoding: sRGB, all default
    writer.write(0, bits: 2)  // no extensions
    writer.write(1, bits: 1)  // CustomTransformData: all default
    writer.padToByte()
  }

  /// A single regular Modular frame covering the whole picture.
  private static func writeFrameHeader(frame: Frame, to writer: inout JXLBitWriter) {
    writer.write(0, bits: 1)  // all_default
    writer.write(0, bits: 2)  // regular frame
    writer.write(1, bits: 1)  // Modular
    writer.write(0, bits: 2)  // no flags
    writer.write(0, bits: 1)  // no YCbCr
    writer.write(0, bits: 2)  // upsampling 1
    if frame.hasAlpha { writer.write(0, bits: 2) }  // alpha upsampling 1
    writer.write(1, bits: 2)  // group_size_shift 1: 256 x 256 groups
    writer.write(0, bits: 2)  // one pass
    writer.write(0, bits: 1)  // no crop
    writer.write(0, bits: 2)  // blend mode: replace
    if frame.hasAlpha { writer.write(0, bits: 2) }  // alpha blend mode: replace
    writer.write(1, bits: 1)  // is_last
    writer.write(0, bits: 2)  // empty name
    writer.write(0, bits: 1)  // loop filter not all default
    writer.write(0, bits: 1)  // no Gabor-like filter
    writer.write(0, bits: 2)  // no edge-preserving filter
    writer.write(0, bits: 2)  // no loop filter extensions
    writer.write(0, bits: 2)  // no frame header extensions
  }

  /// The table of contents: no permutation, then one size per section.
  private static func writeTableOfContents(sizes: [Int], to writer: inout JXLBitWriter) {
    writer.write(0, bits: 1)
    writer.padToByte()
    for size in sizes {
      if size < 1 << 10 {
        writer.write(0, bits: 2)
        writer.write(size, bits: 10)
      } else if size < 17_408 {
        writer.write(1, bits: 2)
        writer.write(size - 1024, bits: 14)
      } else if size < 4_211_712 {
        writer.write(2, bits: 2)
        writer.write(size - 17_408, bits: 22)
      } else {
        writer.write(3, bits: 2)
        writer.write(size - 4_211_712, bits: 30)
      }
    }
    writer.padToByte()
  }

  // MARK: Global section

  /// A symbol of the tree stream: the hybrid split with exponent 0 makes token n + 1 carry the n
  /// bits below the leading one of a value, and 0 stand for 0.
  private static func writeTreeValue(
    _ value: Int, code: JXLPrefixCode, to writer: inout JXLBitWriter
  ) {
    if value == 0 {
      code.write(0, to: &writer)
      return
    }
    let exponent = JXLPrefixCode.bitLength(value) - 1
    code.write(exponent + 1, to: &writer)
    writer.write(value - (1 << exponent), bits: exponent)
  }

  private static func writeGlobalSection(
    plan: Plan, frame: Frame, to writer: inout JXLBitWriter
  ) {
    writer.write(1, bits: 1)  // LF channel dequantisation: all default
    writer.write(1, bits: 1)  // the frame has a global MA tree

    // Entropy code of the tree: six contexts, one prefix code with the symbols 0...3.
    let treeCode = JXLPrefixCode(frequencies: [1, 1, 1, 1], alphabetSize: 4)
    writer.write(0, bits: 1)  // no LZ77
    writer.write(1, bits: 1)  // simple context map
    writer.write(0, bits: 2)  // zero bits per entry: all six contexts share a histogram
    writer.write(1, bits: 1)  // prefix codes
    writer.write(0, bits: 4)  // hybrid integer: split exponent 0 (no mantissa fields follow)
    JXLPrefixCode.writeAlphabetSize(4, to: &writer)
    treeCode.writeHeader(to: &writer)

    // The tree itself.
    for node in plan.tree {
      switch node {
      case .split(let channel):
        writeTreeValue(1, code: treeCode, to: &writer)  // property 0 (channel), stored as 0 + 1
        writeTreeValue(channel << 1, code: treeCode, to: &writer)  // split value, zig-zag packed
      case .leaf:
        writeTreeValue(0, code: treeCode, to: &writer)  // property -1: a leaf
        writeTreeValue(gradientPredictor, code: treeCode, to: &writer)
        writeTreeValue(0, code: treeCode, to: &writer)  // offset 0
        writeTreeValue(0, code: treeCode, to: &writer)  // multiplier 1: log2 part
        writeTreeValue(0, code: treeCode, to: &writer)  // multiplier 1: mantissa part
      }
    }

    // Entropy code of the samples: one context per tree leaf.
    writer.write(0, bits: 1)  // no LZ77
    let leafCount = plan.leafOfChannel.count
    var clusterOfLeaf = [Int](repeating: 0, count: leafCount)
    for channel in 0..<leafCount {
      clusterOfLeaf[plan.leafOfChannel[channel]] = plan.clusterOfChannel[channel]
    }
    writer.write(1, bits: 1)  // simple context map
    let entryBits = JXLPrefixCode.bitLength(plan.clusterCount - 1)
    writer.write(entryBits, bits: 2)
    for cluster in clusterOfLeaf { writer.write(cluster, bits: entryBits) }
    writer.write(1, bits: 1)  // prefix codes
    for _ in 0..<plan.clusterCount {
      writer.write(4, bits: 4)  // split exponent 4
      writer.write(2, bits: 3)  // 2 mantissa bits in the token
      writer.write(0, bits: 2)  // none from the low end
    }
    for code in plan.codes { JXLPrefixCode.writeAlphabetSize(code.alphabetSize, to: &writer) }
    for code in plan.codes { code.writeHeader(to: &writer) }

    // Header of the global Modular stream.
    writer.write(1, bits: 1)  // use the global tree
    writer.write(1, bits: 1)  // default weighted predictor parameters
    if plan.yCoCg {
      writer.write(1, bits: 2)  // one transform
      writer.write(0, bits: 2)  // reversible colour transform
      writer.write(0, bits: 5)  // first channel 0
      writer.write(0, bits: 2)  // type 6, YCoCg
    } else {
      writer.write(0, bits: 2)  // no transforms
    }
  }

  // MARK: Groups

  private static func writeGroup(
    _ group: Int, plan: Plan, frame: Frame, includeHeader: Bool, to writer: inout JXLBitWriter
  ) throws {
    try Task.checkCancellation()
    if includeHeader {
      writer.write(1, bits: 1)  // use the global tree
      writer.write(1, bits: 1)  // default weighted predictor parameters
      writer.write(0, bits: 2)  // no transforms
    }
    let channels = frame.channelCount
    let buffers = GroupBuffers(channelCount: channels)
    let size = load(group: group, frame: frame, yCoCg: plan.yCoCg, into: buffers)
    let count = size.width * size.height
    for channel in 0..<channels {
      residuals(
        of: buffers.planes[channel], width: size.width, height: size.height,
        into: buffers.residuals)
      let code = plan.codes[plan.clusterOfChannel[channel]]
      code.lengths.withUnsafeBufferPointer { lengths in
        code.codes.withUnsafeBufferPointer { codes in
          for index in 0..<count {
            let part = split(Int(buffers.residuals[index]))
            let length = lengths[part.token]
            // Token code and extra bits go out together: at most 15 + 7 bits.
            writer.write(
              codes[part.token] | (part.extra << length), bits: length + part.extraBits)
          }
        }
      }
    }
  }
}
