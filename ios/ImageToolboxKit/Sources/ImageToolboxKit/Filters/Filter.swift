import Foundation

/// One image operation with its settings applied. `FilterRegistry` builds it from a `FilterStep`.
public protocol Filter: Sendable {
  /// Returns a new picture of the same size. Pixels are premultiplied RGBA, as in `RasterImage`.
  func apply(to image: RasterImage) async throws -> RasterImage
}

/// The section of the add-filter sheet a filter belongs to.
public enum FilterCategory: String, CaseIterable, Sendable {
  case lightAndColour
  case blur
  case sharpenAndNoise
  case colourMatrix
  case lut
  case dithering
  case morphology
  case toneMapping
  case histogram
  case distortion
  case glitchAndCRT
}

/// The library a filter's pixels come from. A filter uses one engine only.
public enum FilterEngine: String, Sendable {
  case coreImage
  case metal
  case cpu
}

/// Errors from building or running a filter chain.
public enum FilterError: Error, Equatable, Sendable {
  /// A step names a filter that is not in `FilterRegistry`.
  case unknownFilter(String)
  /// The engine could not produce an image, for example Core Image failed to render.
  case renderFailed(String)
}
