import Foundation

/// One filter in a chain: its id and the settings the user changed. Missing settings use the defaults.
public struct FilterStep: Codable, Equatable, Sendable {
  public let id: String
  public private(set) var values: [String: FilterValue]

  public init(id: String, values: [String: FilterValue] = [:]) {
    self.id = id
    self.values = values
  }

  public mutating func set(_ value: FilterValue, for key: String) {
    values[key] = value
  }
}

/// Filters applied one after another, in list order. Codable, so a chain can be saved as a template.
public struct FilterChain: Codable, Equatable, Sendable {
  public private(set) var steps: [FilterStep]

  public init(steps: [FilterStep] = []) {
    self.steps = steps
  }

  public mutating func append(_ step: FilterStep) {
    steps.append(step)
  }

  public mutating func remove(at index: Int) {
    guard steps.indices.contains(index) else { return }
    steps.remove(at: index)
  }

  /// Moves a step. `destination` is the index the step has after the move.
  public mutating func move(from source: Int, to destination: Int) {
    guard steps.indices.contains(source), steps.indices.contains(destination) else { return }
    let step = steps.remove(at: source)
    steps.insert(step, at: destination)
  }

  public mutating func setValue(_ value: FilterValue, forKey key: String, at index: Int) {
    guard steps.indices.contains(index) else { return }
    steps[index].set(value, for: key)
  }

  /// Puts every setting of a step back to its default.
  public mutating func resetValues(at index: Int) {
    guard steps.indices.contains(index) else { return }
    steps[index] = FilterStep(id: steps[index].id)
  }

  /// Runs every step in order. Throws `CancellationError` if the task is cancelled between steps.
  public func apply(to image: RasterImage) async throws -> RasterImage {
    var current = image
    for step in steps {
      try Task.checkCancellation()
      current = try await FilterRegistry.make(step).apply(to: current)
    }
    return current
  }
}

/// A named chain the user saves to reuse.
public struct FilterTemplate: Codable, Equatable, Sendable {
  public var name: String
  public var chain: FilterChain

  public init(name: String, chain: FilterChain) {
    self.name = name
    self.chain = chain
  }

  /// JSON with sorted keys, so the same template always gives the same bytes.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  public static func decode(_ data: Data) throws -> FilterTemplate {
    try JSONDecoder().decode(FilterTemplate.self, from: data)
  }
}
