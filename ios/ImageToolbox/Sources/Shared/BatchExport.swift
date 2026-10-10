import CoreGraphics
import ImageIO
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One file a batch produces: its bytes and the name it is saved under.
struct BatchFile: Sendable {
  let fileName: String
  let data: Data
}

/// Runs one tool's operation over several pictures, with progress and cancel. Every tool with a
/// batch mode uses this model, so the batch behaves the same everywhere.
@MainActor
@Observable
final class BatchExportModel {
  /// A picture with its position in the batch, so each file can be named apart from the others.
  struct Item: Sendable {
    let index: Int
    let picture: LoadedImage
  }

  enum BatchError: Error {
    case processingFailed
  }

  private(set) var pictures: [LoadedImage] = []
  private(set) var failedCount = 0
  private(set) var isLoading = false
  /// Set while a batch runs. Nil when idle.
  private(set) var progress: BatchProgress?
  /// Files from the last finished batch, ready to share together.
  private(set) var exports: [ExportFile] = []
  private(set) var exportFailed = false
  @ObservationIgnored private var task: Task<Void, Never>?

  func load(_ items: [PhotosPickerItem]) async {
    cancel()
    isLoading = true
    let loaded = await PhotoLoader.load(items)
    pictures = loaded
    failedCount = items.count - loaded.count
    exports = []
    exportFailed = false
    isLoading = false
  }

  /// Runs `process` on every picture, several at a time. A picture that `process` cannot handle
  /// stops the whole batch.
  func run(label: String, process: @escaping @Sendable (Item) async -> BatchFile?) {
    runMany(label: label, process: { item in await process(item).map { [$0] } })
  }

  /// Like `run`, for an operation that produces several files from one picture, such as a split.
  func runMany(label: String, process: @escaping @Sendable (Item) async -> [BatchFile]?) {
    guard !pictures.isEmpty, task == nil else { return }
    let items = pictures.enumerated().map { Item(index: $0.offset, picture: $0.element) }
    exports = []
    exportFailed = false
    progress = BatchProgress(completed: 0, total: items.count)
    task = Task {
      do {
        let files = try await BatchRunner.run(
          items,
          label: label,
          operation: { item -> [BatchFile] in
            guard let files = await process(item) else { throw BatchError.processingFailed }
            return files
          },
          progress: { [weak self] report in
            Task { @MainActor in self?.progress = report }
          })
        exports = files.flatMap { $0 }.map { ExportFile(data: $0.data, fileName: $0.fileName) }
      } catch is CancellationError {
        exports = []
      } catch {
        exportFailed = true
      }
      progress = nil
      task = nil
    }
  }

  func cancel() {
    task?.cancel()
  }
}

/// The batch controls shown in a tool: pick several pictures, process them all, and share the results.
struct BatchSection: View {
  let identifier: String
  let model: BatchExportModel
  @Binding var pickedItems: [PhotosPickerItem]
  /// Builds the per-picture operation from the tool's current settings, when the batch starts.
  let makeProcess: () -> (@Sendable (BatchExportModel.Item) async -> BatchFile?)

  var body: some View {
    GlassSection("Batch") {
      MultiPhotoButton(title: "Choose pictures", selection: $pickedItems, maxCount: 50)
        .accessibilityIdentifier("\(identifier).batchPick")
      if model.isLoading {
        ProgressView()
      }
      if model.failedCount > 0 {
        ErrorText(message: "\(model.failedCount) pictures could not be read.")
      }

      if !model.pictures.isEmpty {
        if let progress = model.progress {
          ProgressView(value: progress.fraction)
          Text("Exporting \(progress.completed) of \(progress.total)")
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Cancel") { model.cancel() }
            .buttonStyle(.glass)
            .accessibilityIdentifier("\(identifier).batchCancel")
        } else {
          Button("Process all \(model.pictures.count) pictures") {
            model.run(label: identifier, process: makeProcess())
          }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("\(identifier).batchRun")
        }

        if model.exportFailed {
          ErrorText(message: "The batch stopped because a picture could not be processed.")
        }

        if !model.exports.isEmpty {
          ShareLink(items: model.exports, preview: { SharePreview($0.fileName) }) {
            Label("Share all \(model.exports.count) files", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.glass)
          .accessibilityIdentifier("\(identifier).batchShare")
        }
      }
    }
    .onChange(of: pickedItems) { _, items in
      Task { await model.load(items) }
    }
  }
}

/// File names for batch outputs that keep the picture's own container, such as metadata edits.
enum BatchNaming {
  /// The extension of the container the picture's bytes are in, falling back to `jpg`.
  static func fileExtension(of data: Data) -> String {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source)
    else { return "jpg" }
    let identifier = type as String
    return OutputFormat(typeIdentifier: identifier)?.fileExtension
      ?? UTType(identifier)?.preferredFilenameExtension
      ?? "jpg"
  }
}
