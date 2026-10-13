import Foundation
import Testing

@testable import ImageToolboxKit

// Layouts of the Sketch, Simple Color Palette, Infinite Painter and Procreate palettes, checked
// against the kotlinx.serialization output of the Android coders.

@Suite("Android layout: Sketch, Simple, Infinite Painter and Procreate palettes")
struct PaletteAndroidLayoutTestsJSONApps {

  @Test("Sketch writer writes compact JSON with the Android key order and null names")
  func sketchWriterLayout() {
    let data = SketchPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255, alpha: 128),
    ])
    let expected =
      "{\"compatibleVersion\":\"1.4\",\"pluginVersion\":\"1.4\",\"colors\":["
      + "{\"name\":\"Red\",\"red\":1.0,\"green\":0.0,\"blue\":0.0,\"alpha\":1.0},"
      + "{\"name\":null,\"red\":0.0,\"green\":0.5019607843137255,\"blue\":1.0,"
      + "\"alpha\":0.5019607843137255}]}"
    #expect(String(decoding: data, as: UTF8.self) == expected)
  }

  @Test("Simple palette writer writes indented JSON with linear components and null names")
  func simpleWriterLayout() {
    let data = SimplePaletteCoder.encode([PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
    let expected =
      "{\n"
      + "    \"name\": null,\n"
      + "    \"colors\": [\n"
      + "        {\n"
      + "            \"name\": \"Red\",\n"
      + "            \"components\": [\n"
      + "                1.0,\n"
      + "                0.0,\n"
      + "                0.0\n"
      + "            ]\n"
      + "        }\n"
      + "    ]\n"
      + "}"
    #expect(String(decoding: data, as: UTF8.self) == expected)
  }

  @Test("Simple palette reader converts linear components to sRGB and keeps the alpha")
  func simpleReaderOnAndroidBytes() throws {
    let file =
      "{\"name\":\"Demo\",\"colors\":[{\"name\":\"Red\",\"components\":[1.0,0.0,0.0]},"
      + "{\"components\":[0.2158605,0.2158605,0.2158605,0.5]}]}"
    let colours = try SimplePaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 128, green: 128, blue: 128, alpha: 128),
      ])
  }

  @Test("Infinite Painter writer writes indented signed ARGB values and an empty name")
  func infinitePainterWriterLayout() {
    let data = InfinitePainterPaletteCoder.encode([
      PaletteColour(red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 1),
    ])
    let expected =
      "{\n"
      + "    \"colors\": [\n"
      + "        -65536,\n"
      + "        -16777215\n"
      + "    ],\n"
      + "    \"name\": \"\"\n"
      + "}"
    #expect(String(decoding: data, as: UTF8.self) == expected)
  }

  @Test("Infinite Painter reader takes signed ARGB values with their alpha")
  func infinitePainterReaderOnAndroidBytes() throws {
    let file = "{\"colors\":[-16777216,-1,-65536],\"name\":\"X\"}"
    let colours = try InfinitePainterPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(red: 0, green: 0, blue: 0),
        PaletteColour(red: 255, green: 255, blue: 255),
        PaletteColour(red: 255, green: 0, blue: 0),
      ])
  }

  @Test("Procreate writer writes the palette array with HSB swatches and the null fields")
  func procreateWriterLayout() throws {
    let data = ProcreateSwatchesPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 0, alpha: 128),
    ])
    let entries = try ZipReader.entries(in: data) { $0 == "Swatches.json" }
    let json = try #require(entries.first).data
    let swatch =
      "\"colorSpace\":null,\"origin\":null,\"colorModel\":null,"
      + "\"colorProfile\":null,\"version\":null,\"components\":null}"
    let expected =
      "[{\"name\":\"\",\"swatches\":["
      + "{\"name\":\"Red\",\"hue\":0.0,\"saturation\":1.0,\"brightness\":1.0,\"alpha\":1.0,"
      + swatch + ","
      + "{\"name\":null,\"hue\":0.0,\"saturation\":0.0,\"brightness\":0.0,"
      + "\"alpha\":0.5019607843137255," + swatch + "]}]"
    #expect(String(decoding: json, as: UTF8.self) == expected)
  }

  @Test("Procreate reader reads an Android Swatches.json with null optional fields")
  func procreateReaderOnAndroidBytes() throws {
    let json =
      "[{\"name\":\"Pal\",\"swatches\":[{\"name\":\"Red\",\"hue\":0.0,\"saturation\":1.0,"
      + "\"brightness\":1.0,\"alpha\":1.0,\"colorSpace\":null,\"origin\":null,"
      + "\"colorModel\":null,\"colorProfile\":null,\"version\":null,\"components\":null}]}]"
    let archive = try ZipWriter.archive([
      ZipWriter.Entry(name: "Swatches.json", data: Data(json.utf8))
    ])
    let colours = try ProcreateSwatchesPaletteCoder.decode(archive)
    #expect(colours == [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)])
  }
}
