import CoreGraphics
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI
import Synchronization

/// Holds the background removal tool's state: the picked picture, the automatic removal and the
/// brush strokes that refine the subject's mask by hand.
@MainActor
@Observable
final class BackgroundRemovalToolModel {
  /// How the subject is found.
  enum Engine: String, CaseIterable, Hashable, Sendable {
    /// Vision's foreground instance mask.
    case vision
    /// U2-Net portable, a small salient object network converted to Core ML.
    case u2netPortable

    /// The engines whose files are in the app, so the picker never offers a missing model.
    static var available: [Engine] {
      allCases.filter { $0 == .vision || $0.modelURL != nil }
    }

    var title: LocalizedStringKey {
      switch self {
      case .vision: "Automatic (Vision)"
      case .u2netPortable: "U2-Net Portable"
      }
    }

    var summary: LocalizedStringKey {
      switch self {
      case .vision:
        "Vision finds the main subject on this device. Everything else becomes transparent."
      case .u2netPortable:
        "A small neural network that runs on this device and finds the standout object."
      }
    }

    /// The model file in the app bundle: compiled by Xcode, or a package compiled on first use.
    /// Nil for Vision, and for a model that is not in the bundle.
    var modelURL: URL? {
      let name: String
      switch self {
      case .vision: return nil
      case .u2netPortable: name = "u2netp"
      }
      return Bundle.main.url(forResource: name, withExtension: "mlmodelc")
        ?? Bundle.main.url(forResource: name, withExtension: "mlpackage")
    }
  }

  /// Why the automatic removal gave no picture.
  private enum RemovalFailure: Error, Sendable {
    case noSubject
    case rendering
    case modelUnavailable
  }

  /// What a brush stroke does to the subject's opacity.
  enum RefineMode: Hashable, Sendable {
    /// Brings the original picture back under the brush.
    case restore
    /// Makes the picture under the brush transparent.
    case erase
  }

  /// One brush stroke on the subject's mask. Points and radius are in picture pixels.
  struct MaskEdit: Sendable {
    let mode: RefineMode
    var points: [CGPoint]
    let radius: Double

    /// Stamps the brush along the stroke, at least every half radius, so a fast drag leaves
    /// no gaps.
    nonisolated func apply(to mask: inout SubjectMask, original: RasterImage) {
      let spacing = max(radius / 2, 1)
      var last: CGPoint?
      for point in points {
        if let last {
          let dx = Double(point.x - last.x)
          let dy = Double(point.y - last.y)
          let steps = max(Int((dx * dx + dy * dy).squareRoot() / spacing), 1)
          for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            stamp(
              at: CGPoint(
                x: last.x + (point.x - last.x) * fraction,
                y: last.y + (point.y - last.y) * fraction),
              on: &mask,
              original: original)
          }
        } else {
          stamp(at: point, on: &mask, original: original)
        }
        last = point
      }
    }

