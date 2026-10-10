import Foundation

/// A most-significant-bit-first writer.
private struct BZip2BitWriter {
  private(set) var bytes: [UInt8] = []
  private var buffer: UInt64 = 0
  private var bitCount = 0

  mutating func write(_ value: Int, bits: Int) {
    buffer = buffer << UInt64(bits) | UInt64(value) & ((1 << UInt64(bits)) - 1)
    bitCount += bits
    while bitCount >= 8 {
      bitCount -= 8
      bytes.append(UInt8(truncatingIfNeeded: buffer >> UInt64(bitCount)))
    }
  }

  mutating func write(_ value: UInt32) {
    write(Int(value >> 16), bits: 16)
    write(Int(value & 0xFFFF), bits: 16)
  }

  /// Pads the last byte with zero bits.
  mutating func finish() -> [UInt8] {
    if bitCount > 0 { write(0, bits: 8 - bitCount) }
    return bytes
  }
}

/// Sorting of the cyclic rotations of a block, which is the Burrows-Wheeler transform.
enum BurrowsWheeler {

  /// The start index of every rotation of `block`, in sorted order. Equal rotations, which only
  /// occur for periodic blocks, come in any order.
  static func sortedRotations(_ block: UnsafeBufferPointer<UInt8>) -> [Int32] {
    let count = block.count
    guard count > 1 else { return count == 1 ? [0] : [] }

    var order = [Int32](repeating: 0, count: count)
    var rank = [Int32](repeating: 0, count: count)
    var scratch = [Int32](repeating: 0, count: count)
    var nextRank = [Int32](repeating: 0, count: count)

    // Sort by the first byte.
    var buckets = [Int](repeating: 0, count: 257)
    for byte in block { buckets[Int(byte) + 1] += 1 }
    for index in 0..<256 { buckets[index + 1] += buckets[index] }
    for index in 0..<count {
      let byte = Int(block[index])
      order[buckets[byte]] = Int32(index)
      buckets[byte] += 1
    }
    rank[Int(order[0])] = 0
    for index in 1..<count {
      let current = Int(order[index])
      let before = Int(order[index - 1])
      rank[current] = rank[before] + (block[current] != block[before] ? 1 : 0)
    }

    // Prefix doubling: sort by the pair (rank of the first k bytes, rank of the next k).
    var span = 1
    while span < count {
      let classes = Int(rank[Int(order[count - 1])]) + 1
      if classes == count { break }

      // Order by the second half first: the rotation that starts `span` before each sorted one.
      for index in 0..<count {
        var start = Int(order[index]) - span
        if start < 0 { start += count }
        scratch[index] = Int32(start)
      }
      // A stable counting sort on the first half then gives the pair order.
      var counts = [Int](repeating: 0, count: classes + 1)
      for index in 0..<count { counts[Int(rank[index]) + 1] += 1 }
      for index in 0..<classes { counts[index + 1] += counts[index] }
      for index in 0..<count {
        let start = Int(scratch[index])
        let bucket = Int(rank[start])
        order[counts[bucket]] = Int32(start)
        counts[bucket] += 1
      }

      nextRank[Int(order[0])] = 0
      for index in 1..<count {
        let current = Int(order[index])
        let before = Int(order[index - 1])
        var currentSecond = current + span
        if currentSecond >= count { currentSecond -= count }
        var beforeSecond = before + span
        if beforeSecond >= count { beforeSecond -= count }
        let same =
          rank[current] == rank[before] && rank[currentSecond] == rank[beforeSecond]
        nextRank[current] = nextRank[before] + (same ? 0 : 1)
      }
      swap(&rank, &nextRank)
      span *= 2
    }
    return order
  }
}

/// Huffman code lengths with a length limit.
enum LimitedHuffman {

  /// Code lengths for the given weights, none longer than `limit`. Every symbol gets a code.
  static func lengths(weights: [Int], limit: Int) -> [UInt8] {
    var adjusted = weights.map { max($0, 1) }
    while true {
      let depths = unrestrictedLengths(adjusted)
      if depths.max()! <= limit { return depths.map { UInt8($0) } }
      adjusted = adjusted.map { 1 + $0 / 2 }
    }
  }

  private static func unrestrictedLengths(_ weights: [Int]) -> [Int] {
    let count = weights.count
    guard count > 1 else { return [1] }
    // Nodes 0..<count are leaves, the rest are merged nodes.
    var weight = weights
    var parent = [Int](repeating: -1, count: count)
    var alive = Array(0..<count)
    alive.sort { weight[$0] != weight[$1] ? weight[$0] < weight[$1] : $0 < $1 }
    while alive.count > 1 {
      let first = alive.removeFirst()
      let second = alive.removeFirst()
      let node = weight.count
      weight.append(weight[first] + weight[second])
      parent.append(-1)
      parent[first] = node
      parent[second] = node
      var insertAt = 0
      while insertAt < alive.count, weight[alive[insertAt]] <= weight[node] { insertAt += 1 }
      alive.insert(node, at: insertAt)
    }
    return (0..<count).map { leaf in
      var depth = 0
      var node = leaf
      while parent[node] >= 0 {
        node = parent[node]
        depth += 1
      }
      return depth
    }
  }
}

