import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Texture presets")
struct TexturePresetTests {

  private func sourceName(_ source: TexturePresetSource) -> String {
    switch source {
    case .fastNoise: "fastNoise"
    case .pattern: "pattern"
    case .raymarch: "raymarch"
    case .classic: "classic"
    }
  }

  @Test("the catalogue holds the 177 Android presets, split by renderer")
  func catalogueCounts() {
    let all = TexturePresets.all
    #expect(all.count == 177)
    #expect(Set(all.map(\.id)).count == 177, "ids must be unique")
    let bySource = Dictionary(grouping: all, by: { sourceName($0.source) }).mapValues(\.count)
    #expect(bySource == ["fastNoise": 122, "pattern": 28, "raymarch": 15, "classic": 12])
  }

  @Test("categories match the Android TextureCategory mapping")
  func categoryCounts() {
    let all = TexturePresets.all
    let byCategory = Dictionary(grouping: all, by: \.category).mapValues(\.count)
    #expect(
      byCategory == [.nature: 19, .materials: 26, .space: 12, .patterns: 65, .abstract: 55])
    let listed = TextureCategory.allCases.reduce(0) { $0 + TexturePresets.presets(in: $1).count }
    #expect(listed == 177)
    #expect(TexturePresets.preset(id: "Brick")?.category == .materials)
    #expect(TexturePresets.preset(id: "Cloud")?.category == .abstract)
    #expect(TexturePresets.preset(id: "Mandelbrot")?.category == .patterns)
    #expect(TexturePresets.preset(id: "Mandelbrot")?.isApproximation == false)
    #expect(TexturePresets.preset(id: "Check")?.category == .patterns)
    #expect(TexturePresets.preset(id: "Truchet")?.category == .patterns)
    #expect(TexturePresets.preset(id: "BrushedMetal")?.category == .materials)
  }

  @Test("FastNoise defaults are copied from the Android presets")
  func fastNoiseDefaults() throws {
    let brick = try #require(TexturePresets.preset(id: "Brick"))
    #expect(brick.source == .fastNoise(.grid))
    #expect(brick.scale == 0.02)
    #expect(brick.colours == [0xFFB8_AD99, 0xFF6F_2418, 0xFFB6_4C32, 0xFFD7_7A55])
    #expect(brick.parameters.count == 5)
    #expect(
      brick.parameters[0] == TextureParameter("aspect_ratio", 2.15, 0.5...4, .aspect))
    #expect(brick.parameters[4].role == .other)

    let cloud = try #require(TexturePresets.preset(id: "Cloud"))
    #expect(cloud.scale == 0.0045)
    #expect(cloud.colours.count == 3)
    #expect(cloud.parameters[1].value == 0.22)

    let geode = try #require(TexturePresets.preset(id: "Geode"))
    #expect(geode.parameters.last?.role == .contrast)
  }

  @Test("pattern, raymarch and classic defaults come from the Android code")
  func otherDefaults() throws {
    let hatch = try #require(TexturePresets.preset(id: "HatchPattern"))
    #expect(hatch.source == .pattern(.hatchPattern))
    #expect(hatch.scale == 12)
    #expect(hatch.colours.count == 4)
    #expect(hatch.parameters == [TextureParameter("thickness", 0.5, 0.02...0.98)])

    let sphere = try #require(TexturePresets.preset(id: "Sphere3D"))
    #expect(sphere.source == .raymarch(.sphere3D))
    #expect(sphere.parameters.count == 17)
    #expect(sphere.value("fieldOfView") == 45)
    #expect(sphere.colours.count == 2)
    #expect(sphere.colours[0] >> 24 == 0xFF)

    let metal = try #require(TexturePresets.preset(id: "BrushedMetal"))
    #expect(metal.source == .classic(.brushedMetal))
    #expect(metal.colours == [0xFF88_8888])
  }

  @Test("titles split the camel case of the id")
  func titles() throws {
    #expect(try #require(TexturePresets.preset(id: "AdvancedWood")).title == "Advanced Wood")
    #expect(
      try #require(TexturePresets.preset(id: "SquareSpiralPattern")).title
        == "Square Spiral Pattern")
    #expect(try #require(TexturePresets.preset(id: "Sphere3D")).title == "Sphere3D")
    #expect(try #require(TexturePresets.preset(id: "XRayBotanical")).title == "X Ray Botanical")
  }

  @Test("parameter defaults lie inside their Android slider ranges")
  func defaultsInRange() {
    for preset in TexturePresets.all {
      for parameter in preset.parameters {
        #expect(
          parameter.range.contains(parameter.value),
          "\(preset.id).\(parameter.name) is outside its range")
      }
    }
  }

  @Test("every FastNoise value has a role and five values per preset")
  func fastNoiseRoles() {
    for preset in TexturePresets.all {
      guard case .fastNoise = preset.source else { continue }
      #expect(preset.parameters.count == 5, "\(preset.id) does not have five values")
      #expect(
        preset.parameters.allSatisfy { $0.role != nil },
        "\(preset.id) has a value without a role")
    }
  }

  @Test("FastNoise presets are the native textures, with the native parameter order")
  func fastNoiseTableMatchesPresets() throws {
    var fastNoise = 0
    for preset in TexturePresets.all {
      guard case .fastNoise = preset.source else { continue }
      fastNoise += 1
      let entry = try #require(NativeTextureTable.entry(for: preset.id), "\(preset.id)")
      #expect(entry.colours == preset.colours, "\(preset.id) colours differ")
      #expect(entry.parameters.first == Float(preset.scale), "\(preset.id) scale differs")
      let values = Array(entry.parameters.dropFirst())
      #expect(values == preset.parameters.map { Float($0.value) }, "\(preset.id) values differ")
    }
    #expect(fastNoise == 122)
  }

  @Test("FastNoise presets match the Android native code pixel for pixel at 64 by 64")
  func fastNoiseMatchesNativeCode() {
    for preset in TexturePresets.all {
      guard case .fastNoise = preset.source else { continue }
      let image = TexturePresetRenderer.render(preset, seed: 1337, width: 64, height: 64)
      let hash = fnv1a(image?.pixels ?? [])
      #expect(hash == nativeGoldenHashes[preset.id], "\(preset.id) differs from the native code")
    }
  }

  @Test("every preset renders at the requested size, opaque except where the native code blends")
  func everyPresetRenders() {
    for preset in TexturePresets.all {
      let image = TexturePresetRenderer.render(preset, seed: 3, width: 37, height: 29)
      #expect(image != nil, "\(preset.id) did not render")
      #expect(image?.width == 37)
      #expect(image?.height == 29)
      #expect(image?.pixels.count == 37 * 29 * 4)
      // The native mixing truncates its alpha, so Caustics can land on 254. Raymarch pictures
      // keep the transparent background of the Android preset, and are checked in their own suite.
      if case .raymarch = preset.source { continue }
      var translucent = 0
      for index in stride(from: 3, to: image?.pixels.count ?? 0, by: 4)
      where (image?.pixels[index] ?? 0) < 254 {
        translucent += 1
      }
      #expect(translucent == 0, "\(preset.id) has transparent pixels")
    }
  }

  @Test("every preset draws a picture that is not a single colour")
  func everyPresetHasDetail() {
    for preset in TexturePresets.all {
      guard let image = TexturePresetRenderer.render(preset, seed: 11, width: 128, height: 128)
      else {
        Issue.record("\(preset.id) did not render")
        continue
      }
      var colours = Set<UInt32>()
      for index in stride(from: 0, to: image.pixels.count, by: 4) {
        let packed =
          UInt32(image.pixels[index]) << 16 | UInt32(image.pixels[index + 1]) << 8
          | UInt32(image.pixels[index + 2])
        colours.insert(packed)
      }
      #expect(colours.count > 1, "\(preset.id) is one colour")
    }
  }

  @Test("the same preset, seed and size always give the same picture")
  func deterministic() {
    for preset in TexturePresets.all {
      let first = TexturePresetRenderer.render(preset, seed: 7, width: 40, height: 40)
      let second = TexturePresetRenderer.render(preset, seed: 7, width: 40, height: 40)
      #expect(first?.pixels == second?.pixels, "\(preset.id) is not deterministic")
    }
  }

  @Test("the seed changes every FastNoise preset whose native code reads it")
  func seedChangesNoise() {
    // These native textures are pure geometry or escape-time fractals: their code never reads the
    // seed, so their picture is the same for every seed.
    let seedFree: Set<String> = [
      "ApollonianGasket", "BurningShip", "ChladniPlate", "CymaticRosette", "FiberOpticBundle",
      "GildedFiligree", "JuliaSet", "KaleidoscopeCrystal", "Mandelbrot", "MicroscopicDiatoms",
      "MoebiusWeave", "MoireGuilloche", "OrigamiFacets", "PhyllotaxisBloom", "PrismaticLight",
      "Quasicrystal", "SierpinskiTriangle", "SpectralPrism", "TopologicalKnot",
    ]
    let presets = TexturePresets.all.filter {
      if case .fastNoise = $0.source { return true }
      return false
    }
    #expect(presets.count == 122)
    for preset in presets {
      let first = TexturePresetRenderer.render(preset, seed: 1, width: 128, height: 128)
      let second = TexturePresetRenderer.render(preset, seed: 2, width: 128, height: 128)
      if seedFree.contains(preset.id) {
        #expect(first?.pixels == second?.pixels, "\(preset.id) should not depend on the seed")
      } else {
        #expect(first?.pixels != second?.pixels, "\(preset.id) ignores the seed")
      }
    }
  }

  @Test("empty sizes give nil")
  func emptySizes() {
    let preset = TexturePresets.all[0]
    #expect(TexturePresetRenderer.render(preset, seed: 1, width: 0, height: 5) == nil)
    #expect(TexturePresetRenderer.render(preset, seed: 1, width: 5, height: -1) == nil)
  }
}

