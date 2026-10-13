import ImageToolboxKit
import SwiftUI

/// A square editor for one tone curve. Dragging near a point moves that point. Dragging on empty
/// space adds a point there and moves it. The selected point is removed by the caller.
struct CurveEditorView: View {
  let curve: ToneCurve
  @Binding var selectedIndex: Int?
  let onChange: (ToneCurve) -> Void
  let onEnd: () -> Void
  /// A centred curve shows the neutral line at one half and keeps its endpoints on it.
  var centered = false

  /// The point being dragged, from the first touch until the drag ends.
  @State private var dragging: Int?

  /// Distance in points within which a touch takes an existing point instead of adding one.
  private static let grabRadius: CGFloat = 26

  var body: some View {
    GeometryReader { proxy in
      Canvas { context, size in
        draw(in: &context, side: min(size.width, size.height))
      }
      .contentShape(Rectangle())
      .gesture(drag(side: min(proxy.size.width, proxy.size.height)))
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement()
    .accessibilityLabel("Tone curve")
  }

  private func drag(side: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if dragging == nil {
          if let index = nearestPoint(to: value.startLocation, side: side) {
            dragging = index
          } else {
            let point = Self.curvePoint(at: value.startLocation, side: side)
            let added = curve.addingPoint(x: point.x, y: point.y)
            guard added != curve,
              let index = added.points.firstIndex(where: { abs($0.x - point.x) < 1e-9 })
            else { return }
            // The added point moves on the next update, once the view holds the new curve.
            onChange(added)
            dragging = index
            selectedIndex = index
            return
          }
        }
        guard let index = dragging else { return }
        selectedIndex = index
        var target = Self.curvePoint(at: value.location, side: side)
        if centered && (index == 0 || index == curve.points.count - 1) {
          target.y = 0.5
        }
        onChange(curve.movingPoint(at: index, to: target))
      }
      .onEnded { _ in
        dragging = nil
        onEnd()
      }
  }

  /// The index of the control point closest to `location`, if one is within the grab radius.
  private func nearestPoint(to location: CGPoint, side: CGFloat) -> Int? {
    let distances = curve.points.enumerated().map {
      index, point -> (index: Int, distance: CGFloat) in
      let center = CGPoint(x: CGFloat(point.x) * side, y: CGFloat(1 - point.y) * side)
      return (index, hypot(center.x - location.x, center.y - location.y))
    }
    guard let nearest = distances.min(by: { $0.distance < $1.distance }),
      nearest.distance < Self.grabRadius
    else { return nil }
    return nearest.index
  }

  /// Maps a point on the square to curve coordinates, with y pointing up.
  private static func curvePoint(at location: CGPoint, side: CGFloat) -> CurvePoint {
    CurvePoint(
      x: min(max(Double(location.x / side), 0), 1),
      y: min(max(Double(1 - location.y / side), 0), 1))
  }

  private func draw(in context: inout GraphicsContext, side: CGFloat) {
    let frame = CGRect(x: 0, y: 0, width: side, height: side)
    context.fill(
      Path(roundedRect: frame, cornerRadius: 12), with: .color(.secondary.opacity(0.08)))

    for step in 1...3 {
      let offset = side * CGFloat(step) / 4
      var grid = Path()
      grid.move(to: CGPoint(x: offset, y: 0))
      grid.addLine(to: CGPoint(x: offset, y: side))
      grid.move(to: CGPoint(x: 0, y: offset))
      grid.addLine(to: CGPoint(x: side, y: offset))
      context.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
    }

    var baseline = Path()
    if centered {
      baseline.move(to: CGPoint(x: 0, y: side / 2))
      baseline.addLine(to: CGPoint(x: side, y: side / 2))
    } else {
      baseline.move(to: CGPoint(x: 0, y: side))
      baseline.addLine(to: CGPoint(x: side, y: 0))
    }
    context.stroke(
      baseline, with: .color(.secondary.opacity(0.5)),
      style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

    let samples = 128
    var path = Path()
    for step in 0...samples {
      let x = Double(step) / Double(samples)
      let point = CGPoint(x: CGFloat(x) * side, y: CGFloat(1 - curve.value(at: x)) * side)
      if step == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)

    for (index, point) in curve.points.enumerated() {
      let radius: CGFloat = selectedIndex == index ? 8 : 6
      let center = CGPoint(x: CGFloat(point.x) * side, y: CGFloat(1 - point.y) * side)
      let dot = Path(
        ellipseIn: CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      context.fill(dot, with: .color(.white))
      context.stroke(dot, with: .color(.accentColor), lineWidth: 2)
    }
  }
}
