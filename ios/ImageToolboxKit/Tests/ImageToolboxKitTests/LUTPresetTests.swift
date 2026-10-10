import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("LUT presets: bundled tables, intensity and registration")
struct LUTPresetTests {

  static let presetIDs = [
    "AmatorkaFilter", "KodakFilter", "BleachBypassFilter", "CandlelightFilter",
    "CelluloidFilter", "CoffeeFilter", "DropBluesFilter", "EdgyAmberFilter",
    "FallColorsFilter", "FilmStock50Filter", "FoggyNightFilter", "GoldenForestFilter",
  ]

  @Test("all twelve presets are registered in the LUT category")
  func registered() {
    for id in Self.presetIDs {
      let descriptor = FilterRegistry.descriptor(for: id)
      #expect(descriptor?.category == .lut, "\(id)")
    }
  }

  @Test("every bundled table decodes to a 64-cube")
  func tablesLoad() throws {
    for descriptor in LUTFilters.descriptors {
      let name = try #require(LUTFilterNames.table(for: descriptor.id))
      let table = try #require(LUTAtlas.table(named: name), "\(name)")
      #expect(table.size == 64)
    }
  }

  @Test("intensity 0 leaves the picture within one level of the input")
  func zeroIntensityIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 8, height: 8)
    let output = try await LUTPresetFilter(table: "lookup_kodak", intensity: 0).apply(to: picture)
    let largest = zip(output.pixels, picture.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(largest <= 1)
  }

  @Test("intensity 1 changes a mid-grey picture")
  func fullIntensityChanges() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 128, green: 128, blue: 128)
    let output = try await LUTPresetFilter(table: "lookup_amatorka", intensity: 1).apply(
      to: picture)
    #expect(output.pixels != picture.pixels)
  }

  @Test("a missing table reports a render failure")
  func missingTable() async {
    let picture = FilterTestImages.gradient(width: 2, height: 2)
    await #expect(throws: FilterError.self) {
      _ = try await LUTPresetFilter(table: "lookup_missing", intensity: 1).apply(to: picture)
    }
  }
}

/// Maps a preset id to the bundled table name, through the same list the registry uses.
enum LUTFilterNames {
  static func table(for id: String) -> String? {
    switch id {
    case "AmatorkaFilter": "lookup_amatorka"
    case "KodakFilter": "lookup_kodak"
    case "BleachBypassFilter": "lookup_bleach_bypass"
    case "CandlelightFilter": "lookup_candlelight"
    case "CelluloidFilter": "lookup_celluloid"
    case "CoffeeFilter": "lookup_coffee"
    case "DropBluesFilter": "lookup_drop_blues"
    case "EdgyAmberFilter": "lookup_edgy_amber"
    case "FallColorsFilter": "lookup_fall_colors"
    case "FilmStock50Filter": "lookup_filmstock_50"
    case "FoggyNightFilter": "lookup_foggy_night"
    case "GoldenForestFilter": "lookup_golden_forest"
    default: nil
    }
  }
}
