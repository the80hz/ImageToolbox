import CoreGraphics
import Foundation

/// An ordered stack of markup layers over a base picture.
///
/// The value is immutable. Every edit returns a new document, so it can be stored directly in
/// `UndoHistory<MarkupDocument>`.
///
/// Coordinate system: layer geometry is in pixels of the base image, with the origin at the
/// top-left corner and y growing downwards. This matches `RasterImage` and `ImageGeometry.crop`.
/// `MarkupRenderer` flips y when it draws, because Core Graphics has its origin at the bottom-left.
///
/// A locked layer keeps its content, position, visibility and place in the stack. Every edit
/// below leaves it unchanged, except `setLocked`, which unlocks it.
public struct MarkupDocument: Equatable, Sendable {
  /// Bottom to top. The first layer is drawn first, and the last layer is on top.
  public private(set) var layers: [MarkupLayer]

  public init(layers: [MarkupLayer] = []) {
    self.layers = layers
  }

  /// Returns the document with `layer` added on top.
  public func add(_ layer: MarkupLayer) -> MarkupDocument {
    var copy = self
    copy.layers.append(layer)
    return copy
  }

  /// Returns the document without the layer at `index`. An invalid index, or a locked layer,
  /// returns the document as it is.
  public func remove(at index: Int) -> MarkupDocument {
    guard layers.indices.contains(index), !layers[index].isLocked else { return self }
    var copy = self
    copy.layers.remove(at: index)
    return copy
  }

  /// Returns the document with the layer at `source` moved so that it sits at `destination` in the
  /// result. Both indices must be valid for the current layers, and the layer must not be locked.
  /// Otherwise the document is returned as it is.
  public func move(from source: Int, to destination: Int) -> MarkupDocument {
    guard source != destination, layers.indices.contains(source),
      layers.indices.contains(destination), !layers[source].isLocked
    else { return self }
    var copy = self
    let layer = copy.layers.remove(at: source)
    copy.layers.insert(layer, at: destination)
    return copy
  }

  /// Returns the document with the layer at `index` shown or hidden. A locked layer stays as it is.
  public func setVisible(_ visible: Bool, at index: Int) -> MarkupDocument {
    guard layers.indices.contains(index), !layers[index].isLocked,
      layers[index].isVisible != visible
    else { return self }
    var copy = self
    copy.layers[index].isVisible = visible
    return copy
  }

  /// Returns the document with the layer at `index` locked or unlocked. This is the only edit that
  /// works on a locked layer.
  public func setLocked(_ locked: Bool, at index: Int) -> MarkupDocument {
    guard layers.indices.contains(index), layers[index].isLocked != locked else { return self }
    var copy = self
    copy.layers[index].isLocked = locked
    return copy
  }

  /// Returns the document with the layer at `index` changed by `change`. This covers opacity,
  /// flips, blend mode, corner radius, line count and the content of a layer. A locked layer, an
  /// invalid index, or a change that alters nothing returns the document as it is.
  public func updating(at index: Int, _ change: (inout MarkupLayer) -> Void) -> MarkupDocument {
    guard layers.indices.contains(index), !layers[index].isLocked else { return self }
    var layer = layers[index]
    change(&layer)
    guard layer != layers[index] else { return self }
    var copy = self
    copy.layers[index] = layer
    return copy
  }
}
