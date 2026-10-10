import Foundation
import ImageToolboxKit
import Observation
import SwiftUI

/// Holds the Compress PDF section's state: the chosen PDF, its quality and the compressed result.
/// Nothing is compressed until the user asks.
@MainActor
@Observable
final class PDFCompressionModel {
  /// A compressed PDF. `keptOriginal` is true when the compressed file was not smaller, so the
  /// core returned the chosen file unchanged.
  struct Compressed: Sendable {
    let data: Data
    let originalSize: Int

    var keptOriginal: Bool { data.count == originalSize }
  }

  /// JPEG quality of the page pictures in a compressed PDF, from 0.1 to 1.
  var quality = 0.7 {
    didSet { changed() }
  }

  /// The longer side, in pixels, of each page picture in a compressed PDF.
  private static let maxSide = 2000

  private(set) var source: Data?
  private(set) var compressed: Compressed?
  private(set) var isCompressing = false
  private(set) var errorMessage: LocalizedStringKey?
  @ObservationIgnored private var generation = 0

  /// Keeps the PDF chosen for compression.
  func open(_ data: Data) {
    source = data
    errorMessage = nil
    changed()
  }

  func reportUnreadable() {
    source = nil
    errorMessage = "The file could not be read."
    changed()
  }

  /// Re-encodes the pages of the chosen PDF at the chosen quality. A result that finishes after
  /// the file or the quality has changed is dropped.
  func compress() async {
    guard let source, !isCompressing else { return }
    let quality = self.quality
    let maxSide = Self.maxSide
    let started = generation
    isCompressing = true
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<Data, PDFCompression.Failure> in
      do {
        return .success(try PDFCompression.compress(source, quality: quality, maxSide: maxSide))
      } catch let failure as PDFCompression.Failure {
        return .failure(failure)
      } catch {
        return .failure(.writeFailed)
      }
    }.value
    isCompressing = false
    guard started == generation else { return }

    switch result {
    case .success(let output):
      compressed = Compressed(data: output, originalSize: source.count)
      errorMessage = nil
    case .failure(let failure):
      compressed = nil
      errorMessage = Self.message(for: failure)
    }
  }

  private static func message(for failure: PDFCompression.Failure) -> LocalizedStringKey {
    switch failure {
    case .unreadable, .noPages: "This file is not a readable PDF."
    case .invalidSize, .encodeFailed, .writeFailed: "The PDF could not be written."
    }
  }

  /// A new file or quality makes the compressed result stale, and drops a result still being made.
  private func changed() {
    compressed = nil
    generation += 1
  }
}
