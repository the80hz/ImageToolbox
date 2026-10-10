import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import ImageToolboxKit

@Suite("PDF contact sheet captions")
struct PDFCaptionsTests {

  private static let everyField = Set(PDFCaptionField.allCases)

  /// A JPEG of a small picture with the given EXIF and TIFF tags, as a camera would write it.
  private static func jpeg(exif: [CFString: Any], tiff: [CFString: Any]) throws -> Data {
    let picture = TestImages.solid(RGBA(red: 200, green: 100, blue: 50), width: 16, height: 16)
    let output = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
    let properties: [CFString: Any] = [
      kCGImagePropertyExifDictionary: exif, kCGImagePropertyTIFFDictionary: tiff,
    ]
    CGImageDestinationAddImage(destination, picture, properties as CFDictionary)
    try #require(CGImageDestinationFinalize(destination))
    return output as Data
  }

  @Test("the number has at least three digits and as many as the total")
  func sequenceNumberPadding() {
    #expect(PDFCaptions.sequenceText(7, total: 9) == "007")
    #expect(PDFCaptions.sequenceText(7, total: 1_000) == "0007")
    #expect(PDFCaptions.sequenceText(1_234, total: 2_000) == "1234")
  }

  @Test("every field gives its line, in the order of the Android sheet")
  func linesFollowTheAndroidOrder() throws {
    let exif = PDFPictureExif(
      make: "Canon", model: "EOS R6", lensModel: "RF 35mm", exposureTime: 0.004, fNumber: 1.8,
      iso: 400, dateTimeOriginal: " 2024:05:01 12:00:00 ")
    let input = PDFCaptionInput(
      sequence: 3, total: 12, width: 4_000, height: 3_000, byteCount: 2_500_000, exif: exif)
    let lines = PDFCaptions.lines(
      for: input, fields: Self.everyField, customText: "Trip\n\n  Lisbon  ")
    let size = Int64(2_500_000).formatted(.byteCount(style: .file))
    #expect(
      lines == [
        "003",
        "4000 × 3000 • \(size)",
        "Canon EOS R6 • RF 35mm",
        "1/250s • f/1.8 • ISO 400",
        "2024:05:01 12:00:00",
        "Trip",
        "Lisbon",
      ])
  }

  @Test("no fields give no lines, and a picture without tags gives only the lines it can fill")
  func missingTagsLeaveLinesOut() {
    let input = PDFCaptionInput(sequence: 1, total: 1, width: 10, height: 20, byteCount: 0)
    #expect(PDFCaptions.lines(for: input, fields: []).isEmpty)
    let lines = PDFCaptions.lines(
      for: input, fields: [.sequenceNumber, .imageDimensions, .cameraModel, .exposureSettings])
    #expect(lines == ["001", "10 × 20"])
  }

  @Test("the camera name leads with the make unless the model already holds it")
  func cameraName() {
    #expect(PDFCaptions.cameraName(make: "NIKON", model: "NIKON D850") == "NIKON D850")
    #expect(
      PDFCaptions.cameraName(make: "NIKON CORPORATION", model: "NIKON D850")
        == "NIKON CORPORATION NIKON D850")
    #expect(PDFCaptions.cameraName(make: "Apple", model: "iPhone 16") == "Apple iPhone 16")
    #expect(PDFCaptions.cameraName(make: "Apple", model: nil) == "Apple")
    #expect(PDFCaptions.cameraName(make: nil, model: "X100V") == "X100V")
    #expect(PDFCaptions.cameraName(make: " ", model: "") == nil)
  }

  @Test("a shutter speed of half a second or less is a fraction, a longer one is in seconds")
  func exposureText() {
    #expect(PDFCaptions.exposureText(0.5) == "1/2s")
    #expect(PDFCaptions.exposureText(1.0 / 8_000) == "1/8000s")
    #expect(PDFCaptions.exposureText(2) == "2s")
    #expect(PDFCaptions.exposureText(1.5) == "1.5s")
    #expect(PDFCaptions.compact(1.8) == "1.8")
    #expect(PDFCaptions.compact(4) == "4")
  }

  @Test("the custom text gives one line for each line that is not blank")
  func customTextLines() {
    let input = PDFCaptionInput(sequence: 1, total: 1, width: 1, height: 1, byteCount: 0)
    let lines = PDFCaptions.lines(
      for: input, fields: [.customText], customText: "  First \n\n\nSecond\r\n   ")
    #expect(lines == ["First", "Second"])
  }

  @Test("the tags are read from the EXIF and TIFF tags of the picture")
  func readsTags() throws {
    let exif: [CFString: Any] = [
      kCGImagePropertyExifDateTimeOriginal: "2024:05:01 12:00:00",
      kCGImagePropertyExifExposureTime: 0.004,
      kCGImagePropertyExifFNumber: 1.8,
      kCGImagePropertyExifISOSpeedRatings: [400],
      kCGImagePropertyExifLensModel: "RF 35mm",
    ]
    let tiff: [CFString: Any] = [
      kCGImagePropertyTIFFMake: "Canon",
      kCGImagePropertyTIFFModel: "EOS R6",
    ]
    let read = PDFPictureExif.read(from: try Self.jpeg(exif: exif, tiff: tiff))
    #expect(read.make == "Canon")
    #expect(read.model == "EOS R6")
    #expect(read.lensModel == "RF 35mm")
    #expect(read.iso == 400)
    #expect(read.dateTimeOriginal == "2024:05:01 12:00:00")
    #expect(abs((read.exposureTime ?? 0) - 0.004) < 0.0001)
    #expect(abs((read.fNumber ?? 0) - 1.8) < 0.001)
  }

  @Test("data that is not a picture has no tags")
  func unreadableDataHasNoTags() {
    #expect(PDFPictureExif.read(from: Data("not a picture".utf8)) == PDFPictureExif())
  }
}
