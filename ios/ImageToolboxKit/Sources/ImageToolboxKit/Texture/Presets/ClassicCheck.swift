import Foundation

/// `CheckFilter` of the native code: squares of `xScale` by `yScale` in the grid turned by the
/// angle, read in radians as the Java class stores it. The edges are softened by the fuzziness,
/// which the native code takes out of 100. The preset colours are the foreground, then the
/// background.
enum ClassicCheck {
  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let foreground = preset.colours.first.map { Int($0) } ?? 0xFFFF_FFFF
    let background = preset.colours.count > 1 ? Int(preset.colours[1]) : 0xFF00_0000
    let xScale = Float(max(ClassicMath.toInt(preset.value("xScale", fallback: 8)), 1))
    let yScale = Float(max(ClassicMath.toInt(preset.value("yScale", fallback: 8)), 1))
    let fuzziness = Float(ClassicMath.toInt(preset.value("fuzziness", fallback: 0))) / 100
    let angle = Float(preset.value("angle", fallback: 0))
    let sine = sinf(angle)
    let cosine = cosf(angle)
    return ClassicNative.draw(width: width, height: height) { x, y in
      let column = Float(x)
      let row = Float(y)
      let nx = (cosine * column + sine * row) / xScale
      let ny = (-sine * column + cosine * row) / yScale
      let parity = Float(
        (ClassicMath.toInt(nx.rounded(.down)) + ClassicMath.toInt(ny.rounded(.down))) & 1)
      let fractionX = abs(ClassicNative.fract(nx))
      let fractionY = abs(ClassicNative.fract(ny))
      let edge = min(
        min(min(fractionX, fractionY), 1 - fractionX), 1 - fractionY)
      let amount: Float
      if fuzziness == 0 {
        amount = parity
      } else {
        let blend = ClassicMath.smoothStep(0, fuzziness * 0.5, edge)
        amount = blend * parity + (1 - blend) * 0.5
      }
      return ClassicNative.mix(amount, background, foreground)
    }
  }
}
