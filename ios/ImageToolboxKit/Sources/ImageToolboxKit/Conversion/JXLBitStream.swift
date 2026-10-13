import Foundation

/// Packs bits least-significant first, the order of the JPEG XL codestream (ISO/IEC 18181-1).
struct JXLBitWriter {
  private(set) var bytes: [UInt8] = []
  private var pending: UInt64 = 0
  private var pendingCount = 0

  /// Number of bits written so far.
  var bitCount: Int { bytes.count * 8 + pendingCount }

  var isByteAligned: Bool { pendingCount == 0 }

  /// Appends the low `count` bits of `value`. `count` is in 0...32.
  mutating func write(_ value: Int, bits count: Int) {
    precondition(count >= 0 && count <= 32, "a field is at most 32 bits")
    guard count > 0 else { return }
    let mask: UInt64 = (1 << UInt64(count)) - 1
    pending |= (UInt64(truncatingIfNeeded: value) & mask) << UInt64(pendingCount)
    pendingCount += count
    while pendingCount >= 8 {
      bytes.append(UInt8(truncatingIfNeeded: pending))
      pending >>= 8
      pendingCount -= 8
    }
  }

  /// Fills the rest of the current byte with zero bits.
  mutating func padToByte() {
    guard pendingCount > 0 else { return }
    bytes.append(UInt8(truncatingIfNeeded: pending))
    pending = 0
    pendingCount = 0
  }

  /// Appends whole bytes. The writer must be on a byte boundary.
  mutating func append(_ other: [UInt8]) {
    precondition(isByteAligned, "bytes can only be appended on a byte boundary")
    bytes.append(contentsOf: other)
  }
}

/// A canonical prefix code over a small alphabet, with the JPEG XL header that describes it.
///
/// The header is the Brotli style used by JPEG XL: either a "simple" code for at most four used
/// symbols, or a "complex" code whose symbol lengths are themselves prefix coded. Codes are
/// canonical and are written most-significant bit first, so `codes` holds them bit-reversed for a
/// least-significant-first writer.
struct JXLPrefixCode {
  /// JPEG XL limits a code to 15 bits.
  static let maxLength = 15

  let alphabetSize: Int
  /// Code length per symbol. A symbol that is alone in its code has length 0 and takes no bits.
  private(set) var lengths: [Int]
  /// Bit-reversed canonical code per symbol, ready for `JXLBitWriter.write`.
  private(set) var codes: [Int]
  /// For a simple code, the symbols in the order the header lists them.
  private let simpleSymbols: [Int]?
  private let simpleUsesSkewedTree: Bool

  /// Whether the header is the complex form (five or more used symbols).
  var isComplex: Bool { simpleSymbols == nil }

  /// Builds the code for the symbol counts in `frequencies`. Symbols at or above `alphabetSize`
  /// must have a count of zero.
  init(frequencies: [Int], alphabetSize: Int) {
    precondition(alphabetSize >= 1 && frequencies.count >= alphabetSize)
    self.alphabetSize = alphabetSize
    var used = (0..<alphabetSize).filter { frequencies[$0] > 0 }
    var lengths = [Int](repeating: 0, count: alphabetSize)

    if used.count <= 4 {
      used.sort { frequencies[$0] != frequencies[$1] ? frequencies[$0] > frequencies[$1] : $0 < $1 }
      if used.isEmpty { used = [0] }
      let counts = used.map { frequencies[$0] }
      let (assigned, skewed) = Self.simpleLengths(counts: counts)
      for (index, symbol) in used.enumerated() { lengths[symbol] = assigned[index] }
      simpleSymbols = used
      simpleUsesSkewedTree = skewed
    } else {
      lengths = Self.huffmanLengths(
        frequencies: Array(frequencies[0..<alphabetSize]), maxLength: Self.maxLength)
      simpleSymbols = nil
      simpleUsesSkewedTree = false
    }
    self.lengths = lengths
    self.codes = Self.canonicalCodes(lengths: lengths)
  }

  /// Writes the code for `symbol`.
  @inline(__always)
  func write(_ symbol: Int, to writer: inout JXLBitWriter) {
    writer.write(codes[symbol], bits: lengths[symbol])
  }

