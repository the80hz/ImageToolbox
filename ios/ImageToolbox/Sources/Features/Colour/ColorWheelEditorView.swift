import ImageToolboxKit
import SwiftUI

/// A round colour wheel. The dot's direction is the hue pushed into one tonal range, and its
/// distance from the centre is the amount. The dot in the centre means no change.
struct ColorWheelEditorView: View {
  let point: ColorWheelPoint
  let onChange: (ColorWheelPoint) -> Void
  let onEnd: () -> Void

  /// Space kept between the wheel's edge and the dot, in points.
  private static let inset: CGFloat = 14

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let radius = side / 2 - Self.inset
      let center = CGPoint(x: side / 2, y: side / 2)
      let dot = CGPoint(
        x: center.x + CGFloat(point.x) * radius,
        y: center.y - CGFloat(point.y) * radius)

      ZStack {
        Circle()
          .fill(AngularGradient(colors: Self.hueColors, center: .center))
          .opacity(0.85)
        Circle()
          .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        Circle()
          .fill(.white)
          .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
          .frame(width: 18, height: 18)
          .position(dot)
      }
      .frame(width: side, height: side)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let x = (value.location.x - center.x) / radius
            let y = -(value.location.y - center.y) / radius
            onChange(ColorWheelPoint(x: Double(x), y: Double(y)).normalized)
          }
          .onEnded { _ in onEnd() }
      )
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement()
    .accessibilityLabel("Colour wheel")
  }

  /// The hue at each angle, clockwise from three o'clock. The shader maps angle to hue with the
  /// same convention, so the colour under the dot is the colour that the wheel pushes towards.
  private static var hueColors: [Color] {
    (0...24).map { step in
      let turn = Double(step) / 24
      let hue = turn - 0.25 - (turn - 0.25).rounded(.down)
      return Color(hue: hue, saturation: 1, brightness: 1)
    }
  }
}
