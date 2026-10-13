import Foundation

@testable import ImageToolboxKit

/// FastNoiseLite compared with the upstream C++ header (MIT License, Copyright (c) 2023 Jordan Peck
/// and Contributors, the copy in the Android fast-noise module). The expected values are the bit
/// patterns of `GetNoise` and `DomainWarp` for the points below, compiled with clang and
/// `-ffp-contract=off`. Noise cases give one value per point, warp cases the x and y of each point.
struct FastNoiseGolden {
  let name: String
  let noise: FastNoiseLite.NoiseType
  let fractal: FastNoiseLite.FractalType
  let octaves: Int
  let gain: Float
  let lacunarity: Float
  let weighted: Float
  let pingPong: Float
  let frequency: Float
  let distance: FastNoiseLite.CellularDistanceFunction
  let returnType: FastNoiseLite.CellularReturnType
  let jitter: Float
  let warp: FastNoiseLite.DomainWarpType
  let warpAmp: Float
  let isWarp: Bool
  let points: Int
  let expected: String
}

func caseOf(
  _ name: String,
  _ noise: FastNoiseLite.NoiseType,
  _ fractal: FastNoiseLite.FractalType,
  _ octaves: Int,
  _ gain: Float,
  _ lacunarity: Float,
  _ weighted: Float,
  _ pingPong: Float,
  _ frequency: Float,
  _ distance: FastNoiseLite.CellularDistanceFunction,
  _ returnType: FastNoiseLite.CellularReturnType,
  _ jitter: Float,
  _ warp: FastNoiseLite.DomainWarpType,
  _ warpAmp: Float,
  _ isWarp: Bool,
  _ points: Int,
  _ expected: String
) -> FastNoiseGolden {
  FastNoiseGolden(
    name: name, noise: noise, fractal: fractal, octaves: octaves, gain: gain,
    lacunarity: lacunarity, weighted: weighted, pingPong: pingPong, frequency: frequency,
    distance: distance, returnType: returnType, jitter: jitter, warp: warp, warpAmp: warpAmp,
    isWarp: isWarp, points: points, expected: expected)
}

let goldenPoints: [(Float, Float)] = [
  (0.37, -1.21), (3.5, 2.25), (-7.125, 4.5), (100.3, -55.9),
  (0.0, 0.0), (1.0, 1.0), (-0.25, 0.75), (12.5, -3.375),
]

