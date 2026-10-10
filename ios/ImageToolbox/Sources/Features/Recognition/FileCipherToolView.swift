import ImageToolboxKit
import SwiftUI

struct FileCipherToolView: View {
  @State private var model = FileCipherToolModel()

  var body: some View {
    ToolScaffold(identifier: "fileCipher") {
      GlassSection("File") {
        OpenDataFileButton(
          title: "Choose file",
          onData: { data in model.loadInput(data) },
          onFailure: { model.reportUnreadableFile() }
        )
        .accessibilityIdentifier("fileCipher.pick")

        if let input = model.input {
          Text("\(input.count) bytes")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      GlassSection("Password") {
        SecureField("Password", text: Bindable(model).password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityIdentifier("fileCipher.password")

        Picker("Algorithm", selection: Bindable(model).algorithm) {
          ForEach(FileCipher.Family.allCases, id: \.self) { family in
            Section {
              ForEach(FileCipher.Algorithm.allCases.filter { $0.family == family }) { algorithm in
                Text(verbatim: algorithm.title).tag(algorithm)
              }
            } header: {
              Text(verbatim: family.title)
            }
          }
        }
        .accessibilityIdentifier("fileCipher.algorithm")

        Text("The key is derived from the password. A lost password cannot be recovered.")
          .font(.footnote)
          .foregroundStyle(.secondary)

        Text(
          "CBC, CTR, CFB, CFB8, OFB and RC4 add an HMAC-SHA256 tag. EAX, OCB3 and GCM-SIV authenticate by themselves. RC4 is kept only for compatibility."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      GlassSection("Action") {
        HStack(spacing: 12) {
          Button("Encrypt") {
            Task { await model.encrypt() }
          }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("fileCipher.encrypt")

          Button("Decrypt") {
            Task { await model.decrypt() }
          }
          .buttonStyle(.glass)
          .accessibilityIdentifier("fileCipher.decrypt")
        }
        .disabled(model.input == nil || model.isWorking)

        if model.isWorking {
          ProgressView()
        }
      }

      if let output = model.output {
        GlassSection("Result") {
          ShareFileButton(title: "Share file", data: output, fileName: model.outputFileName)
            .accessibilityIdentifier("fileCipher.share")

          SaveFileButton(title: "Save to Files", data: output, fileName: model.outputFileName)
            .accessibilityIdentifier("fileCipher.save")
        }
      }

      if let errorMessage = model.errorMessage {
        ErrorText(message: errorMessage)
      }
    }
  }
}
