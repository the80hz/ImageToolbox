import CoreGraphics
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// What the preview shows for the current settings: the adjusted picture, its histogram, and the
/// colour scope the user picked, if any.
struct CurvesPreview: Sendable {
  let image: CGImage
  let histogram: ImageHistogram
  let scope: CGImage?
}

/// The editor shows one of these groups of controls.
enum CurvesEditorMode: CaseIterable, Sendable {
  case curves
  case cmyk
  case lab
  case relations
  case colorWheels
}

/// One tone curve the editor can show: an RGB channel, a CMYK component or a Lab component.
enum ToneChannel: CaseIterable, Hashable, Sendable {
  case master
  case red
  case green
  case blue
  case cyan
  case magenta
  case yellow
  case black
  case lightness
  case labA
  case labB

  /// The channels that belong to one editor mode, in the order the picker shows them.
  static func channels(for mode: CurvesEditorMode) -> [ToneChannel] {
    switch mode {
    case .curves: [.master, .red, .green, .blue]
    case .cmyk: [.cyan, .magenta, .yellow, .black]
    case .lab: [.lightness, .labA, .labB]
    case .relations, .colorWheels: []
    }
  }

  var path: WritableKeyPath<CurveAdjustments, ToneCurve> {
    switch self {
    case .master: \.curves.master
    case .red: \.curves.red
    case .green: \.curves.green
    case .blue: \.curves.blue
    case .cyan: \.cmyk.cyan
    case .magenta: \.cmyk.magenta
    case .yellow: \.cmyk.yellow
    case .black: \.cmyk.black
    case .lightness: \.lab.lightness
    case .labA: \.lab.a
    case .labB: \.lab.b
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .master: "Master"
    case .red: "Red"
    case .green: "Green"
    case .blue: "Blue"
    case .cyan: "Cyan"
    case .magenta: "Magenta"
    case .yellow: "Yellow"
    case .black: "Black"
    case .lightness: "Lightness"
    case .labA: "a"
    case .labB: "b"
    }
  }
}

@MainActor
@Observable
final class CurvesToolModel {
  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// The editor group on screen. Switching it selects that group's first channel.
  var mode = CurvesEditorMode.curves {
    didSet {
      if let first = ToneChannel.channels(for: mode).first {
        toneChannel = first
      }
    }
  }

  /// The tone curve the editor shows in the curves, CMYK and Lab modes. Not an undo step.
  var toneChannel = ToneChannel.master

  /// The hue, saturation or value curve the editor shows in the relations mode.
  var relationKind = RelationCurveKind.hueVsSat

  /// The colour scope shown under the result, or nil for none. Changing it refreshes the preview.
  var scopeKind: ColourScopeKind? = .waveform {
    didSet { changed() }
  }

  /// Output container. Changing it makes the export stale until `refresh()` runs.
  var format: OutputFormat = .png {
    didSet { changed() }
  }

  /// Lossy quality in 0.1...1. Only JPEG and HEIC use it.
  var quality = 0.9 {
    didSet { changed() }
  }

  private(set) var state = CurveAdjustments()
  /// Every change of the adjustments, with undo and redo over it. A step is recorded when a drag
  /// ends or a button is pressed.
  private(set) var history = UndoHistory(CurveAdjustments())

  private(set) var source: LoadedImage?
  private(set) var sourceHistogram: ImageHistogram?
  /// Smaller copy of the picture for the live preview, so dragging a point stays responsive.
  @ObservationIgnored private var previewSource: CGImage?
  private(set) var preview: CurvesPreview?
  private(set) var exportData: Data?
  private(set) var exportFileName = "curves.png"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// The longest side of the live preview, in pixels.
  static let previewSide = 1024.0

  var canUndo: Bool { history.canUndo }
  var canRedo: Bool { history.canRedo }

  // MARK: - Tone curves

  func tone(_ channel: ToneChannel) -> ToneCurve {
    state[keyPath: channel.path]
  }

  /// Replaces one tone curve while a point is dragged. The change is recorded by `commit()`.
  func setTone(_ curve: ToneCurve, for channel: ToneChannel) {
    state[keyPath: channel.path] = curve
    changed()
  }

  /// Removes a control point of the tone curve the editor shows, as one undo step.
  func removeTonePoint(at index: Int) {
    state[keyPath: toneChannel.path] = state[keyPath: toneChannel.path].removingPoint(at: index)
    commit()
    changed()
  }

  /// Clears the tone curve the editor shows, as one undo step.
  func resetTone() {
    state[keyPath: toneChannel.path] = .identity
    commit()
    changed()
  }

  // MARK: - Hue, saturation and value curves

  func relation(_ kind: RelationCurveKind) -> ToneCurve {
    state.relations[kind]
  }

  /// Replaces one hue, saturation or value curve while a point is dragged. Recorded by `commit()`.
  func setRelation(_ curve: ToneCurve, for kind: RelationCurveKind) {
    state.relations[kind] = curve
    changed()
  }

  /// Removes a control point of the relation curve the editor shows, as one undo step.
  func removeRelationPoint(at index: Int) {
    state.relations[relationKind] = state.relations[relationKind].removingPoint(at: index)
    commit()
    changed()
  }

