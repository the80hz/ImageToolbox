import Foundation

/// Every filter the app knows, by id. Chains and templates refer to filters only through this table.
public enum FilterRegistry {

  /// Every descriptor. Within a category, the add-filter sheet keeps this order.
  public static let descriptors: [FilterDescriptor] =
    LightColourFilters.descriptors
    + BlurFilters.descriptors
    + SharpenNoiseFilters.descriptors
    + ColourMatrixFilters.descriptors
    + LUTFilters.descriptors
    + DitheringFilters.descriptors
    + OrderedDitheringFilters.descriptors
    + MorphologyFilters.descriptors
    + ToneMappingFilters.descriptors
    + HistogramFilters.descriptors
    + ClaheFilters.descriptors
    + DistortionFilters.descriptors
    + GlitchCRTFilters.descriptors

  /// Lookup by id. If two descriptors share an id, the first wins; a test reports the duplicate.
  private static let byID: [String: FilterDescriptor] = Dictionary(
    descriptors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

  public static func descriptor(for id: String) -> FilterDescriptor? {
    byID[id]
  }

  /// Builds the filter for a step. Missing or out-of-range settings fall back as `values(for:of:)` does.
  public static func make(_ step: FilterStep) throws -> any Filter {
    guard let descriptor = byID[step.id] else {
      throw FilterError.unknownFilter(step.id)
    }
    return descriptor.build(values(for: step, of: descriptor))
  }

  /// The settings a step runs with: each parameter's stored value, normalised, or its default.
  public static func values(for step: FilterStep, of descriptor: FilterDescriptor) -> FilterValues {
    var storage: [String: FilterValue] = [:]
    for parameter in descriptor.parameters {
      storage[parameter.key] = parameter.normalized(step.values[parameter.key])
    }
    return FilterValues(storage: storage)
  }
}
