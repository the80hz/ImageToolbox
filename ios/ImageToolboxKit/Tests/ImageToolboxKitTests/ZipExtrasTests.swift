import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Zip entry names and limits")
struct ZipNameAndLimitTests {

  // MARK: - Names (the cases of the Android ArchivePathTest, and more)

  @Test("a nested relative path is accepted, and Windows separators are normalised")
  func acceptsRelativePaths() {
    #expect(ZipEntryPath.safeSegments("pages/001.jpg") == ["pages", "001.jpg"])
    #expect(ZipEntryPath.safeSegments("pages\\001.jpg") == ["pages", "001.jpg"])
    #expect(ZipEntryPath.safeName("pages\\sub/001.jpg") == "pages/sub/001.jpg")
  }

  @Test("traversal, absolute paths and drive letters are refused")
  func rejectsUnsafePaths() {
    #expect(ZipEntryPath.safeSegments("../secret") == nil)
    #expect(ZipEntryPath.safeSegments("pages/../../secret") == nil)
    #expect(ZipEntryPath.safeSegments("pages/./a") == nil)
    #expect(ZipEntryPath.safeSegments("/etc/passwd") == nil)
    #expect(ZipEntryPath.safeSegments("\\share\\file") == nil)
    #expect(ZipEntryPath.safeSegments("C:/Windows/file") == nil)
    #expect(ZipEntryPath.safeSegments("c:\\Windows\\file") == nil)
    #expect(ZipEntryPath.safeSegments("a/..") == nil)
    // A name like "C:" without a slash, and dots inside a name, are fine.
    #expect(ZipEntryPath.safeSegments("C:file") == ["C:file"])
    #expect(ZipEntryPath.safeSegments("..a/b..") == ["..a", "b.."])
  }

  @Test("empty, blank and NUL names are refused, and blank segments are dropped")
  func blankSegments() {
    #expect(ZipEntryPath.safeSegments("") == nil)
    #expect(ZipEntryPath.safeSegments("   ") == nil)
    #expect(ZipEntryPath.safeSegments("/") == nil)
    #expect(ZipEntryPath.safeSegments("a\0b") == nil)
    #expect(ZipEntryPath.safeSegments("a//b") == ["a", "b"])
    #expect(ZipEntryPath.safeSegments("a/ /b/") == ["a", "b"])
    #expect(ZipEntryPath.safeSegments("a/\u{3000}/b") == ["a", "b"])
    #expect(ZipEntryPath.safeSegments(" a /b") == [" a ", "b"])
    // A combining mark after a slash does not hide the slash from the traversal check.
    #expect(ZipEntryPath.safeSegments("a/\u{301}/../b") == nil)
  }

