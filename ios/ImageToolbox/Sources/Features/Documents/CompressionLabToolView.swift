import ImageToolboxKit
import PhotosUI
import SwiftUI

struct CompressionLabToolView: View {
  @State private var model = CompressionLabToolModel()

  var body: some View {
    ToolScaffold(identifier: "compressionLab") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("compressionLab.pick")
      }

      if model.source != nil {
        GlassSection("Search") {
          Picker("Search", selection: Bindable(model).mode) {
            Text("Quality").tag(CompressionLabToolModel.Mode.manual)
            Text("SSIM").tag(CompressionLabToolModel.Mode.targetSSIM)
            Text("Size").tag(CompressionLabToolModel.Mode.targetSize)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("compressionLab.mode")

          searchSlider

          Text(
            "Each format is searched on its own. SSIM and PSNR compare the result with the original picture."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        GlassSection("Formats") {
          ForEach(model.availableTargets, id: \.self) { target in
            Toggle(isOn: targetBinding(target)) {
              Text(verbatim: Self.name(of: target))
            }
            .accessibilityIdentifier("compressionLab.target.\(target.fileExtension)")
          }
        }

        GlassSection("Compare") {
          Button("Compare") {
            Task { await model.compare() }
          }
          .buttonStyle(.glassProminent)
          .disabled(model.isRunning || model.selectedTargets.isEmpty)
          .accessibilityIdentifier("compressionLab.compare")

          if model.isRunning {
            ProgressView()
            Text("Comparing formats")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if !model.rows.isEmpty {
            resultTable
          }
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
  }

  /// The slider for the chosen search. Each mode has its own goal.
  @ViewBuilder
  private var searchSlider: some View {
    switch model.mode {
    case .manual:
      ParameterSlider(
        title: "Quality",
        value: Bindable(model).quality,
        range: 0.05...1,
        step: 0.05,
        format: "%.2f"
      )
      .accessibilityIdentifier("compressionLab.quality")
    case .targetSSIM:
      ParameterSlider(
        title: "Minimum SSIM",
        value: Bindable(model).ssimGoal,
        range: 0.5...1,
        step: 0.01,
        format: "%.2f"
      )
      .accessibilityIdentifier("compressionLab.ssim")
    case .targetSize:
      ParameterSlider(
        title: "Size limit, KB",
        value: Bindable(model).sizeLimitKB,
        range: 10...5000,
        step: 10,
        format: "%.0f"
      )
      .accessibilityIdentifier("compressionLab.size")
    }
  }

  private func targetBinding(_ target: ConversionTarget) -> Binding<Bool> {
    Binding(
      get: { model.selectedTargets.contains(target) },
      set: { model.setTarget(target, isIncluded: $0) }
    )
  }

  /// The results as a table. It scrolls sideways on a narrow screen.
  private var resultTable: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
        GridRow {
          headerCell("Format")
          headerCell("Quality")
          headerCell("Size, KB")
          headerCell("SSIM")
          headerCell("PSNR, dB")
          headerCell("Time, s")
        }

        ForEach(model.rows) { row in
          resultRow(row)
        }
      }
      .font(.footnote.monospacedDigit())
      .accessibilityIdentifier("compressionLab.results")
    }
  }

  private func headerCell(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  /// One format's row. A format that reached no goal shows one message across the other columns.
  private func resultRow(_ row: CompressionLabToolModel.Row) -> some View {
    GridRow {
      Text(verbatim: Self.name(of: row.target))
      if let trial = row.trial {
        Text(trial.quality, format: .number.precision(.fractionLength(2)))
        Text(Double(trial.size) / 1024, format: .number.precision(.fractionLength(1)))
        Text(trial.ssim, format: .number.precision(.fractionLength(2)))
        Text(trial.psnr, format: .number.precision(.fractionLength(1)))
        Text(trial.seconds, format: .number.precision(.fractionLength(2)))
      } else {
        Text("Could not compress with this format.")
          .foregroundStyle(.secondary)
          .gridCellColumns(5)
      }
    }
  }

  /// The names of the formats. These are proper nouns, so they are not translated.
  private static func name(of target: ConversionTarget) -> String {
    switch target {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .heic: "HEIC"
    case .avif: "AVIF"
    case .tiff: "TIFF"
    case .bmp: "BMP"
    case .gif: "GIF"
    case .jpeg2000: "JPEG 2000"
    case .ico: "ICO"
    case .tga: "TGA"
    case .webp: "WebP"
    case .qoi: "QOI"
    case .telegramSticker: "Telegram sticker"
    case .jpegXL: "JPEG XL"
    }
  }
}
