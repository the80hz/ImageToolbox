import ImageToolboxKit

/// The drawing tool's edits are the kit's (`DrawingEdit` and its parts), so that replaying them
/// is tested in the kit. These names keep the tool's code short.
extension DrawingToolModel {
  typealias PaintKind = DrawingPaintKind
  typealias Stroke = DrawingStroke
  typealias SprayStroke = DrawingSpray
  typealias ShapeEdit = DrawingShapeEdit
  typealias WarpSample = DrawingWarpSample
  typealias WarpStroke = DrawingWarpStroke
  typealias LassoAction = DrawingLassoAction
  typealias PencilPatch = DrawingPencilPatch
  typealias Edit = DrawingEdit
}
