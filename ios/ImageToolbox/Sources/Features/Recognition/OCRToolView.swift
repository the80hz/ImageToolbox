import ImageToolboxKit
import SwiftUI
import UIKit

struct OCRToolView: View {
  @State private var model = OCRToolModel()

  var body: some View {
    ToolScaffold(identifier: "textRecognition") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("textRecognition.pick")
      }

      if model.source != nil {
        GlassSection("Recognition") {
          Picker("Language", selection: Bindable(model).language) {
            ForEach(model.supportedLanguages, id: \.self) { code in
              Text(verbatim: OCRToolModel.languageName(for: code)).tag(code)
            }
          }
          .accessibilityIdentifier("textRecognition.language")

          Text("Text is recognized on this device.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button("Recognize") {
            Task { await model.recognize() }
          }
          .buttonStyle(.glassProminent)
          .disabled(model.isRecognizing)
          .accessibilityIdentifier("textRecognition.recognize")

          if model.isRecognizing {
            ProgressView()
          }
        }
      }

      if let lines = model.lines {
        GlassSection("Result") {
          if lines.isEmpty {
            Text("No text found.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(lines.indices, id: \.self) { index in
              lineRow(lines[index])
            }

            HStack(spacing: 12) {
              Button("Copy text") {
                UIPasteboard.general.string = model.recognizedText
              }
              .buttonStyle(.glass)
              .accessibilityIdentifier("textRecognition.copy")

              ShareLink("Share text", item: model.recognizedText)
                .buttonStyle(.glass)
                .accessibilityIdentifier("textRecognition.share")
            }
          }
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .task {
      await model.loadLanguages()
    }
  }

  /// One recognized line with its confidence in percent.
  private func lineRow(_ line: RecognizedLine) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: line.text)
        .textSelection(.enabled)
      Text("Confidence: \(Int((line.confidence * 100).rounded()))%")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("textRecognition.line")
  }
}
