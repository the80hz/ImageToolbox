// Generated from the Android texture catalogue. Do not edit by hand.
// Numbers come from FastNoiseTextureParams.kt, labels from FastNoiseParams.kt,
// and the noise family and roles from the generator table.

extension TexturePresets {
  /// FastNoise presets, fourth part, in the order of the Android catalogue.
  static let fastNoiseFourth: [TexturePreset] = [
    .fastNoise(
      "ElectricArcField", .abstract, .ridged, scale: 0.008,
      colours: [0xFF03_0511, 0xFF17_3A91, 0xFF32_C8FF, 0xFFFF_FFFF],
      [
        TextureParameter("texture_arc_count", 0.72, 0.0...1.0, .frequency),
        TextureParameter("turbulence", 0.72, 0.0...1.0, .warp),
        TextureParameter("texture_arc_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.9, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CloudChamber", .abstract, .bands, scale: 0.008,
      colours: [0xFF08_0913, 0xFF2D_416A, 0xFF9B_C5E7, 0xFFEA_F2FF],
      [
        TextureParameter("texture_track_density", 0.55, 0.0...1.0, .frequency),
        TextureParameter("texture_deflection", 0.7, 0.0...1.0, .warp),
        TextureParameter("texture_track_sharpness", 0.86, 0.0...1.0, .softness),
        TextureParameter("glow", 0.7, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.6, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "TurbulentInk", .abstract, .warp, scale: 0.006,
      colours: [0xFFF0_E8D8, 0xFF17_4A72, 0xFF9E_284F, 0xFF17_1629],
      [
        TextureParameter("texture_ribbon_density", 0.7, 0.0...1.0, .frequency),
        TextureParameter("turbulence", 0.78, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.68, 0.0...1.0, .softness),
        TextureParameter("texture_bleed", 0.62, 0.0...1.0, .other),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CellularEmbryo", .abstract, .edge, scale: 0.008,
      colours: [0xFF22_0E26, 0xFF72_3259, 0xFFE0_7B93, 0xFFFF_D0B3],
      [
        TextureParameter("texture_embryo_density", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_morphology", 0.48, 0.0...1.0, .jitter),
        TextureParameter("texture_membrane_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("glow", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "NeuralGarden", .abstract, .ridged, scale: 0.008,
      colours: [0xFF06_120D, 0xFF11_684A, 0xFF6B_D87A, 0xFFB8_FFBA],
      [
        TextureParameter("texture_neuron_density", 0.76, 0.0...1.0, .frequency),
        TextureParameter("texture_branching", 0.82, 0.0...1.0, .detail),
        TextureParameter("texture_fiber_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("glow", 0.64, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "MagneticField", .abstract, .bands, scale: 0.008,
      colours: [0xFF07_0A17, 0xFF24_52A0, 0xFFE2_3D70, 0xFFFF_E5A6],
      [
        TextureParameter("texture_line_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_pole_distortion", 0.42, 0.0...1.0, .warp),
        TextureParameter("texture_line_sharpness", 0.74, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "RiverDelta", .nature, .ridged, scale: 0.006,
      colours: [0xFF25_190E, 0xFF8B_693B, 0xFF16_88A5, 0xFF8E_DDE0],
      [
        TextureParameter("texture_channel_density", 0.76, 0.0...1.0, .frequency),
        TextureParameter("texture_erosion", 0.86, 0.0...1.0, .gain),
        TextureParameter("texture_channel_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("texture_water_glow", 0.48, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "LichenColony", .nature, .cellular, scale: 0.009,
      colours: [0xFF29_291A, 0xFF66_743A, 0xFFB1_B85B, 0xFFC7_D9A7],
      [
        TextureParameter("texture_colony_density", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_spread", 0.58, 0.0...1.0, .jitter),
        TextureParameter("texture_edge_sharpness", 0.7, 0.0...1.0, .softness),
        TextureParameter("texture_moisture", 0.48, 0.0...1.0, .other),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "BacterialCulture", .nature, .edge, scale: 0.009,
      colours: [0xFF16_0C20, 0xFF66_3078, 0xFFE0_5C9E, 0xFFFF_D37C],
      [
        TextureParameter("texture_colony_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_growth_variation", 0.62, 0.0...1.0, .jitter),
        TextureParameter("texture_membrane_sharpness", 0.68, 0.0...1.0, .softness),
        TextureParameter("glow", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "FluidVorticity", .abstract, .turbulence, scale: 0.007,
      colours: [0xFF07_1326, 0xFF16_55A2, 0xFFE4_4574, 0xFFFF_D36E],
      [
        TextureParameter("texture_vortex_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("turbulence", 0.78, 0.0...1.0, .warp),
        TextureParameter("texture_ridge_sharpness", 0.7, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CrystalGrowth", .abstract, .cellular, scale: 0.008,
      colours: [0xFF10_1525, 0xFF3F_62A1, 0xFFA9_D8EE, 0xFFFF_F0C2],
      [
        TextureParameter("texture_crystal_density", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_anisotropy", 0.48, 0.0...1.0, .other),
        TextureParameter("texture_facet_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.78, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "GalacticWeb", .space, .edge, scale: 0.007,
      colours: [0xFF01_0208, 0xFF18_2B69, 0xFF6B_3EA0, 0xFFFF_E9CA],
      [
        TextureParameter("texture_node_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_gravity_warp", 0.68, 0.0...1.0, .warp),
        TextureParameter("texture_filament_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.86, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "VeinedLeaf", .nature, .ridged, scale: 0.004,
      colours: [0xFF07_180C, 0xFF1E_6732, 0xFF75_BC50, 0xFFD6_E782],
      [
        TextureParameter("texture_vein_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_curvature", 0.52, 0.0...1.0, .warp),
        TextureParameter("texture_vein_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("texture_translucency", 0.62, 0.0...1.0, .other),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "PorousSponge", .abstract, .cellular, scale: 0.009,
      colours: [0xFF5B_3718, 0xFFB1_6C27, 0xFFE5_B24E, 0xFFFF_E2A0],
      [
        TextureParameter("texture_pore_density", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_irregularity", 0.42, 0.0...1.0, .jitter),
        TextureParameter("texture_pore_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("texture_moisture", 0.42, 0.0...1.0, .other),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "RainOnGlass", .nature, .cellular, scale: 0.008,
      colours: [0xFF07_1728, 0xFF19_4C70, 0xFF69_BDD2, 0xFFDF_FBFF],
      [
        TextureParameter("texture_drop_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_streaking", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_drop_sharpness", 0.74, 0.0...1.0, .softness),
        TextureParameter("texture_refraction", 0.78, 0.0...1.0, .other),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "EmberField", .abstract, .cellular, scale: 0.008,
      colours: [0xFF10_0504, 0xFF76_200B, 0xFFF0_5A14, 0xFFFF_E06B],
      [
        TextureParameter("texture_ember_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_updraft", 0.62, 0.0...1.0, .warp),
        TextureParameter("texture_ember_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("glow", 0.88, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "QuantumFoam", .space, .edge, scale: 0.008,
      colours: [0xFF06_0616, 0xFF35_3499, 0xFF23_C9CB, 0xFFF6_6AC2],
      [
        TextureParameter("texture_bubble_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_uncertainty", 0.78, 0.0...1.0, .jitter),
        TextureParameter("texture_boundary_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("glow", 0.78, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "ChladniPlate", .patterns, .bands, scale: 0.008,
      colours: [0xFF06_080B, 0xFF2E_343A, 0xFF8E_9AA3, 0xFFF1_D78A],
      [
        TextureParameter("texture_mode_count", 0.76, 0.0...1.0, .frequency),
        TextureParameter("texture_asymmetry", 0.28, 0.0...1.0, .other),
        TextureParameter("texture_line_sharpness", 0.88, 0.0...1.0, .softness),
        TextureParameter("texture_metallic", 0.36, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.7, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CymaticRosette", .patterns, .radial, scale: 0.001,
      colours: [0xFF07_1426, 0xFF17_6FB0, 0xFF55_D3DE, 0xFFFF_6500],
      [
        TextureParameter("texture_petal_count", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_resonance", 0.44, 0.0...1.0, .other),
        TextureParameter("texture_ridge_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("glow", 0.76, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "LichtenbergFigure", .abstract, .ridged, scale: 0.008,
      colours: [0xFF08_030C, 0xFF5E_176E, 0xFFE5_44A7, 0xFFFF_E9FF],
      [
        TextureParameter("texture_branch_count", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_branching", 0.66, 0.0...1.0, .detail),
        TextureParameter("texture_arc_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("glow", 0.9, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.6, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Quasicrystal", .patterns, .bands, scale: 0.008,
      colours: [0xFF09_0B18, 0xFF28_54A0, 0xFF27_BEBB, 0xFFFF_D962],
      [
        TextureParameter("texture_symmetry", 0.7, 0.0...1.0, .frequency),
        TextureParameter("texture_phase_warp", 0.36, 0.0...1.0, .warp),
        TextureParameter("texture_ridge_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("glow", 0.62, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Mandelbrot", .patterns, .mandelbrot, scale: 0.004,
      colours: [0xFF02_030B, 0xFF17_3B72, 0xFF7B_2EA3, 0xFFFF_C85C],
      [
        TextureParameter("texture_iteration_detail", 0.82, 0.0...1.0, .detail),
        TextureParameter("texture_center_offset", 0.36, 0.0...1.0, .other),
        TextureParameter("texture_boundary_sharpness", 0.86, 0.0...1.0, .softness),
        TextureParameter("glow", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.7, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "BurningShip", .patterns, .burningShip, scale: 0.0035,
      colours: [0xFF05_0207, 0xFF5A_1728, 0xFFE5_4522, 0xFFFF_D56A],
      [
        TextureParameter("texture_iteration_detail", 0.82, 0.0...1.0, .detail),
        TextureParameter("texture_center_offset", 0.44, 0.0...1.0, .other),
        TextureParameter("texture_boundary_sharpness", 0.86, 0.0...1.0, .softness),
        TextureParameter("glow", 0.62, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.7, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "JuliaSet", .patterns, .julia, scale: 0.004,
      colours: [0xFF03_0713, 0xFF21_4E96, 0xFF8B_46C7, 0xFFFF_E2A8],
      [
        TextureParameter("iterations", 0.82, 0.0...1.0, .detail),
        TextureParameter("texture_constant_phase", 0.58, 0.0...1.0, .angle),
        TextureParameter("texture_filament_sharpness", 0.86, 0.0...1.0, .softness),
        TextureParameter("glow", 0.6, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.7, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "KaleidoscopeCrystal", .patterns, .radial, scale: 0.008,
      colours: [0xFF09_0B1C, 0xFF23_67B7, 0xFFE0_4DA4, 0xFF62_F5CA],
      [
        TextureParameter("texture_segments", 0.8, 0.0...1.0, .frequency),
        TextureParameter("texture_fold_warp", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_facet_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("glow", 0.56, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.6, 0.0...3.0, .contrast),
      ]
    ),
  ]
}
