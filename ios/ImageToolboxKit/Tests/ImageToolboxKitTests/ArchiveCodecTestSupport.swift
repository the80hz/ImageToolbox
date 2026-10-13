import Foundation

@testable import ImageToolboxKit

/// Sample data and system tools for the xz, lzma, bzip2, zstd and 7z tests.
enum ArchiveTestData {

  /// A small deterministic generator, so the samples are the same on every run.
  struct Generator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state >> 33
    }
  }

  private static let words = [
    "the", "image", "toolbox", "archive", "of", "pixels", "and", "colour", "a", "to", "in",
    "compression", "block", "stream", "dictionary", "literal", "match", "entropy", "table",
    "symbol", "window", "frame", "header", "checksum", "zebra", "quartz", "jumps", "over",
  ]

  /// Lines `ImageToolbox archive test line N`, the text of the embedded vectors.
  static func lines(_ count: Int) -> Data {
    Data((0..<count).map { "ImageToolbox archive test line \($0)\n" }.joined().utf8)
  }

  /// Word salad with natural repetition.
  static func text(_ size: Int, seed: UInt64 = 1) -> Data {
    var generator = Generator(state: seed)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(size + 16)
    while bytes.count < size {
      let word = words[Int(generator.next() % UInt64(words.count))]
      bytes += Array(word.utf8)
      bytes.append(generator.next() % 17 == 0 ? 10 : 32)
    }
    return Data(bytes.prefix(size))
  }

  /// Bytes that do not compress.
  static func random(_ size: Int, seed: UInt64 = 7) -> Data {
    var generator = Generator(state: seed)
    return Data((0..<size).map { _ in UInt8(truncatingIfNeeded: generator.next() >> 3) })
  }

  /// Long runs of a few values, with some noise.
  static func runs(_ size: Int, seed: UInt64 = 3) -> Data {
    var generator = Generator(state: seed)
    var bytes: [UInt8] = []
    while bytes.count < size {
      let value = UInt8(truncatingIfNeeded: generator.next())
      let length = Int(generator.next() % 600) + 1
      bytes += [UInt8](repeating: value, count: length)
      if generator.next() % 5 == 0 { bytes.append(UInt8(truncatingIfNeeded: generator.next())) }
    }
    return Data(bytes.prefix(size))
  }

  /// A mix of text, runs and random blocks, like a real file with embedded images.
  static func mixed(_ size: Int, seed: UInt64 = 11) -> Data {
    var generator = Generator(state: seed)
    var result = Data()
    while result.count < size {
      let part = min(size - result.count, Int(generator.next() % 20_000) + 500)
      switch generator.next() % 3 {
      case 0: result += text(part, seed: generator.next())
      case 1: result += runs(part, seed: generator.next())
      default: result += random(part, seed: generator.next())
      }
    }
    return result
  }

  /// Every kind of sample at a few sizes.
  static func samples() -> [(name: String, data: Data)] {
    [
      ("empty", Data()),
      ("one byte", Data([0x41])),
      ("lines", lines(60)),
      ("text 100k", text(100_000)),
      ("runs 70k", runs(70_000)),
      ("random 40k", random(40_000)),
      ("mixed 200k", mixed(200_000)),
    ]
  }
}

/// Runs the command line tools of this Mac. A test that needs a tool is skipped when it is missing.
enum SystemTool {

  static func path(_ name: String) -> String? {
    for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
      let candidate = directory + "/" + name
      if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }

  struct Result {
    let status: Int32
    let output: Data
    let errors: String
  }

  /// Runs `name` with `input` on its standard input and returns what it writes.
  static func run(
    _ name: String, _ arguments: [String], input: Data = Data(), in directory: URL? = nil
  ) throws -> Result {
    guard let executable = path(name) else { throw ToolMissing(name: name) }
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArchiveTool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let inputURL = scratch.appendingPathComponent("stdin")
    let errorURL = scratch.appendingPathComponent("stderr")
    try input.write(to: inputURL)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)

    let process = Process()
    let pipe = Pipe()
    process.currentDirectoryURL = directory
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = try FileHandle(forReadingFrom: inputURL)
    process.standardOutput = pipe
    process.standardError = try FileHandle(forWritingTo: errorURL)
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let errors = String(decoding: (try? Data(contentsOf: errorURL)) ?? Data(), as: UTF8.self)
    return Result(status: process.terminationStatus, output: output, errors: errors)
  }

  /// Runs `name` in a scratch directory that holds the given files, and returns it with the
  /// directory's path. The directory is removed when `body` returns.
  static func inDirectory<T>(
    files: [String: Data], _ body: (URL) throws -> T
  ) throws -> T {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArchiveDir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (name, data) in files {
      let url = directory.appendingPathComponent(name)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url)
    }
    return try body(directory)
  }

  struct ToolMissing: Error { let name: String }

  static func isAvailable(_ name: String) -> Bool { path(name) != nil }
}

/// Decodes a base64 vector that is wrapped over several lines.
func archiveVector(_ text: String) -> Data {
  Data(base64Encoded: text.filter { !$0.isWhitespace })!
}
