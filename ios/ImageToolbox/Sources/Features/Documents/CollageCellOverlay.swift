import ImageToolboxKit
import SwiftUI

/// The cells drawn over the preview. A tap selects a picture. A drag moves a cell in a free layout and pans the
/// picture in a template. The corner handles of a selected free cell resize it, and the handles on the lines between
/// the cells of a template move those lines.
struct CollageCellOverlay: View {
  let model: CollageToolModel

  private static let space = "collage.cells.overlay"
  private static let handleSize: CGFloat = 22

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let outlines = model.cellOutlines
      // The corner handles of a free cell sit on the corners of its bounding box.
      let frames = outlines.map { scaled($0.boundingBox, to: size) }
      ZStack(alignment: .topLeading) {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { model.selectCell(nil) }

        ForEach(model.drawOrder, id: \.self) { index in
          if outlines.indices.contains(index) {
            cell(index, outline: outlines[index], previewSize: size)
          }
        }

        if model.arrangement == .free, let selected = model.selectedCell,
          frames.indices.contains(selected)
        {
          ForEach(FreeCollageLayout.Handle.allCases, id: \.self) { handle in
            handleView(handle, of: selected, frame: frames[selected], previewSize: size)
          }
        }

        if model.arrangement == .template {
          ForEach(Array(model.dividers.enumerated()), id: \.offset) { index, divider in
            dividerHandle(divider, index: index, previewSize: size)
          }
        }
      }
      .coordinateSpace(.named(Self.space))
    }
  }

  private func cell(_ index: Int, outline: CGPath, previewSize: CGSize) -> some View {
    let isSelected = model.selectedCell == index
    let shape = Path(outline).applying(
      CGAffineTransform(scaleX: previewSize.width, y: previewSize.height))
    let label = CGPoint(x: shape.boundingRect.minX + 18, y: shape.boundingRect.minY + 12)
    return
      shape
      .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
      .overlay {
        shape.stroke(
          isSelected ? Color.accentColor : Color.white.opacity(0.85),
          lineWidth: isSelected ? 3 : 1.5)
      }
      .overlay {
        Text(verbatim: "\(index + 1)")
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.black.opacity(0.55), in: .capsule)
          .position(label)
          .allowsHitTesting(false)
      }
      .contentShape(shape)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
          .onChanged { value in
            model.selectCell(index)
            if model.arrangement == .free {
              model.dragCell(index, translation: value.translation, previewSize: previewSize)
            } else {
              model.panPicture(index, translation: value.translation, previewSize: previewSize)
            }
          }
          .onEnded { _ in model.endDrag() }
      )
      .accessibilityLabel("Picture \(index + 1)")
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      .accessibilityAction { model.selectCell(index) }
      .accessibilityIdentifier("collage.cell.\(index)")
  }

  private func handleView(
    _ handle: FreeCollageLayout.Handle, of index: Int, frame: CGRect, previewSize: CGSize
  ) -> some View {
    let corner = point(of: handle, in: frame)
    let hitSize = Self.handleSize * 2
    return Circle()
      .fill(Color.accentColor)
      .overlay(Circle().strokeBorder(.white, lineWidth: 2))
      .frame(width: Self.handleSize, height: Self.handleSize)
      .frame(width: hitSize, height: hitSize)
      .contentShape(Rectangle())
      .offset(x: corner.x - hitSize / 2, y: corner.y - hitSize / 2)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
          .onChanged { value in
            model.dragCorner(
              index, handle: handle, translation: value.translation, previewSize: previewSize)
          }
          .onEnded { _ in model.endDrag() }
      )
      .accessibilityHidden(true)
  }

  /// A grip at the middle of a divider. It is wider than the line it shows, so it is easy to catch with a finger.
  private func dividerHandle(
    _ divider: CollageDivider, index: Int, previewSize: CGSize
  ) -> some View {
    let line = model.dividerLine(divider)
    let start = CGPoint(x: line.start.x * previewSize.width, y: line.start.y * previewSize.height)
    let end = CGPoint(x: line.end.x * previewSize.width, y: line.end.y * previewSize.height)
    let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let isVertical = divider.orientation == .vertical
    let hitSize = CGSize(
      width: isVertical ? 32 : abs(end.x - start.x), height: isVertical ? abs(end.y - start.y) : 32)
    return Capsule()
      .fill(Color.white)
      .overlay(Capsule().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
      .frame(width: isVertical ? 6 : 28, height: isVertical ? 28 : 6)
      .frame(width: hitSize.width, height: hitSize.height)
      .contentShape(Rectangle())
      .position(middle)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
          .onChanged { value in
            model.dragDivider(divider, translation: value.translation, previewSize: previewSize)
          }
          .onEnded { _ in model.endDividerDrag() }
      )
      .accessibilityLabel(
        isVertical ? "Vertical divider \(index + 1)" : "Horizontal divider \(index + 1)"
      )
      .accessibilityIdentifier("collage.divider.\(index)")
  }

  private func scaled(_ fraction: CGRect, to size: CGSize) -> CGRect {
    CGRect(
      x: fraction.minX * size.width, y: fraction.minY * size.height,
      width: fraction.width * size.width, height: fraction.height * size.height)
  }

  private func point(of handle: FreeCollageLayout.Handle, in frame: CGRect) -> CGPoint {
    switch handle {
    case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
    case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
    case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
    case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
    }
  }
}