  /// Writes the prefix-code header. The alphabet size is written by the caller.
  func writeHeader(to writer: inout JXLBitWriter) {
    // An alphabet of one symbol needs no code: the decoder reads nothing for it.
    if alphabetSize == 1 { return }
    if let symbols = simpleSymbols {
      writer.write(1, bits: 2)  // HSKIP == 1 marks a simple code
      writer.write(symbols.count - 1, bits: 2)
      let symbolBits = Self.bitLength(alphabetSize - 1)
      for symbol in symbols { writer.write(symbol, bits: symbolBits) }
      if symbols.count == 4 { writer.write(simpleUsesSkewedTree ? 1 : 0, bits: 1) }
    } else {
      writeComplexHeader(to: &writer)
    }
  }

  /// Size of the header in bits.
  func headerBitCount() -> Int {
    var scratch = JXLBitWriter()
    writeHeader(to: &scratch)
    return scratch.bitCount
  }

  /// Bits this code spends on `frequencies`, not counting extra bits.
  func dataBitCount(frequencies: [Int]) -> Int {
    var total = 0
    for symbol in 0..<min(alphabetSize, frequencies.count) {
      total += frequencies[symbol] * lengths[symbol]
    }
    return total
  }

  // MARK: Writing the alphabet size

  /// Writes the alphabet size of one histogram: one flag bit, then 4 + n bits for sizes above 1.
  static func writeAlphabetSize(_ size: Int, to writer: inout JXLBitWriter) {
    precondition(size >= 1)
    if size == 1 {
      writer.write(0, bits: 1)
      return
    }
    let exponent = bitLength(size - 1) - 1
    writer.write(1, bits: 1)
    writer.write(exponent, bits: 4)
    writer.write(size - 1 - (1 << exponent), bits: exponent)
  }

  // MARK: Simple codes

  /// Lengths for up to four symbols sorted by falling count, and whether the skewed
  /// 1-2-3-3 tree is used for four of them.
  private static func simpleLengths(counts: [Int]) -> (lengths: [Int], skewed: Bool) {
    switch counts.count {
    case 1: return ([0], false)
    case 2: return ([1, 1], false)
    case 3: return ([1, 2, 2], false)
    default:
      let balanced = 2 * counts.reduce(0, +)
      let skewed = counts[0] + 2 * counts[1] + 3 * (counts[2] + counts[3])
      return skewed < balanced ? ([1, 2, 3, 3], true) : ([2, 2, 2, 2], false)
    }
  }

  // MARK: Complex codes

  /// Order in which the code length code lengths are listed (the Brotli order).
  private static let codeLengthOrder = [
    1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  ]

  /// How a code length code length from 0 to 5 is written: value and bit count.
  private static let codeLengthLengthBits: [(value: Int, bits: Int)] = [
    (0b00, 2), (0b0111, 4), (0b011, 3), (0b10, 2), (0b01, 2), (0b1111, 4),
  ]

  private func writeComplexHeader(to writer: inout JXLBitWriter) {
    // The decoder stops reading lengths once the code is complete, so the zeros after the last
    // used symbol are not written.
    let last = lengths.lastIndex { $0 > 0 } ?? 0
    var items: [(symbol: Int, extra: Int)] = []
    var index = 0
    while index <= last {
      if lengths[index] != 0 {
        items.append((lengths[index], 0))
        index += 1
        continue
      }
      var run = 0
      while index + run <= last && lengths[index + run] == 0 { run += 1 }
      index += run
      while run > 0 {
        if run < 3 {
          for _ in 0..<run { items.append((0, 0)) }
          run = 0
        } else {
          // Two repeat codes in a row would be read as one longer run, so a literal zero follows
          // each repeat that is not the last piece.
          let piece = min(run, 10)
          items.append((17, piece - 3))
          run -= piece
          if run > 0 {
            items.append((0, 0))
            run -= 1
          }
        }
      }
    }

    var counts = [Int](repeating: 0, count: 18)
    for item in items { counts[item.symbol] += 1 }
    if counts.filter({ $0 > 0 }).count < 2 {
      // A code of one symbol would be incomplete. A second symbol costs nothing to declare.
      counts[counts[0] == 0 ? 0 : 1] += 1
    }
    let codeLengths = Self.huffmanLengths(frequencies: counts, maxLength: 5)
    let codeLengthCodes = Self.canonicalCodes(lengths: codeLengths)

    writer.write(0, bits: 2)  // HSKIP == 0: no code length code length is skipped
    let lastListed = Self.codeLengthOrder.lastIndex { codeLengths[$0] > 0 } ?? 0
    for position in 0...lastListed {
      let entry = Self.codeLengthLengthBits[codeLengths[Self.codeLengthOrder[position]]]
      writer.write(entry.value, bits: entry.bits)
    }
    for item in items {
      writer.write(codeLengthCodes[item.symbol], bits: codeLengths[item.symbol])
      if item.symbol == 17 { writer.write(item.extra, bits: 3) }
    }
  }

