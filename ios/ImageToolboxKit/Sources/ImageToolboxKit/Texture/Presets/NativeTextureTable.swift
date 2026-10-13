// The 122 FastNoise presets of the Android app, as its native texture code receives them: the
// texture code, the values in native order (scale first) and the ARGB colours. The app defaults
// give the numbers, and the KSP mapping gives the order. This file is generated; do not edit it.

enum NativeTextureTable {
  struct Entry: Sendable {
    let id: String
    let code: Int
    let parameters: [Float]
    let colours: [UInt32]

    init(_ id: String, _ code: Int, _ parameters: [Float], _ colours: [UInt32]) {
      self.id = id
      self.code = code
      self.parameters = parameters
      self.colours = colours
    }
  }

  /// The entry of a preset by its Android enum name, or nil for other presets.
  static func entry(for id: String) -> Entry? {
    lookup[id]
  }

  private static let lookup: [String: Entry] = Dictionary(
    uniqueKeysWithValues: entries.map { ($0.id, $0) })

  static let entries: [Entry] = [
    Entry(
      "Lava", 0, [0.008, 32.0, 1.35, 0.55, 0.52, 0.72], [0xFF12_0B0A, 0xFFD5_2B0A, 0xFFFF_D45A]),
    Entry(
      "Cloud", 1, [0.0045, 0.48, 0.22, 0.62, 24.0, 0.92], [0xFF6F_A9DC, 0xFF9E_ADBC, 0xFFF8_FBFF]),
    Entry(
      "Smoke", 2, [0.006, 34.0, 0.56, 2.2, 1.35, 0.5], [0xFF11_1318, 0xFF44_4A52, 0xFFD5_D9DD]),
    Entry(
      "Stone", 3, [0.011, 0.3, 0.58, 0.024, 18.0, 1.12], [0xFF34_3536, 0xFFAA_A79F, 0xFFE2_DED3]),
    Entry(
      "AdvancedWood", 4, [0.0039, 11.4, 0.3, 15.0, 7.42, 0.17],
      [0xFF3A_190B, 0xFFB9_6E32, 0xFF1D_0D07]),
    Entry(
      "Camouflage", 5, [0.007, 0.36, 0.58, 0.76, 28.0, 0.035],
      [0xFF20_2719, 0xFF4F_6134, 0xFF78_6344, 0xFFB4_A477]),
    Entry(
      "Paper", 6, [0.012, 72.0, 0.24, 0.16, 0.14, 0.35],
      [0xFFE4_D4AE, 0xFFF5_E9C9, 0xFFB5_9C70, 0xFF8A_6841]),
    Entry(
      "Rust", 7, [0.009, 0.55, 0.0, 0.42, 16.0, 1.25],
      [0xFF59_6065, 0xFF3A_170B, 0xFF9B_3E13, 0xFFE0_7822]),
    Entry(
      "Fabric", 8, [0.018, 28.0, 28.0, 0.14, 0.48, 0.1],
      [0xFF49_6B82, 0xFF78_95A7, 0xFF26_3C4B, 0xFFB6_CAD4]),
    Entry(
      "Topography", 9, [0.0055, 16.0, 0.11, 0.42, 12.0, 1.1],
      [0xFF17_3C3B, 0xFFB5_C98A, 0xFFF2_E6B6]),
    Entry(
      "Cell", 10, [0.018, 0.92, 0.12, 0.28, 6.0, 0.42],
      [0xFF10_1A24, 0xFF21_6E78, 0xFF5A_D1C8, 0xFFC9_FFF4]),
    Entry(
      "Crack", 11, [0.019, 0.065, 0.72, 9.0, 0.72, 0.45],
      [0xFF8D_8374, 0xFFC0_B6A5, 0xFF16_1412, 0xFF55_4E45]),
    Entry(
      "WaterRipple", 12, [0.0075, 22.0, 22.0, 0.58, 0.55, 0.62],
      [0xFF07_3456, 0xFF16_8EAE, 0xFFB9_F7F2]),
    Entry(
      "Foliage", 13, [0.022, 0.72, 0.16, 0.38, 0.62, 0.58],
      [0xFF10_2A13, 0xFF24_5C25, 0xFF4E_9A3D, 0xFFA4_CE65]),
    Entry(
      "Brick", 14, [0.02, 2.15, 0.09, 0.18, 0.42, 0.55],
      [0xFFB8_AD99, 0xFF6F_2418, 0xFFB6_4C32, 0xFFD7_7A55]),
    Entry(
      "Terrain", 15, [0.0045, 0.34, 0.7, 0.46, 0.58, 0.86],
      [0xFF19_4D73, 0xFF5F_873F, 0xFF74_6C5D, 0xFFE9_EEE8]),
    Entry(
      "Ice", 16, [0.014, 0.075, 0.48, 0.64, 8.0, 0.32],
      [0xFF15_5A79, 0xFF79_C8DC, 0xFFD8_F4F5, 0xFFF5_FFFF]),
    Entry(
      "Sand", 17, [0.005, 12.0, 0.32, 0.62, 0.22, 1.18], [0xFF9A_632E, 0xFFD6_A85A, 0xFFF2_D58D]),
    Entry(
      "Nebula", 18, [0.004, 44.0, 0.64, 0.38, 0.72, 1.45],
      [0xFF05_0713, 0xFF54_2577, 0xFF23_67A2, 0xFFF2_A4DF]),
    Entry(
      "Honeycomb", 19, [0.018, 0.095, 0.5, 0.12, 0.72, 0.35],
      [0xFF24_1305, 0xFF6F_3A08, 0xFFE5_9B12, 0xFFFF_D45C]),
    Entry(
      "Grass", 20, [0.012, 1.0, 50.0, 1.0, 0.35, 0.45],
      [0xFF3A_2B18, 0xFF1D_491F, 0xFF4D_8A32, 0xFF9B_C45A]),
    Entry(
      "Dirt", 21, [0.009, 0.62, 0.35, 0.22, 0.68, 0.52],
      [0xFF2A_190E, 0xFF69_4226, 0xFFA1_764D, 0xFFB1_A28C]),
    Entry(
      "Leather", 22, [0.011, 0.58, 0.42, 0.5, 0.38, 0.035],
      [0xFF30_160F, 0xFF7B_3D25, 0xFFB3_6B43, 0xFF1C_0C08]),
    Entry(
      "Concrete", 23, [0.014, 0.45, 0.28, 0.65, 0.14, 1.08],
      [0xFF5A_5955, 0xFF99_968E, 0xFFC7_C3B9, 0xFF35_3532]),
    Entry(
      "Asphalt", 24, [0.02, 0.72, 0.44, 0.28, 0.48, 1.3],
      [0xFF17_191A, 0xFF3E_4242, 0xFF89_8B85, 0xFFB0_A995]),
    Entry(
      "Moss", 25, [0.018, 0.74, 0.58, 0.38, 0.62, 0.46],
      [0xFF29_2516, 0xFF29_451C, 0xFF64_8044, 0xFFB1_BD69]),
    Entry(
      "Fire", 26, [0.006, 8.0, 36.0, 0.78, 0.18, 0.62],
      [0xFF10_0807, 0xFFB5_1B08, 0xFFFF_7A0A, 0xFFFF_E98A]),
    Entry(
      "Aurora", 27, [0.004, 7.0, 34.0, 0.72, 0.2, 1.32],
      [0xFF06_1227, 0xFF42_D9A0, 0xFF65_E4E8, 0xFFA5_6DE2]),
    Entry(
      "OilSlick", 28, [0.008, 13.0, 32.0, 0.82, 0.3, 1.2],
      [0xFF10_101A, 0xFFD5_329B, 0xFF25_D4D0, 0xFFF0_C33C]),
    Entry(
      "Watercolor", 29, [0.006, 0.72, 0.65, 0.38, 0.22, 0.62],
      [0xFFF4_EBD8, 0xFF33_7FB3, 0xFFD8_5D79, 0xFF49_3F76]),
    Entry(
      "AbstractFlow", 30, [0.006, 12.0, 46.0, 0.3, 1.25, 0.62],
      [0xFF11_1128, 0xFF51_55D9, 0xFFDE_4BB3, 0xFF7E_F2E7]),
    Entry(
      "Opal", 31, [0.007, 0.82, 0.48, 8.0, 28.0, 0.62],
      [0xFFDD_E8DF, 0xFF4F_D5D1, 0xFFF0_72B6, 0xFFFF_C857]),
    Entry(
      "DamascusSteel", 32, [0.006, 22.0, 0.72, 34.0, 0.58, 1.4],
      [0xFF17_1C20, 0xFF66_727A, 0xFFC8_D0D2, 0xFF30_4C57]),
    Entry(
      "Lightning", 33, [0.006, 7.0, 42.0, 0.055, 0.82, 0.9],
      [0xFF03_0612, 0xFF25_46A8, 0xFF68_C9FF, 0xFFF2_FCFF]),
    Entry(
      "Velvet", 34, [0.014, 0.78, 0.18, 0.7, 0.62, 0.34],
      [0xFF17_051E, 0xFF5E_176A, 0xFFC1_48B8, 0xFFF0_A6D8]),
    Entry(
      "InkMarbling", 35, [0.006, 14.0, 48.0, 0.52, 0.5, 1.25],
      [0xFFF3_E9D3, 0xFF16_4B78, 0xFF9D_2949, 0xFF1C_1831]),
    Entry(
      "HolographicFoil", 36, [0.008, 12.0, 0.7, 0.82, 0.3, 0.72],
      [0xFFCD_D4DE, 0xFF4D_E5E2, 0xFFE9_5AC8, 0xFFF7_EA72]),
    Entry(
      "Bioluminescence", 37, [0.009, 0.72, 0.58, 30.0, 0.86, 0.62],
      [0xFF03_1A1A, 0xFF0B_514D, 0xFF20_E6C2, 0xFFC4_FFF1]),
    Entry(
      "CosmicVortex", 38, [0.008, 5.0, 12.0, 0.52, 0.28, 0.82],
      [0xFF02_030B, 0xFF27_4AA8, 0xFF8D_3EC2, 0xFFFF_DDA0]),
    Entry(
      "LavaLamp", 39, [0.007, 6.0, 0.24, 32.0, 0.58, 1.3],
      [0xFF1C_0929, 0xFFFF_3D81, 0xFFFF_8A24, 0xFFFF_D45C]),
    Entry(
      "EventHorizon", 40, [0.008, 0.72, 0.15, 0.065, 0.82, 0.22],
      [0xFF01_0107, 0xFFFF_5A18, 0xFFFF_E0A3, 0xFF7C_48FF]),
    Entry(
      "FractalBloom", 41, [0.01, 7.0, 5.0, 4.2, 0.7, 0.72],
      [0xFF09_061B, 0xFF59_40D6, 0xFFFF_3E93, 0xFFFF_E88A]),
    Entry(
      "ChromaticTunnel", 42, [0.009, 18.0, 5.5, 7.0, 0.48, 0.78],
      [0xFF03_0516, 0xFF00_D5FF, 0xFFFF_2C9C, 0xFFFF_F1B8]),
    Entry(
      "EclipseCorona", 43, [0.008, 0.23, 0.2, 34.0, 0.62, 0.8],
      [0xFF02_030A, 0xFF76_5BFF, 0xFFFF_9B45, 0xFFFF_FFFF]),
    Entry(
      "StrangeAttractor", 44, [0.01, 3.0, 18.0, 6.0, 0.035, 0.8],
      [0xFF03_0511, 0xFF14_D9C5, 0xFFFF_3A79, 0xFFFF_F1B5]),
    Entry(
      "FerrofluidCrown", 45, [0.012, 19.0, 0.14, 0.22, 0.86, 0.42],
      [0xFFE8_E1D4, 0xFF07_090C, 0xFF35_3D43, 0xFFD9_F7FF]),
    Entry(
      "Supernova", 46, [0.01, 0.27, 0.075, 0.72, 0.68, 0.24],
      [0xFF02_030B, 0xFF69_23B7, 0xFFFF_4D22, 0xFFFF_F2C5]),
    Entry(
      "Iris", 47, [0.014, 0.12, 0.38, 46.0, 0.72, 0.82],
      [0xFF08_0A0D, 0xFF12_3646, 0xFF37_B6A5, 0xFFE6_B650]),
    Entry(
      "PeacockFeather", 48, [0.012, 0.24, 54.0, 0.58, 0.8, 0.42],
      [0xFF06_150F, 0xFF16_7D55, 0xFF12_48BC, 0xFFE4_BC45]),
    Entry(
      "NautilusShell", 49, [0.011, 3.4, 19.0, 0.13, 0.68, 0.46],
      [0xFF15_2228, 0xFF4A_2D22, 0xFFD9_AD79, 0xFFFF_F0D1]),
    Entry(
      "RingedPlanet", 50, [0.009, 0.24, 0.72, 0.16, 0.62, 0.25],
      [0xFF02_040D, 0xFF15_234D, 0xFFE5_8C62, 0xFFFF_E1A6]),
    Entry(
      "Geode", 51, [0.008, 0.78, 0.42, 0.82, 0.58, 1.45],
      [0xFF12_0E20, 0xFF70_46A8, 0xFF3E_D7D1, 0xFFF4_DDA6]),
    Entry(
      "PrismaticLight", 52, [0.008, 0.72, 0.82, 0.84, 0.72, 1.45],
      [0xFF07_091A, 0xFF24_6DD8, 0xFFE9_4DA9, 0xFFFF_E47A]),
    Entry(
      "StainedGlass", 53, [0.008, 0.54, 0.48, 0.84, 0.38, 1.35],
      [0xFF12_0F18, 0xFF2E_8BD2, 0xFFE5_4472, 0xFFFF_D34E]),
    Entry(
      "KelpForest", 54, [0.006, 0.72, 0.78, 0.68, 0.64, 1.45],
      [0xFF03_1C22, 0xFF07_594F, 0xFF42_A66E, 0xFFD1_F29B]),
    Entry(
      "FrostFern", 55, [0.008, 0.78, 0.62, 0.82, 0.68, 1.45],
      [0xFF10_273A, 0xFF55_9AB4, 0xFFB8_E8ED, 0xFFE8_FBFF]),
    Entry(
      "LiquidCrystal", 56, [0.008, 0.66, 0.62, 0.58, 0.72, 1.3],
      [0xFF09_0A18, 0xFF18_BFD2, 0xFFE1_42A9, 0xFFFF_E96A]),
    Entry(
      "DragonScales", 57, [0.007, 0.66, 0.28, 0.82, 0.52, 1.45],
      [0xFF07_1913, 0xFF17_664B, 0xFF39_B778, 0xFFE0_C96B]),
    Entry(
      "FireflySwarm", 58, [0.007, 0.52, 0.82, 0.88, 0.95, 1.6],
      [0xFF02_0B12, 0xFF0B_4D49, 0xFF80_D85A, 0xFFFF_FFB0]),
    Entry(
      "Mycelium", 59, [0.008, 0.78, 0.72, 0.8, 0.66, 1.55],
      [0xFF07_100B, 0xFF24_452E, 0xFFB7_C985, 0xFFF4_E8C1]),
    Entry(
      "Kintsugi", 60, [0.008, 0.6, 0.48, 0.82, 0.7, 1.35],
      [0xFF10_131A, 0xFF34_4158, 0xFFD9_9B32, 0xFFFF_E7A3]),
    Entry(
      "CarbonFiber", 61, [0.01, 0.72, 0.3, 0.82, 0.34, 1.65],
      [0xFF03_0405, 0xFF15_191C, 0xFF34_3B40, 0xFF88_949B]),
    Entry(
      "CircuitBoard", 62, [0.008, 0.72, 0.32, 0.86, 0.6, 1.55],
      [0xFF03_170F, 0xFF07_5A3B, 0xFFC2_8B28, 0xFF7B_FFD1]),
    Entry(
      "SoapFilm", 63, [0.007, 0.68, 0.72, 0.55, 0.72, 1.25],
      [0xFF10_182B, 0xFF20_CDE2, 0xFFF4_5CB4, 0xFFFF_E66D]),
    Entry(
      "MoireGuilloche", 64, [0.008, 0.64, 0.4, 0.82, 0.38, 1.65],
      [0xFF07_0914, 0xFF27_47A5, 0xFFBD_4BC8, 0xFFF2_EAFB]),
    Entry(
      "SnakeSkin", 65, [0.009, 0.62, 0.4, 0.72, 0.4, 1.35],
      [0xFF17_170E, 0xFF4E_5A2D, 0xFF9D_A75A, 0xFFB8_D7A4]),
    Entry(
      "Terrazzo", 66, [0.008, 0.48, 0.42, 0.78, 0.2, 1.35],
      [0xFFE5_DCCF, 0xFF31_5C72, 0xFFC8_5554, 0xFFE5_A73D]),
    Entry(
      "GalaxyFilaments", 67, [0.007, 0.78, 0.7, 0.84, 0.72, 1.65],
      [0xFF02_030A, 0xFF17_3B78, 0xFF81_37A6, 0xFFD9_EEFF]),
    Entry(
      "VolcanicObsidian", 68, [0.008, 0.72, 0.58, 0.84, 0.52, 1.7],
      [0xFF02_0304, 0xFF17_141D, 0xFF3B_2744, 0xFFEF_6C3D]),
    Entry(
      "MotherboardHeatmap", 69, [0.008, 0.62, 0.38, 0.76, 0.68, 1.45],
      [0xFF07_120E, 0xFF08_705B, 0xFFFF_7B22, 0xFFFF_F1A8]),
    Entry(
      "MicroscopicDiatoms", 70, [0.007, 0.62, 0.3, 0.74, 0.58, 1.35],
      [0xFF08_2431, 0xFF1E_7181, 0xFF74_D8C9, 0xFFD9_C8FF]),
    Entry(
      "ReactionDiffusion", 71, [0.009, 0.82, 0.74, 0.8, 0.5, 1.6],
      [0xFF09_0B17, 0xFF30_3785, 0xFFE6_4C93, 0xFF59_EBB0]),
    Entry(
      "CoralGrowth", 72, [0.008, 0.68, 0.62, 0.7, 0.72, 1.4],
      [0xFF07_1D2A, 0xFFEA_536E, 0xFFFF_A468, 0xFFFF_C2D8]),
    Entry(
      "SlimeMold", 73, [0.008, 0.8, 0.82, 0.84, 0.66, 1.65],
      [0xFF08_110A, 0xFF59_6F17, 0xFFD5_D928, 0xFFFF_F5A0]),
    Entry(
      "DendriticCrystal", 74, [0.008, 0.68, 0.52, 0.8, 0.82, 1.5],
      [0xFF07_1829, 0xFF25_678C, 0xFFA8_E5F0, 0xFFDF_FFFF]),
    Entry(
      "ElectricArcField", 75, [0.008, 0.72, 0.72, 0.82, 0.9, 1.55],
      [0xFF03_0511, 0xFF17_3A91, 0xFF32_C8FF, 0xFFFF_FFFF]),
    Entry(
      "CloudChamber", 76, [0.008, 0.55, 0.7, 0.86, 0.7, 1.6],
      [0xFF08_0913, 0xFF2D_416A, 0xFF9B_C5E7, 0xFFEA_F2FF]),
    Entry(
      "TurbulentInk", 77, [0.006, 0.7, 0.78, 0.68, 0.62, 1.4],
      [0xFFF0_E8D8, 0xFF17_4A72, 0xFF9E_284F, 0xFF17_1629]),
    Entry(
      "CellularEmbryo", 78, [0.008, 0.62, 0.48, 0.72, 0.58, 1.35],
      [0xFF22_0E26, 0xFF72_3259, 0xFFE0_7B93, 0xFFFF_D0B3]),
    Entry(
      "NeuralGarden", 79, [0.008, 0.76, 0.82, 0.84, 0.64, 1.65],
      [0xFF06_120D, 0xFF11_684A, 0xFF6B_D87A, 0xFFB8_FFBA]),
    Entry(
      "MagneticField", 80, [0.008, 0.68, 0.42, 0.74, 0.72, 1.4],
      [0xFF07_0A17, 0xFF24_52A0, 0xFFE2_3D70, 0xFFFF_E5A6]),
    Entry(
      "RiverDelta", 81, [0.006, 0.76, 0.86, 0.84, 0.48, 1.65],
      [0xFF25_190E, 0xFF8B_693B, 0xFF16_88A5, 0xFF8E_DDE0]),
    Entry(
      "LichenColony", 82, [0.009, 0.64, 0.58, 0.7, 0.48, 1.35],
      [0xFF29_291A, 0xFF66_743A, 0xFFB1_B85B, 0xFFC7_D9A7]),
    Entry(
      "BacterialCulture", 83, [0.009, 0.68, 0.62, 0.68, 0.58, 1.35],
      [0xFF16_0C20, 0xFF66_3078, 0xFFE0_5C9E, 0xFFFF_D37C]),
    Entry(
      "FluidVorticity", 84, [0.007, 0.72, 0.78, 0.7, 0.72, 1.4],
      [0xFF07_1326, 0xFF16_55A2, 0xFFE4_4574, 0xFFFF_D36E]),
    Entry(
      "CrystalGrowth", 85, [0.008, 0.64, 0.48, 0.8, 0.78, 1.5],
      [0xFF10_1525, 0xFF3F_62A1, 0xFFA9_D8EE, 0xFFFF_F0C2]),
    Entry(
      "GalacticWeb", 86, [0.007, 0.72, 0.68, 0.8, 0.86, 1.55],
      [0xFF01_0208, 0xFF18_2B69, 0xFF6B_3EA0, 0xFFFF_E9CA]),
    Entry(
      "VeinedLeaf", 87, [0.004, 0.68, 0.52, 0.78, 0.62, 1.4],
      [0xFF07_180C, 0xFF1E_6732, 0xFF75_BC50, 0xFFD6_E782]),
    Entry(
      "PorousSponge", 88, [0.009, 0.64, 0.42, 0.72, 0.42, 1.35],
      [0xFF5B_3718, 0xFFB1_6C27, 0xFFE5_B24E, 0xFFFF_E2A0]),
    Entry(
      "RainOnGlass", 89, [0.008, 0.68, 0.58, 0.74, 0.78, 1.4],
      [0xFF07_1728, 0xFF19_4C70, 0xFF69_BDD2, 0xFFDF_FBFF]),
    Entry(
      "EmberField", 90, [0.008, 0.72, 0.62, 0.76, 0.88, 1.55],
      [0xFF10_0504, 0xFF76_200B, 0xFFF0_5A14, 0xFFFF_E06B]),
    Entry(
      "QuantumFoam", 91, [0.008, 0.72, 0.78, 0.72, 0.78, 1.5],
      [0xFF06_0616, 0xFF35_3499, 0xFF23_C9CB, 0xFFF6_6AC2]),
    Entry(
      "ChladniPlate", 92, [0.008, 0.76, 0.28, 0.88, 0.36, 1.7],
      [0xFF06_080B, 0xFF2E_343A, 0xFF8E_9AA3, 0xFFF1_D78A]),
    Entry(
      "CymaticRosette", 93, [0.001, 0.68, 0.44, 0.78, 0.76, 1.45],
      [0xFF07_1426, 0xFF17_6FB0, 0xFF55_D3DE, 0xFFFF_6500]),
    Entry(
      "LichtenbergFigure", 94, [0.008, 0.72, 0.66, 0.84, 0.9, 1.6],
      [0xFF08_030C, 0xFF5E_176E, 0xFFE5_44A7, 0xFFFF_E9FF]),
    Entry(
      "Quasicrystal", 95, [0.008, 0.7, 0.36, 0.76, 0.62, 1.45],
      [0xFF09_0B18, 0xFF28_54A0, 0xFF27_BEBB, 0xFFFF_D962]),
    Entry(
      "Mandelbrot", 96, [0.004, 0.82, 0.36, 0.86, 0.58, 1.7],
      [0xFF02_030B, 0xFF17_3B72, 0xFF7B_2EA3, 0xFFFF_C85C]),
    Entry(
      "BurningShip", 97, [0.0035, 0.82, 0.44, 0.86, 0.62, 1.7],
      [0xFF05_0207, 0xFF5A_1728, 0xFFE5_4522, 0xFFFF_D56A]),
    Entry(
      "JuliaSet", 98, [0.004, 0.82, 0.58, 0.86, 0.6, 1.7],
      [0xFF03_0713, 0xFF21_4E96, 0xFF8B_46C7, 0xFFFF_E2A8]),
    Entry(
      "KaleidoscopeCrystal", 99, [0.008, 0.8, 0.58, 0.84, 0.56, 1.6],
      [0xFF09_0B1C, 0xFF23_67B7, 0xFFE0_4DA4, 0xFF62_F5CA]),
    Entry(
      "SpectralPrism", 100, [0.008, 0.64, 0.58, 0.8, 0.8, 1.45],
      [0xFF08_0A12, 0xFF22_5CD1, 0xFFDD_3DAD, 0xFF72_F5B3]),
    Entry(
      "TopologicalKnot", 101, [0.008, 0.62, 0.54, 0.82, 0.76, 1.55],
      [0xFF04_0713, 0xFF24_579A, 0xFFC2_45D6, 0xFFFF_E29A]),
    Entry(
      "XRayBotanical", 102, [0.008, 0.66, 0.48, 0.76, 0.74, 1.45],
      [0xFF02_0A0B, 0xFF0C_4F50, 0xFF5C_C7A7, 0xFFE8_FFE0]),
    Entry(
      "Chromatophore", 103, [0.008, 0.68, 0.52, 0.72, 0.7, 1.4],
      [0xFF16_0918, 0xFF6A_275F, 0xFFE2_576F, 0xFF5C_F277]),
    Entry(
      "BiomechanicalTissue", 104, [0.008, 0.66, 0.58, 0.78, 0.62, 1.5],
      [0xFF10_0C12, 0xFF55_3444, 0xFFB9_7472, 0xFFF0_CAB0]),
    Entry(
      "GildedFiligree", 105, [0.008, 0.68, 0.46, 0.82, 0.74, 1.55],
      [0xFF0A_1019, 0xFF16_3B58, 0xFFC3_8A2A, 0xFFFF_E49A]),
    Entry(
      "AncientRunes", 106, [0.008, 0.62, 0.54, 0.78, 0.72, 1.5],
      [0xFF0B_0C12, 0xFF34_364A, 0xFFA8_5F35, 0xFFFF_D27A]),
    Entry(
      "SolarGranulation", 107, [0.008, 0.72, 0.58, 0.74, 0.86, 1.5],
      [0xFF1C_0502, 0xFF8B_2108, 0xFFF0_6A12, 0xFFFF_F0A0]),
    Entry(
      "LunarEjecta", 108, [0.008, 0.64, 0.48, 0.8, 0.5, 1.5],
      [0xFF0B_0D11, 0xFF35_3A42, 0xFF8B_9098, 0xFFE6_E1D5]),
    Entry(
      "OceanCurrents", 109, [0.007, 0.7, 0.72, 0.76, 0.68, 1.45],
      [0xFF03_1629, 0xFF07_5B8B, 0xFF21_B9C2, 0xFFD9_FFF5]),
    Entry(
      "InkWashMountains", 110, [0.006, 0.62, 0.58, 0.72, 0.42, 1.4],
      [0xFFF1_EBDD, 0xFF9A_9A91, 0xFF44_4844, 0xFF11_1716]),
    Entry(
      "NeonCity", 111, [0.008, 0.68, 0.52, 0.8, 0.86, 1.55],
      [0xFF02_040C, 0xFF14_2D59, 0xFFE6_38A1, 0xFF57_F5E9]),
    Entry(
      "PhyllotaxisBloom", 112, [0.008, 0.68, 0.62, 0.82, 0.72, 1.5],
      [0xFF07_100D, 0xFF1F_6F4A, 0xFFE0_A733, 0xFFFF_D36A]),
    Entry(
      "SierpinskiTriangle", 113, [0.008, 0.68, 0.5, 0.82, 0.66, 1.55],
      [0xFF05_0713, 0xFF24_4B9A, 0xFF46_BFD0, 0xFFFF_E49A]),
    Entry(
      "ApollonianGasket", 114, [0.008, 0.66, 0.52, 0.8, 0.72, 1.5],
      [0xFF08_0511, 0xFF54_2778, 0xFFD3_4EAD, 0xFF75_E8FF]),
    Entry(
      "HyperbolicTiling", 115, [0.008, 0.62, 0.72, 0.8, 0.74, 1.5],
      [0xFF05_0A14, 0xFF24_54A0, 0xFF30_B9B0, 0xFFFF_7A8A]),
    Entry(
      "MoebiusWeave", 116, [0.008, 0.66, 0.62, 0.76, 0.68, 1.45],
      [0xFF08_0A16, 0xFF37_4A94, 0xFFB3_4EC2, 0xFF8F_E3FF]),
    Entry(
      "RorschachInkblot", 117, [0.006, 0.64, 0.92, 0.74, 0.68, 1.65],
      [0xFFF1_EBDD, 0xFF8B_8590, 0xFF3D_283E, 0xFF10_0C14]),
    Entry(
      "SeismicInterference", 118, [0.008, 0.64, 0.52, 0.78, 0.72, 1.5],
      [0xFF07_0A12, 0xFF31_5B8D, 0xFFE3_6A42, 0xFFE7_F2FF]),
    Entry(
      "RayleighBenard", 119, [0.008, 0.7, 0.62, 0.72, 0.82, 1.5],
      [0xFF18_0603, 0xFF86_2208, 0xFFE7_6A16, 0xFFFF_EDA0]),
    Entry(
      "OrigamiFacets", 120, [0.008, 0.72, 0.68, 0.88, 0.42, 1.55],
      [0xFF10_121C, 0xFF58_678B, 0xFFB9_C3D5, 0xFFF0_8470]),
    Entry(
      "FiberOpticBundle", 121, [0.008, 0.72, 0.62, 0.82, 0.88, 1.55],
      [0xFF02_040D, 0xFF18_3C88, 0xFF36_D7E1, 0xFFE8_FFFF]),
  ]
}
