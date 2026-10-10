import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// A file inside an opened archive.
struct ArchiveItem: Identifiable, Sendable {
  let id: Int
  let name: String
  let data: Data
}

/// The archive written by the tool, with the name it is saved under.
struct ArchiveFile: Sendable {
  let data: Data
  let fileName: String
}

/// Why an opened file could not be listed.
enum ArchiveReadFailure: Error, Equatable, Sendable {
  /// The file does not start with the signature of a supported archive, or of a tar inside one.
  case unrecognized
  /// The data is truncated, fails a checksum, or is otherwise malformed.
  case damaged
  /// A file inside the archive is larger than the app can hold in memory.
  case tooLarge
  /// The archive uses a method or feature the readers do not support.
  case unsupported
  /// The archive is encrypted, and the app cannot read it.
  case encrypted
  /// The zip entries are encrypted, and the app must ask for a password.
  case passwordRequired
  /// The password does not match the archive.
  case wrongPassword
  /// The data does not check out with the password, which is wrong or the file is damaged.
  case authenticationFailed
}

@MainActor
@Observable
final class ArchiveToolModel {

  /// The container a new archive is written in.
  enum Container: CaseIterable, Sendable {
    case zip
    case sevenZip
    case tarGzip
    case tarXZ
    case tarBZip2
    case tarZstd

    var fileName: String {
      switch self {
      case .zip: "pictures.zip"
      case .sevenZip: "pictures.7z"
      case .tarGzip: "pictures.tar.gz"
      case .tarXZ: "pictures.tar.xz"
      case .tarBZip2: "pictures.tar.bz2"
      case .tarZstd: "pictures.tar.zst"
      }
    }
  }

  var container = Container.zip
  /// The password of the zip archive being created. Empty writes an archive without encryption.
  var createPassword = ""
  /// The AES key size of the zip archive being created with a password.
  var createStrength = ZipAES.Strength.aes256
  /// The password typed for an encrypted archive that waits to be opened.
  var openPassword = ""

  private(set) var pictures: [LoadedImage] = []
  private(set) var failedCount = 0
  private(set) var isLoading = false
  private(set) var archive: ArchiveFile?
  private(set) var openedName: String?
  private(set) var openedItems: [ArchiveItem] = []
  private(set) var errorMessage: LocalizedStringKey?

  /// An encrypted zip archive that waits for its password.
  private struct LockedArchive {
    let data: Data
    let name: String
  }

  private var lockedArchive: LockedArchive?

  /// Whether an archive is open at the password prompt.
  var isLocked: Bool { lockedArchive != nil }

  func load(_ items: [PhotosPickerItem]) async {
    isLoading = true
    let loaded = await PhotoLoader.load(items)
    pictures = loaded
    failedCount = items.count - loaded.count
    archive = nil
    isLoading = false
  }

  /// Writes the chosen pictures, as they are picked, into one archive.
  func createArchive() async {
    guard !pictures.isEmpty else { return }
    let container = container
    let password = (container == .zip && !createPassword.isEmpty) ? createPassword : nil
    let strength = createStrength
    let sources = pictures.enumerated().map { index, picture -> ZipWriter.Entry in
      let fileExtension = BatchNaming.fileExtension(of: picture.data)
      return ZipWriter.Entry(name: "picture-\(index + 1).\(fileExtension)", data: picture.data)
    }
    let data = await Task.detached(priority: .userInitiated) { () -> Data? in
      Self.makeArchive(sources, container: container, password: password, strength: strength)
    }.value
    guard let data else {
      errorMessage = "The archive could not be created."
      archive = nil
      return
    }
    errorMessage = nil
    archive = ArchiveFile(data: data, fileName: container.fileName)
  }

