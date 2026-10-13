import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Filter registry: ids, defaults and normalisation")
struct FilterRegistryTests {

  @Test("every filter id is unique and names an Android filter class")
  func idsAreUnique() {
    let ids = FilterRegistry.descriptors.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids.allSatisfy { $0.hasSuffix("Filter") })
  }

  @Test("every number parameter has a default inside its range and a positive step")
  func defaultsAreInRange() {
    for descriptor in FilterRegistry.descriptors {
      for parameter in descriptor.parameters {
        guard case .number(let range, let step, let fallback) = parameter.kind else { continue }
        #expect(range.contains(fallback), "\(descriptor.id).\(parameter.key)")
        #expect(step > 0, "\(descriptor.id).\(parameter.key)")
      }
    }
  }

  @Test("an unknown id is reported, not silently skipped")
  func unknownFilter() {
    #expect(throws: FilterError.self) {
      _ = try FilterRegistry.make(FilterStep(id: "NoSuchFilter"))
    }
    #expect(FilterRegistry.descriptor(for: "NoSuchFilter") == nil)
  }

  @Test("a missing number takes the default")
  func missingUsesDefault() throws {
    let descriptor = try #require(FilterRegistry.descriptor(for: "ContrastFilter"))
    let values = FilterRegistry.values(for: FilterStep(id: descriptor.id), of: descriptor)
    #expect(values.number("value") == 2)
  }

  @Test("a number outside the range is clamped to the nearest bound")
  func outOfRangeIsClamped() throws {
    let descriptor = try #require(FilterRegistry.descriptor(for: "ContrastFilter"))
    let high = FilterStep(id: descriptor.id, values: ["value": .number(9)])
    let low = FilterStep(id: descriptor.id, values: ["value": .number(-9)])
    #expect(FilterRegistry.values(for: high, of: descriptor).number("value") == 2)
    #expect(FilterRegistry.values(for: low, of: descriptor).number("value") == 0)
  }

  @Test("a NaN number takes the default, not a bound")
  func nanTakesDefault() throws {
    let descriptor = try #require(FilterRegistry.descriptor(for: "BrightnessFilter"))
    let step = FilterStep(id: descriptor.id, values: ["value": .number(.nan)])
    #expect(FilterRegistry.values(for: step, of: descriptor).number("value") == 0.5)
  }

  @Test("a value of the wrong kind takes the default")
  func wrongKindUsesDefault() throws {
    let descriptor = try #require(FilterRegistry.descriptor(for: "ContrastFilter"))
    let step = FilterStep(id: descriptor.id, values: ["value": .flag(true)])
    #expect(FilterRegistry.values(for: step, of: descriptor).number("value") == 2)
  }

  @Test("every filter survives its parameter extremes on a 1x1 and a small picture")
  func survivesExtremes() async throws {
    let pictures = [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ]
    for descriptor in FilterRegistry.descriptors {
      var steps = [FilterStep(id: descriptor.id)]
      for parameter in descriptor.parameters {
        guard case .number(let range, _, _) = parameter.kind else { continue }
        steps.append(
          FilterStep(id: descriptor.id, values: [parameter.key: .number(range.lowerBound)]))
        steps.append(
          FilterStep(id: descriptor.id, values: [parameter.key: .number(range.upperBound)]))
      }
      for step in steps {
        for picture in pictures {
          let output = try await FilterChain(steps: [step]).apply(to: picture)
          #expect(output.width == picture.width, "\(descriptor.id) width")
          #expect(output.height == picture.height, "\(descriptor.id) height")
          #expect(output.pixels.count == picture.pixels.count, "\(descriptor.id) pixels")
        }
      }
    }
  }
}