  @Test("the length, segment count and segment length are bounded as on Android")
  func bounds() {
    #expect(ZipEntryPath.safeSegments(String(repeating: "a", count: 500))?.first?.count == 240)
    #expect(ZipEntryPath.safeSegments(String(repeating: "a", count: 4096)) != nil)
    #expect(ZipEntryPath.safeSegments(String(repeating: "a", count: 4097)) == nil)
    #expect(
      ZipEntryPath.safeSegments(Array(repeating: "a", count: 256).joined(separator: "/")) != nil)
    #expect(
      ZipEntryPath.safeSegments(Array(repeating: "a", count: 257).joined(separator: "/")) == nil)

    // The limits count UTF-16 units: a character above U+FFFF counts twice and is not cut in two.
    let wide = String(repeating: "\u{1F600}", count: 130)  // 260 units
    #expect(ZipEntryPath.safeSegments(wide)?.first == String(repeating: "\u{1F600}", count: 120))
    let odd = "a" + String(repeating: "\u{1F600}", count: 130)  // the 240th unit is inside a pair
    #expect(
      ZipEntryPath.safeSegments(odd)?.first == "a" + String(repeating: "\u{1F600}", count: 119))
    let tooLong = String(repeating: "\u{1F600}", count: 2049)  // 4098 units
    #expect(ZipEntryPath.safeSegments(tooLong) == nil)
  }

  @Test("an archive entry reports its safe name")
  func entrySafeName() throws {
    let archive = ZipReaderTests.storedArchive
    let entry = try #require(try ZipReader.entries(in: archive) { _ in true }.first)
    #expect(entry.safeName == "readme.txt")
    #expect(ZipReader.Entry(name: "../x", data: Data()).safeName == nil)
  }

  // MARK: - Writer names

  @Test("the writer refuses unsafe names and normalises the others")
  func writerNames() throws {
    #expect(throws: ZipWriter.Failure.unsafeName("../evil.txt")) {
      try ZipWriter.archive([ZipWriter.Entry(name: "../evil.txt", data: Data())])
    }
    #expect(throws: ZipWriter.Failure.unsafeName("")) {
      try ZipWriter.archive([ZipWriter.Entry(name: "", data: Data())])
    }
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "photos\\2026//a.png", data: Data("a".utf8)),
      ZipWriter.Entry(name: "photos/", data: Data()),
    ])
    let list = try ZipReader.list(in: archive)
    #expect(list.map(\.name) == ["photos/2026/a.png", "photos/"])
    #expect(list.map(\.isDirectory) == [false, true])
    #expect(try ZipTools.unzipAccepts(archive))
  }

  // MARK: - Reader limits

  private static func threeFiles() throws -> Data {
    try ZipWriter.archive([
      ZipWriter.Entry(name: "a.bin", data: ZipZip64Tests.noise(100, seed: 21)),
      ZipWriter.Entry(name: "dir/", data: Data()),
      ZipWriter.Entry(name: "b.bin", data: ZipZip64Tests.noise(100, seed: 22)),
      ZipWriter.Entry(name: "c.bin", data: ZipZip64Tests.noise(100, seed: 23)),
    ])
  }

  @Test("the Android limits are 100,000 entries, 64 GiB per entry and 128 GiB in all")
  func androidLimits() {
    #expect(ZipLimits.android.maximumEntries == 100_000)
    #expect(ZipLimits.android.maximumEntrySize == 64 * 1024 * 1024 * 1024)
    #expect(ZipLimits.android.maximumTotalSize == 128 * 1024 * 1024 * 1024)
  }

  @Test("the entry count counts directories, the total counts only the entries that are read")
  func limitsApply() throws {
    let archive = try Self.threeFiles()
    func limits(entries: Int = 10, entry: UInt64 = 1000, total: UInt64 = 1000) -> ZipLimits {
      ZipLimits(maximumEntries: entries, maximumEntrySize: entry, maximumTotalSize: total)
    }
    #expect(try ZipReader.entries(in: archive, limits: limits(entries: 4)) { _ in true }.count == 3)
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive, limits: limits(entries: 3)) { _ in true }
    }
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive, limits: limits(entry: 99)) { _ in true }
    }
    #expect(
      try ZipReader.entries(in: archive, limits: limits(entry: 100, total: 300)) { _ in true }.count
        == 3)
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive, limits: limits(total: 299)) { _ in true }
    }
    // Entries that are not read do not count towards the total.
    let two = try ZipReader.entries(in: archive, limits: limits(total: 200)) {
      $0 != "c.bin"
    }
    #expect(two.map(\.name) == ["a.bin", "b.bin"])
    // The listing limits only the count, as the Android listing does.
    #expect(
      try ZipReader.list(in: archive, limits: limits(entries: 4, entry: 1, total: 1)).count == 4)
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.list(in: archive, limits: limits(entries: 3))
    }
  }

  @Test("the older size arguments keep their meaning")
  func oldArguments() throws {
    let archive = try Self.threeFiles()
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive, maximumEntries: 3, maximumEntrySize: 1000) { _ in true }
    }
    #expect(throws: ZipReader.Failure.tooLarge) {
      try ZipReader.entries(in: archive, maximumEntries: 10, maximumEntrySize: 50) { _ in true }
    }
    let all = try ZipReader.entries(in: archive, maximumEntries: 10, maximumEntrySize: 100) { _ in
      true
    }
    #expect(all.count == 3)
  }

  @Test("a changed entry fails its CRC-32")
  func crcIsChecked() throws {
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "a.bin", data: ZipZip64Tests.noise(64, seed: 31))
    ])
    var broken = archive
    broken[broken.startIndex + 30 + 5 + 10] ^= 0x40  // inside the stored data
    #expect(throws: ZipReader.Failure.malformed) {
      try ZipReader.entries(in: broken) { _ in true }
    }
  }
}

