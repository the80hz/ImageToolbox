import ImageToolboxKit
import PhotosUI
import SwiftUI

struct FormatConversionToolView: View {
  @State private var model = FormatConversionToolModel()
  @State private var batch = BatchExportModel()
  @State private var batchItems: [PhotosPickerItem] = []

  var body: some View {
    ToolScaffold(identifier: "formatConversion") {
      GlassSection("Image") {
        SinglePhotoButton(title: "Choose image", selection: Bindable(model).selection)
          .accessibilityIdentifier("formatConversion.pick")
      }

      BatchSection(identifier: "formatConversion", model: batch, pickedItems: $batchItems) {
        let target = model.target
        let quality = model.quality
        let keepMetadata = AppSettings.load(from: .standard).keepMetadata
        return { item in
          FormatConversionToolModel.batchFile(
            item, target: target, quality: quality, keepMetadata: keepMetadata)
        }
      }

      if model.source != nil {
        GlassSection("Formats") {
          Text(
            "Each format is written by the engine shown. Formats marked unavailable have no encoder on this device."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          ForEach(ConversionTarget.allCases, id: \.self) { target in
            formatRow(target)
          }
        }

        GlassSection("Export") {
          if model.target.isLossy {
            ParameterSlider(
              title: "Quality",
              value: Bindable(model).quality,
              range: 0.1...1,
              step: 0.05,
              format: "%.2f"
            )
          }

          if let exportData = model.exportData {
            ShareFileButton(
              title: "Share file",
              data: exportData,
              fileName: model.exportFileName
            )
            .accessibilityIdentifier("formatConversion.share")

            SaveFileButton(
              title: "Save to Files",
              data: exportData,
              fileName: model.exportFileName
            )
            .accessibilityIdentifier("formatConversion.save")
          }
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

  /// One format of the matrix: its name, the engine that writes it, and whether it can be chosen.
  private func formatRow(_ target: ConversionTarget) -> some View {
    Button {
      model.target = target
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: Self.name(of: target))
            .font(.body.weight(.medium))
          Text(engineLabel(target))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !target.isAvailable {
          Text("Unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if target == model.target {
          Image(systemName: "checkmark")
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!target.isAvailable)
    .accessibilityIdentifier("formatConversion.target.\(target.fileExtension)")
  }

  private func engineLabel(_ target: ConversionTarget) -> LocalizedStringKey {
    switch target.engine {
    case .imageIO: "Apple ImageIO"
    case .libwebp: "libwebp"
    case .qoi: "QOI codec"
    case .jxl: "JPEG XL codec, lossless"
    case .stickerPNG: "Telegram sticker: 512 px, up to 512 KB"
    case .none: "No encoder in this build"
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
