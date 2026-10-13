// Generated from the Android texture catalogue. Do not edit by hand.
// Numbers come from FastNoiseTextureParams.kt, labels from FastNoiseParams.kt,
// and the noise family and roles from the generator table.

extension TexturePresets {
  /// FastNoise presets, second part, in the order of the Android catalogue.
  static let fastNoiseSecond: [TexturePreset] = [
    .fastNoise(
      "Moss", .abstract, .fbm, scale: 0.018,
      colours: [0xFF29_2516, 0xFF29_451C, 0xFF64_8044, 0xFFB1_BD69],
      [
        TextureParameter("density", 0.74, 0.0...1.0, .frequency),
        TextureParameter("texture_fibers", 0.58, 0.0...1.0, .other),
        TextureParameter("texture_moisture", 0.38, 0.0...1.0, .other),
        TextureParameter("variation", 0.62, 0.0...1.0, .jitter),
        TextureParameter("texture_clumps", 0.46, 0.0...1.0, .threshold),
      ]
    ),
    .fastNoise(
      "Fire", .abstract, .turbulence, scale: 0.006,
      colours: [0xFF10_0807, 0xFFB5_1B08, 0xFFFF_7A0A, 0xFFFF_E98A],
      [
        TextureParameter("texture_flame_frequency", 8.0, 1.0...32.0, .frequency),
        TextureParameter("turbulence", 36.0, 0.0...64.0, .warp),
        TextureParameter("texture_intensity", 0.78, 0.0...1.0, .glow),
        TextureParameter("texture_smoke_amount", 0.18, 0.0...1.0, .other),
        TextureParameter("texture_detail", 0.62, 0.0...1.0, .detail),
      ]
    ),
    .fastNoise(
      "Aurora", .space, .simplex, scale: 0.004,
      colours: [0xFF06_1227, 0xFF42_D9A0, 0xFF65_E4E8, 0xFFA5_6DE2],
      [
        TextureParameter("texture_ribbons", 7.0, 1.0...32.0, .frequency),
        TextureParameter("distortion", 34.0, 0.0...64.0, .warp),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
        TextureParameter("texture_stars", 0.2, 0.0...1.0, .other),
        TextureParameter("contrast", 1.32, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "OilSlick", .abstract, .bands, scale: 0.008,
      colours: [0xFF10_101A, 0xFFD5_329B, 0xFF25_D4D0, 0xFFF0_C33C],
      [
        TextureParameter("texture_bands", 13.0, 1.0...32.0, .frequency),
        TextureParameter("distortion", 32.0, 0.0...64.0, .warp),
        TextureParameter("texture_iridescence", 0.82, 0.0...1.0, .other),
        TextureParameter("texture_darkness", 0.3, 0.0...1.0, .threshold),
        TextureParameter("contrast", 1.2, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Watercolor", .abstract, .fbm, scale: 0.006,
      colours: [0xFFF4_EBD8, 0xFF33_7FB3, 0xFFD8_5D79, 0xFF49_3F76],
      [
        TextureParameter("texture_blooms", 0.72, 0.0...1.0, .threshold),
        TextureParameter("texture_pigment", 0.65, 0.0...1.0, .other),
        TextureParameter("texture_edges", 0.38, 0.0...1.0, .softness),
        TextureParameter("texture_paper_amount", 0.22, 0.0...1.0, .other),
        TextureParameter("texture_diffusion", 0.62, 0.0...1.0, .warp),
      ]
    ),
    .fastNoise(
      "AbstractFlow", .abstract, .warp, scale: 0.006,
      colours: [0xFF11_1128, 0xFF51_55D9, 0xFFDE_4BB3, 0xFF7E_F2E7],
      [
        TextureParameter("frequency", 12.0, 1.0...32.0, .frequency),
        TextureParameter("distortion", 46.0, 0.0...64.0, .warp),
        TextureParameter("texture_symmetry", 0.3, 0.0...1.0, .other),
        TextureParameter("texture_sharpness", 1.25, 0.0...3.0, .contrast),
        TextureParameter("glow", 0.62, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Opal", .materials, .bands, scale: 0.007,
      colours: [0xFFDD_E8DF, 0xFF4F_D5D1, 0xFFF0_72B6, 0xFFFF_C857],
      [
        TextureParameter("texture_color_play", 0.82, 0.0...1.0, .other),
        TextureParameter("texture_milkiness", 0.48, 0.0...1.0, .threshold),
        TextureParameter("texture_bands", 8.0, 1.0...32.0, .frequency),
        TextureParameter("distortion", 28.0, 0.0...64.0, .warp),
        TextureParameter("glow", 0.62, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "DamascusSteel", .materials, .bands, scale: 0.006,
      colours: [0xFF17_1C20, 0xFF66_727A, 0xFFC8_D0D2, 0xFF30_4C57],
      [
        TextureParameter("texture_layers", 22.0, 1.0...64.0, .frequency),
        TextureParameter("texture_folding", 0.72, 0.0...1.0, .other),
        TextureParameter("distortion", 34.0, 0.0...64.0, .warp),
        TextureParameter("texture_polish", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.4, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "Lightning", .abstract, .ridged, scale: 0.006,
      colours: [0xFF03_0612, 0xFF25_46A8, 0xFF68_C9FF, 0xFFF2_FCFF],
      [
        TextureParameter("texture_branches", 7.0, 1.0...32.0, .frequency),
        TextureParameter("turbulence", 42.0, 0.0...64.0, .warp),
        TextureParameter("width", 0.055, 0.0...1.0, .width),
        TextureParameter("glow", 0.82, 0.0...1.0, .glow),
        TextureParameter("texture_intensity", 0.9, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Velvet", .materials, .value, scale: 0.014,
      colours: [0xFF17_051E, 0xFF5E_176A, 0xFFC1_48B8, 0xFFF0_A6D8],
      [
        TextureParameter("texture_fibers", 0.78, 0.0...1.0, .other),
        TextureParameter("texture_direction", 0.18, 0.0...6.28, .angle),
        TextureParameter("softness", 0.7, 0.0...1.0, .softness),
        TextureParameter("texture_sheen", 0.62, 0.0...1.0, .glow),
        TextureParameter("texture_folds", 0.34, 0.0...1.0, .warp),
      ]
    ),
    .fastNoise(
      "InkMarbling", .abstract, .warp, scale: 0.006,
      colours: [0xFFF3_E9D3, 0xFF16_4B78, 0xFF9D_2949, 0xFF1C_1831],
      [
        TextureParameter("texture_ribbons", 14.0, 1.0...32.0, .frequency),
        TextureParameter("turbulence", 48.0, 0.0...64.0, .warp),
        TextureParameter("texture_feathering", 0.52, 0.0...1.0, .softness),
        TextureParameter("texture_ink_balance", 0.5, 0.0...1.0, .threshold),
        TextureParameter("contrast", 1.25, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "HolographicFoil", .materials, .bands, scale: 0.008,
      colours: [0xFFCD_D4DE, 0xFF4D_E5E2, 0xFFE9_5AC8, 0xFFF7_EA72],
      [
        TextureParameter("texture_spectrum", 12.0, 1.0...32.0, .frequency),
        TextureParameter("texture_crinkles", 0.7, 0.0...1.0, .warp),
        TextureParameter("texture_diffraction", 0.82, 0.0...1.0, .other),
        TextureParameter("angle", 0.3, 0.0...6.28, .angle),
        TextureParameter("shine", 0.72, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "Bioluminescence", .abstract, .turbulence, scale: 0.009,
      colours: [0xFF03_1A1A, 0xFF0B_514D, 0xFF20_E6C2, 0xFFC4_FFF1],
      [
        TextureParameter("texture_veins", 0.72, 0.0...1.0, .other),
        TextureParameter("texture_branching", 0.58, 0.0...1.0, .detail),
        TextureParameter("turbulence", 30.0, 0.0...64.0, .warp),
        TextureParameter("glow", 0.86, 0.0...1.0, .glow),
        TextureParameter("texture_depth", 0.62, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "CosmicVortex", .space, .spiral, scale: 0.008,
      colours: [0xFF02_030B, 0xFF27_4AA8, 0xFF8D_3EC2, 0xFFFF_DDA0],
      [
        TextureParameter("texture_arms", 5.0, 1.0...16.0, .frequency),
        TextureParameter("texture_twist", 12.0, 0.0...32.0, .warp),
        TextureParameter("turbulence", 0.52, 0.0...1.0, .warp),
        TextureParameter("texture_stars", 0.28, 0.0...1.0, .other),
        TextureParameter("texture_core_glow", 0.82, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "LavaLamp", .abstract, .fbm, scale: 0.007,
      colours: [0xFF1C_0929, 0xFFFF_3D81, 0xFFFF_8A24, 0xFFFF_D45C],
      [
        TextureParameter("texture_blobs", 6.0, 1.0...16.0, .frequency),
        TextureParameter("softness", 0.24, 0.0...1.0, .softness),
        TextureParameter("distortion", 32.0, 0.0...64.0, .warp),
        TextureParameter("glow", 0.58, 0.0...1.0, .glow),
        TextureParameter("contrast", 1.3, 0.0...3.0, .contrast),
      ]
    ),
    .fastNoise(
      "EventHorizon", .space, .rings, scale: 0.008,
      colours: [0xFF01_0107, 0xFFFF_5A18, 0xFFFF_E0A3, 0xFF7C_48FF],
      [
        TextureParameter("texture_disk_tilt", 0.72, 0.0...1.0, .other),
        TextureParameter("texture_horizon_size", 0.15, 0.0...1.0, .threshold),
        TextureParameter("texture_disk_width", 0.065, 0.0...1.0, .width),
        TextureParameter("texture_lensing", 0.82, 0.0...1.0, .warp),
        TextureParameter("texture_stars", 0.22, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "FractalBloom", .abstract, .radial, scale: 0.01,
      colours: [0xFF09_061B, 0xFF59_40D6, 0xFFFF_3E93, 0xFFFF_E88A],
      [
        TextureParameter("texture_petals", 7.0, 1.0...16.0, .frequency),
        TextureParameter("texture_layers", 5.0, 1.0...16.0, .detail),
        TextureParameter("texture_curl", 4.2, 0.0...12.0, .warp),
        TextureParameter("texture_filigree", 0.7, 0.0...1.0, .other),
        TextureParameter("glow", 0.72, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "ChromaticTunnel", .abstract, .rings, scale: 0.009,
      colours: [0xFF03_0516, 0xFF00_D5FF, 0xFFFF_2C9C, 0xFFFF_F1B8],
      [
        TextureParameter("texture_depth", 18.0, 1.0...32.0, .frequency),
        TextureParameter("texture_twist", 5.5, 0.0...16.0, .warp),
        TextureParameter("texture_facets", 7.0, 1.0...16.0, .other),
        TextureParameter("texture_curvature", 0.48, 0.0...1.0, .warp),
        TextureParameter("glow", 0.78, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "EclipseCorona", .space, .radial, scale: 0.008,
      colours: [0xFF02_030A, 0xFF76_5BFF, 0xFFFF_9B45, 0xFFFF_FFFF],
      [
        TextureParameter("texture_moon_size", 0.23, 0.0...1.0, .threshold),
        TextureParameter("texture_corona_size", 0.2, 0.0...1.0, .other),
        TextureParameter("texture_rays", 34.0, 1.0...64.0, .frequency),
        TextureParameter("turbulence", 0.62, 0.0...1.0, .warp),
        TextureParameter("texture_diamond_ring", 0.8, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "StrangeAttractor", .abstract, .rings, scale: 0.01,
      colours: [0xFF03_0511, 0xFF14_D9C5, 0xFFFF_3A79, 0xFFFF_F1B5],
      [
        TextureParameter("texture_lobes", 3.0, 1.0...8.0, .frequency),
        TextureParameter("texture_orbit_density", 18.0, 1.0...64.0, .other),
        TextureParameter("texture_curvature", 6.0, 0.0...12.0, .warp),
        TextureParameter("texture_thickness", 0.035, 0.0...1.0, .width),
        TextureParameter("glow", 0.8, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "FerrofluidCrown", .abstract, .radial, scale: 0.012,
      colours: [0xFFE8_E1D4, 0xFF07_090C, 0xFF35_3D43, 0xFFD9_F7FF],
      [
        TextureParameter("texture_spikes", 19.0, 1.0...32.0, .frequency),
        TextureParameter("texture_spike_length", 0.14, 0.0...1.0, .other),
        TextureParameter("texture_body_size", 0.22, 0.0...1.0, .threshold),
        TextureParameter("texture_metallic", 0.86, 0.0...1.0, .glow),
        TextureParameter("distortion", 0.42, 0.0...1.0, .warp),
      ]
    ),
    .fastNoise(
      "Supernova", .space, .rings, scale: 0.01,
      colours: [0xFF02_030B, 0xFF69_23B7, 0xFFFF_4D22, 0xFFFF_F2C5],
      [
        TextureParameter("texture_shock_radius", 0.27, 0.0...1.0, .threshold),
        TextureParameter("texture_shell_width", 0.075, 0.0...1.0, .width),
        TextureParameter("texture_ejecta", 0.72, 0.0...1.0, .other),
        TextureParameter("turbulence", 0.68, 0.0...1.0, .warp),
        TextureParameter("texture_stars", 0.24, 0.0...1.0, .other),
      ]
    ),
    .fastNoise(
      "Iris", .abstract, .radial, scale: 0.014,
      colours: [0xFF08_0A0D, 0xFF12_3646, 0xFF37_B6A5, 0xFFE6_B650],
      [
        TextureParameter("texture_pupil_size", 0.12, 0.0...1.0, .threshold),
        TextureParameter("texture_iris_size", 0.38, 0.0...1.0, .other),
        TextureParameter("texture_fibers", 46.0, 1.0...96.0, .frequency),
        TextureParameter("texture_color_variation", 0.72, 0.0...1.0, .other),
        TextureParameter("texture_catchlight", 0.82, 0.0...1.0, .glow),
      ]
    ),
    .fastNoise(
      "PeacockFeather", .abstract, .radial, scale: 0.012,
      colours: [0xFF06_150F, 0xFF16_7D55, 0xFF12_48BC, 0xFFE4_BC45],
      [
        TextureParameter("texture_eye_size", 0.24, 0.0...1.0, .threshold),
        TextureParameter("texture_barb_density", 54.0, 1.0...96.0, .frequency),
        TextureParameter("texture_curvature", 0.58, 0.0...1.0, .warp),
        TextureParameter("texture_iridescence", 0.8, 0.0...1.0, .other),
        TextureParameter("softness", 0.42, 0.0...1.0, .softness),
      ]
    ),
    .fastNoise(
      "NautilusShell", .abstract, .spiral, scale: 0.011,
      colours: [0xFF15_2228, 0xFF4A_2D22, 0xFFD9_AD79, 0xFFFF_F0D1],
      [
        TextureParameter("texture_turns", 3.4, 1.0...8.0, .frequency),
        TextureParameter("texture_chambers", 19.0, 1.0...32.0, .other),
        TextureParameter("texture_opening", 0.13, 0.0...1.0, .threshold),
        TextureParameter("texture_ridges", 0.68, 0.0...1.0, .width),
        TextureParameter("texture_pearlescence", 0.46, 0.0...1.0, .glow),
      ]
    ),
  ]
}
