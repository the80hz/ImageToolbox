import Foundation

/// The shading step of the simulated textures 71...121 (`shadeSimulation` in
/// `ProceduralTextures.cpp`): gradients and a Laplacian of the field, an edge term, a per-type
/// remap of the value, then the palette with a light and a glow.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath

  /// Types whose value mixes the edge term first.
  private static let edgeLayeredTypes: Set<Int> = [
    74, 75, 79, 86, 87, 92, 93, 94, 95, 99, 101, 102, 104, 105, 106, 109, 112, 113, 114,
    115, 116, 118, 121,
  ]

  static func shadeSimulation(
    _ textureType: Int, _ field: [Float], _ x: Int, _ y: Int, _ width: Int, _ height: Int,
    _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    func sample(_ sx: Int, _ sy: Int) -> Float {
      let cx = min(max(sx, 0), width - 1)
      let cy = min(max(sy, 0), height - 1)
      return field[cy * width + cx]
    }
    let center = sample(x, y)
    let left = sample(x - 1, y)
    let right = sample(x + 1, y)
    let top = sample(x, y - 1)
    let bottom = sample(x, y + 1)
    let gx = right - left
    let gy = bottom - top
    let gradient = M.clamp01((gx * gx + gy * gy).squareRoot() * 7)
    let laplacian = M.clamp01(abs(left + right + top + bottom - center * 4) * 5)
    let sharpness = M.clamp01(parameter(p, 3, 0.58))
    let glow = M.clamp01(parameter(p, 4, 0.52))
    let contrastAmount = M.maxOf(parameter(p, 5, 1.25), 0.05)
    let edge = M.smoothstep(
      0.02 + (1 - sharpness) * 0.08, 0.45, gradient + laplacian * 0.7)
    var value = M.contrast(center * 0.72 + edge * 0.42, contrastAmount)

    if edgeLayeredTypes.contains(textureType) {
      value = M.contrast(edge * 0.8 + center * 0.42, contrastAmount)
    } else if textureType == 81 || textureType == 88 || textureType == 89 {
      value = M.contrast(center * 0.62 + (1 - edge) * 0.28, contrastAmount)
    } else if textureType == 84 || textureType == 91 {
      value = M.fract(center + gradient * 0.8 + laplacian * 0.45)
    }

    switch textureType {
    case 71:
      value = M.contrast(M.smoothstep(0.38, 0.62, center) * 0.72 + edge * 0.35, contrastAmount)
    case 72:
      value = M.contrast(center * 0.74 + edge * 0.38 + laplacian * 0.16, contrastAmount)
    case 73:
      value = M.contrast(edge * 0.62 + center * 0.28, contrastAmount)
    case 76:
      value = M.clamp01(center * 0.48 + edge * 0.72 + laplacian * 0.38)
    case 78:
      value = M.contrast(center * 0.72 + gradient * 0.5, contrastAmount)
    case 74:
      value = M.contrast(center * 0.48 + edge * 0.76 + laplacian * 0.22, contrastAmount)
    case 75:
      value = M.contrast(center * 0.72 + edge * 0.62, contrastAmount)
    case 79:
      value = M.contrast(center * 0.58 + edge * 0.68 + laplacian * 0.18, contrastAmount)
    case 81:
      value = M.contrast(center * 0.82 + edge * 0.26, contrastAmount)
    case 83:
      value = M.contrast(center * 0.78 + edge * 0.28, contrastAmount)
    case 86:
      value = M.contrast(center * 0.54 + edge * 0.72 + laplacian * 0.18, contrastAmount)
    case 89:
      value = M.contrast(
        center * 0.22 + gradient * 0.86 + M.clamp01((-gx - gy) * 2 + 0.5) * 0.18,
        contrastAmount)
    case 96, 97, 98:
      value = center > 0.995 ? 0 : M.fract(center * 7 + edge * 0.42)
    case 100:
      value = M.fract(center + gradient * 0.7)
    case 102:
      value = M.contrast(center * 0.42 + edge * 0.76 + laplacian * 0.22, contrastAmount)
    case 107, 119:
      value = M.contrast(center * 0.76 + laplacian * 0.48, contrastAmount)
    case 110:
      value = M.contrast(center * 0.82 + edge * 0.16, contrastAmount)
    case 109:
      value = M.contrast(center * 0.36 + edge * 0.74 + M.fract(center * 3) * 0.18, contrastAmount)
    case 115:
      value = M.contrast(center * 0.54 + edge * 0.68 + laplacian * 0.2, contrastAmount)
    case 117:
      value = M.contrast(center * 0.9 + gradient * 0.16, contrastAmount)
    case 120:
      value = M.contrast(center * 0.55 + (-gx - gy + 1) * 0.22 + edge * 0.24, contrastAmount)
    default:
      break
    }

    var result = palette4(c, value)
    let light = M.clamp01((-gx - gy) * 2.8 + gradient * 0.35)
    result = M.mixColor(result, colour(c, 3, 0xFFFF_E8A3), light * (0.2 + glow * 0.55))
    return M.mixColor(result, colour(c, 3, 0xFFFF_E8A3), edge * glow * 0.32)
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
