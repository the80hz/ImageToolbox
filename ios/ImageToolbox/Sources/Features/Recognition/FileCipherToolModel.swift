import Foundation
import ImageToolboxKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FileCipherToolModel {
  /// Held in memory only. It is never written to UserDefaults or to a file.
  var password = ""
  var algorithm = FileCipher.Algorithm.aes256GCM

  private(set) var input: Data?
  private(set) var output: Data?
  private(set) var outputFileName = "encrypted.itcf"
  private(set) var isWorking = false
  private(set) var errorMessage: LocalizedStringKey?

  /// Takes the bytes of a file the user chose. A result from an earlier file no longer applies.
  func loadInput(_ data: Data) {
    input = data
    output = nil
    errorMessage = nil
  }

  func reportUnreadableFile() {
    errorMessage = "Could not read this file."
  }

  func encrypt() async {
    guard let input else { return }
    guard !password.isEmpty else {
      errorMessage = "Enter a password."
      return
    }
    let password = password
    let algorithm = algorithm
    await run(stem: "encrypted", fileExtension: "itcf") {
      try FileCipher.encrypt(input, password: password, algorithm: algorithm)
    }
  }

  func decrypt() async {
    guard let input else { return }
    guard !password.isEmpty else {
      errorMessage = "Enter a password."
      return
    }
    let password = password
    await run(stem: "decrypted", fileExtension: "bin") {
      try FileCipher.decrypt(input, password: password)
    }
  }

  /// Runs one operation on a background thread, because PBKDF2 takes a noticeable time.
  private func run(
    stem: String,
    fileExtension: String,
    _ operation: @escaping @Sendable () throws -> Data
  ) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Data, any Error> in
      Result { try operation() }
    }.value

    switch outcome {
    case .success(let data):
      output = data
      outputFileName = ExportNaming.fileName(
        stem: stem, fileExtension: fileExtension, data: data)
      errorMessage = nil
    case .failure(let error):
      output = nil
      errorMessage = Self.message(for: error)
    }
  }

  private static func message(for error: any Error) -> LocalizedStringKey {
    guard let failure = error as? FileCipher.Failure else {
      return "The file could not be processed."
    }
    switch failure {
    case .notEncrypted: return "This file was not encrypted by this tool."
    case .unsupported: return "This file uses a format version this build cannot open."
    case .authenticationFailed: return "Wrong password or the file is damaged."
    case .keyDerivationFailed: return "The key could not be derived from the password."
    case .tooShort: return "The file is shorter than one cipher block, which this mode needs."
    }
  }
}
