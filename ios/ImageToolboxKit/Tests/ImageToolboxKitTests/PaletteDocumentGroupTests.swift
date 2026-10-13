import Foundation
import Testing

@testable import ImageToolboxKit

// Groups and colour types in the formats that keep them: Adobe Swatch Exchange, ColorPaletteCodable
// binary and the JSON the Android app writes. The byte layouts follow the Android coders.

@Suite("Palette documents: groups and colour types")
struct PaletteDocumentGroupTests {

  private static let spot = PaletteColour(
    name: "S", red: 0, green: 0, blue: 255, colourType: .spot)

  @Test("ASE writes the global colours first, then each group between its start and end blocks")
  func aseWritesGroupBlocks() {
    let document = PaletteDocument(
      colours: [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)],
      groups: [PaletteColourGroup(name: "G", colours: [Self.spot])])
    let expected: [UInt8] = [
      0x41, 0x53, 0x45, 0x46,  // "ASEF"
      0x00, 0x01, 0x00, 0x00,  // version 1.0
      0x00, 0x00, 0x00, 0x04,  // four blocks: two colours, one group start and one group end
      // Global "Red" with the global colour type.
      0x00, 0x01, 0x00, 0x00, 0x00, 0x1C,
      0x00, 0x04, 0x00, 0x52, 0x00, 0x65, 0x00, 0x64, 0x00, 0x00,
      0x52, 0x47, 0x42, 0x20,
      0x3F, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00,
      // Group start with the name "G": block length 6, then the name length and the name.
      0xC0, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x02, 0x00, 0x47, 0x00, 0x00,
      // Spot "S" inside the group: colour type 1.
      0x00, 0x01, 0x00, 0x00, 0x00, 0x18,
      0x00, 0x02, 0x00, 0x53, 0x00, 0x00,
      0x52, 0x47, 0x42, 0x20,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x80, 0x00, 0x00,
      0x00, 0x01,
      // Group end with an empty body.
      0xC0, 0x02, 0x00, 0x00, 0x00, 0x00,
    ]
    #expect(Array(ASEPaletteCoder.encodeDocument(document)) == expected)
  }

  @Test("ASE reads Android group blocks, group names and colour types")
  func aseReadsGroupsAndTypes() throws {
    let file: [UInt8] = [
      0x41, 0x53, 0x45, 0x46, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x04,  // four blocks
      0xC0, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x02, 0x00, 0x47, 0x00, 0x00,  // group "G"
      0x00, 0x01, 0x00, 0x00, 0x00, 0x18,
      0x00, 0x02, 0x00, 0x53, 0x00, 0x00,
      0x52, 0x47, 0x42, 0x20,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x80, 0x00, 0x00,
      0x00, 0x01,  // spot "S" inside the group
      0xC0, 0x02, 0x00, 0x00, 0x00, 0x00,  // group end
      0x00, 0x01, 0x00, 0x00, 0x00, 0x1C,
      0x00, 0x04, 0x00, 0x52, 0x00, 0x65, 0x00, 0x64, 0x00, 0x00,
      0x52, 0x47, 0x42, 0x20,
      0x3F, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x02,  // normal "Red" after the group, so it is a global colour
    ]
    let document = try ASEPaletteCoder.decodeDocument(Data(file))
    #expect(document.name == nil)
    #expect(document.colours.map(\.name) == ["Red"])
    #expect(document.colours.map(\.colourType) == [.normal])
    #expect(document.groups == [PaletteColourGroup(name: "G", colours: [Self.spot])])
  }

  @Test("ASE flat decoding lists the global colours first, then the group colours")
  func aseFlatOrder() throws {
    let document = PaletteDocument(
      colours: [PaletteColour(name: "A", red: 1, green: 2, blue: 3)],
      groups: [PaletteColourGroup(name: "G", colours: [Self.spot])])
    let colours = try ASEPaletteCoder.decode(ASEPaletteCoder.encodeDocument(document))
    #expect(colours == document.allColours)
  }

  @Test("ASE round trip keeps group names and every colour type")
  func aseRoundTrip() throws {
    let document = PaletteDocument(
      colours: [PaletteColour(name: "N", red: 9, green: 8, blue: 7, colourType: .normal)],
      groups: [
        PaletteColourGroup(name: "", colours: [Self.spot]),
        PaletteColourGroup(name: "Two", colours: []),
      ])
    let decoded = try ASEPaletteCoder.decodeDocument(ASEPaletteCoder.encodeDocument(document))
    #expect(decoded == document)
  }

  @Test("ASE rejects an unknown colour type and a group that opens inside a group")
  func aseRejectsInvalidStructure() {
    let unknownType: [UInt8] = [
      0x41, 0x53, 0x45, 0x46, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
      0x00, 0x01, 0x00, 0x00, 0x00, 0x1C,
      0x00, 0x01, 0x00, 0x00,
      0x52, 0x47, 0x42, 0x20,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x03,
    ]
    #expect(throws: PaletteFormatError.unknownColourType(3)) {
      try ASEPaletteCoder.decodeDocument(Data(unknownType))
    }
    let nestedGroup: [UInt8] = [
      0x41, 0x53, 0x45, 0x46, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
      0xC0, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00,
      0xC0, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00,
    ]
    #expect(throws: PaletteFormatError.invalidFormat) {
      try ASEPaletteCoder.decodeDocument(Data(nestedGroup))
    }
  }

  @Test("DCP keeps its groups, with the global colours as the first group")
  func dcpRoundTripKeepsGroups() throws {
    let document = PaletteDocument(
      name: "Set",
      colours: [PaletteColour(name: "A", red: 255, green: 0, blue: 0)],
      groups: [
        PaletteColourGroup(name: "Spots", colours: [Self.spot]),
        PaletteColourGroup(name: "Empty", colours: []),
      ])
    let decoded = try DCPPaletteCoder.decodeDocument(DCPPaletteCoder.encodeDocument(document))
    #expect(decoded == document)
  }

  @Test("DCP stores the colour type byte as 1 global, 2 spot and 3 normal")
  func dcpColourTypeBytes() throws {
    for (type, code) in [
      (PaletteColourType.global, UInt8(1)), (.spot, 2), (.normal, 3),
    ] {
      let data = DCPPaletteCoder.encodeDocument(
        PaletteDocument(colours: [PaletteColour(red: 1, green: 2, blue: 3, colourType: type)]))
      #expect(data.last == code)
      let decoded = try DCPPaletteCoder.decodeDocument(data)
      #expect(decoded.colours.map(\.colourType) == [type])
    }
  }

  @Test("JSON writes the palette name, the groups and the colour type the Android classes write")
  func jsonWritesStructure() throws {
    let document = PaletteDocument(
      name: "P",
      colours: [PaletteColour(name: "Red", red: 255, green: 0, blue: 0)],
      groups: [PaletteColourGroup(name: "G", colours: [Self.spot])])
    let object = try jsonObject(JSONPaletteCoder.encodeDocument(document))
    #expect(object["name"] as? String == "P")
    let colours = try #require(object["colors"] as? [[String: Any]])
    #expect(colours.count == 1)
    #expect(colours[0]["colorType"] == nil)
    #expect(colours[0]["name"] as? String == "Red")
    let groups = try #require(object["groups"] as? [[String: Any]])
    #expect(groups.count == 1)
    #expect(groups[0]["name"] as? String == "G")
    #expect(groups[0]["id"] != nil)
    let groupColours = try #require(groups[0]["colors"] as? [[String: Any]])
    #expect(groupColours[0]["colorType"] as? String == "Spot")
    let text = String(decoding: JSONPaletteCoder.encodeDocument(document), as: UTF8.self)
    #expect(text.hasPrefix(#"{"name":"P","colors":[{"name":"Red""#))
  }

  @Test("JSON reads the palette name, the groups and the colour type names")
  func jsonReadsStructure() throws {
    let json = """
      {"name":"Set","colors":[{"name":"A","colorType":"Normal","colorSpace":"RGB",
      "colorComponents":[1.0,0.0,0.0],"id":"x"}],"groups":[{"id":"y","name":"G",
      "colors":[{"colorSpace":"RGB","colorComponents":[0.0,0.0,1.0],"colorType":"Spot"}]}]}
      """
    let document = try JSONPaletteCoder.decodeDocument(Data(json.utf8))
    #expect(document.name == "Set")
    #expect(document.colours.map(\.colourType) == [.normal])
    let spot = PaletteColour(red: 0, green: 0, blue: 255, colourType: .spot)
    #expect(document.groups == [PaletteColourGroup(name: "G", colours: [spot])])
  }

  @Test("JSON rejects an unknown colour type name")
  func jsonRejectsUnknownType() {
    let json = #"{"colors":[{"colorType":"Metal","colorSpace":"RGB","colorComponents":[0,0,0]}]}"#
    #expect(throws: PaletteFormatError.invalidFormat) {
      try JSONPaletteCoder.decodeDocument(Data(json.utf8))
    }
  }

  /// The top-level JSON object of `data`.
  private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
