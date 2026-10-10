import CoreGraphics
import ImageToolboxKit
import Observation
import PencilKit
import SwiftUI

/// Holds the drawing tool's state: the edits, the brush, the colour and the rendered picture.
///
/// The picture is never stored. Every edit is recorded in `history`, and the picture is what the
/// edits give when they are replayed in order (see `DrawingScene`). Undo and redo therefore
/// work for every mode.
@MainActor
@Observable
final class DrawingToolModel {
  /// The canvas is a square of this many drawing units. The PNG is exported at this size.
  nonisolated static let canvasSide = 1024

  /// What a drag on the canvas does.
  enum Mode: CaseIterable, Sendable {
    case brush
    case shape
    case spray
    case fill
    case lasso
    case spotHealing
    case warp
    /// Apple Pencil and finger strokes through PencilKit. They wait on the canvas until they are
    /// committed as one edit.
    case pencil
  }

  /// The mode the canvas responds to. Changing it drops the lasso outline. Leaving Pencil mode
  /// commits the PencilKit strokes, so that nothing drawn is left out of the picture.
  var mode = Mode.brush {
    didSet {
      if oldValue == .pencil, mode != .pencil {
        commitPencilStrokes()
      }
      lassoOutline = []
    }
  }

  /// What a brush stroke does: ink, highlighter, neon, eraser, blur or pixelation.
  var paintKind = DrawingToolModel.PaintKind.pen

  /// Brush radius in drawing units, from 1 to 120. Applies to edits started after a change.
  var radius = 24.0

  /// Brush hardness from 0 (soft edge) to 1 (hard edge). Applies to edits started after a change.
  var hardness = 0.8

  /// How pen strokes and outlines are broken up: solid, dashed, dot-dashed or zigzag.
  var lineStyle = LineStyle.solid

  /// The kind of shape that shape mode draws, whether it is filled, and its parameters.
  var shapeKind = ShapeKind.rectangle
  var shapeFilled = false
  var shapeSides = 5
  var shapeInnerRatio = 0.5
  var shapeRegular = false
  var shapeRotation = 0.0
  var shapeCornerRadius = 0.0
  var arrowAngle = 150.0
  var arrowScale = 3.0

  /// Spray: dots per point, dot size in drawing units, and square dots instead of round ones.
  var sprayDensity = 50
  var sprayDotSize = 2.0
  var spraySquare = false

  /// Paint bucket: how far a colour may differ from the clicked one, from 0 to 1.
  var fillTolerance = 0.25

  /// How far the warp brush pushes, from 0 (not at all) to 1 (in full), and how it moves pixels.
  var warpStrength = 0.5
  var warpHardness = 0.0
  var warpMode = WarpMode.push

  /// The colour of the whole drawing. Changing it recolours every stroke, fill and lasso fill.
  var colour = Color.black {
    didSet { changed() }
  }

  /// Every edit, with undo and redo over it.
  private(set) var history = UndoHistory<[Edit]>([])
  /// The edit under the finger. It joins `history` when the drag ends.
  private(set) var inProgress: Edit?
  /// PencilKit strokes that are not committed yet, in drawing units. The canvas shows them and
  /// reports each change through `setPencilStrokes(_:)`.
  private(set) var pencilStrokes = PKDrawing()
  /// The lasso outline while it is drawn and until it is cleared, filled or dropped. Not an edit.
  private(set) var lassoOutline: [CGPoint] = []
  /// How many of the `history` edits the `preview` already contains.
  private(set) var renderedCount = 0
  private(set) var preview: CGImage?
  private(set) var exportData: Data?
  /// Bumped on every change to the picture. The view watches it and calls `refresh()` after a
  /// pause.
  private(set) var revision = 0

  /// Whether a drag is under way, from its first point until `endDrag()`.
  private var isDragging = false
  /// The latest point of the drag, in drawing units.
  private var lastDragPoint = CGPoint.zero

  /// Whether any PencilKit stroke waits to be committed.
  var hasPencilStrokes: Bool { !pencilStrokes.strokes.isEmpty }

