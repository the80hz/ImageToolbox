import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Collage settings")
struct CollageSettingsTests {

  /// A throwaway defaults suite, so the tests never touch the app's own preferences.
  private static func defaults() throws -> UserDefaults {
    let suite = try #require(UserDefaults(suiteName: "CollageSettingsTests.\(UUID().uuidString)"))
    return suite
  }

  @Test("settings that were saved load back unchanged")
  func roundTrip() throws {
    let defaults = try Self.defaults()
    let saved = CollageSettings(
      aspectWidth: 9, aspectHeight: 16, exportScale: 0.8, gap: 12, margin: 20, fill: .radial,
      startColour: "#112233", endColour: "#44556677", gradientAngle: 90, borderWidth: 4,
      borderColour: "#FF0000")
    saved.save(to: defaults)
    #expect(CollageSettings.load(from: defaults) == saved)
  }

  @Test("nothing stored gives the defaults, and so does a value that does not decode")
  func defaultsWhenUnreadable() throws {
    let defaults = try Self.defaults()
    #expect(CollageSettings.load(from: defaults) == CollageSettings())
    defaults.set(Data("not json".utf8), forKey: CollageSettings.defaultsKey)
    #expect(CollageSettings.load(from: defaults) == CollageSettings())
  }

  @Test("values outside the range of the tool are brought back into it")
  func clamping() {
    let wild = CollageSettings(
      aspectWidth: -2, aspectHeight: 0, exportScale: 3, gap: 90, margin: -5, fill: .linear,
      startColour: "nope", endColour: "#ABCDEF", gradientAngle: 900, borderWidth: 99,
      borderColour: "#00000080")
    let fixed = wild.clamped
    #expect(fixed.aspectWidth == 1 && fixed.aspectHeight == 1)
    #expect(fixed.exportScale == 1)
    #expect(fixed.gap == 40)
    #expect(fixed.margin == 0)
    #expect(fixed.gradientAngle == 360)
    #expect(fixed.borderWidth == 30)
    #expect(fixed.startColour == "#FFFFFF")
    #expect(fixed.endColour == "#ABCDEF")
    #expect(fixed.borderColour == "#00000080")
  }

  @Test("the background and border follow the stored colours and fill")
  func looksFollowSettings() {
    let linear = CollageSettings(
      fill: .linear, startColour: "#FF0000", endColour: "#0000FF", gradientAngle: 45)
    #expect(
      linear.background
        == .linearGradient(
          from: RGBA(red: 255, green: 0, blue: 0), to: RGBA(red: 0, green: 0, blue: 255),
          angle: 45))
    #expect(CollageSettings().background == .solid(RGBA(red: 255, green: 255, blue: 255)))
    let framed = CollageSettings(borderWidth: 3, borderColour: "#102030")
    #expect(framed.border == CollageBorder(width: 3, color: RGBA(red: 16, green: 32, blue: 48)))
    #expect(CollageSettings().border.isVisible == false)
  }

  @Test("the aspect of the settings is the Android preset it stores")
  func aspect() {
    #expect(
      CollageSettings(aspectWidth: 9, aspectHeight: 16).aspect
        == CollageExportSize.Aspect(width: 9, height: 16))
  }
}