/// FNV-1a over the RGBA bytes of a picture.
private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
  var hash: UInt64 = 1_469_598_103_934_665_603
  for byte in bytes {
    hash ^= UInt64(byte)
    hash = hash &* 1_099_511_628_211
  }
  return hash
}

/// The FNV-1a hash of the 64 by 64 picture of each FastNoise preset with seed 1337, from the
/// native code of the Android fast-noise module compiled with clang (`-ffp-contract=off`).
private let nativeGoldenHashes: [String: UInt64] = [
  "Lava": 0x9b24_f8d0_3480_b3f9,
  "Cloud": 0xf93c_7394_486c_f63c,
  "Smoke": 0xda16_a79c_34ff_8bfb,
  "Stone": 0x6b99_9f55_d144_9bff,
  "AdvancedWood": 0x3f4b_4632_e1b9_e9fb,
  "Camouflage": 0xc20b_e1a9_f369_f282,
  "Paper": 0x06b6_7fc9_db03_af70,
  "Rust": 0x12dd_1c36_8d44_c794,
  "Fabric": 0x9f78_8639_920e_e45a,
  "Topography": 0x49a9_40a8_2041_804b,
  "Cell": 0x3b09_3885_8c7f_ce11,
  "Crack": 0x47e8_e43c_accd_6107,
  "WaterRipple": 0x6e21_fca8_0fdb_e85c,
  "Foliage": 0xbf0e_f74b_5b27_f423,
  "Brick": 0xfcb0_f3c2_2dd4_7613,
  "Terrain": 0x5d4d_aeba_6d0c_b853,
  "Ice": 0xe773_5513_1e86_7ea8,
  "Sand": 0x3208_9c1a_1d14_09c3,
  "Nebula": 0x2d07_31ec_0f3e_b754,
  "Honeycomb": 0x0e38_efc2_2553_635c,
  "Grass": 0x5945_1d46_c5b3_e7aa,
  "Dirt": 0xbda7_f687_7093_cd1b,
  "Leather": 0x9149_94ac_b2cf_6d62,
  "Concrete": 0x7e7b_e450_1c0f_9e15,
  "Asphalt": 0x7cda_7269_bc46_443b,
  "Moss": 0x0ff6_c32e_0cb9_1ac7,
  "Fire": 0xc184_8651_1422_3199,
  "Aurora": 0x3009_755c_4a4e_2dfe,
  "OilSlick": 0xc807_26e2_f00d_f8d0,
  "Watercolor": 0xea6f_5a85_e729_d0e0,
  "AbstractFlow": 0x6749_ff7e_e68b_ff48,
  "Opal": 0xc8e7_ff10_949b_6e1c,
  "DamascusSteel": 0x1dcd_3cb7_8df7_a7ff,
  "Lightning": 0x0835_cfe6_a701_5e5f,
  "Velvet": 0xb97b_d864_1fa4_df5c,
  "InkMarbling": 0xb16d_e6c6_5564_40cc,
  "HolographicFoil": 0xd612_f992_1f9b_88ed,
  "Bioluminescence": 0xaa5d_ca1a_be8c_e883,
  "CosmicVortex": 0xef7b_6aed_5736_a909,
  "LavaLamp": 0x98f0_e56d_a0b9_4761,
  "EventHorizon": 0x3f15_112e_2f3c_7062,
  "FractalBloom": 0xf181_7514_b8fc_e953,
  "ChromaticTunnel": 0x4fbe_ed9d_9f7c_b1f0,
  "EclipseCorona": 0xa1bc_c7f8_a5be_56d2,
  "StrangeAttractor": 0x6b52_4de9_9e01_0de9,
  "FerrofluidCrown": 0x8b4c_47b6_83ba_56c9,
  "Supernova": 0x12b7_adbc_0c5b_c09c,
  "Iris": 0x0c49_f6eb_eb7c_e46e,
  "PeacockFeather": 0x6f8d_b3c0_535f_c265,
  "NautilusShell": 0x3e38_05ae_d20f_0aca,
  "RingedPlanet": 0xaff0_777a_67f3_d7c9,
  "Geode": 0x117c_f828_03d3_9492,
  "PrismaticLight": 0xf00b_2b46_a117_7d9e,
  "StainedGlass": 0xfd9f_ea9b_bad0_f8e2,
  "KelpForest": 0xcf72_6bbe_211c_19b5,
  "FrostFern": 0xc917_988b_4be8_538a,
  "LiquidCrystal": 0xaf63_0268_f3be_57d7,
  "DragonScales": 0xf569_5756_f305_6235,
  "FireflySwarm": 0x4f97_aff0_bad2_74c9,
  "Mycelium": 0xa4b1_3cea_a9fe_020e,
  "Kintsugi": 0x2065_188d_8b5f_892c,
  "CarbonFiber": 0xe6a9_ffd9_a4bb_804a,
  "CircuitBoard": 0x5db7_9314_e191_f793,
  "SoapFilm": 0xc9bd_2db3_14b2_82c1,
  "MoireGuilloche": 0xb9ef_13d8_85ca_b3e3,
  "SnakeSkin": 0x925c_d036_0ccd_308a,
  "Terrazzo": 0xd104_b51e_e3a5_2131,
  "GalaxyFilaments": 0xd8d0_93e7_8228_0f13,
  "VolcanicObsidian": 0x843f_4f8d_3364_c02c,
  "MotherboardHeatmap": 0xe4e6_0425_b716_1fb7,
  "MicroscopicDiatoms": 0xe434_2cac_bced_b05e,
  "ReactionDiffusion": 0xd2ee_5d3a_1768_9161,
  "CoralGrowth": 0x2cc9_f872_b94c_3d4c,
  "SlimeMold": 0x0aa4_4ad8_fbc4_c973,
  "DendriticCrystal": 0x7d36_832b_1c6a_12b8,
  "ElectricArcField": 0x1acc_a3a4_e176_b40d,
  "CloudChamber": 0xedab_126a_f221_7255,
  "TurbulentInk": 0xdf16_3d41_eee0_7f11,
  "CellularEmbryo": 0xc0e5_c9f2_7969_796c,
  "NeuralGarden": 0xadd9_54ed_70e7_9750,
  "MagneticField": 0x7765_ed35_cf20_ee08,
  "RiverDelta": 0x61fc_8e1f_903a_1c7a,
  "LichenColony": 0xfb18_1673_ddc6_a239,
  "BacterialCulture": 0x16d4_c8fd_268a_583a,
  "FluidVorticity": 0x9df7_c460_f035_539f,
  "CrystalGrowth": 0x583b_7fb6_2932_0361,
  "GalacticWeb": 0xc1df_3d29_4083_48f3,
  "VeinedLeaf": 0xcb04_bade_605a_7f7f,
  "PorousSponge": 0xb13b_6839_69c3_9e27,
  "RainOnGlass": 0xbdbf_8a0c_ed5f_b9a2,
  "EmberField": 0x231c_bb5c_0a9d_019e,
  "QuantumFoam": 0x9897_deb7_0b38_df92,
  "ChladniPlate": 0x67d3_ea5a_2da2_d023,
  "CymaticRosette": 0x69c0_738b_1667_b4b9,
  "LichtenbergFigure": 0x43bc_f5c0_7283_bc27,
  "Quasicrystal": 0xea4a_6655_7cc4_02e9,
  "Mandelbrot": 0x5dde_dfa8_9460_8ca5,
  "BurningShip": 0x68da_06ac_287b_512f,
  "JuliaSet": 0x6c1a_7c62_b497_0d0e,
  "KaleidoscopeCrystal": 0x0a1a_a638_17c0_9015,
  "SpectralPrism": 0xce61_8ccb_7307_d849,
  "TopologicalKnot": 0xe0cf_a7c8_49c2_5be0,
  "XRayBotanical": 0x2fc9_f380_821b_9e36,
  "Chromatophore": 0x2de1_8191_fdef_0fab,
  "BiomechanicalTissue": 0x7329_68dc_a2da_c7a2,
  "GildedFiligree": 0x95e4_02ee_4d66_0cd4,
  "AncientRunes": 0xa7dc_18d4_8f0b_0fc4,
  "SolarGranulation": 0x6dff_1855_dc47_a152,
  "LunarEjecta": 0x263e_b05c_9fd6_97d4,
  "OceanCurrents": 0x2df1_6026_0c19_3916,
  "InkWashMountains": 0x060d_08d8_ade8_1411,
  "NeonCity": 0xecd9_eacf_98e2_bcc0,
  "PhyllotaxisBloom": 0x3c9e_120a_d650_047c,
  "SierpinskiTriangle": 0x7779_31cd_533f_f214,
  "ApollonianGasket": 0x7913_23f8_8347_5fa6,
  "HyperbolicTiling": 0x42e2_7e1a_cdd1_6054,
  "MoebiusWeave": 0x666e_a83f_073e_1e41,
  "RorschachInkblot": 0xb007_eb74_ae49_8756,
  "SeismicInterference": 0xc640_e966_a0c1_bda4,
  "RayleighBenard": 0x781e_e838_b02e_663b,
  "OrigamiFacets": 0xba83_7c19_e827_3143,
  "FiberOpticBundle": 0xba6a_a699_a840_92ab,
]
