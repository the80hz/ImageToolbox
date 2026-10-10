// Generated from TextureFilterType.kt and RaymarchTextureParams.kt.
// Do not edit by hand.

/// The 3D scenes of the Android raymarch presets.
public enum RaymarchScene: CaseIterable, Sendable {
  case sphere3D
  case cube3D
  case cubeStair3D
  case cubeSpheres3D
  case emptiedCube3D
  case torus3D
  case mobiusTorus3D
  case gyroRings3D
  case torusGem3D
  case cubeOctahedron3D
  case infiniteSpheroids3D
  case infiniteStructure3D
  case infiniteCylinders3D
  case truchetRings3D
  case truchetPipes3D
}

extension TexturePresets {
  /// Parameters shared by every raymarch preset: `RaymarchTextureParams()` defaults.
  static let raymarchParameters: [TextureParameter] = [
    TextureParameter("innerRadius", 0.9, 0.5...1.2),
    TextureParameter("size", 1.0, 0.25...2.5),
    TextureParameter("thickness", 0.18, 0.03...0.4),
    TextureParameter("roundness", 0.06, 0.0...0.2),
    TextureParameter("count", 3.0, 1.0...12.0),
    TextureParameter("rotationX", 20.0, -180.0...180.0),
    TextureParameter("rotationY", 30.0, -180.0...180.0),
    TextureParameter("rotationZ", 0.0, -180.0...180.0),
    TextureParameter("cameraDistance", 3.5, 1.5...8.0),
    TextureParameter("cameraYaw", 0.0, -180.0...180.0),
    TextureParameter("cameraPitch", 0.0, -80.0...80.0),
    TextureParameter("fieldOfView", 45.0, 20.0...90.0),
    TextureParameter("metallic", 0.8, 0.0...1.0),
    TextureParameter("roughness", 0.25, 0.03...1.0),
    TextureParameter("transmission", 0.0, 0.0...1.0),
    TextureParameter("lightAngle", -35.0, -180.0...180.0),
    TextureParameter("lightElevation", 50.0, -80.0...80.0),
  ]

  /// Raymarch presets, in the order of the Android enum.
  static let raymarch: [TexturePreset] = [
    .raymarch("Sphere3D", .sphere3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("Cube3D", .cube3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("CubeStair3D", .cubeStair3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("CubeSpheres3D", .cubeSpheres3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("EmptiedCube3D", .emptiedCube3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("Torus3D", .torus3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("MobiusTorus3D", .mobiusTorus3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("GyroRings3D", .gyroRings3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("TorusGem3D", .torusGem3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("CubeOctahedron3D", .cubeOctahedron3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("InfiniteSpheroids3D", .infiniteSpheroids3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("InfiniteStructure3D", .infiniteStructure3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("InfiniteCylinders3D", .infiniteCylinders3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("TruchetRings3D", .truchetRings3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
    .raymarch("TruchetPipes3D", .truchetPipes3D, colours: [0xFFB9_ABE5, 0x0000_0000]),
  ]
}
