import CoreGraphics
import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// Holds the PDF tool's state: the chosen document, the page list, the rotation and the result.
/// The Tools section keeps its state in `edit`, and every other section in its own model.
@MainActor
@Observable
final class PDFToolModel {
  /// The new document and the picture of its first page.
  struct Output: Sendable {
    let data: Data
    let preview: CGImage?
  }

  /// Clockwise quarter turns for every page of the result, from 0 to 3.
  var quarterTurns = 0 {
    didSet { changed() }
  }

  /// Page numbers counted from 1 and separated by commas, such as "1,3,2". Empty keeps every page.
  var pagesText = "" {
    didSet { changed() }
  }

  private(set) var pageCount: Int?
  private(set) var preview: CGImage?
  private(set) var exportData: Data?
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var document: Data?
  /// The Tools section: the chosen tool, its options and the file it made.
  let edit = PDFEditSession()
  /// The Compress PDF section.
  let compression = PDFCompressionModel()
  /// The Comic to PDF section.
  let comic = PDFComicModel()
  /// The pictures sections: the searchable PDF, the PDF of the pictures and the contact sheet.
  let pictures = PDFPictureModel()
  /// The Merge PDFs section.
  let merger = PDFMergeModel()

  /// The PDF the viewer shows: the result, or the opened file while there is no result.
  var viewerData: Data? { exportData ?? document }

  /// Whether the chosen tool has the file or picture it needs, such as a second PDF for compare.
  var isEditReady: Bool {
    switch edit.tool {
    case .compare: edit.options.otherDocument != nil
    case .stamp: edit.options.stampImage != nil
    default: true
    }
  }

  /// The picture chosen for the signature could not be read.
  private(set) var stampError: LocalizedStringKey?

  /// Reads the page count of the chosen file. Keeps nothing when the file is not a readable PDF.
  func open(_ data: Data) async {
    let count = await Task.detached(priority: .userInitiated) { () -> Int? in
      try? PDFTools.pageCount(data)
    }.value
    // A locked PDF has no page count, but the unlock tool still needs to open it.
    guard count != nil || PDFSecurity.state(of: data) == .locked else {
      reset(message: Self.message(for: .unreadable))
      return
    }
    document = data
    pageCount = count
    quarterTurns = 0
    pagesText = ""
    errorMessage = nil
    edit.setDocument(data)
    changed()
  }

  /// The file could not be read at all, so there is no document to work with.
  func reportUnreadableFile() {
    reset(message: "The file could not be read.")
  }

  /// Builds the result from the page list and the rotation, and renders its first page. Runs after
  /// a short pause from the view.
  func refresh() async {
    guard let document, let pageCount else { return }
    let quarterTurns = quarterTurns
    guard let indices = Self.pageIndices(from: pagesText, pageCount: pageCount) else {
      exportData = nil
      preview = nil
      errorMessage = "Enter page numbers from 1 to \(pageCount), separated by commas."
      return
    }
    let previewWidth = 800
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<Output, PDFTools.Failure> in
      do {
        var data = try PDFTools.extract(document, pages: indices)
        if quarterTurns != 0 {
          data = try PDFTools.rotate(data, quarterTurns: quarterTurns)
        }
        let preview = try? PDFTools.render(data, page: 0, width: previewWidth)
        return .success(Output(data: data, preview: preview))
      } catch let failure as PDFTools.Failure {
        return .failure(failure)
      } catch {
        return .failure(.unreadable)
      }
    }.value
    guard !Task.isCancelled else { return }

    switch result {
    case .success(let output):
      exportData = output.data
      preview = output.preview
      errorMessage = nil
    case .failure(let failure):
      exportData = nil
      preview = nil
      errorMessage = Self.message(for: failure)
    }
  }

  /// Zero-based indices of the typed page numbers, in the order typed. Empty text gives every page.
  /// Nil when an entry is not a whole number from 1 to `pageCount`.
  static func pageIndices(from text: String, pageCount: Int) -> [Int]? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return Array(0..<pageCount) }
    var indices: [Int] = []
    for entry in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
      guard
        let number = Int(entry.trimmingCharacters(in: .whitespaces)),
        (1...pageCount).contains(number)
      else { return nil }
      indices.append(number - 1)
    }
    return indices
  }

  private static func message(for failure: PDFTools.Failure) -> LocalizedStringKey {
    switch failure {
    case .unreadable: "This file is not a readable PDF."
    case .noPages: "No pages are left to keep."
    case .pageOutOfRange: "One of the page numbers is outside the document."
    case .writeFailed: "The PDF could not be written."
    }
  }

  // MARK: Signature

  /// Decodes the picture for the signature tool. It stays until another picture is chosen.
  func loadStamp(_ item: PhotosPickerItem) async {
    if let loaded = await PhotoLoader.load(item) {
      edit.options.stampImage = loaded.image
      stampError = nil
    } else {
      stampError = "The picture could not be read."
    }
  }

  private func changed() {
    exportData = nil
    revision += 1
  }

  private func reset(message: LocalizedStringKey) {
    document = nil
    pageCount = nil
    preview = nil
    exportData = nil
    errorMessage = message
    edit.setDocument(nil)
  }
}
