import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// Holds the compression lab's state: the picture, the search settings and one row per format.
@MainActor
@Observable
final class CompressionLabToolModel {
  /// How the quality of every format is chosen.
  enum Mode: CaseIterable, Hashable {
    /// The user sets the quality.
    case manual
    /// The lowest quality whose SSIM reaches the goal.
    case targetSSIM
    /// The highest quality whose file fits the size limit.
    case targetSize
  }

  /// The outcome for one format. The trial is nil when the format could not reach the goal.
  struct Row: Identifiable, Sendable {
    let target: ConversionTarget
    let trial: CompressionLab.Trial?

    var id: ConversionTarget { target }
  }

  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  var mode = Mode.targetSSIM {
    didSet { changed() }
  }

  /// Quality for the manual mode, from 0.05 to 1.
  var quality = 0.8 {
    didSet { changed() }
  }

  /// The SSIM goal for the SSIM mode, from 0.5 to 1.
  var ssimGoal = 0.9 {
    didSet { changed() }
  }

  /// The file size limit in kilobytes for the size mode, from 10 to 5000.
  var sizeLimitKB = 500.0 {
    didSet { changed() }
  }

  /// The formats in the comparison. Starts with every format this build can write.
  private(set) var selectedTargets = Set(ConversionTarget.allCases.filter(\.isAvailable)) {
    didSet { changed() }
  }

  private(set) var source: LoadedImage?
  private(set) var rows: [Row] = []
  private(set) var isRunning = false
  private(set) var errorMessage: LocalizedStringKey?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// Counts the changes, so a comparison that finishes after a change is dropped.
  @ObservationIgnored private var generation = 0

  /// The formats this build can write, in the order of `ConversionTarget`.
  var availableTargets: [ConversionTarget] {
    ConversionTarget.allCases.filter(\.isAvailable)
  }

  /// The search that the chosen mode and its slider describe.
  var search: CompressionLab.Search {
    switch mode {
    case .manual: .manual(quality: quality)
    case .targetSSIM: .targetSSIM(ssimGoal)
    case .targetSize: .targetSize(bytes: Int(sizeLimitKB * 1024))
    }
  }

  func setTarget(_ target: ConversionTarget, isIncluded: Bool) {
    if isIncluded {
      selectedTargets.insert(target)
    } else {
      selectedTargets.remove(target)
    }
  }

  /// Runs the search for every selected format. Each format is its own detached job, so the
  /// formats are searched in parallel. The table is replaced when all of them have finished.
  func compare() async {
    guard let source, !isRunning else { return }
    let picture = source
    let search = search
    let targets = availableTargets.filter { selectedTargets.contains($0) }
    let generation = generation
    isRunning = true

    let collected = await withTaskGroup(of: Row.self, returning: [Row].self) { group in
      for target in targets {
        group.addTask {
          await Task.detached(priority: .userInitiated) {
            Row(
              target: target,
              trial: CompressionLab.run(picture.image, target: target, search: search))
          }.value
        }
      }
      var finished: [Row] = []
      for await row in group {
        finished.append(row)
      }
      return finished
    }

    isRunning = false
    guard generation == self.generation else { return }
    // The formats finish in any order, so the table follows the order of the list.
    rows = targets.compactMap { target in
      collected.first(where: { $0.target == target })
    }
  }

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    source = loaded
    errorMessage = nil
    changed()
  }

  /// Any change makes the table stale, so it is cleared until the next comparison.
  private func changed() {
    generation += 1
    rows = []
  }
}
