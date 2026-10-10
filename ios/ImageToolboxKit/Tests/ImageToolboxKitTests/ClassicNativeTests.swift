import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Native JH Labs filters")
struct ClassicNativeTests {
  private func catalogue(_ id: String) throws -> TexturePreset {
    try #require(TexturePresets.preset(id: id))
  }

  /// A preset of one classic kind with the given colours and parameters.
  private func custom(
    _ kind: ClassicKind,
    scale: Double = 32,
    colours: [UInt32] = [],
    _ parameters: [(String, Double)]
  ) -> TexturePreset {
    TexturePreset(
      id: "Custom\(kind)", category: .abstract, source: .classic(kind), scale: scale,
      colours: colours,
      parameters: parameters.map { TextureParameter($0.0, $0.1) })
  }

  private func render(_ preset: TexturePreset, width: Int = 64, height: Int = 64) throws
    -> RasterImage
  {
    try #require(TexturePresetRenderer.render(preset, seed: 1, width: width, height: height))
  }

  /// FNV-1a over the RGBA bytes of a picture, row 0 first. The reference values were computed the
  /// same way from a transliteration of the native code, run on the same inputs.
  private func hash(_ image: RasterImage) -> UInt64 {
    var value: UInt64 = 1_469_598_103_934_665_603
    for byte in image.pixels {
      value ^= UInt64(byte)
      value = value &* 1_099_511_628_211
    }
    return value
  }

  /// The pixel at `(x, y)` as 0xAARRGGBB.
  private func argb(_ image: RasterImage, _ x: Int, _ y: Int) -> UInt32 {
    let index = (y * image.width + x) * 4
    return UInt32(image.pixels[index + 3]) << 24 | UInt32(image.pixels[index]) << 16
      | UInt32(image.pixels[index + 1]) << 8 | UInt32(image.pixels[index + 2])
  }

  @Test("FBM matches the native code, opaque or not")
  func fbmMatchesNative() throws {
    #expect(hash(try render(try catalogue("FBM"))) == 0x6aeb_9dd3_290c_d13d)
    let tilted = custom(.fbm, scale: 20, [("stretch", 1.5), ("angle", 0.7), ("amount", 0.6)])
    #expect(hash(try render(tilted, width: 97, height: 61)) == 0x2009_5094_5bc3_03e6)
    let strong = custom(.fbm, [("amount", 2.5)])
    #expect(hash(try render(strong, width: 40, height: 40)) == 0x5917_c3bb_19d8_48a6)
  }

  @Test("Caustics matches the native code, with the fixed table")
  func causticsMatchesNative() throws {
    #expect(hash(try render(try catalogue("Caustics"))) == 0x000e_af69_f1b8_59c0)
    let tuned = custom(
      .caustics, scale: 20, colours: [0x8020_4060],
      [("amount", 0.8), ("turbulence", 2.5), ("time", 1.3), ("brightness", 37)])
    #expect(hash(try render(tuned, width: 97, height: 61)) == 0xa0a0_1f0d_0aed_fa66)
  }

  @Test("Check matches the native code")
  func checkMatchesNative() throws {
    #expect(hash(try render(try catalogue("Check"))) == 0x84d0_a9ae_0ba2_e383)
    let tilted = custom(
      .check, colours: [0xFFFF_FFFF, 0xFF00_0000],
      [("xScale", 5), ("yScale", 9), ("fuzziness", 40), ("angle", 0.7)])
    #expect(hash(try render(tilted, width: 97, height: 61)) == 0x23fe_891e_9f10_af09)
  }

  @Test("Plasma matches the native code")
  func plasmaMatchesNative() throws {
    #expect(hash(try render(try catalogue("Plasma"))) == 0xbcfd_d0e9_560b_7ccb)
    let rough = custom(
      .plasma, colours: [0xFF00_0000], [("turbulence", 3.5), ("scaling", 0.2)])
    #expect(hash(try render(rough, width: 97, height: 61)) == 0x890b_8d93_c920_0034)
  }

