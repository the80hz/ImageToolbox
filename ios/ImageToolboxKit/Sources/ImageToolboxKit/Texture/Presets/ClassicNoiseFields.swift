import Foundation

/// `CausticsFilter` of the native code: the background colour, brightened where the Perlin table
/// has a ridge. The Android app draws it with the fixed table of `ClassicNative`, so the seed of
/// the preset does not change the picture. The sample jitter, the dispersion and the sample count
/// of the Java class are not read by the native code, so they do not change the picture either.
enum ClassicCaustics {
  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let scale = max(Float(preset.scale), 0.01)
    let amount = Float(preset.value("amount", fallback: 1))
    let time = Float(preset.value("time", fallback: 0))
    let octaves = max(Float(preset.value("turbulence", fallback: 1)), 1)
    // The Android app passes the brightness as an int, which the native code divides by ten.
    let brightness = Float(ClassicMath.toInt(preset.value("brightness", fallback: 10))) / 10
    let background = preset.colours.first.map { Int($0) } ?? 0xFF79_9FFF
    return ClassicNative.draw(width: width, height: height) { x, y in
      let noise = ClassicNative.table.turbulence3(
        Float(x) / scale, Float(y) / scale, time, octaves)
      let ridge = ClassicNative.eighth(1 - abs(noise)) * amount * brightness
      return ClassicNative.mix(ridge, background, 0xffff_ffff)
    }
  }
}

/// `FBMFilter` of the native code: fractal noise of the fixed table, turned by the angle in
/// radians (the Java class does not convert degrees), stretched along one axis and drawn through
/// the grey colour map of the filter. The source of the Android app is transparent, so the
/// amount only sets how opaque the grey is.
enum ClassicFBM {
  /// The octaves of the native code. It reads `getTurbulence`, which `FBMFilter` does not have,
  /// so the default of 4 always applies. The Java octaves, lacunarity, gain and bias are not read.
  static let octaves: Float = 4

  static func render(_ preset: TexturePreset, width: Int, height: Int) -> [Int] {
    let scale = max(Float(preset.scale), 0.01)
    let stretch = max(Float(preset.value("stretch", fallback: 1)), 0.01)
    let angle = Float(preset.value("angle", fallback: 0))
    let amount = Float(preset.value("amount", fallback: 1))
    let sine = sinf(angle)
    let cosine = cosf(angle)
    return ClassicNative.draw(width: width, height: height) { x, y in
      let column = Float(x)
      let row = Float(y)
      let nx = (cosine * column + sine * row) / scale
      let ny = (-sine * column + cosine * row) / (scale * stretch)
      let noise = ClassicNative.table.turbulence3(nx, ny, 0, octaves)
      let value = ClassicMath.clamp((noise + 1) * 0.5, 0, 1)
      return ClassicNative.mix(amount, 0, ClassicNative.grey(value))
    }
  }
}