    private nonisolated func stamp(
      at centre: CGPoint, on mask: inout SubjectMask, original: RasterImage
    ) {
      switch mode {
      case .erase:
        mask.erase(at: centre, radius: radius)
      case .restore:
        mask.restore(at: centre, radius: radius, source: original)
      }
    }
  }

  /// The result of the automatic removal: the original pixels, the subject's opacity and the PNG.
  private struct Removal: Sendable {
    let original: RasterImage
    let automaticMask: SubjectMask
    let picture: PNGPicture
  }

  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// Brush diameter on the screen in points, from 4 to 80. Strokes are stored in picture pixels.
  var brushSize = 24.0
  /// What the next stroke does.
  var refineMode = RefineMode.erase
  /// How the next removal finds the subject.
  var engine = Engine.vision
  /// The engines the picker offers.
  let engines = Engine.available

  private(set) var source: LoadedImage?
  /// The refined picture, as shown on the canvas. Updated after the edits settle.
  private(set) var preview: CGImage?
  /// The refined picture with its PNG encoding. Nil while the edits are being rendered.
  private(set) var result: PNGPicture?
  private(set) var resultFileName = "subject.png"
  private(set) var isRemoving = false
  private(set) var errorMessage: LocalizedStringKey?
  /// Brush strokes applied on top of the automatic mask, oldest first.
  private(set) var edits: [MaskEdit] = []
  /// The stroke under the finger. It joins `edits` when the drag ends.
  private(set) var currentEdit: MaskEdit?
  /// How many of `edits` the `preview` already shows.
  private(set) var renderedCount = 0
  /// Bumped on every change to the edits. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// The original pixels of the picked picture, read once per automatic removal.
  @ObservationIgnored private var original: RasterImage?
  /// The subject's opacity as the automatic removal found it. The edits are replayed on it, so
  /// undo needs no copy of the mask.
  @ObservationIgnored private var automaticMask: SubjectMask?
  /// Bumped when the picture, the removal or the edits change, so late background work is dropped.
  @ObservationIgnored private var generation = 0

  var hasEdits: Bool {
    !edits.isEmpty && !isRemoving
  }

  /// The strokes the preview does not show yet, including the one under the finger.
  var pendingEdits: [MaskEdit] {
    var pending = Array(edits.dropFirst(renderedCount))
    if let currentEdit {
      pending.append(currentEdit)
    }
    return pending
  }

  /// Removes the background on a background thread with the chosen engine. The source's metadata
  /// is copied into the PNG only when the settings ask for it. Brush edits are dropped.
  func removeBackground() async {
    guard let source, !isRemoving else { return }
    isRemoving = true
    defer { isRemoving = false }
    let image = source.image
    let sourceData = source.data
    let engine = engine
    let token = generation
    let outcome = await Task.detached(priority: .userInitiated) {
      await Self.automaticRemoval(of: image, engine: engine, metadataSource: sourceData)
    }.value
    guard token == generation else { return }

    switch outcome {
    case .success(let removal):
      generation += 1
      original = removal.original
      automaticMask = removal.automaticMask
      edits = []
      currentEdit = nil
      renderedCount = 0
      show(removal.picture)
    case .failure(let failure):
      forgetRemoval()
      errorMessage = Self.message(for: failure)
    }
  }

  /// Adds a point to the stroke under the finger. The first point starts the stroke. The point and
  /// the radius are in picture pixels.
  func continueStroke(at point: CGPoint, radius: Double) {
    guard automaticMask != nil, !isRemoving else { return }
    if currentEdit == nil {
      currentEdit = MaskEdit(mode: refineMode, points: [point], radius: radius)
    } else {
      currentEdit?.points.append(point)
    }
  }

  /// Ends the stroke under the finger and keeps it.
  func endStroke() {
    guard let currentEdit else { return }
    edits.append(currentEdit)
    self.currentEdit = nil
    changed()
  }

  /// Removes the last stroke.
  func undoEdit() {
    guard hasEdits else { return }
    edits.removeLast()
    renderedCount = min(renderedCount, edits.count)
    changed()
  }

  /// Removes every stroke, so the picture is back to the automatic removal.
  func resetEdits() {
    guard hasEdits else { return }
    edits = []
    renderedCount = 0
    changed()
  }

  /// Applies the strokes to the automatic mask and encodes the result. Runs after a short pause
  /// from the view.
  func refresh() async {
    guard let original, let automaticMask, let metadata = source?.data else { return }
    let token = generation
    let edits = edits
    let rendered = await Task.detached(priority: .userInitiated) {
      BackgroundRemovalToolModel.render(
        original: original, automatic: automaticMask, edits: edits, metadataSource: metadata)
    }.value
    guard !Task.isCancelled, token == generation else { return }

    guard let rendered else {
      result = nil
      errorMessage = Self.message(for: .rendering)
      return
    }
    renderedCount = edits.count
    show(rendered)
  }

  /// Models that are already loaded, so the second removal does not compile or load again.
  private nonisolated static let loadedModels = Mutex<[Engine: CoreMLSaliency]>([:])

  /// Finds the subject with `engine` and cuts it out. Runs off the main actor.
  private nonisolated static func automaticRemoval(
    of image: CGImage, engine: Engine, metadataSource: Data?
  ) async -> Result<Removal, RemovalFailure> {
    do {
      guard let original = RasterImage(image) else { return .failure(.rendering) }
      let mask: SubjectMask
      let cutOut: CGImage
      switch engine {
      case .vision:
        cutOut = try BackgroundRemover.removeBackground(from: image)
        guard let cutRaster = RasterImage(cutOut),
          cutRaster.width == original.width, cutRaster.height == original.height
        else { return .failure(.rendering) }
        mask = subjectOpacity(cutout: cutRaster, original: original)
      case .u2netPortable:
        mask = try await saliency(for: engine).mask(for: image)
        guard mask.width == original.width, mask.height == original.height else {
          return .failure(.rendering)
        }
        // A mask without a single likely subject pixel means the network found nothing.
        guard mask.alpha.contains(where: { $0 > 0.5 }) else { return .failure(.noSubject) }
        guard let applied = mask.applied(to: original).toCGImage() else {
          return .failure(.rendering)
        }
        cutOut = applied
      }
      guard let picture = PNGPicture(cutOut, metadataSource: metadataSource) else {
        return .failure(.rendering)
      }
      return .success(Removal(original: original, automaticMask: mask, picture: picture))
    } catch let failure as BackgroundRemover.Failure {
      return .failure(failure == .noSubject ? .noSubject : .rendering)
    } catch let failure as CoreMLSaliency.Failure {
      switch failure {
      case .modelUnavailable, .unsupportedModel: return .failure(.modelUnavailable)
      case .prediction, .rendering: return .failure(.rendering)
      }
    } catch {
      return .failure(.rendering)
    }
  }

  /// The loaded network for `engine`. The first call compiles the package if needed.
  private nonisolated static func saliency(for engine: Engine) async throws -> CoreMLSaliency {
    if let loaded = loadedModels.withLock({ $0[engine] }) { return loaded }
    guard let url = engine.modelURL else { throw CoreMLSaliency.Failure.modelUnavailable }
    let saliency = try await CoreMLSaliency(modelURL: url)
    loadedModels.withLock { $0[engine] = saliency }
    return saliency
  }

  /// Replays the strokes on the automatic mask, then renders the picture and its PNG. Runs off the
  /// main actor.
  nonisolated static func render(
    original: RasterImage, automatic: SubjectMask, edits: [MaskEdit], metadataSource: Data?
  ) -> PNGPicture? {
    var mask = automatic
    for edit in edits {
      edit.apply(to: &mask, original: original)
    }
    guard let image = mask.applied(to: original).toCGImage() else { return nil }
    return PNGPicture(image, metadataSource: metadataSource)
  }

  /// The subject's opacity, read from the cut-out. The cut-out's alpha is the picture's own alpha
  /// times the subject's opacity, so dividing by the picture's alpha leaves the opacity alone.
  nonisolated static func subjectOpacity(
    cutout: RasterImage, original: RasterImage
  ) -> SubjectMask {
    var alpha = [Double](repeating: 0, count: original.width * original.height)
    for index in alpha.indices {
      let ownAlpha = Double(original.pixels[index * 4 + 3])
      guard ownAlpha > 0 else { continue }
      alpha[index] = Double(cutout.pixels[index * 4 + 3]) / ownAlpha
    }
    return SubjectMask(width: original.width, height: original.height, alpha: alpha)
  }

  private static func message(for failure: RemovalFailure) -> LocalizedStringKey {
    switch failure {
    case .noSubject: "No subject found."
    case .rendering: "The result could not be rendered."
    case .modelUnavailable: "The neural network could not be loaded."
    }
  }

  private func show(_ picture: PNGPicture) {
    preview = picture.image
    result = picture
    resultFileName = ExportNaming.fileName(
      stem: "subject", fileExtension: "png", data: picture.png)
    errorMessage = nil
  }

  /// Drops the removal and its edits, such as when another picture is chosen.
  private func forgetRemoval() {
    generation += 1
    original = nil
    automaticMask = nil
    edits = []
    currentEdit = nil
    renderedCount = 0
    preview = nil
    result = nil
  }

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    source = loaded
    forgetRemoval()
    errorMessage = nil
  }

  private func changed() {
    generation += 1
    result = nil
    revision += 1
  }
}
