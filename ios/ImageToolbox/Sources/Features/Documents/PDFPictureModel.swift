import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// Holds the state of the pictures sections: the pictures chosen, the searchable PDF, the PDF of
/// the pictures and the contact sheet. The three results are made from the same pictures.
@MainActor
@Observable
final class PDFPictureModel {
  // MARK: Searchable PDF

  /// The pictures for the searchable PDF, in the order picked.
  private(set) var searchablePictures: [LoadedImage] = []
  private(set) var failedPictureCount = 0
  private(set) var isLoadingPictures = false
  private(set) var searchablePDF: Data?
  private(set) var isMakingSearchable = false
  private(set) var searchableError: LocalizedStringKey?
  @ObservationIgnored private var searchableGeneration = 0

  /// Decodes the pictures picked for the searchable PDF. Nothing is recognized until the user asks.
  func loadPictures(_ items: [PhotosPickerItem]) async {
    searchableGeneration += 1
    isLoadingPictures = true
    let loaded = await PhotoLoader.load(items)
    searchablePictures = loaded
    failedPictureCount = items.count - loaded.count
    searchablePDF = nil
    searchableError = nil
    picturePDF = nil
    picturePDFError = nil
    contactChanged()
    isLoadingPictures = false
  }

  /// Recognizes the text of every picture and writes one page per picture, with the text laid
  /// under it. A result that finishes after the pictures have changed is dropped.
  func makeSearchablePDF() async {
    let pictures = searchablePictures.map(\.image)
    guard !pictures.isEmpty, !isMakingSearchable else { return }
    let generation = searchableGeneration
    isMakingSearchable = true
    searchablePDF = nil
    let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
      do {
        let languages = Self.recognitionLanguages()
        return .success(try SearchablePDF.make(from: pictures, languages: languages))
      } catch {
        return .failure(error)
      }
    }.value
    isMakingSearchable = false
    guard generation == searchableGeneration else { return }

    switch result {
    case .success(let pdf):
      searchablePDF = pdf
      searchableError = nil
    case .failure(let error):
      searchableError = Self.searchableMessage(for: error)
    }
  }

  /// The device's preferred languages that Vision can read, or English when none of them can be.
  nonisolated private static func recognitionLanguages() -> [String] {
    let supported = TextRecognizer.supportedLanguages()
    let preferred = Locale.preferredLanguages.filter { supported.contains($0) }
    return preferred.isEmpty ? ["en-US"] : preferred
  }

  private static func searchableMessage(for error: Error) -> LocalizedStringKey {
    switch error {
    case SearchablePDF.Failure.noPictures: "Choose at least one picture."
    case TextRecognizer.Failure.recognitionFailed: "Text could not be recognized."
    default: "The PDF could not be written."
    }
  }

  // MARK: Pictures to PDF

  /// The options of the PDF of the pictures: quality, scale, paper size and the width rule.
  var pdfOptions = ImagesToPDF.Options() {
    didSet {
      picturePDF = nil
      picturePDFError = nil
    }
  }

  /// Whether the pages have a fixed paper size. Off makes each page as large as its picture.
  var fixedPaper: Bool {
    get { pdfOptions.pageSize != nil }
    set { pdfOptions.pageSize = newValue ? (pdfOptions.pageSize ?? .a4) : nil }
  }

  /// The paper size of the pages when the size is fixed.
  var paper: PDFPageSize {
    get { pdfOptions.pageSize ?? .a4 }
    set { pdfOptions.pageSize = newValue }
  }

  /// One page per picture, from the pictures chosen for the searchable PDF.
  private(set) var picturePDF: Data?
  private(set) var picturePDFError: LocalizedStringKey?

  /// Makes the PDF from the chosen pictures. A result that ends after a change is dropped.
  func makePicturePDF() async {
    let pictures = searchablePictures.map(\.image)
    guard !pictures.isEmpty else { return }
    let generation = searchableGeneration
    let options = pdfOptions
    let result = await Task.detached(priority: .userInitiated) { () -> Data? in
      try? ImagesToPDF.make(from: pictures, options: options)
    }.value
    guard generation == searchableGeneration else { return }
    picturePDF = result
    picturePDFError = result == nil ? "The PDF could not be written." : nil
  }

  // MARK: Contact sheet

  /// The grid of the contact sheet, made from the pictures chosen for the searchable PDF.
  var contactSheet = PDFContactSheet() {
    didSet { contactChanged() }
  }

  /// The lines written under each picture, such as its number, size and camera settings.
  var contactFields: Set<PDFCaptionField> = [.sequenceNumber, .imageDimensions, .fileSize] {
    didSet { contactChanged() }
  }

  /// The lines of text written under every picture, after the fields.
  var contactCustomText = "" {
    didSet { contactChanged() }
  }

  private(set) var contactPDF: Data?
  private(set) var contactError: LocalizedStringKey?
  private(set) var isMakingContactSheet = false
  @ObservationIgnored private var contactGeneration = 0

  /// Lays the chosen pictures out in a grid on PDF pages, with the captions read from each picture.
  /// A result that ends after the pictures or the layout changed is dropped.
  func makeContactSheet() async {
    let layout = contactSheet
    let fields = contactFields
    let customText = contactCustomText
    let pictures = searchablePictures
    guard !pictures.isEmpty, !isMakingContactSheet else { return }
    let generation = contactGeneration
    isMakingContactSheet = true
    let result = await Task.detached(priority: .userInitiated) { () -> Data? in
      let items = pictures.enumerated().map { index, picture in
        PDFContactSheet.Item(
          image: picture.image,
          captions: PDFCaptions.lines(
            for: PDFCaptionInput(
              sequence: index + 1, total: pictures.count, width: picture.image.width,
              height: picture.image.height, byteCount: picture.data.count,
              exif: PDFPictureExif.read(from: picture.data)),
            fields: fields, customText: customText))
      }
      return try? layout.make(from: items)
    }.value
    isMakingContactSheet = false
    guard generation == contactGeneration else { return }
    contactPDF = result
    contactError = result == nil ? "The PDF could not be written." : nil
  }

  private func contactChanged() {
    contactPDF = nil
    contactError = nil
    contactGeneration += 1
  }
}
