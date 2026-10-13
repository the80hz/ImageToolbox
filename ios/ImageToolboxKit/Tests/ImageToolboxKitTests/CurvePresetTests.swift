import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Curve presets: JSON, Lightroom XMP and lrtemplate, ACV")
struct CurvePresetTests {

  private static var sampleCurves: CurveSet {
    CurveSet(
      master: ToneCurve(points: [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.8), CurvePoint(x: 1, y: 1),
      ]),
      red: ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.5)])
    )
  }

  @Test("the ImageToolbox JSON preset round-trips every curve")
  func jsonRoundTrip() throws {
    let data = try CurvePresetCodec.encodeJSON(CurvePreset(curves: Self.sampleCurves))
    let decoded = try CurvePresetCodec.decode(data)
    #expect(decoded.curves.master.points.count == 3)
    #expect(abs(decoded.curves.master.value(at: 0.5) - 0.8) < 1e-9)
    #expect(abs(decoded.curves.red.value(at: 1) - 0.5) < 1e-9)
    #expect(decoded.curves.green == .identity)
  }

  @Test("the JSON preset round-trips the colour wheels")
  func jsonWheelsRoundTrip() throws {
    let wheels = ColorWheels(
      shadows: ColorWheelPoint(x: 0.3, y: -0.4), midtones: ColorWheelPoint(x: 0, y: 0),
      highlights: ColorWheelPoint(x: -0.2, y: 0.5), edges: 0.75)
    let data = try CurvePresetCodec.encodeJSON(CurvePreset(wheels: wheels))
    let decoded = try CurvePresetCodec.decode(data)
    #expect(decoded.wheels.shadows == wheels.shadows)
    #expect(decoded.wheels.highlights == wheels.highlights)
    #expect(abs(decoded.wheels.edges - 0.75) < 1e-12)
  }

  @Test("a preset without colour wheels reads as identity wheels")
  func missingWheels() throws {
    let text = #"{"format": "ImageToolbox Curves", "version": 1, "curves": [[[0, 0], [1, 1]]]}"#
    let decoded = try CurvePresetCodec.decode(Data(text.utf8))
    #expect(decoded.wheels == .identity)
  }

  @Test("the JSON preset names its format and version")
  func jsonHeader() throws {
    let data = try CurvePresetCodec.encodeJSON(CurvePreset(curves: Self.sampleCurves))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["format"] as? String == "ImageToolbox Curves")
    #expect(object["version"] as? Int == 1)
  }

  @Test("the Lightroom XMP preset round-trips with 0...255 points")
  func xmpRoundTrip() throws {
    let data = CurvePresetCodec.encodeXMP(CurvePreset(curves: Self.sampleCurves))
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("<crs:ToneCurvePV2012>"))
    #expect(text.contains("<rdf:li>128, 204</rdf:li>"))

    let decoded = try CurvePresetCodec.decode(data)
    // Lightroom stores whole numbers, so the round trip is exact to one step of 1/255.
    #expect(abs(decoded.curves.master.value(at: 0.5) - 0.8) <= 1.0 / 255)
  }

  @Test("an lrtemplate curve is read as master or RGB")
  func lrtemplate() throws {
    let text =
      "s = { ToneCurvePV2012 = { 0, 0, 128, 64, 255, 255 }, ToneCurvePV2012Blue = { 0, 0, 255, 128 } }"
    let decoded = try CurvePresetCodec.decode(Data(text.utf8))
    #expect(abs(decoded.curves.master.value(at: 128.0 / 255) - 64.0 / 255) < 1e-9)
    #expect(abs(decoded.curves.blue.value(at: 1) - 128.0 / 255) < 1e-9)
    #expect(decoded.curves.red == .identity)
  }

  @Test("an Adobe ACV master curve is read from big-endian (output, input) pairs")
  func acv() throws {
    // Version 4, one curve, two points: (input 0 -> output 0) and (input 255 -> output 128).
    let bytes: [UInt8] = [
      0x00, 0x04, 0x00, 0x01, 0x00, 0x02,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x80, 0x00, 0xFF,
    ]
    let decoded = try CurvePresetCodec.decode(Data(bytes))
    let table = decoded.curves.master.lookupTable()
    #expect(table[0] == 0)
    #expect(table[255] == 128)
  }

  @Test("empty data is not supported")
  func unsupportedInputs() {
    #expect(throws: CurvePresetCodec.DecodeError.unsupportedFormat) {
      try CurvePresetCodec.decode(Data())
    }
  }

  @Test("the preset inside a zip archive is read")
  func presetInZip() throws {
    let decoded = try CurvePresetCodec.decode(ZipReaderTests.deflatedArchive)
    #expect(abs(decoded.curves.master.value(at: 0.5) - 0.8) < 1e-9)
    #expect(abs(decoded.curves.green.value(at: 1) - 0.5) < 1e-9)
  }

  @Test("a zip archive without a preset file has no curves")
  func archiveWithoutPreset() {
    #expect(throws: CurvePresetCodec.DecodeError.noCurves) {
      try CurvePresetCodec.decode(ZipReaderTests.storedArchive)
    }
  }

  @Test("a JSON file with another format name is rejected")
  func wrongJSONFormat() {
    let text = #"{"format": "Other", "version": 1, "curves": [[[0, 0], [1, 1]]]}"#
    #expect(throws: CurvePresetCodec.DecodeError.unsupportedFormat) {
      try CurvePresetCodec.decode(Data(text.utf8))
    }
  }

  @Test("text without any curve is rejected")
  func noCurves() {
    #expect(throws: CurvePresetCodec.DecodeError.noCurves) {
      try CurvePresetCodec.decode(Data("nothing useful here".utf8))
    }
  }
}
