import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class OCRToolModel {
  var selection: PhotosPickerItem? {
    didSet {
      guard let selection else { return }
      loadTask?.cancel()
      loadTask = Task { await load(selection) }
    }
  }

  /// Language codes Vision can read, sorted by their names in the current locale.
  private(set) var supportedLanguages: [String] = []
  /// The language code given to Vision. US English is the default.
  var language = "en-US"

  private(set) var source: LoadedImage?
  /// Nil until a picture has been recognized. An empty array means no text was found.
  private(set) var lines: [RecognizedLine]?
  private(set) var isRecognizing = false
  private(set) var errorMessage: LocalizedStringKey?
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// All recognized lines, one per row, from the top of the picture down.
  var recognizedText: String {
    (lines ?? []).map(\.text).joined(separator: "\n")
  }

  /// The name of a language code in the current locale, such as "English (United States)".
  static func languageName(for code: String) -> String {
    Locale.current.localizedString(forIdentifier: code) ?? code
  }

  /// Reads the languages Vision supports. Runs once, when the screen appears.
  func loadLanguages() async {
    guard supportedLanguages.isEmpty else { return }
    let codes = await Task.detached(priority: .userInitiated) {
      TextRecognizer.supportedLanguages()
    }.value
    supportedLanguages = codes.sorted {
      Self.languageName(for: $0) < Self.languageName(for: $1)
    }
  }

  /// Recognizes the text of the picture in the chosen language, on a background thread.
  func recognize() async {
    guard let source, !isRecognizing else { return }
    isRecognizing = true
    defer { isRecognizing = false }
    let image = source.image
    let languages = [language]
    let found = await Task.detached(priority: .userInitiated) {
      () -> [RecognizedLine]? in
      try? TextRecognizer.recognize(image, languages: languages, accurate: true)
    }.value

    guard let found else {
      lines = nil
      errorMessage = "Text could not be recognized."
      return
    }
    lines = found
    errorMessage = nil
  }

  private func load(_ item: PhotosPickerItem) async {
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let loaded else {
      errorMessage = "Could not read this photo."
      return
    }
    source = loaded
    lines = nil
    errorMessage = nil
  }
}
