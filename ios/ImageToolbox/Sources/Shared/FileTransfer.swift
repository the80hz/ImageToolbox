import SwiftUI
import UniformTypeIdentifiers
import os

/// Bytes handed to the system Files exporter as they are.
struct BinaryFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.data]

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

/// Saves a finished file through the system Files picker, so the user chooses the folder.
struct SaveFileButton: View {
  private static let logger = Logger(subsystem: "com.the80hz.imagetoolbox", category: "export")

  let title: LocalizedStringKey
  let data: Data
  let fileName: String

  @State private var isExporting = false

  var body: some View {
    Button {
      isExporting = true
    } label: {
      Label {
        Text(title)
      } icon: {
        Image(systemName: "folder").accessibilityHidden(true)
      }
    }
    .buttonStyle(.glass)
    .fileExporter(
      isPresented: $isExporting,
      document: BinaryFileDocument(data: data),
      contentType: UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .data,
      defaultFilename: fileName
    ) { result in
      if case .failure(let error) = result {
        Self.logger.error("Saving to Files failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}

/// Reads a UTF-8 text file chosen in the system Files picker and hands its text over.
struct OpenTextFileButton: View {
  let title: LocalizedStringKey
  let onText: (String) -> Void

  @State private var isImporting = false

  var body: some View {
    // Text only, like the Paste button beside it. An icon here would be exposed as an image
    // element before the photo picker's images in the accessibility tree.
    Button(title) {
      isImporting = true
    }
    .buttonStyle(.glass)
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.plainText, .text]) { result in
      guard case .success(let url) = result else { return }
      // Files outside the app's sandbox need access requested for the duration of the read.
      let granted = url.startAccessingSecurityScopedResource()
      defer {
        if granted { url.stopAccessingSecurityScopedResource() }
      }
      if let text = try? String(contentsOf: url, encoding: .utf8) {
        onText(text)
      }
    }
  }
}

/// Reads the bytes of a file chosen in the system Files picker, for binary formats such as ACV.
struct OpenDataFileButton: View {
  let title: LocalizedStringKey
  let onData: (Data) -> Void
  let onFailure: () -> Void

  var body: some View {
    OpenNamedFileButton(title: title, onFile: { _, data in onData(data) }, onFailure: onFailure)
  }
}

/// Reads a file chosen in the system Files picker and passes its name with its data, for formats
/// that the file name identifies, such as `.lzma`.
struct OpenNamedFileButton: View {
  let title: LocalizedStringKey
  let onFile: (_ name: String, _ data: Data) -> Void
  let onFailure: () -> Void

  @State private var isImporting = false

  var body: some View {
    // Text only, for the same accessibility reason as OpenTextFileButton.
    Button(title) {
      isImporting = true
    }
    .buttonStyle(.glass)
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
      guard case .success(let url) = result else { return }
      let granted = url.startAccessingSecurityScopedResource()
      defer {
        if granted { url.stopAccessingSecurityScopedResource() }
      }
      if let data = try? Data(contentsOf: url) {
        onFile(url.lastPathComponent, data)
      } else {
        onFailure()
      }
    }
  }
}
