// Generated from the Android texture catalogue. Do not edit by hand.
// Numbers come from FastNoiseTextureParams.kt, labels from FastNoiseParams.kt,
// and the noise family and roles from the generator table.

extension TexturePresets {
  /// FastNoise presets, first part, in the order of the Android catalogue.
  static let fastNoiseFirst: [TexturePreset] = [
    .fastNoise(
      "Brick", .materials, .grid, scale: 0.02,
      colours: [0xFFB8_AD99, 0xFF6F_2418, 0xFFB6_4C32, 0xFFD7_7A55],
      [
        TextureParameter("aspect_ratio", 2.15, 0.5...4.0, .aspect),
        TextureParameter("texture_mortar_width", 0.09, 0.0...1.0, .width),
        TextureParameter("texture_irregularity", 0.18, 0.0...1.0, .jitter),
        TextureParameter("texture_roughness", 0.42, 0.0...1.0, .gain),
        TextureParameter("texture_bevel", 0.55, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Camouflage", .abstract, .fbm, scale: 0.007,
      colours: [0xFF20_2719, 0xFF4F_6134, 0xFF78_6344, 0xFFB4_A477],
      [
        TextureParameter("texture_first_threshold", 0.36, 0.0...1.0, .threshold),
        TextureParameter("texture_second_threshold", 0.58, 0.0...1.0, .other),
        TextureParameter("texture_third_threshold", 0.76, 0.0...1.0, .other),
        TextureParameter("distortion", 28.0, 0.0...64.0, .warp),
        TextureParameter("texture_edge_softness", 0.035, 0.0...1.0, .softness),
      ]
    ),
    .fastNoise(
      "Cell", .abstract, .edge, scale: 0.018,
      colours: [0xFF10_1A24, 0xFF21_6E78, 0xFF5A_D1C8, 0xFFC9_FFF4],
      [
        TextureParameter("jitter", 0.92, 0.0...1.0, .jitter),
        TextureParameter("texture_border_width", 0.12, 0.0...1.0, .width),
        TextureParameter("glow", 0.28, 0.0...1.0, .glow),
        TextureParameter("distortion", 6.0, 0.0...64.0, .warp),
        TextureParameter("variation", 0.42, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Cloud", .abstract, .fbm, scale: 0.0045,
      colours: [0xFF6F_A9DC, 0xFF9E_ADBC, 0xFFF8_FBFF],
      [
        TextureParameter("texture_coverage", 0.48, 0.0...1.0, .threshold),
        TextureParameter("softness", 0.22, 0.0...1.0, .softness),
        TextureParameter("texture_detail", 0.62, 0.0...1.0, .detail),
        TextureParameter("distortion", 24.0, 0.0...64.0, .warp),
        TextureParameter("density", 0.92, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Crack", .abstract, .edge, scale: 0.019,
      colours: [0xFF8D_8374, 0xFFC0_B6A5, 0xFF16_1412, 0xFF55_4E45],
      [
        TextureParameter("width", 0.065, 0.0...1.0, .width),
        TextureParameter("density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("distortion", 9.0, 0.0...64.0, .warp),
        TextureParameter("texture_depth", 0.72, 0.0...1.0, .other),
        TextureParameter("texture_branching", 0.45, 0.0...1.0, .detail),
      ]
    ),
    .fastNoise(
      "Fabric", .materials, .grid, scale: 0.018,
      colours: [0xFF49_6B82, 0xFF78_95A7, 0xFF26_3C4B, 0xFFB6_CAD4],
      [
        TextureParameter("texture_horizontal_threads", 28.0, 1.0...64.0, .frequency),
        TextureParameter("texture_vertical_threads", 28.0, 1.0...64.0, .frequency),
        TextureParameter("texture_irregularity", 0.14, 0.0...1.0, .jitter),
        TextureParameter("texture_depth", 0.48, 0.0...1.0, .other),
        TextureParameter("texture_fuzz", 0.1, 0.0...1.0, .gain),
      ]
    ),
    .fastNoise(
      "Foliage", .nature, .fbm, scale: 0.022,
      colours: [0xFF10_2A13, 0xFF24_5C25, 0xFF4E_9A3D, 0xFFA4_CE65],
      [
        TextureParameter("density", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_edge_softness", 0.16, 0.0...1.0, .softness),
        TextureParameter("texture_veins", 0.38, 0.0...1.0, .other),
        TextureParameter("texture_lighting", 0.62, 0.0...1.0, .glow),
        TextureParameter("variation", 0.58, 0.0...1.0, .jitter),
      ]
    ),
    .fastNoise(
      "Honeycomb", .patterns, .hex, scale: 0.018,
      colours: [0xFF24_1305, 0xFF6F_3A08, 0xFFE5_9B12, 0xFFFF_D45C],
      [
        TextureParameter("texture_border_width", 0.095, 0.0...1.0, .width),
        TextureParameter("texture_bevel", 0.5, 0.0...1.0, .other),
        TextureParameter("texture_irregularity", 0.12, 0.0...1.0, .jitter),
        TextureParameter("fill", 0.72, 0.0...1.0, .threshold),
        TextureParameter("glow", 0.35, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Ice", .materials, .edge, scale: 0.014,
      colours: [0xFF15_5A79, 0xFF79_C8DC, 0xFFD8_F4F5, 0xFFF5_FFFF],
      [
        TextureParameter("texture_crack_width", 0.075, 0.0...1.0, .width),
        TextureParameter("texture_frost", 0.48, 0.0...1.0, .other),
        TextureParameter("texture_depth", 0.64, 0.0...1.0, .other),
        TextureParameter("distortion", 8.0, 0.0...64.0, .warp),
        TextureParameter("sparkle", 0.32, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Lava", .abstract, .warp, scale: 0.008,
      colours: [0xFF12_0B0A, 0xFFD5_2B0A, 0xFFFF_D45A],
      [
        TextureParameter("distortion", 32.0, 0.0...64.0, .warp),
        TextureParameter("texture_flow", 1.35, 0.0...4.0, .other),
        TextureParameter("texture_detail", 0.55, 0.0...1.0, .detail),
        TextureParameter("texture_crust", 0.52, 0.0...1.0, .threshold),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Nebula", .space, .turbulence, scale: 0.004,
      colours: [0xFF05_0713, 0xFF54_2577, 0xFF23_67A2, 0xFFF2_A4DF],
      [
        TextureParameter("turbulence", 44.0, 0.0...64.0, .warp),
        TextureParameter("texture_cloud_density", 0.64, 0.0...1.0, .threshold),
        TextureParameter("texture_stars", 0.38, 0.0...1.0, .other),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.45, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Paper", .materials, .value, scale: 0.012,
      colours: [0xFFE4_D4AE, 0xFFF5_E9C9, 0xFFB5_9C70, 0xFF8A_6841],
      [
        TextureParameter("texture_fiber_density", 72.0, 1.0...128.0, .frequency),
        TextureParameter("texture_fiber_strength", 0.24, 0.0...1.0, .other),
        TextureParameter("grain", 0.16, 0.0...1.0, .gain),
        TextureParameter("texture_stains", 0.14, 0.0...1.0, .other),
        TextureParameter("texture_roughness", 0.35, 0.0...1.0, .gain),
      ]
    ),
    .fastNoise(
      "Rust", .materials, .fbm, scale: 0.009,
      colours: [0xFF59_6065, 0xFF3A_170B, 0xFF9B_3E13, 0xFFE0_7822],
      [
        TextureParameter("texture_corrosion", 0.55, 0.0...1.0, .threshold),
        TextureParameter("texture_pitting", 0.0, 0.0...1.0, .jitter),
        TextureParameter("texture_flakes", 0.42, 0.0...1.0, .other),
        TextureParameter("distortion", 16.0, 0.0...64.0, .warp),
        TextureParameter("contrast", 1.25, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Sand", .nature, .bands, scale: 0.005,
      colours: [0xFF9A_632E, 0xFFD6_A85A, 0xFFF2_D58D],
      [
        TextureParameter("texture_dune_frequency", 12.0, 1.0...32.0, .frequency),
        TextureParameter("texture_wind_angle", 0.32, 0.0...6.28, .angle),
        TextureParameter("texture_ripples", 0.62, 0.0...1.0, .other),
        TextureParameter("grain", 0.22, 0.0...1.0, .gain),
        TextureParameter("contrast", 1.18, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Smoke", .abstract, .turbulence, scale: 0.006,
      colours: [0xFF11_1318, 0xFF44_4A52, 0xFFD5_D9DD],
      [
        TextureParameter("turbulence", 34.0, 0.0...64.0, .warp),
        TextureParameter("density", 0.56, 0.0...1.0, .threshold),
        TextureParameter("texture_wisps", 2.2, 0.0...5.0, .other),
        TextureParameter("contrast", 1.35, 0.0...3.0, .contrast),
        TextureParameter("texture_detail", 0.5, 0.0...1.0, .detail),
      ]
    ),
    .fastNoise(
      "Stone", .materials, .cellular, scale: 0.011,
      colours: [0xFF34_3536, 0xFFAA_A79F, 0xFFE2_DED3],
      [
        TextureParameter("grain", 0.3, 0.0...1.0, .gain),
        TextureParameter("texture_veins", 0.58, 0.0...1.0, .other),
        TextureParameter("texture_vein_scale", 0.024, 0.001...0.1, .width),
        TextureParameter("distortion", 18.0, 0.0...64.0, .warp),
        TextureParameter("contrast", 1.12, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Terrain", .abstract, .fbm, scale: 0.0045,
      colours: [0xFF19_4D73, 0xFF5F_873F, 0xFF74_6C5D, 0xFFE9_EEE8],
      [
        TextureParameter("texture_water_level", 0.34, 0.0...1.0, .threshold),
        TextureParameter("texture_mountain_level", 0.7, 0.0...1.0, .other),
        TextureParameter("texture_erosion", 0.46, 0.0...1.0, .gain),
        TextureParameter("texture_detail", 0.58, 0.0...1.0, .detail),
        TextureParameter("texture_snow_level", 0.86, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Topography", .patterns, .bands, scale: 0.0055,
      colours: [0xFF17_3C3B, 0xFFB5_C98A, 0xFFF2_E6B6],
      [
        TextureParameter("texture_line_count", 16.0, 1.0...32.0, .frequency),
        TextureParameter("texture_line_thickness", 0.11, 0.0...1.0, .width),
        TextureParameter("texture_shading", 0.42, 0.0...1.0, .glow),
        TextureParameter("distortion", 12.0, 0.0...64.0, .warp),
        TextureParameter("contrast", 1.1, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "WaterRipple", .nature, .rings, scale: 0.0075,
      colours: [0xFF07_3456, 0xFF16_8EAE, 0xFFB9_F7F2],
      [
        TextureParameter("frequency", 22.0, 1.0...48.0, .frequency),
        TextureParameter("distortion", 22.0, 0.0...64.0, .warp),
        TextureParameter("texture_caustics", 0.58, 0.0...1.0, .other),
        TextureParameter("texture_depth", 0.55, 0.0...1.0, .other),
        TextureParameter("highlights", 0.62, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "AdvancedWood", .materials, .rings, scale: 0.0039,
      colours: [0xFF3A_190B, 0xFFB9_6E32, 0xFF1D_0D07],
      [
        TextureParameter("rings", 11.4, 1.0...32.0, .frequency),
        TextureParameter("grain", 0.3, 0.0...1.0, .gain),
        TextureParameter("distortion", 15.0, 0.0...64.0, .warp),
        TextureParameter("stretch", 7.42, 1.0...16.0, .aspect),
        TextureParameter("contrast", 0.17, 0.0...1.0, .contrast),
      ]
    ),
    .fastNoise(
      "Grass", .nature, .bands, scale: 0.012,
      colours: [0xFF3A_2B18, 0xFF1D_491F, 0xFF4D_8A32, 0xFF9B_C45A],
      [
        TextureParameter("texture_blade_density", 1.0, 0.0...2.0, .frequency),
        TextureParameter("texture_blade_length", 50.0, 1.0...100.0, .width),
        TextureParameter("texture_wind", 1.0, 0.0...2.0, .warp),
        TextureParameter("texture_patchiness", 0.35, 0.0...1.0, .threshold),
        TextureParameter("highlights", 0.45, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Dirt", .nature, .fbm, scale: 0.009,
      colours: [0xFF2A_190E, 0xFF69_4226, 0xFFA1_764D, 0xFFB1_A28C],
      [
        TextureParameter("texture_clumps", 0.62, 0.0...1.0, .threshold),
        TextureParameter("texture_moisture", 0.35, 0.0...1.0, .other),
        TextureParameter("texture_pebbles", 0.22, 0.0...1.0, .jitter),
        TextureParameter("texture_roughness", 0.68, 0.0...1.0, .gain),
        TextureParameter("variation", 0.52, 0.0...1.0, .jitter),
      ]
    ),
    .fastNoise(
      "Leather", .materials, .value, scale: 0.011,
      colours: [0xFF30_160F, 0xFF7B_3D25, 0xFFB3_6B43, 0xFF1C_0C08],
      [
        TextureParameter("texture_wrinkles", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_pores", 0.42, 0.0...1.0, .jitter),
        TextureParameter("grain", 0.5, 0.0...1.0, .gain),
        TextureParameter("softness", 0.38, 0.0...1.0, .softness),
        TextureParameter("shine", 0.035, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Concrete", .materials, .cellular, scale: 0.014,
      colours: [0xFF5A_5955, 0xFF99_968E, 0xFFC7_C3B9, 0xFF35_3532],
      [
        TextureParameter("texture_aggregate", 0.45, 0.0...1.0, .frequency),
        TextureParameter("texture_stains", 0.28, 0.0...1.0, .other),
        TextureParameter("texture_roughness", 0.65, 0.0...1.0, .gain),
        TextureParameter("texture_cracks", 0.14, 0.0...1.0, .width),
        TextureParameter("contrast", 1.08, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Asphalt", .materials, .cellular, scale: 0.02,
      colours: [0xFF17_191A, 0xFF3E_4242, 0xFF89_8B85, 0xFFB0_A995],
      [
        TextureParameter("texture_aggregate", 0.72, 0.0...1.0, .frequency),
        TextureParameter("texture_tar", 0.44, 0.0...1.0, .other),
        TextureParameter("texture_wear", 0.28, 0.0...1.0, .gain),
        TextureParameter("texture_speckles", 0.48, 0.0...1.0, .jitter),
        TextureParameter("contrast", 1.3, 0.0...3.0, .contrast),
      ]
    ),
  ]
}