  /// Returns the relation curve the editor shows to neutral, as one undo step.
  func resetRelation() {
    state.relations[relationKind] = RelationCurves.neutral
    commit()
    changed()
  }

  // MARK: - Colour wheels

  /// Replaces the colour wheels while one is dragged. The change is recorded by `commit()`.
  func setWheels(_ wheels: ColorWheels) {
    state.wheels = wheels
    changed()
  }

  /// Resets the colour wheels, as one undo step.
  func resetWheels() {
    state.wheels = .identity
    commit()
    changed()
  }

  // MARK: - Undo and presets

  /// Records the current adjustments as one undo step. Called when a drag or a button change ends.
  func commit() {
    history.record(state)
  }

  func undo() {
    guard history.undo() else { return }
    state = history.current
    changed()
  }

  func redo() {
    guard history.redo() else { return }
    state = history.current
    changed()
  }

  /// The RGB curves and the colour wheels as an ImageToolbox preset file. Presets hold these, as in
  /// the Android app, and not the CMYK, Lab or hue, saturation and value curves.
  var presetData: Data? {
    try? CurvePresetCodec.encodeJSON(CurvePreset(curves: state.curves, wheels: state.wheels))
  }

  /// Replaces the RGB curves and the colour wheels with a preset that was read from a file, as one
  /// undo step. The other curves stay as they are.
  func importPreset(_ data: Data) {
    guard let preset = try? CurvePresetCodec.decode(data) else {
      errorMessage = "This file is not a supported curve preset."
      return
    }
    state.curves = preset.curves
    state.wheels = preset.wheels
    commit()
    errorMessage = nil
    changed()
  }

  func reportUnreadablePreset() {
    errorMessage = "Could not read the file."
  }

  // MARK: - Batch and export

  /// Applies every adjustment to one picture of a batch. The batch uses the settings the tool has
  /// when it starts.
  nonisolated static func batchFile(
    _ item: BatchExportModel.Item,
    state: CurveAdjustments,
    format: OutputFormat,
    quality: Double,
    keepMetadata: Bool,
    encoder: any ImageEncoding
  ) -> BatchFile? {
    guard
      let adjusted = CurveRenderer.apply(item.picture.image, adjustments: state),
      let data = encoder.encode(
        adjusted, as: format, quality: quality,
        metadataSource: keepMetadata ? item.picture.data : nil)
    else { return nil }
    let fileName = ExportNaming.fileName(
      stem: "curves-\(item.index + 1)", fileExtension: format.fileExtension, data: data)
    return BatchFile(fileName: fileName, data: data)
  }

  /// Renders the preview from the smaller picture, and the export file from the full picture.
  /// The view calls this after a short pause, so a drag does not start a render per frame.
  func refresh() async {
    guard let source, let previewSource else { return }
    let state = state
    let scopeKind = scopeKind
    let preview = await Task.detached(priority: .userInitiated) { () -> CurvesPreview? in
      guard
        let adjusted = CurveRenderer.apply(previewSource, adjustments: state),
        let histogram = ImageHistogram(adjusted)
      else { return nil }
      let scope: CGImage?
      switch scopeKind {
      case .waveform:
        scope = ColourScopeRenderer.render(adjusted, scope: .waveform, width: 512, height: 256)
      case .vectorscope:
        scope = ColourScopeRenderer.render(adjusted, scope: .vectorscope, width: 512, height: 512)
      case nil:
        scope = nil
      }
      return CurvesPreview(image: adjusted, histogram: histogram, scope: scope)
    }.value
    guard !Task.isCancelled else { return }
    self.preview = preview
    errorMessage = preview == nil ? "The curves could not be applied." : nil

    let format = format
    let quality = quality
    let export = await Task.detached(priority: .userInitiated) { () -> (Data, String)? in
      guard
        let adjusted = CurveRenderer.apply(source.image, adjustments: state),
        let data = ExportEncoding.encode(
          adjusted, as: format, quality: quality, source: source.data)
      else { return nil }
      let name = ExportNaming.fileName(
        stem: "curves", fileExtension: format.fileExtension, data: data)
      return (data, name)
    }.value
    guard !Task.isCancelled else { return }
    if let export {
      exportData = export.0
      exportFileName = export.1
    } else {
      exportData = nil
      errorMessage = "The image could not be encoded as \(format.fileExtension.uppercased())."
    }
  }

  // MARK: - Loading

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }

    let side = Self.previewSide
    let prepared = await Task.detached(priority: .userInitiated) {
      () -> (ImageHistogram?, CGImage?) in
      let histogram = ImageHistogram(loaded.image)
      let largest = Double(max(loaded.image.width, loaded.image.height))
      let scale = min(1, side / largest)
      let width = max(1, Int(Double(loaded.image.width) * scale))
      let height = max(1, Int(Double(loaded.image.height) * scale))
      let small = ImageGeometry.resize(loaded.image, width: width, height: height)
      return (histogram, small)
    }.value

    source = loaded
    sourceHistogram = prepared.0
    previewSource = prepared.1
    state = CurveAdjustments()
    history = UndoHistory(CurveAdjustments())
    errorMessage = nil
    changed()
  }

  private func changed() {
    exportData = nil
    revision += 1
  }
}
