import SwiftUI

struct SVGTraceToolView: View {
  @State private var model = SVGTraceToolModel()

  var body: some View {
    ToolScaffold(identifier: "svgTrace") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("svgTrace.pick")

        if let source = model.source {
          PictureView(image: source.image)
        }
      }

      if model.source != nil {
        GlassSection("Trace") {
          Stepper("Colors: \(model.colours)", value: Bindable(model).colours, in: 1...16)
            .accessibilityIdentifier("svgTrace.colors")

          Toggle("Smooth curves", isOn: Bindable(model).smoothCurves)
            .accessibilityIdentifier("svgTrace.smooth")

          if !model.smoothCurves {
            Text("Outlines are stepped: there is no smoothing.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if model.exportData == nil && model.errorMessage == nil {
            ProgressView()
          }
        }
      }

      if let exportData = model.exportData {
        GlassSection("Export") {
          Text("\(exportData.count) bytes")
            .font(.footnote)
            .foregroundStyle(.secondary)

          ShareFileButton(title: "Share file", data: exportData, fileName: model.exportFileName)
            .accessibilityIdentifier("svgTrace.share")

          SaveFileButton(title: "Save to Files", data: exportData, fileName: model.exportFileName)
            .accessibilityIdentifier("svgTrace.save")
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }
}
