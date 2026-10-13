import Foundation

/// How several frames become one picture.
public enum FusionMode: CaseIterable, Sendable {
  /// Exposure fusion (Mertens): each pixel comes mostly from the frame where it is well exposed,
  /// sharp and saturated.
  case exposure
  /// Focus stacking: each pixel comes mostly from the frame where it is sharpest.
  case focus
  /// The median of the frames, pixel by pixel. Moving objects drop out.
  case median
  /// The average of the frames in linear light, as a long exposure gathers light.
  case longExposure
  /// The brightest value of each pixel is kept where it is brighter than the average, so light
  /// streaks stay.
  case lightTrails
  /// The frames are averaged with newer frames weighted more, so moving objects leave trails.
  case motionTrails
}

/// Settings of a fusion. Ranges follow the Android app. `normalized()` clamps values into them.
public struct FusionParams: Equatable, Sendable {
  public static let minimumImages = 2
  public static let maximumImages = 12

  public var mode: FusionMode
  /// Aligns the frames to the first one with a homography before fusing.
  public var alignImages: Bool
  /// Crops to the area that every aligned frame covers, so no frame shows an empty border.
  public var cropToOverlap: Bool
  public var contrastWeight: Double
  public var saturationWeight: Double
  public var exposureWeight: Double
  /// Odd kernel size of the blur that spreads the sharpness measure (focus stacking).
  public var focusRadius: Int
  public var focusStrength: Double
  public var lightTrailThreshold: Double
  public var trailStrength: Double
  public var trailPersistence: Double

  public init(
    mode: FusionMode = .exposure,
    alignImages: Bool = true,
    cropToOverlap: Bool = true,
    contrastWeight: Double = 1,
    saturationWeight: Double = 1,
    exposureWeight: Double = 1,
    focusRadius: Int = 7,
    focusStrength: Double = 2,
    lightTrailThreshold: Double = 0.08,
    trailStrength: Double = 1,
    trailPersistence: Double = 0.7
  ) {
    self.mode = mode
    self.alignImages = alignImages
    self.cropToOverlap = cropToOverlap
    self.contrastWeight = contrastWeight
    self.saturationWeight = saturationWeight
    self.exposureWeight = exposureWeight
    self.focusRadius = focusRadius
    self.focusStrength = focusStrength
    self.lightTrailThreshold = lightTrailThreshold
    self.trailStrength = trailStrength
    self.trailPersistence = trailPersistence
  }

  /// The same settings with every value inside its range. The focus radius is odd.
  public func normalized() -> FusionParams {
    var result = self
    result.contrastWeight = min(max(contrastWeight, 0), 2)
    result.saturationWeight = min(max(saturationWeight, 0), 2)
    result.exposureWeight = min(max(exposureWeight, 0), 2)
    var radius = min(max(focusRadius, 1), 21)
    if radius % 2 == 0 { radius += 1 }
    result.focusRadius = min(radius, 21)
    result.focusStrength = min(max(focusStrength, 1), 6)
    result.lightTrailThreshold = min(max(lightTrailThreshold, 0), 0.5)
    result.trailStrength = min(max(trailStrength, 0), 1)
    result.trailPersistence = min(max(trailPersistence, 0.1), 1)
    return result
  }
}
