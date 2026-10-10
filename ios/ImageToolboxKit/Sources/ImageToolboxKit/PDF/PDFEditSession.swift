import Foundation
import Observation

/// The state of the PDF tools for one document: the document, the tool chosen, its options and the
/// file it made. The screen binds to it and calls `run()`. A change of document, tool or option
/// drops the file made before, and a run that ends after such a change is dropped too.
@MainActor
@Observable
public final class PDFEditSession {
  /// The document the tools work on. Nil until a PDF is chosen. A locked PDF is kept as well, so
  /// the unlock tool can open it.
  public private(set) var document: Data?

  /// The tool that `run()` uses. Choosing metadata fills its fields from the document.
  public var tool = PDFEditTool.splitIntoParts {
    didSet {
      changed()
      if tool == .metadata { loadMetadata() }
    }
  }

  /// The values the tools read. Each tool reads its own fields and ignores the others.
  public var options = PDFEditOptions() {
    didSet { changed() }
  }

  /// The file of the last run, for the current tool and options. Nil before a run and after a
  /// change.
  public private(set) var output: PDFEditOutput?
  /// Why the last run failed. Any other error counts as `PDFEditFailure.writeFailed`.
  public private(set) var failure: PDFEditFailure?
  public private(set) var isRunning = false
  @ObservationIgnored private var generation = 0

  public init() {}

  /// Makes `data` the document, or clears it with nil. The metadata fields are read from it.
  public func setDocument(_ data: Data?) {
    document = data
    changed()
    loadMetadata()
  }

  /// Runs the tool on the document and keeps its file, or the reason it failed. Does nothing
  /// without a document or while another run is going.
  public func run() async {
    guard let document, !isRunning else { return }
    let tool = self.tool
    let options = self.options
    let started = generation
    isRunning = true
    failure = nil
    let result = await Task.detached(priority: .userInitiated) {
      () -> Result<PDFEditOutput, PDFEditFailure> in
      do {
        return .success(try PDFEditPipeline.run(tool, on: document, options: options))
      } catch let error as PDFEditFailure {
        return .failure(error)
      } catch {
        return .failure(.writeFailed)
      }
    }.value
    isRunning = false
    guard started == generation else { return }
    switch result {
    case .success(let made): output = made
    case .failure(let error): failure = error
    }
  }

  /// Drops the file and the failure, and ends the run in progress for the file it would make.
  private func changed() {
    generation += 1
    output = nil
    failure = nil
  }

  /// Fills the metadata fields from the document, so the tool starts from what the file holds.
  private func loadMetadata() {
    guard let document, let metadata = try? PDFMetadata.read(from: document) else { return }
    options.metadata = metadata
  }
}
