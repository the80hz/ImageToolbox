import Foundation

/// `PlasmaFilter` of the native code with `useImageColors`: a Perlin turbulence over a square of
/// four by four units, shifted by the phase of the field seed (567), and mixed with the source
/// colour. The colour map is the linear ramp from black to white of the Java class.
enum ClassicPlasma {
  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let turbulence = max(Float(preset.value("turbulence", fallback: 1)), 1)
    let scaling = Float(preset.value("scaling", fallback: 0))
    // The field seed of the Java class is 567, and the native code scales it by 0.0001.
    let phase = Float(567) * 0.0001
    let source = preset.colours.first.map { Int($0) } ?? 0xFF00_0000
    let colours = ClassicLinearColormap(low: 0xff00_0000, high: 0xffff_ffff)
    return ClassicNative.draw(width: width, height: height) { x, y in
      let nx = Float(x) / Float(width) * 4
      let ny = Float(y) / Float(height) * 4
      let noise = ClassicNative.table.turbulence3(nx + phase, ny, phase, turbulence)
      let value = ClassicMath.clamp((noise + 1) * 0.5 + scaling, 0, 1)
      return ClassicNative.mix(value, source, colours.colour(value))
    }
  }
}