extension BZip2Codec {

  private static let maximumCodeLength = 17
  private static let groupSize = 50

  /// A bzip2 file holding `data`. `level` is the block size in hundreds of kilobytes, 1 to 9.
  public static func compress(_ data: Data, level: Int = 9) throws -> Data {
    guard (1...9).contains(level) else { throw ArchiveCodecError.unsupported }
    var writer = BZip2BitWriter()
    for byte in [UInt8]("BZh".utf8) + [UInt8(0x30 + level)] { writer.write(Int(byte), bits: 8) }

    let content = [UInt8](data)
    let blockLimit = level * 100_000 - 19
    var combinedCRC: UInt32 = 0
    var position = 0
    while position < content.count {
      var block: [UInt8] = []
      block.reserveCapacity(min(content.count - position, blockLimit) + 8)
      let blockStart = position
      // Initial run-length coding: four to 255 equal bytes become four bytes and a count.
      while position < content.count && block.count < blockLimit {
        let byte = content[position]
        var run = 1
        while run < 255, position + run < content.count, content[position + run] == byte {
          run += 1
        }
        if run >= 4 {
          block += [byte, byte, byte, byte, UInt8(run - 4)]
        } else {
          block += [UInt8](repeating: byte, count: run)
        }
        position += run
      }
      let crc = content.withUnsafeBufferPointer {
        ArchiveChecksum.bzip2CRC(UnsafeBufferPointer(rebasing: $0[blockStart..<position]))
      }
      combinedCRC = (combinedCRC << 1 | combinedCRC >> 31) ^ crc
      writeBlock(block, crc: crc, to: &writer)
    }

    writer.write(Int(endMagic >> 24), bits: 24)
    writer.write(Int(endMagic & 0xFF_FFFF), bits: 24)
    writer.write(combinedCRC)
    return Data(writer.finish())
  }

  private static func writeBlock(_ block: [UInt8], crc: UInt32, to writer: inout BZip2BitWriter) {
    // Burrows-Wheeler transform.
    let rotations = block.withUnsafeBufferPointer { BurrowsWheeler.sortedRotations($0) }
    let count = block.count
    var originalPointer = 0
    var transformed = [UInt8](repeating: 0, count: count)
    for (index, start) in rotations.enumerated() {
      let start = Int(start)
      if start == 0 { originalPointer = index }
      transformed[index] = block[start == 0 ? count - 1 : start - 1]
    }

    // The bytes in use, as a two-level bitmap.
    var used = [Bool](repeating: false, count: 256)
    for byte in block { used[Int(byte)] = true }
    let usedBytes = (0..<256).filter { used[$0] }
    var symbolOf = [Int](repeating: 0, count: 256)
    for (index, byte) in usedBytes.enumerated() { symbolOf[byte] = index }
    let alphabetSize = usedBytes.count + 2
    let endOfBlock = alphabetSize - 1

    // Move-to-front coding with zero runs as RUNA and RUNB.
    var symbols: [UInt16] = []
    symbols.reserveCapacity(count + 1)
    var front = (0..<usedBytes.count).map { UInt8($0) }
    var zeros = 0
    func flushZeros() {
      // The run length in bijective base two: digit 1 is RUNA and digit 2 is RUNB.
      var pending = zeros - 1
      while true {
        symbols.append(pending & 1 == 1 ? 1 : 0)
        if pending < 2 { break }
        pending = (pending - 2) / 2
      }
      zeros = 0
    }
    for byte in transformed {
      let symbol = UInt8(symbolOf[Int(byte)])
      var index = 0
      while front[index] != symbol { index += 1 }
      if index == 0 {
        zeros += 1
      } else {
        if zeros > 0 { flushZeros() }
        var move = index
        while move > 0 {
          front[move] = front[move - 1]
          move -= 1
        }
        front[0] = symbol
        symbols.append(UInt16(index + 1))
      }
    }
    if zeros > 0 { flushZeros() }
    symbols.append(UInt16(endOfBlock))

    let (lengths, selectors) = chooseTables(symbols, alphabetSize: alphabetSize)

    // Header.
    writer.write(Int(blockMagic >> 24), bits: 24)
    writer.write(Int(blockMagic & 0xFF_FFFF), bits: 24)
    writer.write(crc)
    writer.write(0, bits: 1)
    writer.write(originalPointer, bits: 24)

    var groupsUsed = 0
    for group in 0..<16 where (0..<16).contains(where: { used[group * 16 + $0] }) {
      groupsUsed |= 0x8000 >> group
    }
    writer.write(groupsUsed, bits: 16)
    for group in 0..<16 where groupsUsed & (0x8000 >> group) != 0 {
      var mask = 0
      for bit in 0..<16 where used[group * 16 + bit] { mask |= 0x8000 >> bit }
      writer.write(mask, bits: 16)
    }

    writer.write(lengths.count, bits: 3)
    writer.write(selectors.count, bits: 15)
    var order = Array(0..<UInt8(lengths.count))
    for selector in selectors {
      let index = order.firstIndex(of: selector)!
      for _ in 0..<index { writer.write(1, bits: 1) }
      writer.write(0, bits: 1)
      order.remove(at: index)
      order.insert(selector, at: 0)
    }

    for table in lengths {
      var current = Int(table[0])
      writer.write(current, bits: 5)
      for length in table.map(Int.init) {
        while current < length {
          writer.write(0b10, bits: 2)
          current += 1
        }
        while current > length {
          writer.write(0b11, bits: 2)
          current -= 1
        }
        writer.write(0, bits: 1)
      }
    }

    // Codes of every table, assigned in canonical order.
    let codes = lengths.map { assignCodes($0) }
    for (index, symbol) in symbols.enumerated() {
      let table = Int(selectors[index / groupSize])
      writer.write(codes[table][Int(symbol)], bits: Int(lengths[table][Int(symbol)]))
    }
  }

