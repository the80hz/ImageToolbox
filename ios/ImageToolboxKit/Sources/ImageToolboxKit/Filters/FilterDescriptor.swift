import Foundation

/// What the app shows about a filter before it runs: its name, section, settings and how to build it.
public struct FilterDescriptor: Sendable {
  /// The Android class name, such as `GaussianBlurFilter`. Templates store it, so it must not change.
  public let id: String
  /// Localization key of the name. It is the Android string resource name.
  public let titleKey: String
  public let category: FilterCategory
  public let engine: FilterEngine
  public let parameters: [FilterParameter]
  /// Extra words the add-filter search matches, besides the name.
  public let keywords: [String]
  private let make: @Sendable (FilterValues) -> any Filter

  public init(
    id: String,
    titleKey: String,
    category: FilterCategory,
    engine: FilterEngine,
    parameters: [FilterParameter] = [],
    keywords: [String] = [],
    make: @escaping @Sendable (FilterValues) -> any Filter
  ) {
    self.id = id
    self.titleKey = titleKey
    self.category = category
    self.engine = engine
    self.parameters = parameters
    self.keywords = keywords
    self.make = make
  }

  /// Builds the filter from settings that are already normalised.
  func build(_ values: FilterValues) -> any Filter {
    make(values)
  }
}
