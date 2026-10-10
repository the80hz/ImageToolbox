import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Core Image bridge keeps pixels exact")
struct CoreImageBridgeTests {

  @Test("rendering without a change returns the same pixels, row order included")
  func identityRoundTrip() throws {
    let picture = FilterTestImages.gradient(width: 7, height: 5)
    let rendered = try CoreImageBridge.render(picture, filterID: "test") { $0 }
    #expect(rendered.width == 7)
    #expect(rendered.height == 5)
    #expect(rendered.pixels == picture.pixels)
  }
}
