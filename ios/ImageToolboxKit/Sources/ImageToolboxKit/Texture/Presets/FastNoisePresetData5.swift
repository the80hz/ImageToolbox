// Generated from the Android texture catalogue. Do not edit by hand.
// Numbers come from FastNoiseTextureParams.kt, labels from FastNoiseParams.kt,
// and the noise family and roles from the generator table.

extension TexturePresets {
  /// FastNoise presets, fifth part, in the order of the Android catalogue.
  static let fastNoiseFifth: [TexturePreset] = [
    .fastNoise(
      "SpectralPrism", .abstract, .radial, scale: 0.008,
      colours: [0xFF08_0A12, 0xFF22_5CD1, 0xFFDD_3DAD, 0xFF72_F5B3],
      [
        TextureParameter("texture_facet_count", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_refraction", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("bloom", 0.8, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "TopologicalKnot", .patterns, .spiral, scale: 0.008,
      colours: [0xFF04_0713, 0xFF24_579A, 0xFFC2_45D6, 0xFFFF_E29A],
      [
        TextureParameter("texture_turns", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_twist", 0.54, 0.0...1.0, .warp),
        TextureParameter("texture_tube_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.76, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "XRayBotanical", .abstract, .ridged, scale: 0.008,
      colours: [0xFF02_0A0B, 0xFF0C_4F50, 0xFF5C_C7A7, 0xFFE8_FFE0],
      [
        TextureParameter("texture_leaf_density", 0.66, 0.0...1.0, .frequency),
        TextureParameter("texture_curvature", 0.48, 0.0...1.0, .warp),
        TextureParameter("texture_vein_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("texture_luminescence", 0.74, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Chromatophore", .abstract, .cellular, scale: 0.008,
      colours: [0xFF16_0918, 0xFF6A_275F, 0xFFE2_576F, 0xFF5C_F277],
      [
        TextureParameter("texture_cell_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_pulse_phase", 0.52, 0.0...1.0, .angle),
        TextureParameter("texture_cell_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("texture_iridescence", 0.7, 0.0...1.0, .other),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "BiomechanicalTissue", .abstract, .bands, scale: 0.008,
      colours: [0xFF10_0C12, 0xFF55_3444, 0xFFB9_7472, 0xFFF0_CAB0],
      [
        TextureParameter("texture_rib_density", 0.66, 0.0...1.0, .frequency),
        TextureParameter("texture_tension", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_ridge_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("texture_wet_sheen", 0.62, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "GildedFiligree", .abstract, .spiral, scale: 0.008,
      colours: [0xFF0A_1019, 0xFF16_3B58, 0xFFC3_8A2A, 0xFFFF_E49A],
      [
        TextureParameter("texture_curl_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_ornament", 0.46, 0.0...1.0, .other),
        TextureParameter("texture_line_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("texture_metallic", 0.74, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "AncientRunes", .patterns, .edge, scale: 0.008,
      colours: [0xFF0B_0C12, 0xFF34_364A, 0xFFA8_5F35, 0xFFFF_D27A],
      [
        TextureParameter("texture_glyph_density", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_erosion", 0.54, 0.0...1.0, .gain),
        TextureParameter("texture_stroke_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SolarGranulation", .space, .cellular, scale: 0.008,
      colours: [0xFF1C_0502, 0xFF8B_2108, 0xFFF0_6A12, 0xFFFF_F0A0],
      [
        TextureParameter("texture_granule_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_convection", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.74, 0.0...1.0, .softness),
        TextureParameter("texture_heat_glow", 0.86, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "LunarEjecta", .space, .cellular, scale: 0.008,
      colours: [0xFF0B_0D11, 0xFF35_3A42, 0xFF8B_9098, 0xFFE6_E1D5],
      [
        TextureParameter("texture_crater_density", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_ray_length", 0.48, 0.0...1.0, .other),
        TextureParameter("texture_rim_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("texture_albedo", 0.5, 0.0...1.0, .other),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "OceanCurrents", .nature, .simplex, scale: 0.007,
      colours: [0xFF03_1629, 0xFF07_5B8B, 0xFF21_B9C2, 0xFFD9_FFF5],
      [
        TextureParameter("texture_current_density", 0.7, 0.0...1.0, .frequency),
        TextureParameter("texture_curl", 0.72, 0.0...1.0, .warp),
        TextureParameter("texture_stream_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("glow", 0.68, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "InkWashMountains", .nature, .ridged, scale: 0.006,
      colours: [0xFFF1_EBDD, 0xFF9A_9A91, 0xFF44_4844, 0xFF11_1716],
      [
        TextureParameter("texture_ridge_count", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_mist", 0.58, 0.0...1.0, .other),
        TextureParameter("texture_ridge_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("texture_paper_glow", 0.42, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "NeonCity", .abstract, .grid, scale: 0.008,
      colours: [0xFF02_040C, 0xFF14_2D59, 0xFFE6_38A1, 0xFF57_F5E9],
      [
        TextureParameter("texture_building_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_perspective", 0.52, 0.0...1.0, .other),
        TextureParameter("texture_edge_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("texture_neon_glow", 0.86, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "PhyllotaxisBloom", .nature, .spiral, scale: 0.008,
      colours: [0xFF07_100D, 0xFF1F_6F4A, 0xFFE0_A733, 0xFFFF_D36A],
      [
        TextureParameter("texture_seed_density", 0.68, 0.0...1.0, .frequency),
        TextureParameter("texture_spiral_angle", 0.62, 0.0...1.0, .angle),
        TextureParameter("texture_seed_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SierpinskiTriangle", .patterns, .sierpinski, scale: 0.008,
      colours: [0xFF05_0713, 0xFF24_4B9A, 0xFF46_BFD0, 0xFFFF_E49A],
      [
        TextureParameter("texture_depth", 0.68, 0.0...1.0, .detail),
        TextureParameter("rotation", 0.5, 0.0...1.0, .angle),
        TextureParameter("texture_edge_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.66, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "ApollonianGasket", .patterns, .edge, scale: 0.008,
      colours: [0xFF08_0511, 0xFF54_2778, 0xFFD3_4EAD, 0xFF75_E8FF],
      [
        TextureParameter("texture_recursion", 0.66, 0.0...1.0, .detail),
        TextureParameter("texture_curvature", 0.52, 0.0...1.0, .warp),
        TextureParameter("texture_boundary_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "HyperbolicTiling", .patterns, .hex, scale: 0.008,
      colours: [0xFF05_0A14, 0xFF24_54A0, 0xFF30_B9B0, 0xFFFF_7A8A],
      [
        TextureParameter("texture_polygon_sides", 0.62, 0.0...1.0, .frequency),
        TextureParameter("texture_curvature", 0.72, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.8, 0.0...1.0, .softness),
        TextureParameter("glow", 0.74, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "MoebiusWeave", .patterns, .bands, scale: 0.008,
      colours: [0xFF08_0A16, 0xFF37_4A94, 0xFFB3_4EC2, 0xFF8F_E3FF],
      [
        TextureParameter("texture_band_count", 0.66, 0.0...1.0, .frequency),
        TextureParameter("texture_twist", 0.62, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.76, 0.0...1.0, .softness),
        TextureParameter("texture_sheen", 0.68, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "RorschachInkblot", .patterns, .fbm, scale: 0.006,
      colours: [0xFFF1_EBDD, 0xFF8B_8590, 0xFF3D_283E, 0xFF10_0C14],
      [
        TextureParameter("texture_lobe_count", 0.64, 0.0...1.0, .frequency),
        TextureParameter("texture_symmetry", 0.92, 0.0...1.0, .other),
        TextureParameter("texture_edge_sharpness", 0.74, 0.0...1.0, .softness),
        TextureParameter("texture_bleed", 0.68, 0.0...1.0, .other),
        TextureParameter("contrast", 1.65, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "SeismicInterference", .abstract, .rings, scale: 0.008,
      colours: [0xFF07_0A12, 0xFF31_5B8D, 0xFFE3_6A42, 0xFFE7_F2FF],
      [
        TextureParameter("texture_source_count", 0.64, 0.0...1.0, .frequency),
        TextureParameter("phase", 0.52, 0.0...1.0, .angle),
        TextureParameter("texture_ridge_sharpness", 0.78, 0.0...1.0, .softness),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "RayleighBenard", .abstract, .edge, scale: 0.008,
      colours: [0xFF18_0603, 0xFF86_2208, 0xFFE7_6A16, 0xFFFF_EDA0],
      [
        TextureParameter("texture_cell_density", 0.7, 0.0...1.0, .frequency),
        TextureParameter("texture_convection", 0.62, 0.0...1.0, .warp),
        TextureParameter("texture_edge_sharpness", 0.72, 0.0...1.0, .softness),
        TextureParameter("texture_heat_glow", 0.82, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.5, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "OrigamiFacets", .patterns, .grid, scale: 0.008,
      colours: [0xFF10_121C, 0xFF58_678B, 0xFFB9_C3D5, 0xFFF0_8470],
      [
        TextureParameter("texture_fold_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_asymmetry", 0.68, 0.0...1.0, .other),
        TextureParameter("texture_crease_sharpness", 0.88, 0.0...1.0, .softness),
        TextureParameter("texture_sheen", 0.42, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "FiberOpticBundle", .abstract, .hex, scale: 0.008,
      colours: [0xFF02_040D, 0xFF18_3C88, 0xFF36_D7E1, 0xFFE8_FFFF],
      [
        TextureParameter("texture_fiber_density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_bend", 0.62, 0.0...1.0, .warp),
        TextureParameter("texture_core_sharpness", 0.82, 0.0...1.0, .softness),
        TextureParameter("glow", 0.88, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.55, 0.0...3.0, .contrast),
      ]
    ),
  ]
}
