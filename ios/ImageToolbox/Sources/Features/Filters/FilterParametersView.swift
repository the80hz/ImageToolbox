import ImageToolboxKit
import SwiftUI
import UIKit

/// The settings of one filter step: a control per parameter and a button that resets them all.
struct FilterParametersView: View {
  let descriptor: FilterDescriptor
  let step: FilterStep
  let model: FiltersToolModel

  var body: some View {
    let values = FilterRegistry.values(for: step, of: descriptor)
    ForEach(descriptor.parameters, id: \.key) { parameter in
      control(for: parameter, values: values)
    }

    Button("Reset settings") {
      model.resetSelected()
    }
    .buttonStyle(.glass)
    .accessibilityIdentifier("filters.reset")
  }

  @ViewBuilder
  private func control(for parameter: FilterParameter, values: FilterValues) -> some View {
    let title = LocalizedStringKey(parameter.titleKey)
    switch parameter.kind {
    case .number(let range, let step, _):
      ParameterSlider(
        title: title,
        value: Binding(
          get: { values.number(parameter.key) },
          set: { model.setValue(.number($0), forKey: parameter.key) }),
        onEditingEnded: { model.commit() },
        range: range,
        step: step,
        format: "%.2f"
      )
      .accessibilityIdentifier("filters.parameter.\(parameter.key)")

    case .flag:
      Toggle(
        title,
        isOn: Binding(
          get: { values.flag(parameter.key) },
          set: {
            model.setValue(.flag($0), forKey: parameter.key)
            model.commit()
          })
      )

    case .choice(let options, _):
      Picker(
        title,
        selection: Binding(
          get: { values.choice(parameter.key) },
          set: {
            model.setValue(.choice($0), forKey: parameter.key)
            model.commit()
          })
      ) {
        ForEach(options, id: \.self) { option in
          Text(verbatim: option).tag(option)
        }
      }
      .pickerStyle(.menu)

    case .color:
      ColorPicker(
        title,
        selection: Binding(
          get: { Color(values.color(parameter.key)) },
          set: {
            model.setValue(.color($0.filterColor), forKey: parameter.key)
            model.commit()
          }),
        supportsOpacity: true
      )

    case .point:
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
        ParameterSlider(
          title: "X",
          value: Binding(
            get: { values.point(parameter.key).x },
            set: {
              model.setValue(
                .point(FilterPoint(x: $0, y: values.point(parameter.key).y)), forKey: parameter.key)
            }),
          onEditingEnded: { model.commit() },
          range: 0...1,
          step: 0.01,
          format: "%.2f"
        )
        ParameterSlider(
          title: "Y",
          value: Binding(
            get: { values.point(parameter.key).y },
            set: {
              model.setValue(
                .point(FilterPoint(x: values.point(parameter.key).x, y: $0)), forKey: parameter.key)
            }),
          onEditingEnded: { model.commit() },
          range: 0...1,
          step: 0.01,
          format: "%.2f"
        )
      }
    }
  }
}

extension Color {
  fileprivate init(_ color: FilterColor) {
    self.init(
      red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
  }

  /// The components in sRGB. Colours that cannot be expressed there read as black.
  fileprivate var filterColor: FilterColor {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return FilterColor(
      red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
  }
}
