import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Filter chains and templates: order, editing and serialisation")
struct FilterChainTests {

  @Test("a chain survives a JSON round trip unchanged")
  func chainRoundTrip() throws {
    let chain = FilterChain(steps: [
      FilterStep(id: "BrightnessFilter", values: ["value": .number(0.25)]),
      FilterStep(id: "NegativeFilter"),
      FilterStep(id: "ContrastFilter", values: ["value": .number(1.5)]),
    ])
    let data = try JSONEncoder().encode(chain)
    let decoded = try JSONDecoder().decode(FilterChain.self, from: data)
    #expect(decoded == chain)
  }

  @Test("a template survives its sorted-key JSON form, and the bytes repeat")
  func templateRoundTrip() throws {
    let template = FilterTemplate(
      name: "Warm",
      chain: FilterChain(steps: [
        FilterStep(id: "ContrastFilter", values: ["value": .number(0.75)]),
        FilterStep(id: "BrightnessFilter", values: ["value": .number(-0.1)]),
      ]))
    let first = try template.encoded()
    #expect(try FilterTemplate.decode(first) == template)
    #expect(try template.encoded() == first)
  }

  @Test("append, move and remove keep the order the user sees")
  func editing() {
    var chain = FilterChain()
    chain.append(FilterStep(id: "A"))
    chain.append(FilterStep(id: "B"))
    chain.append(FilterStep(id: "C"))
    chain.move(from: 2, to: 0)
    #expect(chain.steps.map(\.id) == ["C", "A", "B"])
    chain.remove(at: 1)
    #expect(chain.steps.map(\.id) == ["C", "B"])
  }

  @Test("out-of-range edits are ignored")
  func outOfRangeEdits() {
    var chain = FilterChain(steps: [FilterStep(id: "A")])
    chain.remove(at: 5)
    chain.move(from: 0, to: 9)
    chain.setValue(.number(1), forKey: "value", at: 4)
    #expect(chain.steps.map(\.id) == ["A"])
    #expect(chain.steps[0].values.isEmpty)
  }

  @Test("an empty chain returns the picture unchanged")
  func emptyChainIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 4, height: 4)
    let output = try await FilterChain().apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("steps run in list order")
  func order() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 64, green: 64, blue: 64)
    let negativeFirst = FilterChain(steps: [
      FilterStep(id: "NegativeFilter"),
      FilterStep(id: "ContrastFilter", values: ["value": .number(0)]),
    ])
    let contrastFirst = FilterChain(steps: [
      FilterStep(id: "ContrastFilter", values: ["value": .number(0)]),
      FilterStep(id: "NegativeFilter"),
    ])
    let a = try await negativeFirst.apply(to: picture)
    let b = try await contrastFirst.apply(to: picture)
    // Gain 0 turns every channel into middle grey, 127 as Aire truncates 127.5.
    // Negative first: 64 -> 191 -> 127. Grey first: 127 -> 255 - 127 = 128.
    #expect(a.pixels[0] == 127)
    #expect(b.pixels[0] == 128)
  }

  @Test("an unknown step fails the whole chain")
  func unknownStepFailsChain() async {
    let chain = FilterChain(steps: [FilterStep(id: "NoSuchFilter")])
    await #expect(throws: FilterError.self) {
      _ = try await chain.apply(to: FilterTestImages.gradient(width: 2, height: 2))
    }
  }
}
