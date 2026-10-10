import Foundation

/// Everything the curve tool applies to a picture. The stages run in the order the Android app runs
/// them: RGB tone curves, CMYK, Lab, hue/saturation/value curves, then the colour wheels.
public struct CurveAdjustments: Equatable, Sendable {
  public var curves: CurveSet
  public var cmyk: CMYKCurves
  public var lab: LabCurves
  public var relations: RelationCurves
  public var wheels: ColorWheels

  public init(
    curves: CurveSet = .identity,
    cmyk: CMYKCurves = CMYKCurves(),
    lab: LabCurves = LabCurves(),
    relations: RelationCurves = RelationCurves(),
    wheels: ColorWheels = .identity
  ) {
    self.curves = curves
    self.cmyk = cmyk
    self.lab = lab
    self.relations = relations
    self.wheels = wheels
  }

  /// True when no stage changes a pixel.
  public var isIdentity: Bool {
    curves == .identity && cmyk.isIdentity && lab.isIdentity && relations.isIdentity
      && wheels.isIdentity
  }
}
