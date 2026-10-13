import Foundation
import Testing

@testable import ImageToolboxKit

// Layout of the JSON palette format, checked against the kotlinx.serialization output of the
// Android classes. The random "id" values are replaced before the text is compared.

@Suite("Android layout: JSON palettes")
struct PaletteAndroidLayoutTestsJSON {

  /// The text with every "id" value replaced by a fixed word.
  private static func withoutIDs(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self).replacingOccurrences(
      of: ##""id":"[^"]*""##, with: ##""id":"ID""##, options: .regularExpression)
  }

  @Test("JSON writer orders the keys as the Android classes do and keeps decimal points")
  func jsonWriterLayout() {
    let data = JSONPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 0, alpha: 128),
    ])
    let expected =
      ##"{"colors":[{"name":"Red","colorSpace":"RGB","colorComponents":[1.0,0.0,0.0],"id":"ID"},"##
      + ##"{"colorSpace":"RGB","colorComponents":[0.0,0.0,0.0],"alpha":0.5019607843137255,"id":"ID"}],"##
      + ##""id":"ID"}"##
    #expect(Self.withoutIDs(data) == expected)
  }

  @Test("JSON writer writes an empty palette as an object with only its id")
  func jsonEmptyPalette() {
    #expect(Self.withoutIDs(JSONPaletteCoder.encode([])) == ##"{"id":"ID"}"##)
  }

  @Test("JSON reader accepts Android output with a colour type, a group and unknown keys")
  func jsonReaderOnAndroidBytes() throws {
    let file =
      ##"{"name":"Pal","colors":[{"name":"Red","colorType":"Global","colorSpace":"RGB","##
      + ##""colorComponents":[1.0,0.0,0.0],"alpha":1.0,"id":"8f2c"}],"##
      + ##""groups":[{"id":"g1","name":"G","colors":[{"colorSpace":"CMYK","##
      + ##""colorComponents":[0.0,0.0,0.0,1.0],"id":"c2"}]}],"id":"p1"}"##
    let colours = try JSONPaletteCoder.decode(Data(file.utf8))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(red: 0, green: 0, blue: 0),
      ])
  }
}
