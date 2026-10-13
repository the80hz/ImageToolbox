import CoreGraphics
import Foundation
import Vision

/// One line of recognised text. The box is in normalised image coordinates, with the origin at the
/// bottom left, as Vision reports it.
public struct RecognizedLine: Equatable, Sendable {
  public let text: String
  public let confidence: Float
  public let boundingBox: CGRect

  public init(text: String, confidence: Float, boundingBox: CGRect) {
    self.text = text
    self.confidence = confidence
    self.boundingBox = boundingBox
  }
}

/// Text recognition with Vision, which runs on the device with no network access.
public enum TextRecognizer {

  public enum Failure: Error, Equatable {
    case recognitionFailed
  }

  /// The language codes Vision can read at the given level (for example "en-US" or "ru-RU").
  public static func supportedLanguages(accurate: Bool = true) -> [String] {
    let level: VNRequestTextRecognitionLevel = accurate ? .accurate : .fast
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    return (try? request.supportedRecognitionLanguages()) ?? []
  }

  /// Recognises the lines of text in `image`, from the top of the picture down.
  /// - Parameters:
  ///   - languages: language codes to try, in order of preference.
  ///   - accurate: uses the slower, more accurate recognition level.
  public static func recognize(
    _ image: CGImage,
    languages: [String] = ["en-US"],
    accurate: Bool = true
  ) throws -> [RecognizedLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = accurate ? .accurate : .fast
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = accurate
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw Failure.recognitionFailed
    }
    let observations = request.results ?? []
    return observations.compactMap { observation -> RecognizedLine? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return RecognizedLine(
        text: candidate.string,
        confidence: candidate.confidence,
        boundingBox: observation.boundingBox)
    }
    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
  }
}