  /// Undo steps the picture has, plus uncommitted PencilKit strokes, which Undo removes one by one.
  var canUndo: Bool { history.canUndo || hasPencilStrokes }
  var canRedo: Bool { history.canRedo }

  /// Whether any edit or stroke is recorded, so that Clear has something to remove.
  var hasEdits: Bool { !history.current.isEmpty || hasPencilStrokes }

  /// Whether the lasso outline encloses an area that Clear or Fill can act on.
  var canApplyLasso: Bool { !isDragging && lassoOutline.count >= 3 }

  /// The edits the preview does not show yet, including the one under the finger.
  var pendingEdits: [Edit] {
    var pending = Array(history.current.dropFirst(renderedCount))
    if let inProgress {
      pending.append(inProgress)
    }
    return pending
  }

  /// The shape parameters as the kit takes them. Lines take the line style; filled shapes ignore it.
  var shapeOptions: ShapeOptions {
    ShapeOptions(
      sides: shapeSides, innerRatio: shapeInnerRatio, isRegular: shapeRegular,
      rotation: shapeRotation, cornerRadius: shapeCornerRadius, arrowAngle: arrowAngle,
      arrowScale: arrowScale, lineStyle: lineStyle)
  }

  /// Handles one point of a drag, in drawing units. The first point starts the drag.
  func drag(to point: CGPoint) {
    guard point.x.isFinite, point.y.isFinite else { return }
    if isDragging {
      extend(to: point)
    } else {
      isDragging = true
      begin(at: point)
    }
    lastDragPoint = point
  }

  /// Ends the drag. What it made becomes one undo step.
  func endDrag() {
    guard isDragging else { return }
    isDragging = false
    if mode == .lasso {
      // Fewer than three corners enclose nothing, so such an outline is dropped.
      if lassoOutline.count < 3 {
        lassoOutline = []
      }
      return
    }
    // The last point of the drag always counts, even when it is too close to the last spot.
    if case .heal(var centres, let radius)? = inProgress, centres.last != lastDragPoint {
      centres.append(lastDragPoint)
      inProgress = .heal(centres: centres, radius: radius)
    }
    guard let edit = inProgress else { return }
    inProgress = nil
    // A warp drag that did not move changes nothing, so it is not recorded.
    if case .warp(let warp) = edit, warp.samples.isEmpty {
      return
    }
    commit(edit)
  }

  /// Clears or fills the pixels inside the lasso outline, as one undo step.
  func applyLasso(_ action: LassoAction) {
    guard canApplyLasso else { return }
    commit(.lasso(polygon: lassoOutline, action: action))
    lassoOutline = []
  }

  /// Drops the lasso outline without changing the picture.
  func dropLasso() {
    lassoOutline = []
  }

  /// Steps back over the last edit. While PencilKit strokes wait to be committed, the last of them
  /// is removed instead, because they are not in the history yet.
  func undo() {
    if hasPencilStrokes {
      pencilStrokes.strokes.removeLast()
      return
    }
    guard history.undo() else { return }
    changed()
  }

  /// Steps forward over an edit that was undone.
  func redo() {
    guard history.redo() else { return }
    changed()
  }

  /// Removes every edit and every uncommitted stroke, as one undo step.
  func clear() {
    guard hasEdits else { return }
    pencilStrokes = PKDrawing()
    history.record([])
    changed()
  }

  /// Stores the strokes that the PencilKit canvas shows. The canvas calls this after each change.
  func setPencilStrokes(_ drawing: PKDrawing) {
    guard drawing != pencilStrokes else { return }
    pencilStrokes = drawing
  }

  /// Puts the PencilKit strokes into the picture as one undo step, and clears them from the canvas.
  /// Strokes that leave no ink on the canvas are dropped without an edit.
  func commitPencilStrokes() {
    let drawing = pencilStrokes
    guard !drawing.strokes.isEmpty else { return }
    pencilStrokes = PKDrawing()
    guard let patch = DrawingPencil.patch(from: drawing) else { return }
    commit(.pencil(patch))
  }

