import Foundation
import ImageIO

/// A line of text that a contact sheet writes under each picture.
public enum PDFCaptionField: String, CaseIterable, Sendable {
  case sequenceNumber
  case imageDimensions
  case fileSize
  case cameraModel
  case lens
  case exposureSettings
  case dateTaken
  case customText
}

/// The camera tags of a picture: EXIF and TIFF values that a caption can show. A tag the picture
/// does not hold stays nil.
public struct PDFPictureExif: Equatable, Sendable {
  public var make: String?
  public var model: String?
  public var lensModel: String?
  /// The exposure time in seconds, such as 0.004 for 1/250 s.
  public var exposureTime: Double?
  public var fNumber: Double?
  public var iso: Int?
  /// The date the picture was taken, as written in the file, such as "2024:05:01 12:00:00".
  public var dateTimeOriginal: String?

  public init(
    make: String? = nil, model: String? = nil, lensModel: String? = nil,
    exposureTime: Double? = nil, fNumber: Double? = nil, iso: Int? = nil,
    dateTimeOriginal: String? = nil
  ) {
    self.make = make
    self.model = model
    self.lensModel = lensModel
    self.exposureTime = exposureTime
    self.fNumber = fNumber
    self.iso = iso
    self.dateTimeOriginal = dateTimeOriginal
  }

  /// Reads the tags of the first image in `data`. Data that ImageIO cannot read gives no tags.
  public static func read(from data: Data) -> PDFPictureExif {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return PDFPictureExif() }
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    return PDFPictureExif(
      make: tiff[kCGImagePropertyTIFFMake] as? String,
      model: tiff[kCGImagePropertyTIFFModel] as? String,
      lensModel: exif[kCGImagePropertyExifLensModel] as? String,
      exposureTime: (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
      fNumber: (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
      iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue,
      dateTimeOriginal: exif[kCGImagePropertyExifDateTimeOriginal] as? String)
  }
}

/// What a caption is made from: the place of the picture in the sheet, its size and its tags.
public struct PDFCaptionInput: Equatable, Sendable {
  /// The number of the picture, counted from 1.
  public var sequence: Int
  /// The number of pictures in the sheet.
  public var total: Int
  public var width: Int
  public var height: Int
  /// The size of the picture file in bytes.
  public var byteCount: Int
  public var exif: PDFPictureExif

  public init(
    sequence: Int, total: Int, width: Int, height: Int, byteCount: Int,
    exif: PDFPictureExif = PDFPictureExif()
  ) {
    self.sequence = sequence
    self.total = total
    self.width = width
    self.height = height
    self.byteCount = byteCount
    self.exif = exif
  }
}

/// The caption lines of a contact sheet, built as the Android app builds them. A line joins its
/// parts with a bullet, and a line with no parts is left out.
public enum PDFCaptions {

  /// The lines for one picture, top to bottom: the number, the size, the camera, the exposure, the
  /// date, then each line of the custom text. Empty `fields` give no lines.
  public static func lines(
    for input: PDFCaptionInput, fields: Set<PDFCaptionField>, customText: String = ""
  ) -> [String] {
    guard !fields.isEmpty else { return [] }
    var lines: [String] = []
    if fields.contains(.sequenceNumber) {
      lines.append(sequenceText(input.sequence, total: input.total))
    }
    let sizeLine = joined([
      fields.contains(.imageDimensions) ? "\(input.width) × \(input.height)" : nil,
      fields.contains(.fileSize) ? sizeText(input.byteCount) : nil,
    ])
    append(sizeLine, to: &lines)
    let cameraLine = joined([
      fields.contains(.cameraModel)
        ? cameraName(make: input.exif.make, model: input.exif.model) : nil,
      fields.contains(.lens) ? trimmed(input.exif.lensModel) : nil,
    ])
    append(cameraLine, to: &lines)
    if fields.contains(.exposureSettings) {
      let exposure = joined([
        input.exif.exposureTime.map(exposureText),
        input.exif.fNumber.map { "f/\(compact($0))" },
        input.exif.iso.map { "ISO \($0)" },
      ])
      append(exposure, to: &lines)
    }
    if fields.contains(.dateTaken) {
      append(trimmed(input.exif.dateTimeOriginal), to: &lines)
    }
    if fields.contains(.customText) {
      for line in customText.split(whereSeparator: \.isNewline) {
        append(trimmed(String(line)), to: &lines)
      }
    }
    return lines
  }

  /// The number with leading zeros, to at least three digits and as many as the total has.
  static func sequenceText(_ sequence: Int, total: Int) -> String {
    let width = max(3, String(total).count)
    let digits = String(sequence)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }

  /// The camera name: the model, or the make and the model unless the model already holds the make.
  static func cameraName(make: String?, model: String?) -> String? {
    let make = trimmed(make) ?? ""
    guard let model = trimmed(model) else { return make.isEmpty ? nil : make }
    if make.isEmpty || model.localizedCaseInsensitiveContains(make) { return model }
    return "\(make) \(model)"
  }

  /// A shutter speed: "1/250s" for a time of half a second or less, otherwise the seconds, such as
  /// "2s".
  static func exposureText(_ seconds: Double) -> String {
    guard seconds > 0 else { return "\(compact(seconds))s" }
    if seconds <= 0.5 {
      return "1/\(max(1, Int((1 / seconds).rounded())))s"
    }
    return "\(compact(seconds))s"
  }

  /// A number without a fraction when it has none, such as "2" for 2.0 and "1.8" for 1.8.
  static func compact(_ value: Double) -> String {
    if value == value.rounded() { return String(Int(value)) }
    return String(format: "%.1f", value)
  }

  private static func sizeText(_ bytes: Int) -> String {
    Int64(bytes).formatted(.byteCount(style: .file))
  }

  private static func joined(_ parts: [String?]) -> String? {
    let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
    return present.isEmpty ? nil : present.joined(separator: " • ")
  }

  private static func append(_ line: String?, to lines: inout [String]) {
    guard let line, !line.isEmpty else { return }
    lines.append(line)
  }

  private static func trimmed(_ text: String?) -> String? {
    guard let text else { return nil }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