  /// Packs the pictures into the chosen container, or returns nil when that fails. A zip archive
  /// is encrypted with WinZip AES when a password is given.
  nonisolated static func makeArchive(
    _ sources: [ZipWriter.Entry], container: Container,
    password: String? = nil, strength: ZipAES.Strength = .aes256
  ) -> Data? {
    switch container {
    case .zip:
      let options = ZipWriter.Options(password: password, strength: strength)
      return try? ZipWriter.archive(sources, options: options)
    case .sevenZip:
      return try? SevenZipArchive.archive(
        sources.map { SevenZipArchive.Entry(name: $0.name, data: $0.data) })
    case .tarGzip:
      return tarData(sources).flatMap { try? GzipCodec.compress($0) }
    case .tarXZ:
      return tarData(sources).flatMap { try? XZCodec.compress($0) }
    case .tarBZip2:
      return tarData(sources).flatMap { try? BZip2Codec.compress($0) }
    case .tarZstd:
      return tarData(sources).flatMap { try? ZstdCodec.compress($0) }
    }
  }

  nonisolated private static func tarData(_ sources: [ZipWriter.Entry]) -> Data? {
    try? TarArchive.archive(sources.map { TarArchive.Entry(name: $0.name, data: $0.data) })
  }

  /// Lists the files of an archive: zip, 7z, RAR, or tar, optionally compressed with gzip, xz,
  /// bzip2 or zstd, or a `.lzma` file. The kind is found by the first bytes of the file, and a
  /// `.lzma` file by its name. An encrypted zip or 7z waits at the password prompt until
  /// `unlockArchive()` is called with the password.
  func openArchive(_ data: Data, named name: String) async {
    openPassword = ""
    await read(data, named: name, password: nil)
  }

  /// Opens the encrypted archive at the password prompt with the typed password. A wrong password
  /// leaves the prompt in place, so the user can try again.
  func unlockArchive() async {
    guard let locked = lockedArchive, !openPassword.isEmpty else { return }
    await read(locked.data, named: locked.name, password: openPassword)
  }

  func reportUnreadableArchive() {
    lockedArchive = nil
    errorMessage = "Could not read the file."
  }

