import Foundation
import ImageToolboxKit
import PhotosUI
import SwiftUI

struct ArchiveToolView: View {
  private enum Mode: CaseIterable {
    case create
    case open
  }

  @State private var model = ArchiveToolModel()
  @State private var mode = Mode.create
  @State private var pickedItems: [PhotosPickerItem] = []

  var body: some View {
    ToolScaffold(identifier: "archiveTools") {
      Picker("Mode", selection: $mode) {
        Text("Create").tag(Mode.create)
        Text("Open").tag(Mode.open)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("archiveTools.mode")

      switch mode {
      case .create:
        createSection
      case .open:
        openSection
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
    .onChange(of: pickedItems) { _, items in
      Task { await model.load(items) }
    }
  }

  @ViewBuilder
  private var createSection: some View {
    GlassSection("Pictures") {
      MultiPhotoButton(title: "Choose pictures", selection: $pickedItems, maxCount: 50)
        .accessibilityIdentifier("archiveTools.pick")
      if model.isLoading {
        ProgressView()
      }
      if model.failedCount > 0 {
        ErrorText(message: "\(model.failedCount) pictures could not be read.")
      }
      Text("Pictures: \(model.pictures.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    GlassSection("Archive") {
      Picker("Container", selection: Bindable(model).container) {
        Text("ZIP").tag(ArchiveToolModel.Container.zip)
        Text("7Z").tag(ArchiveToolModel.Container.sevenZip)
        Text("TAR.GZ").tag(ArchiveToolModel.Container.tarGzip)
        Text("TAR.XZ").tag(ArchiveToolModel.Container.tarXZ)
        Text("TAR.BZ2").tag(ArchiveToolModel.Container.tarBZip2)
        Text("TAR.ZST").tag(ArchiveToolModel.Container.tarZstd)
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("archiveTools.container")

      if model.container == .zip {
        SecureField("Password", text: Bindable(model).createPassword)
          .textFieldStyle(.roundedBorder)
          .textContentType(.newPassword)
          .autocorrectionDisabled()
          .accessibilityIdentifier("archiveTools.password")
        Picker("Key size", selection: Bindable(model).createStrength) {
          ForEach(ZipAES.Strength.allCases, id: \.self) { strength in
            Text(verbatim: Self.keySizeTitle(strength)).tag(strength)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("archiveTools.strength")
        Text(
          "Leave empty for an archive without encryption. A lost password cannot be recovered."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Button("Create archive") {
        Task { await model.createArchive() }
      }
      .buttonStyle(.glassProminent)
      .disabled(model.pictures.isEmpty)
      .accessibilityIdentifier("archiveTools.create")

      if let archive = model.archive {
        ShareFileButton(title: "Share archive", data: archive.data, fileName: archive.fileName)
          .accessibilityIdentifier("archiveTools.share")
        SaveFileButton(title: "Save to Files", data: archive.data, fileName: archive.fileName)
          .accessibilityIdentifier("archiveTools.save")
      }
    }
  }

  @ViewBuilder
  private var openSection: some View {
    GlassSection("Archive") {
      OpenNamedFileButton(
        title: "Open archive",
        onFile: { name, data in Task { await model.openArchive(data, named: name) } },
        onFailure: { model.reportUnreadableArchive() }
      )
      .accessibilityIdentifier("archiveTools.open")

      if model.isLocked {
        Text("This archive is encrypted. Enter its password to open it.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        SecureField("Password", text: Bindable(model).openPassword)
          .textFieldStyle(.roundedBorder)
          .textContentType(.password)
          .autocorrectionDisabled()
          .accessibilityIdentifier("archiveTools.unlockPassword")
        Button("Open") {
          Task { await model.unlockArchive() }
        }
        .buttonStyle(.glassProminent)
        .disabled(model.openPassword.isEmpty)
        .accessibilityIdentifier("archiveTools.unlock")
      }

      if let openedName = model.openedName {
        Text("\(openedName): \(model.openedItems.count) files")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    if !model.openedItems.isEmpty {
      GlassSection("Files") {
        ForEach(model.openedItems) { item in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: item.name)
                .lineLimit(1)
                .truncationMode(.middle)
              Text("\(item.data.count) bytes")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ShareFileButton(
              title: "Share",
              data: item.data,
              fileName: (item.name as NSString).lastPathComponent
            )
            .accessibilityIdentifier("archiveTools.item")
          }
        }
      }
    }
  }

  /// The name of a key size as the zip tools write it. The names are not translated.
  private static func keySizeTitle(_ strength: ZipAES.Strength) -> String {
    switch strength {
    case .aes128: "AES-128"
    case .aes192: "AES-192"
    case .aes256: "AES-256"
    }
  }
}