  /// Renders every edit into the preview and encodes it as PNG. Runs after a short pause from the
  /// view.
  func refresh() async {
    let edits = history.current
    let count = edits.count
    let side = Self.canvasSide
    let colour = rgbComponents
    guard count > 0 else {
      renderedCount = 0
      preview = nil
      exportData = nil
      return
    }

    let rendered = await Task.detached(priority: .userInitiated) { () -> (CGImage, Data)? in
      let picture = DrawingScene.render(edits, side: side, colour: colour)
      guard
        let image = picture.toCGImage(),
        let encoded = ExportEncoding.encode(image, as: .png, source: nil)
      else { return nil }
      return (image, encoded)
    }.value
    guard !Task.isCancelled else { return }

    preview = rendered?.0
    exportData = rendered?.1
    renderedCount = count
  }

  /// The colour as 0 to 255 channels, for the kit's raster.
  var rgbComponents: (red: UInt8, green: UInt8, blue: UInt8) {
    let resolved = colour.resolve(in: EnvironmentValues())
    return (
      Self.channel(resolved.red), Self.channel(resolved.green), Self.channel(resolved.blue)
    )
  }

  // MARK: - Gestures

  private func begin(at point: CGPoint) {
    switch mode {
    case .brush:
      inProgress = .stroke(
        Stroke(
          points: [point], brush: paintBrush, kind: paintKind,
          style: paintKind == .pen || paintKind == .neon ? lineStyle : .solid))
    case .shape:
      inProgress = .shape(
        ShapeEdit(
          kind: shapeKind, start: point, end: point, filled: shapeFilled,
          brush: Brush(radius: radius, hardness: hardness), options: shapeOptions))
    case .spray:
      inProgress = .spray(
        SprayStroke(
          points: [point], radius: radius, density: sprayDensity, dotSize: sprayDotSize,
          square: spraySquare, seed: UInt64.random(in: .min ... .max)))
    case .fill:
      inProgress = .flood(at: point, tolerance: fillTolerance)
    case .lasso:
      lassoOutline = [point]
    case .spotHealing:
      inProgress = .heal(centres: [point], radius: radius)
    case .warp:
      inProgress = .warp(
        WarpStroke(
          samples: [], radius: radius, strength: warpStrength, hardness: warpHardness,
          mode: warpMode))
    case .pencil:
      // The PencilKit canvas takes pencil and finger input itself, so a drag here does nothing.
      break
    }
  }

  private func extend(to point: CGPoint) {
    if mode == .lasso {
      lassoOutline.append(point)
      return
    }
    switch inProgress {
    case .stroke(var stroke)?:
      stroke.points.append(point)
      inProgress = .stroke(stroke)

    case .shape(var shape)?:
      shape.end = point
      inProgress = .shape(shape)

    case .spray(var spray)?:
      spray.points.append(point)
      inProgress = .spray(spray)

    case .heal(var centres, let radius)?:
      // Spots are spaced at half the radius, so that a drag heals a band rather than dots.
      let spacing = CGFloat(max(radius / 2, 1))
      guard let last = centres.last, hypot(point.x - last.x, point.y - last.y) >= spacing else {
        return
      }
      centres.append(point)
      inProgress = .heal(centres: centres, radius: radius)

    case .warp(var warp)?:
      let direction = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
      guard direction != .zero else { return }
      warp.samples.append(DrawingToolModel.WarpSample(centre: point, direction: direction))
      inProgress = .warp(warp)

    default:
      break
    }
  }

  /// The brush of a brush stroke. The highlighter is always hard-edged, as Android's is.
  private var paintBrush: Brush {
    Brush(radius: radius, hardness: paintKind == .highlighter ? 1 : hardness)
  }

  /// Records an edit as one undo step. A new edit clears the redo steps.
  private func commit(_ edit: Edit) {
    history.record(history.current + [edit])
    changed()
  }

  private static func channel(_ value: Float) -> UInt8 {
    UInt8((min(max(Double(value), 0), 1) * 255).rounded())
  }

  private func changed() {
    exportData = nil
    revision += 1
  }
}