  @Test("Quilt matches the native code")
  func quiltMatchesNative() throws {
    // The orbit is chaotic, so the last bit of sinf and cosf decides the cells it visits. The
    // values were computed with the Darwin libm, which this test runs on.
    #expect(hash(try render(try catalogue("Quilt"))) == 0x9b33_f93b_1f23_1c49)
    let other = custom(
      .quilt,
      [("iterations", 4000), ("a", 0.9), ("b", -0.3), ("c", 0.4), ("d", 0.2), ("k", 2)])
    #expect(hash(try render(other, width: 97, height: 61)) == 0xd250_55b4_4f97_4800)
  }

  @Test("BrushedMetal matches the native code, mono and stereo")
  func brushedMetalMatchesNative() throws {
    #expect(hash(try render(try catalogue("BrushedMetal"))) == 0xc715_9dcc_a6d5_7ee6)
    let tinted = custom(
      .brushedMetal, colours: [0xFF40_5060],
      [("radius", 3), ("amount", 0.3), ("shine", 0.5)])
    #expect(hash(try render(tinted, width: 97, height: 61)) == 0x45e4_dddf_d3fa_5ca5)
    let stereo = custom(
      .brushedMetal, colours: [0xFF88_8888],
      [("radius", 4), ("amount", 0.2), ("shine", 0.3), ("monochrome", 0)])
    #expect(hash(try render(stereo, width: 40, height: 20)) == 0xdfc4_9893_33aa_b71d)
  }

  @Test("Cellular matches the native code, on its default and a tuned preset")
  func cellularMatchesNative() throws {
    #expect(hash(try render(try catalogue("Cellular"))) == 0xb68d_1117_ecaa_2c03)
    let tuned = custom(
      .cellular, scale: 20, colours: [0xff33_6699],
      [
        ("stretch", 1.3), ("angle", 0.3), ("angleCoefficient", 0.5),
        ("gradientCoefficient", 0.2), ("f1", 1.5), ("f2", -0.5), ("randomness", 0.5),
        ("distancePower", 3), ("turbulence", 2.5),
      ])
    #expect(hash(try render(tuned, width: 97, height: 61)) == 0xc27c_c9d6_fae2_4818)
  }

  @Test("the grey colour map of the FBM filter truncates v times 255")
  func greyColourMap() {
    #expect(ClassicNative.grey(0) == 0xff00_0000)
    #expect(ClassicNative.grey(0.5) == 0xff7f_7f7f)
    #expect(ClassicNative.grey(1) == 0xffff_ffff)
    #expect(ClassicNative.grey(-3) == 0xff00_0000)
    #expect(ClassicNative.grey(7) == 0xffff_ffff)
  }

  @Test("mix_colors blends in float and truncates each channel")
  func mixColours() {
    #expect(ClassicNative.mix(0.5, 0, 0xffff_ffff) == 0x7f7f_7f7f)
    #expect(ClassicNative.mix(0, 0xff12_3456, 0xffff_ffff) == 0xff12_3456)
    #expect(ClassicNative.mix(3, 0xff12_3456, 0xffff_ffff) == 0xffff_ffff)
    #expect(ClassicNative.mix(-1, 0xff12_3456, 0xffff_ffff) == 0xff12_3456)
  }

  @Test("powi(8) and fract follow the native code")
  func powerAndFraction() {
    #expect(ClassicNative.eighth(0.5) == 0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5)
    #expect(ClassicNative.fract(-1.25) == -0.25)
    #expect(ClassicNative.fract(2.75) == 0.75)
  }

  @Test("the Check squares alternate, with the foreground on odd cells")
  func checkSquares() throws {
    let preset = custom(
      .check, colours: [0xFFFF_FFFF, 0xFF00_0000],
      [("xScale", 8), ("yScale", 8), ("fuzziness", 0), ("angle", 0)])
    let image = try render(preset, width: 16, height: 16)
    #expect(argb(image, 0, 0) == 0xff00_0000)
    #expect(argb(image, 8, 0) == 0xffff_ffff)
    #expect(argb(image, 0, 8) == 0xffff_ffff)
    #expect(argb(image, 8, 8) == 0xff00_0000)
  }

  @Test("the native table is the same for every seed")
  func tableIsFixed() throws {
    let preset = try catalogue("Caustics")
    let first = try render(preset, width: 32, height: 32)
    let other = try #require(
      TexturePresetRenderer.render(preset, seed: 987_654, width: 32, height: 32))
    #expect(first.pixels == other.pixels)
  }
}
