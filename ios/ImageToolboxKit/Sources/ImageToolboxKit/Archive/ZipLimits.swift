import Foundation

/// What a zip archive may hold when it is read. The Android app's archive library (`lib/archive`,
/// `ExtractionLimits`) allows 100,000 entries, 64 GiB for one entry and 128 GiB for all entries.
public struct ZipLimits: Equatable, Sendable {
  /// The most entries (directories included) the archive may list. More than that is an error.
  public var maximumEntries: Int
  /// The largest uncompressed size of one entry that is read.
  public var maximumEntrySize: UInt64
  /// The largest sum of the uncompressed sizes of all the entries that are read.
  public var maximumTotalSize: UInt64

  public init(maximumEntries: Int, maximumEntrySize: UInt64, maximumTotalSize: UInt64) {
    self.maximumEntries = maximumEntries
    self.maximumEntrySize = maximumEntrySize
    self.maximumTotalSize = maximumTotalSize
  }

  /// The limits of the Android app. The reader here works in memory and refuses an entry of 2 GiB
  /// or more whatever the limit says, so the 64 GiB and 128 GiB bounds only matter on paper.
  public static let android = ZipLimits(
    maximumEntries: 100_000,
    maximumEntrySize: 64 << 30,
    maximumTotalSize: 128 << 30)
}

/// The rules the Android app applies to the name of an archive entry (`ArchivePath.safeSegments`):
/// backslashes count as separators, empty and blank segments are dropped, absolute paths, drive
/// letters, `.` and `..` segments, NUL characters and over-long paths are refused, and a segment
/// is cut to 240 characters.
public enum ZipEntryPath {

  /// The longest accepted path, in UTF-16 units, as Kotlin counts them.
  public static let maximumLength = 4096
  public static let maximumSegments = 256
  public static let maximumSegmentLength = 240

  /// The path split into safe segments, or nil when the path is not safe to use as a file name.
  public static func safeSegments(_ path: String) -> [String]? {
    var path = path
    return path.withUTF8 { segments(in: $0) }
  }

  /// The segments joined with "/", or nil when the path is not safe.
  public static func safeName(_ path: String) -> String? {
    safeSegments(path)?.joined(separator: "/")
  }

  // MARK: - Scanning

  private enum Segment {
    case skip
    case reject
    case keep(String)
  }

  /// The scan works on the UTF-8 bytes. UTF-16 lengths, which are what the Android limits count,
  /// follow from the lead bytes: one unit for every character, two for those above U+FFFF.
  private static func segments(in bytes: UnsafeBufferPointer<UInt8>) -> [String]? {
    var length = 0
    for byte in bytes {
      if byte == 0 { return nil }
      if byte & 0xC0 != 0x80 { length += byte >= 0xF0 ? 2 : 1 }
    }
    guard length <= maximumLength, !bytes.isEmpty, !isSeparator(bytes[0]) else { return nil }
    if bytes.count >= 3, bytes[1] == 0x3A, isSeparator(bytes[2]), isLetter(bytes[0]) {
      return nil
    }

    var segments: [String] = []
    var start = 0
    var index = 0
    while index <= bytes.count {
      if index == bytes.count || isSeparator(bytes[index]) {
        switch segment(in: bytes, from: start, to: index) {
        case .skip:
          break
        case .reject:
          return nil
        case .keep(let text):
          segments.append(text)
          if segments.count > maximumSegments { return nil }
        }
        start = index + 1
      }
      index += 1
    }
    return segments.isEmpty ? nil : segments
  }

  private static func segment(
    in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int
  ) -> Segment {
    guard end > start else { return .skip }
    var blank = true
    var hasNonASCII = false
    var units = 0
    var cut = end
    var cutDecided = false
    var index = start
    while index < end {
      let byte = bytes[index]
      if byte >= 0x80 {
        hasNonASCII = true
        blank = false
      } else if !isASCIIWhitespace(byte) {
        blank = false
      }
      if byte & 0xC0 != 0x80 {
        let width = byte >= 0xF0 ? 2 : 1
        // A character that would pass the limit is dropped whole, so no pair is cut in two.
        if !cutDecided && units + width > maximumSegmentLength {
          cut = index
          cutDecided = true
        }
        units += width
      }
      index += 1
    }
    if blank { return .skip }

    if hasNonASCII {
      let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
      if text.allSatisfy(\.isWhitespace) { return .skip }
    } else if bytes[start] == 0x2E,
      end - start == 1 || (end - start == 2 && bytes[start + 1] == 0x2E)
    {
      return .reject  // "." and ".."
    }
    return .keep(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<cut]), as: UTF8.self))
  }

  private static func isSeparator(_ byte: UInt8) -> Bool {
    byte == 0x2F || byte == 0x5C
  }

  private static func isLetter(_ byte: UInt8) -> Bool {
    (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
  }

  /// Space, the controls from tab to carriage return, and the separators 0x1C to 0x1F, which is
  /// what Java counts as white space in the ASCII range.
  private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) || (byte >= 0x1C && byte <= 0x1F)
  }
}