let goldenCases: [FastNoiseGolden] = [
  caseOf(
    "OpenSimplex2_plain", .openSimplex2, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "be634ca8 3f5c53f2 3e33dc61 bf3cbec2 00000000 3ed7259f 3e0bb670 bf02e6e3"),
  caseOf(
    "OpenSimplex2_fbm", .openSimplex2, .fbm, 4, 0.6, 2.1,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bddb6488 3ec773e5 3e203da1 bf17dd9c 00000000 3ee3f3ed 3b364b20 bd30a3b0"),
  caseOf(
    "OpenSimplex2_ridged", .openSimplex2, .ridged, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3f26ad62 bf110e9a 3ebe7f8b bd945997 3f800001 bdb36e07 3f47fa18 bd2f8df4"),
  caseOf(
    "OpenSimplex2_pingpong", .openSimplex2, .pingPong, 3, 0.5, 2.0,
    0.3, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "be833cb1 be21d785 bcb7a836 be2ab3e6 bf5767dd 3ee97e8b bef7eca8 3f4e2155"),
  caseOf(
    "OpenSimplex2_weighted_fbm", .openSimplex2, .fbm, 5, 0.5, 2.0,
    0.4, 2.0, 0.2, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "be2adff9 be91bacb 3c9dac3c 3d76b4e2 00000000 3efdc92f 3dda50c5 bea0848e"),
  caseOf(
    "OpenSimplex2S_plain", .openSimplex2S, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "be031520 3f175867 3e02a36d beee0d2b 907e10b4 3e7c7b47 3da17e7b be97981a"),
  caseOf(
    "OpenSimplex2S_fbm", .openSimplex2S, .fbm, 4, 0.6, 2.1,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bcfde1e7 3ea34c2e 3e1c938a bee857f5 90dc9ae0 3e935286 bc836081 bd8fd886"),
  caseOf(
    "OpenSimplex2S_ridged", .openSimplex2S, .ridged, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3f4771e4 be42a2b1 3ef09844 3e843fce 3f800001 3ea43449 3f5d1f1e 3ed40999"),
  caseOf(
    "OpenSimplex2S_pingpong", .openSimplex2S, .pingPong, 3, 0.5, 2.0,
    0.3, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "befb901f 3f18876c be9fff5b 3eddb244 bf5767dd 3e7e7d33 bf20a33b 3e18b00a"),
  caseOf(
    "OpenSimplex2S_weighted_fbm", .openSimplex2S, .fbm, 5, 0.5, 2.0,
    0.4, 2.0, 0.2, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bd34e637 be0c858f 3ca8fef3 3d82d28f 90a39225 3ecdae1a 3c28d3e1 be575f3c"),
  caseOf(
    "Perlin_plain", .perlin, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bd4c1744 3e5faead bc937eef bddff718 00000000 3dc7018e 3cfe05d5 be9325f5"),
  caseOf(
    "Perlin_fbm", .perlin, .fbm, 4, 0.6, 2.1,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3d3401ea 3e42184d 3d8efe71 bca90ede 00000000 3deca1b9 bd0a1f16 be24b321"),
  caseOf(
    "Perlin_ridged", .perlin, .ridged, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3f662b00 3eb707b6 3f4cbed6 3f3133ca 3f800001 3f3cdadb 3f711305 3ed935da"),
  caseOf(
    "Perlin_pingpong", .perlin, .pingPong, 3, 0.5, 2.0,
    0.3, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bf319746 3e0f2c98 bf1a783b bebc20ed bf5767dd bee02809 bf41101b 3e107042"),
  caseOf(
    "Perlin_weighted_fbm", .perlin, .fbm, 5, 0.5, 2.0,
    0.4, 2.0, 0.2, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3cee8af8 3e10f547 3d2aec76 bd855916 00000000 3e6242eb bd246703 be7c69e9"),
  caseOf(
    "ValueCubic_plain", .valueCubic, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3e56f220 3dc99c8e 3d18c1a0 be51ac84 3e3f4fb9 3e1eddcd 3e2f025c ba9bc0e4"),
  caseOf(
    "ValueCubic_fbm", .valueCubic, .fbm, 4, 0.6, 2.1,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3dc6458f 3d820c2c be179734 bd13381c 3dbb5e5d 3dcaa3a3 3de3311b bdfe0cb6"),
  caseOf(
    "ValueCubic_ridged", .valueCubic, .ridged, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3f352438 3f471d73 3f3c25fe 3f036b0f 3f2d7122 3f341a04 3f2ca3b2 3f3be3b5"),
  caseOf(
    "ValueCubic_pingpong", .valueCubic, .pingPong, 3, 0.5, 2.0,
    0.3, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "beaa075e befde6ce bef00264 bd15cfdd be9e9e2f bebbda0f bea373f4 befd668a"),
  caseOf(
    "ValueCubic_weighted_fbm", .valueCubic, .fbm, 5, 0.5, 2.0,
    0.4, 2.0, 0.2, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3dcce360 bdf617c7 3e038b18 bddb82ca 3dc42136 3d52e435 3dbc3a6c bdc520e5"),
  caseOf(
    "Value_plain", .value, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3ed89c01 3ea11ca2 3e30d0cf bef711c7 3ed739b0 3ed0b90e 3ed5930e be744bc0"),
  caseOf(
    "Value_fbm", .value, .fbm, 4, 0.6, 2.1,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3e5e8094 3e017528 be5d007c bdf8685a 3e52ca28 3e595c07 3e69ad73 beb3fe56"),
  caseOf(
    "Value_ridged", .value, .ridged, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3ea9858a 3ed6abd8 3eecad48 3cde7d68 3e8c7d13 3e990ec7 3e8daf9b 3e9354c4"),
  caseOf(
    "Value_pingpong", .value, .pingPong, 3, 0.5, 2.0,
    0.3, 2.0, 0.05, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3ead2313 3e29508e bdfd9199 3f173d35 3edb88c5 3ec4de6a 3ed7fce5 bd8a0130"),
  caseOf(
    "Value_weighted_fbm", .value, .fbm, 5, 0.5, 2.0,
    0.4, 2.0, 0.2, .euclideanSq, .distance, 1.0,
    .openSimplex2, 1.0, false, 8,
    "3e203bd2 be58128f 3e71f6a7 be6be18e 3e5b7250 3e06cc00 3e79a670 bdb8b946"),
  caseOf(
    "Cellular_Euclidean_CellValue", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .cellValue, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3d6007c1 3f311afe bf358019 bf342f1e 3d6007c1 bf3521c1 3d6007c1 3dedc639"),
  caseOf(
    "Cellular_Euclidean_Distance", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf674f84 bf39f0f0 be9ad15e bed55e52 bf267fc7 bf0f67b0 bed657e2 bf2e53ca"),
  caseOf(
    "Cellular_Euclidean_Distance2", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance2, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bebc98b8 be328aa8 bdf8d098 bdf36cf0 be86c166 beb67c80 bed14854 bec1052c"),
  caseOf(
    "Cellular_Euclidean_Distance2Add", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance2Add, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf22cdf0 bee6939a be590584 be891cc8 bee9e07a beeaa5f0 bed3d01c bf076b30"),
  caseOf(
    "Cellular_Euclidean_Distance2Sub", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance2Sub, 0.8,
    .openSimplex2, 1.0, false, 8,
    "beedf9b0 bee56374 bf51b164 bf33be75 bf1ce0ec bf4bd690 bf7d7839 bf322ecc"),
  caseOf(
    "Cellular_Euclidean_Distance2Mul", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance2Mul, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf7833d7 bf631406 bf318d99 bf3e3749 bf5f0712 bf5bc49b bf5400c4 bf668f04"),
  caseOf(
    "Cellular_Euclidean_Distance2Div", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclidean, .distance2Div, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf58e9a6 bf2b2576 be52d814 bead15c0 bf06874e bea21948 bc88f3c0 bef9cfbe"),
  caseOf(
    "Cellular_EuclideanSq_CellValue", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .cellValue, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3d6007c1 3f311afe bf358019 bf342f1e 3d6007c1 bf3521c1 3d6007c1 3dedc639"),
  caseOf(
    "Cellular_EuclideanSq_Distance", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf7d9e6f bf6cd3c3 bf03693a bf28e8cc bf60b598 bf4e7a60 bf297a1e bf65f192"),
  caseOf(
    "Cellular_EuclideanSq_Distance2", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance2, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf19dc8e bea2fa06 be69b34c be64f570 beea0b48 bf15f72f bf268289 bf1ca2f9"),
  caseOf(
    "Cellular_EuclideanSq_Distance2Add", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance2Add, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf4bbd7e bf1f2863 bebdd60e bee22628 bf2add9e bf3238c8 bf27fe54 bf414a46"),
  caseOf(
    "Cellular_EuclideanSq_Distance2Sub", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance2Sub, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf1c3e1e bec95280 bf370398 bf105490 bf14500c bf477ccf bf7d086a bf36b167"),
  caseOf(
    "Cellular_EuclideanSq_Distance2Mul", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance2Mul, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf7f8666 bf79770f bf4fec2d bf5e30eb bf7781a5 bf75be7c bf70e086 bf7af17a"),
  caseOf(
    "Cellular_EuclideanSq_Distance2Div", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .euclideanSq, .distance2Div, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf7a082f bf63dfdb bebd232e bf0fd426 bf465caf bf087048 bd07ce80 bf3cde4c"),
  caseOf(
    "Cellular_Manhattan_CellValue", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .cellValue, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3d6007c1 3f311afe bf358019 bf342f1e 3d6007c1 bf3521c1 3d6007c1 3dedc639"),
  caseOf(
    "Cellular_Manhattan_Distance", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf640bed bf2ddda2 be6e3dec be3e1aa8 bf229c02 befc51e0 beab9e68 bf18ea8c"),
  caseOf(
    "Cellular_Manhattan_Distance2", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance2, 0.8,
    .openSimplex2, 1.0, false, 8,
    "be74b908 bdf14778 3b79ac00 3de32a60 bdc05a38 bdbb4ae8 be427cd4 be4db2f0"),
  caseOf(
    "Cellular_Manhattan_Distance2Add", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance2Add, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf109d18 becc0690 bdea5740 bd190af0 bebaa748 be95924c be866e68 becc5748"),
  caseOf(
    "Cellular_Manhattan_Distance2Sub", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance2Sub, 0.8,
    .openSimplex2, 1.0, false, 8,
    "beb244aa bee0969a bf4376d9 bf34140a beeade8c bf19406d bf5ad001 bf1a8230"),
  caseOf(
    "Cellular_Manhattan_Distance2Mul", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance2Mul, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf755d11 bf5bc566 bf1d67f3 bf0c3374 bf55b0bf bf45045a bf3b1119 bf56cfce"),
  caseOf(
    "Cellular_Manhattan_Distance2Div", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .manhattan, .distance2Div, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf5b44a6 bf22e5a8 be713958 be88aeba bf18edc1 bee22e68 be37a038 befe01e4"),
  caseOf(
    "Cellular_Hybrid_CellValue", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .cellValue, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3d6007c1 3f311afe bf358019 bf342f1e 3d6007c1 bf3521c1 3d6007c1 3dedc639"),
  caseOf(
    "Cellular_Hybrid_Distance", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf61aa5c bf1ab165 3e820e94 3e1e4228 bf03519a be9946a0 3b36ae00 befdb83c"),
  caseOf(
    "Cellular_Hybrid_Distance2", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance2, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3e23d4c0 3f105a0e 3f468cd8 3f7638d4 3ee5de28 3ea53ee8 3e237908 3e6593f0"),
  caseOf(
    "Cellular_Hybrid_Distance2Add", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance2Add, 0.8,
    .openSimplex2, 1.0, false, 8,
    "beb8b52c bca57580 3f03ca10 3f0ee4b0 bd031430 3c3f8480 3da653c0 be0aee44"),
  caseOf(
    "Cellular_Hybrid_Distance2Sub", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance2Sub, 0.8,
    .openSimplex2, 1.0, false, 8,
    "3d29f8c0 3e2c2dd0 bef4f4e4 be455ed8 bd1bf520 bec17a78 bf57d86c be8f7dcc"),
  caseOf(
    "Cellular_Hybrid_Distance2Mul", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance2Mul, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf6e67f7 bf30c8c6 3de80e30 3e07ae18 bf25abc0 bf095ff4 bed64de6 bf30f418"),
  caseOf(
    "Cellular_Hybrid_Distance2Div", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.3, .hybrid, .distance2Div, 0.8,
    .openSimplex2, 1.0, false, 8,
    "bf65d96f bf3f3870 be9665b4 bed2ae50 bf29f385 bef0cdaa be0a81c8 bf1682a4"),
  caseOf(
    "Cellular_fbm", .cellular, .fbm, 3, 0.5, 2.0,
    0.0, 2.0, 0.2, .euclidean, .distance2Sub, 1.0,
    .openSimplex2, 1.0, false, 8,
    "bf092483 bf58059c bf43e5ba bf1a18c5 bf4cc09a bf33c82d bf6634a5 bf1a1090"),
  caseOf(
    "Cellular_jitter_zero", .cellular, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.05, .euclidean, .distance2Sub, 0.0,
    .openSimplex2, 1.0, false, 8,
    "bdfd1930 bec03544 bf3d4a61 bed220ca 00000000 bdf485c8 bd9d9690 bf438af5"),
  caseOf(
    "warp_OpenSimplex2", .openSimplex2, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2, 0.7, true, 4,
    "3ec6149b bf955fcc 405db821 4007dbda c0e35cdc 40904965 42c899b1 c25f2181"),
  caseOf(
    "warp_OpenSimplex2_progressive", .openSimplex2, .domainWarpProgressive, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2, 0.7, true, 4,
    "3eb9915a bf98dc77 405dfb9b 4004cfc9 c0e34516 40921d0d 42c88e7f c25f2fdd"),
  caseOf(
    "warp_OpenSimplex2_independent", .openSimplex2, .domainWarpIndependent, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2, 0.7, true, 4,
    "3eb7ecb2 bf98feb2 405e2f7c 400493ad c0e34070 40922094 42c88d8d c25f321e"),
  caseOf(
    "warp_OpenSimplex2Reduced", .openSimplex2, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2Reduced, 0.7, true, 4,
    "3ec5fc2e bfcae4e2 40600101 40032d19 c0df3ca6 408c9547 42c80989 c2603860"),
  caseOf(
    "warp_OpenSimplex2Reduced_progressive", .openSimplex2, .domainWarpProgressive, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2Reduced, 0.7, true, 4,
    "3ebf0972 bfd7e0da 405a7a51 3ffb47c7 c0dec58b 408b34e8 42c80693 c260ab1d"),
  caseOf(
    "warp_OpenSimplex2Reduced_independent", .openSimplex2, .domainWarpIndependent, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .openSimplex2Reduced, 0.7, true, 4,
    "3ed6daa5 bfdd4002 405a0301 3ffb5268 c0de80e8 408bb57b 42c7fd16 c2609d2d"),
  caseOf(
    "warp_BasicGrid", .openSimplex2, .none, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .basicGrid, 0.7, true, 4,
    "3ec1e3b1 bfcce97f 405eda0a 3ff062ee c0dd4dd8 40878ec8 42c7d5bd c25f8be6"),
  caseOf(
    "warp_BasicGrid_progressive", .openSimplex2, .domainWarpProgressive, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .basicGrid, 0.7, true, 4,
    "3ec7579b bfe097a0 4061cec0 3fdc7826 c0d91397 40876d80 42c7e063 c26017b1"),
  caseOf(
    "warp_BasicGrid_independent", .openSimplex2, .domainWarpIndependent, 3, 0.5, 2.0,
    0.0, 2.0, 0.07, .euclideanSq, .distance, 1.0,
    .basicGrid, 0.7, true, 4,
    "3edeef3d bfe28d3d 405fcb0c 3fd8d2cb c0d8f5bc 4087fdf3 42c7e1a0 c2601f78"),
]