  // MARK: Code construction

  /// Length-limited Huffman code lengths. Counts below a rising floor are raised until the
  /// longest code fits `maxLength`. Unused symbols get length 0.
  static func huffmanLengths(frequencies: [Int], maxLength: Int) -> [Int] {
    var result = [Int](repeating: 0, count: frequencies.count)
    let used = frequencies.indices.filter { frequencies[$0] > 0 }
    if used.count == 1 {
      result[used[0]] = 1
      return result
    }
    guard used.count > 1 else { return result }
    var floorCount = 1
    while true {
      let depths = treeDepths(weights: used.map { max(frequencies[$0], floorCount) })
      if depths.max() ?? 0 <= maxLength {
        for (position, symbol) in used.enumerated() { result[symbol] = depths[position] }
        return result
      }
      floorCount *= 2
    }
  }

  /// Depth of each leaf in a Huffman tree built from `weights` (at least two).
  private static func treeDepths(weights: [Int]) -> [Int] {
    let leafCount = weights.count
    let order = weights.indices.sorted {
      weights[$0] != weights[$1] ? weights[$0] < weights[$1] : $0 < $1
    }
    let nodeCount = 2 * leafCount - 1
    var weight = [Int](repeating: 0, count: nodeCount)
    var parent = [Int](repeating: -1, count: nodeCount)
    for (position, leaf) in order.enumerated() { weight[position] = weights[leaf] }

    var nextLeaf = 0
    var nextInternal = leafCount
    var created = leafCount
    // Takes the lighter of the next unused leaf and the next unused merged node.
    func takeLightest() -> Int {
      if nextLeaf < leafCount
        && (nextInternal >= created || weight[nextLeaf] <= weight[nextInternal])
      {
        nextLeaf += 1
        return nextLeaf - 1
      }
      nextInternal += 1
      return nextInternal - 1
    }
    while created < nodeCount {
      let first = takeLightest()
      let second = takeLightest()
      weight[created] = weight[first] + weight[second]
      parent[first] = created
      parent[second] = created
      created += 1
    }

    var depth = [Int](repeating: 0, count: nodeCount)
    for node in stride(from: nodeCount - 2, through: 0, by: -1) {
      depth[node] = depth[parent[node]] + 1
    }
    var result = [Int](repeating: 0, count: leafCount)
    for (position, leaf) in order.enumerated() { result[leaf] = depth[position] }
    return result
  }

  /// Canonical codes for `lengths`, bit-reversed. Symbols of equal length are ordered by value.
  static func canonicalCodes(lengths: [Int]) -> [Int] {
    var countPerLength = [Int](repeating: 0, count: maxLength + 2)
    for length in lengths where length > 0 { countPerLength[length] += 1 }
    var nextCode = [Int](repeating: 0, count: maxLength + 2)
    var code = 0
    for length in 1...maxLength {
      code = (code + countPerLength[length - 1]) << 1
      nextCode[length] = code
    }
    var codes = [Int](repeating: 0, count: lengths.count)
    for (symbol, length) in lengths.enumerated() where length > 0 {
      codes[symbol] = reversed(nextCode[length], bits: length)
      nextCode[length] += 1
    }
    return codes
  }

  private static func reversed(_ value: Int, bits: Int) -> Int {
    var result = 0
    var source = value
    for _ in 0..<bits {
      result = (result << 1) | (source & 1)
      source >>= 1
    }
    return result
  }

  /// Number of bits needed to write `value`; zero needs none.
  static func bitLength(_ value: Int) -> Int {
    value <= 0 ? 0 : Int.bitWidth - value.leadingZeroBitCount
  }
}
