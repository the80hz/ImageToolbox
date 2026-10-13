// Generated from TextureParams.kt and GmicTextureParams.kt. Do not edit by hand.

/// The classic filters of the Android catalogue: JHLabs filters and GMIC textures.
public enum ClassicKind: CaseIterable, Sendable {
  case brushedMetal
  case organicFibers
  case gmicReactionDiffusion
  case truchet
  case caustics
  case cellular
  case check
  case fbm
  case marble
  case plasma
  case quilt
  case wood
}

extension TexturePresets {
  /// Classic presets, in the order of the Android enum.
  static let classic: [TexturePreset] = [
    .classic(
      "BrushedMetal", .materials, .brushedMetal, scale: 1.0,
      colours: [0xFF88_8888],
      [
        TextureParameter("radius", 10.0, 0.0...50.0),
        TextureParameter("amount", 0.1, 0.0...1.0),
        TextureParameter("shine", 0.1, 0.0...1.0),
      ]
    ),
    .classic(
      "OrganicFibers", .abstract, .organicFibers, scale: 1.0,
      colours: [],
      [
        TextureParameter("agentDensity", 20.0, 0.0...50.0),
        TextureParameter("iterations", 20.0, 1.0...256.0),
        TextureParameter("orientations", 3.0, 2.0...16.0),
        TextureParameter("sensorDistance", 15.0, 0.0...400.0),
        TextureParameter("sensorAngle", 15.0, 0.0...180.0),
        TextureParameter("motionDistance", 3.0, 0.0...400.0),
        TextureParameter("motionAngle", 15.0, 0.0...180.0),
        TextureParameter("motionMoment", 30.0, 0.0...100.0),
        TextureParameter("trailBlur", 1.0, 0.0...20.0),
        TextureParameter("particleSize", 19.0, 1.0...128.0),
        TextureParameter("particleThickness", 10.0, 0.0...100.0),
        TextureParameter("quantizedOrientations", 24.0, 1.0...32.0),
        TextureParameter("opacity", 50.0, 0.0...100.0),
        TextureParameter("sharpening", 0.0, 0.0...100.0),
      ]
    ),
    .classic(
      "GmicReactionDiffusion", .abstract, .gmicReactionDiffusion, scale: 1.0,
      colours: [],
      [
        TextureParameter("iterations", 5.0, 1.0...10.0),
        TextureParameter("size", 5.0, 0.0...20.0),
      ]
    ),
    .classic(
      "Truchet", .patterns, .truchet, scale: 32.0,
      colours: [0xFFFF_FFFF, 0xFF00_0000],
      [
        TextureParameter("radius", 5.0, 1.0...64.0),
        TextureParameter("smoothness", 1.0, 0.0...10.0),
      ]
    ),
    .classic(
      "Caustics", .abstract, .caustics, scale: 32.0,
      colours: [0xFF79_9FFF],
      [
        TextureParameter("brightness", 10.0, 0.0...100.0),
        TextureParameter("amount", 1.0, 0.0...10.0),
        TextureParameter("turbulence", 1.0, 0.0...10.0),
        TextureParameter("dispersion", 0.0, 0.0...10.0),
        TextureParameter("time", 0.0, 0.0...10.0),
      ]
    ),
    .classic(
      "Cellular", .abstract, .cellular, scale: 32.0,
      colours: [0xFFFF_FFFF],
      [
        TextureParameter("stretch", 1.0, 0.1...20.0),
        TextureParameter("angle", 0.0, -360.0...360.0),
        TextureParameter("angleCoefficient", 0.0, -10.0...10.0),
        TextureParameter("gradientCoefficient", 0.0, -10.0...10.0),
        TextureParameter("f1", 1.0, -5.0...5.0),
        TextureParameter("f2", 0.0, -5.0...5.0),
        TextureParameter("randomness", 0.0, 0.0...1.0),
        TextureParameter("distancePower", 2.0, 0.1...10.0),
        TextureParameter("turbulence", 1.0, 0.0...10.0),
        TextureParameter("amount", 1.0, -10.0...10.0),
        TextureParameter("gain", 0.5, 0.0...1.0),
        TextureParameter("bias", 0.5, 0.0...1.0),
      ]
    ),
    .classic(
      "Check", .patterns, .check, scale: 1.0,
      colours: [0xFFFF_FFFF, 0xFF00_0000],
      [
        TextureParameter("xScale", 8.0, 1.0...128.0),
        TextureParameter("yScale", 8.0, 1.0...128.0),
        TextureParameter("fuzziness", 0.0, 0.0...128.0),
        TextureParameter("angle", 0.0, -360.0...360.0),
      ]
    ),
    .classic(
      "FBM", .abstract, .fbm, scale: 32.0,
      colours: [],
      [
        TextureParameter("amount", 1.0, 0.01...10.0),
        TextureParameter("stretch", 1.0, 0.1...20.0),
        TextureParameter("angle", 0.0, -360.0...360.0),
      ]
    ),
    .classic(
      "Marble", .abstract, .marble, scale: 32.0,
      colours: [],
      [
        TextureParameter("stretch", 1.0, 0.1...20.0),
        TextureParameter("angle", 0.0, -360.0...360.0),
        TextureParameter("turbulence", 1.0, 0.0...10.0),
        TextureParameter("turbulenceFactor", 0.4, 0.0...5.0),
      ]
    ),
    .classic(
      "Plasma", .abstract, .plasma, scale: 1.0,
      colours: [0xFF00_0000],
      [
        TextureParameter("turbulence", 1.0, 0.0...10.0),
        TextureParameter("scaling", 0.0, 0.0...1.0),
      ]
    ),
    .classic(
      "Quilt", .patterns, .quilt, scale: 1.0,
      colours: [],
      [
        TextureParameter("iterations", 25000.0, 1.0...50000.0),
        TextureParameter("a", -0.59, -2.0...2.0),
        TextureParameter("b", 0.2, -2.0...2.0),
        TextureParameter("c", 0.1, -2.0...2.0),
        TextureParameter("d", 0.0, -2.0...2.0),
        TextureParameter("k", 0.0, 0.0...20.0),
      ]
    ),
    .classic(
      "Wood", .abstract, .wood, scale: 32.0,
      colours: [],
      [
        TextureParameter("rings", 2.0, 0.0...5.0),
        TextureParameter("turbulence", 1.0, 0.0...10.0),
        TextureParameter("gain", 0.5, 0.0...1.0),
        TextureParameter("bias", 0.5, 0.0...1.0),
        TextureParameter("stretch", 1.0, 0.1...20.0),
        TextureParameter("angle", 0.0, -360.0...360.0),
      ]
    ),
  ]
}
