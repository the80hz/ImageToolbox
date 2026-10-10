import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("JSON and zipped palette formats: Sketch, Simple, Infinite Painter and Procreate")
struct PaletteJSONFormatsTests {

  private static let sample: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255, alpha: 128),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
  ]

  /// The largest difference between two colours in any channel, including alpha.
  private static func largestDifference(_ lhs: PaletteColour, _ rhs: PaletteColour) -> Int {
    [
      abs(Int(lhs.red) - Int(rhs.red)), abs(Int(lhs.green) - Int(rhs.green)),
      abs(Int(lhs.blue) - Int(rhs.blue)), abs(Int(lhs.alpha) - Int(rhs.alpha)),
    ].max() ?? 0
  }

  @Test("Sketch round trip keeps names, colours and alpha")
  func sketchRoundTrip() throws {
    #expect(try SketchPaletteCoder.decode(SketchPaletteCoder.encode(Self.sample)) == Self.sample)
  }

  @Test("Sketch reads the version fields and colours without names")
  func sketchDecode() throws {
    let json = """
      {"compatibleVersion":"1.4","pluginVersion":"1.4",
       "colors":[{"red":1,"green":0,"blue":0,"alpha":1}]}
      """
    #expect(
      try SketchPaletteCoder.decode(Data(json.utf8)) == [PaletteColour(red: 255, green: 0, blue: 0)]
    )
  }

  @Test("Simple Color Palette converts linear components to sRGB")
  func simpleDecode() throws {
    let json = """
      {"name":"Demo","colors":[{"name":"Mid","components":[0.2158,0.2158,0.2158]}]}
      """
    let colours = try SimplePaletteCoder.decode(Data(json.utf8))
    #expect(colours.count == 1)
    #expect(colours[0].name == "Mid")
    #expect(abs(Int(colours[0].red) - 128) <= 1)
    #expect(colours[0].red == colours[0].green && colours[0].green == colours[0].blue)
  }

  @Test("Simple Color Palette round trip stays within one step of each channel")
  func simpleRoundTrip() throws {
    let colours = try SimplePaletteCoder.decode(SimplePaletteCoder.encode(Self.sample))
    #expect(colours.map(\.name) == Self.sample.map(\.name))
    for (decoded, original) in zip(colours, Self.sample) {
      #expect(Self.largestDifference(decoded, original) <= 1)
    }
  }

  @Test("Infinite Painter reads signed ARGB values, as the Android coder does")
  func infinitePainterDecode() throws {
    let json = #"{"colors": [-16777216, -1, -65536, -16711936, -16776961], "name": "Basic"}"#
    let colours = try InfinitePainterPaletteCoder.decode(Data(json.utf8))
    #expect(
      colours == [
        PaletteColour(red: 0, green: 0, blue: 0),
        PaletteColour(red: 255, green: 255, blue: 255),
        PaletteColour(red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 255, blue: 0),
        PaletteColour(red: 0, green: 0, blue: 255),
      ])
  }

  @Test("Infinite Painter writes opaque signed ARGB values")
  func infinitePainterEncode() {
    let text = String(
      decoding: InfinitePainterPaletteCoder.encode([
        PaletteColour(red: 255, green: 0, blue: 0, alpha: 0)
      ]),
      as: UTF8.self)
    #expect(text.contains("-65536"))
    #expect(text.contains("\"name\""))
  }

  @Test("Procreate writes HSB swatches inside Swatches.json in a zip archive")
  func procreateLayout() throws {
    let data = ProcreateSwatchesPaletteCoder.encode([PaletteColour(red: 255, green: 0, blue: 0)])
    let entries = try ZipReader.entries(in: data) { _ in true }
    #expect(entries.map(\.name) == ["Swatches.json"])
    let text = String(decoding: entries[0].data, as: UTF8.self)
    #expect(text.contains("\"hue\":0"))
    #expect(text.contains("\"brightness\":1"))
  }

  @Test("Procreate round trip keeps names, and colours to within one step")
  func procreateRoundTrip() throws {
    let colours = try ProcreateSwatchesPaletteCoder.decode(
      ProcreateSwatchesPaletteCoder.encode(Self.sample))
    #expect(colours.map(\.name) == Self.sample.map(\.name))
    for (decoded, original) in zip(colours, Self.sample) {
      #expect(Self.largestDifference(decoded, original) <= 1)
    }
  }

  @Test("Procreate reads a single palette object as well as a list")
  func procreateSinglePalette() throws {
    let json = #"{"name":"One","swatches":[null,{"hue":0,"saturation":1,"brightness":1}]}"#
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "Swatches.json", data: Data(json.utf8))
    ])
    #expect(
      try ProcreateSwatchesPaletteCoder.decode(archive) == [
        PaletteColour(red: 255, green: 0, blue: 0)
      ])
  }
}