  private static func assignCodes(_ lengths: [UInt8]) -> [Int] {
    var codes = [Int](repeating: 0, count: lengths.count)
    var code = 0
    for length in (lengths.min() ?? 1)...(lengths.max() ?? 1) {
      for (symbol, symbolLength) in lengths.enumerated() where Int(symbolLength) == length {
        codes[symbol] = code
        code += 1
      }
      code <<= 1
    }
    return codes
  }

  /// Chooses the number of Huffman tables, their code lengths and the table of each group of
  /// fifty symbols, by refining an initial split of the alphabet a few times.
  private static func chooseTables(_ symbols: [UInt16], alphabetSize: Int) -> (
    lengths: [[UInt8]], selectors: [UInt8]
  ) {
    let tableCount: Int
    switch symbols.count {
    case ..<200: tableCount = 2
    case ..<600: tableCount = 3
    case ..<1200: tableCount = 4
    case ..<2400: tableCount = 5
    default: tableCount = 6
    }

    var frequencies = [Int](repeating: 0, count: alphabetSize)
    for symbol in symbols { frequencies[Int(symbol)] += 1 }

    // Initial split: each table favours a range of symbols with about equal total frequency.
    var costs = [[Int]](repeating: [Int](repeating: 15, count: alphabetSize), count: tableCount)
    var remaining = symbols.count
    var start = 0
    var tablesLeft = tableCount
    while tablesLeft > 0 {
      let target = remaining / tablesLeft
      var end = start - 1
      var accumulated = 0
      while accumulated < target && end < alphabetSize - 1 {
        end += 1
        accumulated += frequencies[end]
      }
      if end > start && tablesLeft != tableCount && tablesLeft != 1
        && (tableCount - tablesLeft) % 2 == 1
      {
        accumulated -= frequencies[end]
        end -= 1
      }
      if start <= end {
        for symbol in start...end { costs[tablesLeft - 1][symbol] = 0 }
      }
      tablesLeft -= 1
      start = end + 1
      remaining -= accumulated
    }

    var selectors: [UInt8] = []
    for _ in 0..<4 {
      selectors.removeAll(keepingCapacity: true)
      var tableFrequencies = [[Int]](
        repeating: [Int](repeating: 0, count: alphabetSize), count: tableCount)
      var groupStart = 0
      while groupStart < symbols.count {
        let group = symbols[groupStart..<min(groupStart + groupSize, symbols.count)]
        var best = 0
        var bestCost = Int.max
        for table in 0..<tableCount {
          var cost = 0
          for symbol in group { cost += costs[table][Int(symbol)] }
          if cost < bestCost {
            bestCost = cost
            best = table
          }
        }
        selectors.append(UInt8(best))
        for symbol in group { tableFrequencies[best][Int(symbol)] += 1 }
        groupStart += groupSize
      }
      for table in 0..<tableCount {
        let lengths = LimitedHuffman.lengths(
          weights: tableFrequencies[table], limit: maximumCodeLength)
        costs[table] = lengths.map(Int.init)
      }
    }
    return (costs.map { $0.map { UInt8($0) } }, selectors)
  }
}
