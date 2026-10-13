// Generated from PatternTextureType.kt and PatternTextureShaders.kt.
// Do not edit by hand.

/// The pattern shapes of the Android `PatternTextureType` enum.
public enum PatternKind: CaseIterable, Sendable {
  case hatchPattern
  case smoothHatch
  case xorPattern
  case squareSpiralPattern
  case crossStitchPattern
  case plaidPattern
  case generatedWaves
  case voronoiHatch
  case loopPattern
  case scintillatingGrid
  case circleSpiralPattern
  case testChart
  case bentRows
  case diamondsIllusion
  case randomTriangles
  case hexCubePattern
  case squareLooper
  case moireInterference
  case truchetArcs
  case circuitPattern
  case rosacePattern
  case rosettePattern
  case lightArray
  case voronoiGems
  case citySkyline
  case winterLandscape
  case circleRipplePattern
  case squareRipplePattern
}

extension TexturePresets {
  /// Pattern presets, in the order of the Android `PatternTextureType` enum.
  static let patterns: [TexturePreset] = [
    .pattern(
      "HatchPattern", .hatchPattern, scale: 12.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("thickness", 0.5, 0.02...0.98)
      ]
    ),
    .pattern(
      "SmoothHatch", .smoothHatch, scale: 12.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("hardness", 1.0, 0.1...8.0),
        TextureParameter("balance", 0.5, 0.01...0.99),
      ]
    ),
    .pattern(
      "XorPattern", .xorPattern, scale: 12.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("intensity", 4.0, 1.0...16.0)
      ]
    ),
    .pattern(
      "SquareSpiralPattern", .squareSpiralPattern, scale: 5.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 4.0, 1.0...12.0),
        TextureParameter("thickness", 0.4, 0.05...0.95),
      ]
    ),
    .pattern(
      "CrossStitchPattern", .crossStitchPattern, scale: 12.0,
      colours: [0xFF00_0000, 0xFFD5_C4AB, 0xFF34_77A3, 0xFFFF_FFFF],
      [
        TextureParameter("thickness", 0.65, 0.1...0.95),
        TextureParameter("shadows", 0.6, 0.0...1.0),
      ]
    ),
    .pattern(
      "PlaidPattern", .plaidPattern, scale: 12.0,
      colours: [0xFFFF_FF00, 0xFFFF_0000, 0xFFFF_00FF, 0xFF00_FFFF],
      [
        TextureParameter("seed", 0.0, 0.0...10000.0),
        TextureParameter("thickness", 0.45, 0.05...0.95),
      ]
    ),
    .pattern(
      "GeneratedWaves", .generatedWaves, scale: 12.0,
      colours: [0xFFFF_FF00, 0xFFFF_0000, 0xFFFF_00FF, 0xFF00_FFFF],
      [
        TextureParameter("variability", 0.5, 0.0...1.0),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "VoronoiHatch", .voronoiHatch, scale: 12.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("seed", 0.0, 0.0...10000.0),
        TextureParameter("thickness", 0.45, 0.05...0.95),
        TextureParameter("variability", 1.0, 0.0...1.0),
      ]
    ),
    .pattern(
      "LoopPattern", .loopPattern, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 8.0, 1.0...64.0),
        TextureParameter("radius", 0.15, 0.01...0.5),
        TextureParameter("thickness", 0.1, 0.01...0.5),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "ScintillatingGrid", .scintillatingGrid, scale: 12.0,
      colours: [0xFF00_0000, 0xFF80_8080, 0xFFFF_FFFF, 0xFFFF_FFFF],
      [
        TextureParameter("thickness", 0.08, 0.01...0.4),
        TextureParameter("radius", 0.09, 0.01...0.4),
      ]
    ),
    .pattern(
      "CircleSpiralPattern", .circleSpiralPattern, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 5.0, 1.0...24.0)
      ]
    ),
    .pattern(
      "TestChart", .testChart, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      []
    ),
    .pattern(
      "BentRows", .bentRows, scale: 12.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("offset", 0.2, 0.0...0.5),
        TextureParameter("thickness", 0.04, 0.005...0.15),
      ]
    ),
    .pattern(
      "DiamondsIllusion", .diamondsIllusion, scale: 4.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 5.0, 1.0...16.0),
        TextureParameter("thickness", 0.5, 0.05...0.95),
      ]
    ),
    .pattern(
      "RandomTriangles", .randomTriangles, scale: 1.0,
      colours: [0xFFFF_0000, 0xFFFF_FF00, 0xFF00_FFFF, 0xFFFF_00FF],
      [
        TextureParameter("count", 40.0, 1.0...100.0),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "HexCubePattern", .hexCubePattern, scale: 8.0,
      colours: [0xFFFF_0000, 0xFFFF_FF00, 0xFF00_FFFF, 0xFF00_0000],
      [
        TextureParameter("thickness", 0.03, 0.0...0.3)
      ]
    ),
    .pattern(
      "SquareLooper", .squareLooper, scale: 8.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("time", 0.0, 0.0...10.0),
        TextureParameter("thickness", 0.15, 0.01...0.8),
      ]
    ),
    .pattern(
      "MoireInterference", .moireInterference, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("intensity", 30.0, 1.0...100.0),
        TextureParameter("thickness", 0.5, 0.05...0.95),
      ]
    ),
    .pattern(
      "TruchetArcs", .truchetArcs, scale: 8.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("seed", 0.0, 0.0...10000.0),
        TextureParameter("thickness", 0.15, 0.02...0.45),
      ]
    ),
    .pattern(
      "CircuitPattern", .circuitPattern, scale: 8.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("seed", 0.0, 0.0...10000.0),
        TextureParameter("thickness", 0.05, 0.01...0.25),
        TextureParameter("radius", 0.13, 0.03...0.3),
      ]
    ),
    .pattern(
      "RosacePattern", .rosacePattern, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 24.0, 3.0...64.0),
        TextureParameter("radius", 0.4, 0.05...0.8),
        TextureParameter("thickness", 0.02, 0.005...0.15),
      ]
    ),
    .pattern(
      "RosettePattern", .rosettePattern, scale: 1.0,
      colours: [0xFF00_0000, 0xFFFF_FFFF, 0xFF80_8080, 0xFF00_FFFF],
      [
        TextureParameter("count", 24.0, 3.0...64.0),
        TextureParameter("radius", 0.3, 0.05...0.8),
        TextureParameter("thickness", 0.01, 0.005...0.15),
      ]
    ),
    .pattern(
      "LightArray", .lightArray, scale: 4.0,
      colours: [0xFF00_0000, 0xFFFF_FF00, 0xFF00_FFFF, 0xFFFF_00FF],
      [
        TextureParameter("intensity", 0.7, 0.0...2.0),
        TextureParameter("layers", 3.0, 1.0...6.0),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "VoronoiGems", .voronoiGems, scale: 8.0,
      colours: [0xFFFF_0000, 0xFFFF_FF00, 0xFF00_FFFF, 0xFFFF_00FF],
      [
        TextureParameter("seed", 0.0, 0.0...10000.0),
        TextureParameter("shadows", 0.5, 0.0...1.0),
        TextureParameter("variability", 1.0, 0.0...1.0),
      ]
    ),
    .pattern(
      "CitySkyline", .citySkyline, scale: 1.0,
      colours: [0xFF0A_1018, 0xFF70_3235, 0xFFFF_8000, 0xFFFF_FF00],
      [
        TextureParameter("layers", 4.0, 1.0...8.0),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "WinterLandscape", .winterLandscape, scale: 1.0,
      colours: [0xFF0A_1018, 0xFF66_99CC, 0xFF21_6B3B, 0xFFFF_FFFF],
      [
        TextureParameter("time", 0.0, 0.0...10.0),
        TextureParameter("seed", 0.0, 0.0...10000.0),
      ]
    ),
    .pattern(
      "CircleRipplePattern", .circleRipplePattern, scale: 8.0,
      colours: [0xFFFF_FF00, 0xFF00_0000, 0xFFFF_FFFF, 0xFF00_00FF],
      [
        TextureParameter("radius", 0.4, 0.1...0.49),
        TextureParameter("shapeAspect", 0.7, 0.25...2.0),
      ]
    ),
    .pattern(
      "SquareRipplePattern", .squareRipplePattern, scale: 8.0,
      colours: [0xFF00_FFFF, 0xFFFF_00FF, 0xFFFF_FFFF, 0xFF00_0000],
      [
        TextureParameter("thickness", 0.08, 0.01...0.3),
        TextureParameter("offset", 0.08, 0.0...0.3),
      ]
    ),
  ]
}