  private func read(_ data: Data, named name: String, password: String?) async {
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<[ArchiveItem], ArchiveReadFailure> in
      Self.readItems(data, named: name, password: password)
    }.value
    switch result {
    case .success(let items):
      lockedArchive = nil
      openPassword = ""
      errorMessage = nil
      openedName = name
      openedItems = items
    case .failure(.passwordRequired):
      lockedArchive = LockedArchive(data: data, name: name)
      openedItems = []
      openedName = nil
      errorMessage = nil
    case .failure(let failure):
      if failure != .wrongPassword && failure != .authenticationFailed {
        lockedArchive = nil
      }
      openedItems = []
      openedName = nil
      errorMessage = Self.message(for: failure)
    }
  }

  private static func message(for failure: ArchiveReadFailure) -> LocalizedStringKey {
    switch failure {
    case .unrecognized: "This file is not a supported archive."
    case .damaged: "The archive is damaged and cannot be read."
    case .tooLarge: "A file in the archive is too large to open."
    case .unsupported: "The archive uses a feature this app cannot read."
    case .encrypted: "The archive is encrypted and cannot be opened here."
    case .passwordRequired: "This archive is encrypted. Enter its password to open it."
    case .wrongPassword: "The password is wrong."
    case .authenticationFailed: "Wrong password or the file is damaged."
    }
  }

  /// The files of an archive, read from its bytes. An encrypted zip or 7z needs `password`;
  /// without one the result is `.passwordRequired`. The name tells a `.lzma` file apart, since
  /// that format has no signature.
  nonisolated static func readItems(
    _ data: Data, named name: String, password: String? = nil
  ) -> Result<[ArchiveItem], ArchiveReadFailure> {
    let bytes = [UInt8](data.prefix(6))
    do {
      let entries: [(name: String, data: Data)]
      if bytes.starts(with: [0x50, 0x4B]) {
        entries = try zipEntries(data, password: password).map { ($0.name, $0.data) }
      } else if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
        entries = try SevenZipArchive.entries(in: data, password: password).map {
          ($0.name, $0.data)
        }
      } else if bytes.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) {
        entries = try RARReader.entries(in: data).map { ($0.name, $0.data) }
      } else if name.lowercased().hasSuffix(".lzma") {
        entries = try lzmaEntries(data, named: name)
      } else {
        let (tar, compressed) = try unpackedTar(data)
        guard let listed = try? TarArchive.entries(in: tar) else {
          // A damaged compressed tar is damaged; any other data that is not tar is unrecognized.
          return .failure(compressed ? .damaged : .unrecognized)
        }
        entries = listed.map { ($0.name, $0.data) }
      }
      return .success(
        entries.enumerated().map { index, entry in
          ArchiveItem(id: index, name: entry.name, data: entry.data)
        })
    } catch {
      return .failure(failure(for: error))
    }
  }

  /// The entries of a `.lzma` file: the one file it holds, named without `.lzma`, or the entries of
  /// the tar that a `.tar.lzma` file holds.
  nonisolated private static func lzmaEntries(
    _ data: Data, named name: String
  ) throws -> [(name: String, data: Data)] {
    let plain = try LZMACodec.decompress(data)
    if let listed = try? TarArchive.entries(in: plain) {
      return listed.map { (name: $0.name, data: $0.data) }
    }
    let base = String(name.dropLast(".lzma".count))
    return [(name: base.isEmpty ? "archive" : base, data: plain)]
  }

  /// The entries of a zip archive. Encrypted entries are decrypted with `password`. Without a
  /// password, an archive with encrypted entries is refused before any entry is read.
  nonisolated private static func zipEntries(
    _ data: Data, password: String?
  ) throws -> [ZipReader.Entry] {
    if password == nil {
      guard try ZipReader.encryptionStatus(of: data) != .passwordRequired else {
        throw ZipReader.PasswordFailure.passwordRequired
      }
    }
    // The app's limits, not the library's small defaults, so that photos of any size open.
    return try ZipReader.entries(in: data, password: password, limits: .android) { _ in true }
  }

  /// The tar bytes of `data`, decompressed when it starts with a gzip, xz, bzip2 or zstd
  /// signature. The flag tells whether it was compressed. Other data is taken as plain tar.
  nonisolated private static func unpackedTar(_ data: Data) throws -> (tar: Data, compressed: Bool)
  {
    let bytes = [UInt8](data.prefix(6))
    if bytes.starts(with: [0x1F, 0x8B]) { return (try GzipCodec.decompress(data), true) }
    if bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
      return (try XZCodec.decompress(data), true)
    }
    if bytes.starts(with: [0x42, 0x5A, 0x68]) { return (try BZip2Codec.decompress(data), true) }
    if bytes.starts(with: [0x28, 0xB5, 0x2F, 0xFD]) {
      return (try ZstdCodec.decompress(data), true)
    }
    return (data, false)
  }

  /// Maps the errors of the readers onto the messages the user sees.
  nonisolated private static func failure(for error: Error) -> ArchiveReadFailure {
    if let error = error as? SevenZipArchive.PasswordFailure {
      switch error {
      case .passwordRequired: return .passwordRequired
      // 7z keeps no password check, so a failed checksum means a wrong password or damage.
      case .wrongPassword: return .authenticationFailed
      }
    }
    if let error = error as? ZipReader.PasswordFailure {
      switch error {
      case .passwordRequired: return .passwordRequired
      case .wrongPassword: return .wrongPassword
      case .authenticationFailed: return .authenticationFailed
      }
    }
    if let error = error as? ZipReader.Failure {
      switch error {
      case .malformed: return .damaged
      case .unsupported: return .unsupported
      case .tooLarge: return .tooLarge
      }
    }
    if let error = error as? RARReader.Failure {
      switch error {
      case .notRAR: return .unrecognized
      case .malformed: return .damaged
      case .encrypted: return .encrypted
      case .unsupported: return .unsupported
      case .tooLarge: return .tooLarge
      }
    }
    if let error = error as? ArchiveCodecError {
      switch error {
      case .malformed, .checksumMismatch: return .damaged
      case .unsupported: return .unsupported
      case .tooLarge: return .tooLarge
      }
    }
    return .damaged
  }
}
