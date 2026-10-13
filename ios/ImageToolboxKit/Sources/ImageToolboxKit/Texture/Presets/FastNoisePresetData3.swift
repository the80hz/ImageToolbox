// Generated from the Android texture catalogue. Do not edit by hand.
// Numbers come from FastNoiseTextureParams.kt, labels from FastNoiseParams.kt,
// and the noise family and roles from the generator table.

extension TexturePresets {
  /// FastNoise presets, third part, in the order of the Android catalogue.
  static let fastNoiseThird: [TexturePreset] = [
    .fastNoise(
      "RingedPlanet", .space, .rings, scale: 0.009,
      colours: [0xFF02_040D, 0xFF15_234D, 0xFFE5_8C62, 0xFFFF_E1A6],
      [
        TextureParameter("texture_planet_size", 0.24, 0.0...1.0, .threshold),
        TextureParameter("texture_ring_tilt", 0.72, 0.0...1.0, .angle),
        TextureParameter("texture_ring_width", 0.16, 0.0...1.0, .width),
        TextureParameter("texture_atmosphere", 0.62, 0.0...1.0, .glow),
        TextureParameter("texture_stars", 0.25, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Geode", .materials, .bands, scale: 0.008,
      colours: [0xFF12_0E20, 0xFF70_46A8, 0xFF3E_D7D1, 0xFFF4_DDA6],
      [
        TextureParameter("texture_bands", 0.78, 0.0...1.0, .frequency),
        TextureParameter("distortion", 0.42, 0.0...1.0, .warp),
        TextureParameter("texture_crystal_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("sparkle", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "PrismaticLight", .abstract, .radial, scale: 0.008,
      colours: [0xFF07_091A, 0xFF24_6DD8, 0xFFE9_4DA9, 0xFFFF_E47A],
      [
        TextureParameter("texture_facets", 0.72, 0.0...1.0, .frequency),
        TextureParameter("dispersion", 0.82, 0.0...1.0, .other),
        TextureParameter("texture_beam_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("bloom", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "StainedGlass", .materials, .edge, scale: 0.008,
      colours: [0xFF12_0F18, 0xFF2E_8BD2, 0xFFE5_4472, 0xFFFF_D34E],
      [
        TextureParameter("texture_cells", 0.54, 0.0...1.0, .frequency),
        TextureParameter("texture_irregularity", 0.48, 0.0...1.0, .jitter),
        TextureParameter("texture_lead_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("glow", 0.38, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "KelpForest", .nature, .simplex, scale: 0.006,
      colours: [0xFF03_1C22, 0xFF07_594F, 0xFF42_A66E, 0xFFD1_F29B],
      [
        TextureParameter("density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("current", 0.78, 0.0...1.0, .warp),
        TextureParameter("texture_depth_sharpness", 0.68, 0.0...1.0, .softness),
        TextureParameter("texture_light_rays", 0.64, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "FrostFern", .nature, .ridged, scale: 0.008,
      colours: [0xFF10_273A, 0xFF55_9AB4, 0xFFB8_E8ED, 0xFFE8_FBFF],
      [
        TextureParameter("texture_branches", 0.78, 0.0...1.0, .frequency),
        TextureParameter("texture_branching", 0.62, 0.0...1.0, .detail),
        TextureParameter("texture_crystal_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("texture_frost_glow", 0.68, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "LiquidCrystal", .materials, .edge, scale: 0.008,
      colours: [0xFF09_0A18, 0xFF18_BFD2, 0xFFE1_42A9, 0xFFFF_E96A],
      [
        TextureParameter("texture_domains", 0.66, 0.0...1.0, .frequency),
        TextureParameter("dispersion", 0.62, 0.0...1.0, .other),
        TextureParameter("texture_boundary_sharpness", 0.58, 0.0...1.0, .softness),
        TextureParameter("shine", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.3, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "DragonScales", .materials, .hex, scale: 0.007,
      colours: [0xFF07_1913, 0xFF17_664B, 0xFF39_B778, 0xFFE0_C96B],
      [
        TextureParameter("texture_scale_density", 0.66, 0.0...1.0, .frequency),
        TextureParameter("texture_curvature", 0.28, 0.0...1.0, .warp),
        TextureParameter("texture_rim_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("texture_iridescence", 0.52, 0.0...1.0, .other),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "FireflySwarm", .nature, .cellular, scale: 0.007,
      colours: [0xFF02_0B12, 0xFF0B_4D49, 0xFF80_D85A, 0xFFFF_FFB0],
      [
        TextureParameter("density", 0.52, 0.0...1.0, .frequency),
        TextureParameter("texture_drift", 0.82, 0.0...1.0, .warp),
        TextureParameter("texture_trail_sharpness", 0.88, 0.0...1.0, .softness),
        TextureParameter("glow", 0.95, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.6, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Mycelium", .nature, .ridged, scale: 0.008,
      colours: [0xFF07_100B, 0xFF24_452E, 0xFFB7_C985, 0xFFF4_E8C1],
      [
        TextureParameter("texture_network_density", 0.78, 0.0...1.0, .frequency),
        TextureParameter("texture_branching", 0.72, 0.0...1.0, .detail),
        TextureParameter("texture_fiber_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.66, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Kintsugi", .materials, .edge, scale: 0.008,
      colours: [0xFF10_131A, 0xFF34_4158, 0xFFD9_9B32, 0xFFFF_E7A3],
      [
        TextureParameter("texture_crack_density", 0.6, 0.0...1.0, .frequency),
        TextureParameter("texture_irregularity", 0.48, 0.0...1.0, .jitter),
        TextureParameter("texture_gold_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("texture_metallic", 0.7, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CarbonFiber", .materials, .grid, scale: 0.01,
      colours: [0xFF03_0405, 0xFF15_191C, 0xFF34_3B40, 0xFF88_949B],
      [
        TextureParameter("texture_weave_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_twill", 0.3, 0.0...1.0, .other),
        TextureParameter("texture_fiber_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("texture_sheen", 0.34, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CircuitBoard", .materials, .grid, scale: 0.008,
      colours: [0xFF03_170F, 0xFF07_5A3B, 0xFFC2_8B28, 0xFF7B_FFD1],
      [
        TextureParameter("texture_trace_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_routing", 0.32, 0.0...1.0, .jitter),
        TextureParameter("texture_trace_sharpness", 0.86, 0.0...1.0, .softness),
        TextureParameter("texture_emission", 0.6, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SoapFilm", .materials, .bands, scale: 0.007,
      colours: [0xFF10_182B, 0xFF20_CDE2, 0xFFF4_5CB4, 0xFFFF_E66D],
      [
        TextureParameter("texture_bands", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_flow", 0.72, 0.0...1.0, .warp),
        TextureParameter("texture_film_sharpness", 0.55, 0.0...1.0, .softness),
        TextureParameter("shine", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.25, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "MoireGuilloche", .patterns, .bands, scale: 0.008,
      colours: [0xFF07_0914, 0xFF27_47A5, 0xFFBD_4BC8, 0xFFF2_EAFB],
      [
        TextureParameter("frequency", 0.64, 0.0...1.0, .frequency),
        TextureParameter("offset", 0.4, 0.0...1.0, .other),
        TextureParameter("texture_line_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.38, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SnakeSkin", .materials, .edge, scale: 0.009,
      colours: [0xFF17_170E, 0xFF4E_5A2D, 0xFF9D_A75A, 0xFFB8_D7A4],
      [
        TextureParameter("texture_scale_density", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_irregularity", 0.4, 0.0...1.0, .jitter),
        TextureParameter("texture_rim_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("texture_sheen", 0.4, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Terrazzo", .materials, .cellular, scale: 0.008,
      colours: [0xFFE5_DCCF, 0xFF31_5C72, 0xFFC8_5554, 0xFFE5_A73D],
      [
        TextureParameter("texture_chip_density", 0.48, 0.0...1.0, .frequency),
        TextureParameter("variation", 0.42, 0.0...1.0, .jitter),
        TextureParameter("texture_chip_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("texture_polish", 0.2, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "GalaxyFilaments", .space, .turbulence, scale: 0.007,
      colours: [0xFF02_030A, 0xFF17_3B78, 0xFF81_37A6, 0xFFD9_EEFF],
      [
        TextureParameter("texture_filament_density", 0.78, 0.0...1.0, .frequency),
        TextureParameter("turbulence", 0.7, 0.0...1.0, .warp),
        TextureParameter("texture_filament_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("texture_star_glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "VolcanicObsidian", .materials, .cellular, scale: 0.008,
      colours: [0xFF02_0304, 0xFF17_141D, 0xFF3B_2744, 0xFFEF_6C3D],
      [
        TextureParameter("texture_facets", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_fracturing", 0.58, 0.0...1.0, .jitter),
        TextureParameter("texture_edge_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("texture_lava_glow", 0.52, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.7, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "MotherboardHeatmap", .patterns, .grid, scale: 0.008,
      colours: [0xFF07_120E, 0xFF08_705B, 0xFFFF_7B22, 0xFFFF_F1A8],
      [
        TextureParameter("texture_trace_density", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_heat_spread", 0.38, 0.0...1.0, .warp),
        TextureParameter("texture_trace_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("texture_heat_glow", 0.68, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "MicroscopicDiatoms", .abstract, .edge, scale: 0.007,
      colours: [0xFF08_2431, 0xFF1E_7181, 0xFF74_D8C9, 0xFFD9_C8FF],
      [
        TextureParameter("texture_colony_density", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_shell_variation", 0.3, 0.0...1.0, .jitter),
        TextureParameter("texture_pore_sharpness", 0.74, 0.0...1.0, .softness),
        TextureParameter("texture_luminescence", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "ReactionDiffusion", .abstract, .fbm, scale: 0.009,
      colours: [0xFF09_0B17, 0xFF30_3785, 0xFFE6_4C93, 0xFF59_EBB0],
      [
        TextureParameter("texture_pattern_scale", 0.82, 0.0...1.0, .frequency),
        TextureParameter("feedback", 0.74, 0.0...1.0, .threshold),
        TextureParameter("texture_edge_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.5, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.6, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "CoralGrowth", .nature, .fbm, scale: 0.008,
      colours: [0xFF07_1D2A, 0xFFEA_536E, 0xFFFF_A468, 0xFFFF_C2D8],
      [
        TextureParameter("texture_branch_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_growth_bias", 0.62, 0.0...1.0, .threshold),
        TextureParameter("texture_edge_sharpness", 0.7, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SlimeMold", .nature, .warp, scale: 0.008,
      colours: [0xFF08_110A, 0xFF59_6F17, 0xFFD5_D928, 0xFFFF_F5A0],
      [
        TextureParameter("texture_trail_density", 0.8, 0.0...1.0, .frequency),
        TextureParameter("texture_chemotaxis", 0.82, 0.0...1.0, .warp),
        TextureParameter("texture_trail_sharpness", 0.84, 0.0...1.0, .softness),
        TextureParameter("glow", 0.66, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "DendriticCrystal", .abstract, .ridged, scale: 0.008,
      colours: [0xFF07_1829, 0xFF25_678C, 0xFFA8_E5F0, 0xFFDF_FFFF],
      [
        TextureParameter("texture_branch_count", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_branching", 0.52, 0.0...1.0, .detail),
        TextureParameter("texture_crystal_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.82, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
  ]
}
