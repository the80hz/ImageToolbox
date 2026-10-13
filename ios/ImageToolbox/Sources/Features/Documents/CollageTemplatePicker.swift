import ImageToolboxKit
import SwiftUI

/// The templates that take the chosen pictures, each drawn as a small thumbnail of its cells. Tapping one picks it.
struct CollageTemplatePicker: View {
  let model: CollageToolModel

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 12) {
        ForEach(Array(model.availableTemplates.enumerated()), id: \.offset) { index, template in
          let isSelected = model.template == template
          Button {
            model.template = template
          } label: {
            VStack(spacing: 6) {
              CollageTemplateThumbnail(template: template, count: model.pictures.count)
                .frame(width: 64, height: 64)
                .padding(6)
                .background(
                  isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                  in: .rect(cornerRadius: 10))
              Text(template.title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(template.title)
          .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
          .accessibilityIdentifier("collage.template.\(index)")
        }
      }
      .padding(.vertical, 4)
    }
    .scrollIndicators(.hidden)
  }
}

/// One template drawn as its cells, filled with the secondary colour, in a square.
struct CollageTemplateThumbnail: View {
  let template: CollageTemplate
  let count: Int

  /// The side of the square the cells are worked out on, in points. The thumbnail scales them to its own size.
  private static let side: CGFloat = 100

  var body: some View {
    let cells =
      CollageTemplates.cells(
        template, count: count, width: Double(Self.side), height: Double(Self.side),
        settings: CollageLayout.Settings(gap: 6, margin: 6)) ?? []
    GeometryReader { proxy in
      let scale = proxy.size.width / Self.side
      ZStack {
        ForEach(cells.indices, id: \.self) { index in
          Path(cells[index])
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .fill(Color.secondary.opacity(0.55))
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }
}
