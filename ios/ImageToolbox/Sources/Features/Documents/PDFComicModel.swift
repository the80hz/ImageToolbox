import Foundation
import ImageToolboxKit
import Observation
import SwiftUI

/// Holds the Comic to PDF section's state: the chosen archive, its options and the PDF made from it,
/// or the error. A change of an option makes the PDF again from the same archive.
@MainActor
@Observable
final class PDFComicModel {
  private(set) var pdf: Data?
  private(set) var isConverting = false
  private(set) var errorMessage: LocalizedStringKey?
  /// How the pictures are ordered and made into pages.
  var options = ComicConverter.Options() {
    didSet {
      guard archive != nil else { return }
      Task { await convert() }
    }
  }
  @ObservationIgnored private var archive: Data?
  @ObservationIgnored private var generation = 0

  /// Chooses an archive and makes its PDF.
  func open(_ archive: Data) async {
    self.archive = archive
    await convert()
  }

  /// The fixed page size is on when the options have a paper size.
  var fixedPaper: Bool {
    get { options.pageSize != nil }
    set { options.pageSize = newValue ? (options.pageSize ?? .a4) : nil }
  }

  /// The paper size of the pages when the page size is fixed.
  var paper: PDFPageSize {
    get { options.pageSize ?? .a4 }
    set { options.pageSize = newValue }
  }

  /// Makes the PDF from the chosen archive and the current options. A result that finishes after a
  /// newer conversion has started is dropped.
  func convert() async {
    guard let archive else { return }
    generation += 1
    let started = generation
    let options = self.options
    isConverting = true
    pdf = nil
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<Data, ComicConverter.Failure> in
      do {
        return .success(try ComicConverter.pdf(fromArchive: archive, options: options))
      } catch let failure as ComicConverter.Failure {
        return .failure(failure)
      } catch {
        return .failure(.writeFailed)
      }
    }.value
    guard started == generation else { return }
    isConverting = false

    switch result {
    case .success(let made):
      pdf = made
    case .failure(let failure):
      errorMessage = Self.message(for: failure)
    }
  }

  func reportUnreadableArchive() {
    generation += 1
    archive = nil
    isConverting = false
    pdf = nil
    errorMessage = "The file could not be read."
  }

  private static func message(for failure: ComicConverter.Failure) -> LocalizedStringKey {
    switch failure {
    case .malformedArchive: "This file is not a readable ZIP, CBZ or CBR archive."
    case .unsupportedArchive:
      "This archive uses a feature that cannot be read, such as encryption or Zip64."
    case .archiveTooLarge: "The archive has too many files, or a picture in it is too large."
    case .noPictures: "This archive holds no JPEG, PNG, WebP or GIF pictures."
    case .undecodablePicture(let name): "The picture \(name) could not be read."
    case .invalidParameter: "Check the values entered for this tool."
    case .writeFailed: "The PDF could not be written."
    }
  }
}
