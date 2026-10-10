import Foundation
import ImageToolboxKit
import Observation
import SwiftUI

/// Holds the Merge PDFs section's state: the files to join, in the order chosen, and the result.
@MainActor
@Observable
final class PDFMergeModel {
  /// The PDFs to join, in the order chosen.
  private(set) var files: [Data] = []
  private(set) var merged: Data?
  private(set) var isMerging = false
  private(set) var errorMessage: LocalizedStringKey?
  @ObservationIgnored private var generation = 0

  /// Adds files to the end of the list. A nil entry is a file that could not be read.
  func add(_ newFiles: [Data?]) {
    files += newFiles.compactMap { $0 }
    errorMessage = newFiles.contains(where: { $0 == nil }) ? "Some files could not be read." : nil
    changed()
  }

  func clear() {
    files = []
    errorMessage = nil
    changed()
  }

  /// Joins the files in the order chosen. A result that ends after the list has changed is dropped.
  func merge() async {
    let files = self.files
    guard files.count > 1, !isMerging else { return }
    let started = generation
    isMerging = true
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<Data, PDFTools.Failure> in
      do {
        return .success(try PDFTools.merge(files))
      } catch let failure as PDFTools.Failure {
        return .failure(failure)
      } catch {
        return .failure(.writeFailed)
      }
    }.value
    isMerging = false
    guard started == generation else { return }

    switch result {
    case .success(let pdf):
      merged = pdf
      errorMessage = nil
    case .failure(let failure):
      merged = nil
      errorMessage = Self.message(for: failure)
    }
  }

  private func changed() {
    merged = nil
    generation += 1
  }

  private static func message(for failure: PDFTools.Failure) -> LocalizedStringKey {
    switch failure {
    case .unreadable, .noPages: "Each file must be an unlocked, readable PDF."
    case .pageOutOfRange, .writeFailed: "The PDF could not be written."
    }
  }
}