@Suite("Traditional zip encryption")
struct ZipCryptoTests {

  /// `zip -X -e -P secret` (Info-ZIP 3.0): `t.txt` is deflated, `hello.txt` stored. Both have a
  /// data descriptor, so the check byte of the header comes from the modification time.
  static let infoZipEncrypted = ZipTools.data(
    base64: """
      UEsDBBQACQAIAOtzSV3vnnj0KwAAAEoAAAAFAAAAdC50eHRHNntQPdAjXSWFea78u94NjwHe+e8hLg/VUBVDW9sPwSB2
      dms/seXycGwaUEsHCO+eePQrAAAASgAAAFBLAwQKAAkAAABgckldgJ3H7x8AAAATAAAACQAAAGhlbGxvLnR4dC9h/JwV
      YWvVuFlRtschVqkv/SSJSBHty0ayG4+mkR1QSwcIgJ3H7x8AAAATAAAAUEsBAh4DFAAJAAgA63NJXe+eePQrAAAASgAA
      AAUAAAAAAAAAAQAAAKSBAAAAAHQudHh0UEsBAh4DCgAJAAAAYHJJXYCdx+8fAAAAEwAAAAkAAAAAAAAAAQAAAKSBXgAA
      AGhlbGxvLnR4dFBLBQYAAAAAAgACAGoAAAC0AAAAAAA=
      """)

  static let text = Data(
    "traditional pkware text, traditional pkware text, traditional pkware text\n".utf8)

  @Test("an Info-ZIP archive is decrypted with the password")
  func decrypts() throws {
    let entries = try ZipReader.entries(in: Self.infoZipEncrypted, password: "secret") { _ in true }
    #expect(
      entries == [
        ZipReader.Entry(name: "t.txt", data: Self.text),
        ZipReader.Entry(name: "hello.txt", data: ZipZip64Tests.helloText),
      ])
  }

  @Test("the password is asked for, and a wrong one is not accepted")
  func passwords() throws {
    #expect(throws: ZipReader.PasswordFailure.passwordRequired) {
      try ZipReader.entries(in: Self.infoZipEncrypted) { _ in true }
    }
    for wrong in ["Secret", "secre", "x", "secret "] {
      do {
        _ = try ZipReader.entries(in: Self.infoZipEncrypted, password: wrong) { _ in true }
        Issue.record("The password \"\(wrong)\" must not open the archive")
      } catch let failure as ZipReader.PasswordFailure {
        #expect(failure == .wrongPassword || failure == .authenticationFailed)
      }
    }
    #expect(try ZipReader.encryptionStatus(of: Self.infoZipEncrypted) == .passwordRequired)
    #expect(try ZipReader.isPasswordCorrect("secret", in: Self.infoZipEncrypted))
    #expect(try !ZipReader.isPasswordCorrect("Secret", in: Self.infoZipEncrypted))
    #expect(try ZipReader.list(in: Self.infoZipEncrypted).allSatisfy(\.isEncrypted))
  }

  @Test("the system unzip agrees on the password of the fixture")
  func unzipAgrees() throws {
    try ZipTools.withFile(Self.infoZipEncrypted) { url in
      let right = try ZipTools.run("/usr/bin/unzip", ["-tq", "-P", "secret", url.path])
      let wrong = try ZipTools.run("/usr/bin/unzip", ["-tq", "-P", "wrong", url.path])
      #expect(right.status == 0)
      #expect(wrong.status != 0)
    }
  }

  @Test("strong encryption and unknown AES variants are reported as unsupported")
  func unsupportedEncryption() throws {
    // Set bit 6 (strong encryption) in the flags of the first central record.
    var strong = Self.infoZipEncrypted
    let directory = Int(ZipLayout(strong).directoryOffset32)
    strong[strong.startIndex + directory + 8] |= 0x40
    #expect(try ZipReader.encryptionStatus(of: strong) == .unsupported)
    #expect(throws: ZipReader.Failure.unsupported) {
      try ZipReader.entries(in: strong, password: "secret") { _ in true }
    }
  }
}
