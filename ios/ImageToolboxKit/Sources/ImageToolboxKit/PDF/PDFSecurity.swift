import Foundation
import PDFKit

/// Password protection of a PDF, with PDFKit's encryption.
public enum PDFSecurity {

  /// What opening the data gives.
  public enum State: Equatable, Sendable {
    /// The document opens without a password.
    case open
    /// The document is encrypted and needs a password.
    case locked
    /// The data is not a PDF that can be read.
    case unreadable
  }

  public static func state(of data: Data) -> State {
    guard let document = PDFDocument(data: data) else { return .unreadable }
    if document.isLocked { return .locked }
    return document.pageCount > 0 ? .open : .unreadable
  }

  /// The document encrypted so that `password` is needed to open it. The same password is the
  /// owner password, so it also lifts any restriction. A blank password throws `invalidParameter`,
  /// and a document that is locked already throws `locked`.
  public static func protect(_ data: Data, password: String) throws -> Data {
    guard !password.isEmpty else { throw PDFEditFailure.invalidParameter }
    let document = try PDFKitAccess.open(data)
    let options: [PDFDocumentWriteOption: Any] = [
      .userPasswordOption: password, .ownerPasswordOption: password,
    ]
    guard let encrypted = document.dataRepresentation(options: options) else {
      throw PDFEditFailure.writeFailed
    }
    return encrypted
  }

  /// The document with no password and no restrictions. A wrong password throws `wrongPassword`.
  /// A document that opens without a password but carries restrictions is freed too.
  ///
  /// PDFKit keeps the encryption of a document when it writes it, so the pages are copied into
  /// a new document. Outlines and other data outside the pages are not kept.
  public static func unlock(_ data: Data, password: String) throws -> Data {
    guard let document = PDFDocument(data: data) else { throw PDFEditFailure.unreadable }
    if document.isLocked {
      guard !password.isEmpty, document.unlock(withPassword: password) else {
        throw PDFEditFailure.wrongPassword
      }
    }
    guard document.pageCount > 0 else { throw PDFEditFailure.unreadable }
    let copy = try PDFKitAccess.copy(document, pages: Array(0..<document.pageCount))
    copy.documentAttributes = PDFMetadata.carriedAttributes(of: document)
    return try PDFKitAccess.write(copy)
  }
}
