import Foundation

/// The JH Labs filters of the Android texture generator, except Marble and Wood (see
/// `ClassicMarbleWood`). Each one follows the native code of the Android fork, which draws the
/// picture for every JH Labs filter (see `ClassicNative`), run over the whole picture with the
/// parameters that the Android app passes. Cellular keeps its own file (see
/// `ClassicCellularFilter`). The results are ARGB pixels, row 0 first.
enum ClassicJHLabs {
  static func render(
    _ preset: TexturePreset,
    kind: ClassicKind,
    width: Int,
    height: Int
  ) -> [Int] {
    switch kind {
    case .brushedMetal:
      return ClassicBrushedMetal.render(preset, width: width, height: height)
    case .caustics:
      return ClassicCaustics.render(preset, width: width, height: height)
    case .cellular:
      return ClassicCellularFilter.render(preset, width: width, height: height)
    case .check:
      return ClassicCheck.render(preset, width: width, height: height)
    case .fbm:
      return ClassicFBM.render(preset, width: width, height: height)
    case .marble:
      return ClassicMarbleWood.marble(preset, width: width, height: height)
    case .plasma:
      return ClassicPlasma.render(preset, width: width, height: height)
    case .quilt:
      return ClassicQuilt.render(preset, width: width, height: height)
    case .wood:
      return ClassicMarbleWood.wood(preset, width: width, height: height)
    case .organicFibers, .gmicReactionDiffusion, .truchet:
      preconditionFailure("\(kind) is not drawn by the JH Labs filters")
    }
  }
}
