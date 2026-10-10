import Foundation

/// Fuses frames of one size into one picture. The frames must already be aligned, see
/// `FrameAlignment`. Each mode follows the Android app's algorithm.
public enum FrameFusion {

  /// Returns nil when there are fewer than two frames, the sizes differ, or there are too many.
  public static func fuse(_ frames: [RasterImage], params: FusionParams = FusionParams())
    -> RasterImage?
  {
    guard
      frames.count >= FusionParams.minimumImages,
      frames.count <= FusionParams.maximumImages,
      let first = frames.first,
      frames.allSatisfy({ $0.width == first.width && $0.height == first.height })
    else { return nil }

    let settings = params.normalized()
    let pictures = frames.map(ColourPlanes.init)
    switch settings.mode {
    case .exposure:
      return exposureFusion(pictures, settings).raster()
    case .focus:
      return focusStack(pictures, settings).raster()
    case .median:
      return median(pictures).raster()
    case .longExposure:
      return linearAverage(pictures).encoded().raster()
    case .lightTrails:
      return lightTrails(pictures, settings).encoded().raster()
    case .motionTrails:
      return motionTrails(pictures, settings).encoded().raster()
    }
  }

  // MARK: - Exposure

  /// Mertens exposure fusion: weights from contrast, saturation and exposedness, blended over
  /// Laplacian pyramids so that seams between frames stay invisible.
  static func exposureFusion(_ pictures: [ColourPlanes], _ params: FusionParams) -> ColourPlanes {
    let width = pictures[0].width
    let height = pictures[0].height
    let weights: [Plane] = pictures.map { mertensWeight($0, params) }

    // Normalise the weights per pixel so they sum to one. The guard only prevents division by zero:
    // weights can be tiny on flat areas, so a larger constant would change the result.
    var normalised = weights
    for index in 0..<(width * height) {
      let total = max(
        weights.reduce(Float(0)) { $0 + $1.values[index] }, Float.leastNormalMagnitude)
      for frame in normalised.indices {
        normalised[frame].values[index] = weights[frame].values[index] / total
      }
    }

    let levels = max(1, Int(log2(Double(min(width, height)))))
    let blendedRed = blend(pictures.map(\.red), weights: normalised, levels: levels)
    let blendedGreen = blend(pictures.map(\.green), weights: normalised, levels: levels)
    let blendedBlue = blend(pictures.map(\.blue), weights: normalised, levels: levels)
    return ColourPlanes(
      width: width, height: height,
      red: blendedRed.mapped { min(max($0, 0), 1) },
      green: blendedGreen.mapped { min(max($0, 0), 1) },
      blue: blendedBlue.mapped { min(max($0, 0), 1) })
  }

  /// Luminance of a picture with Rec. 601 weights.
  private static func luminance(_ picture: ColourPlanes) -> Plane {
    var values = [Float](repeating: 0, count: picture.width * picture.height)
    for index in values.indices {
      let red: Float = picture.red.values[index] * 0.299
      let green: Float = picture.green.values[index] * 0.587
      let blue: Float = picture.blue.values[index] * 0.114
      values[index] = red + green + blue
    }
    return Plane(width: picture.width, height: picture.height, values: values)
  }

  /// The standard deviation of the three channels at each pixel: the saturation measure.
  private static func saturation(_ picture: ColourPlanes) -> Plane {
    var values = [Float](repeating: 0, count: picture.width * picture.height)
    for index in values.indices {
      let red: Float = picture.red.values[index]
      let green: Float = picture.green.values[index]
      let blue: Float = picture.blue.values[index]
      let mean: Float = (red + green + blue) / 3
      let deltaRed: Float = red - mean
      let deltaGreen: Float = green - mean
      let deltaBlue: Float = blue - mean
      let squares: Float = deltaRed * deltaRed + deltaGreen * deltaGreen + deltaBlue * deltaBlue
      values[index] = (squares / 3).squareRoot()
    }
    return Plane(width: picture.width, height: picture.height, values: values)
  }

  /// One frame's Mertens weight at each pixel: contrast, saturation and exposedness, each raised to
  /// its weight from the settings.
  private static func mertensWeight(_ picture: ColourPlanes, _ params: FusionParams) -> Plane {
    let contrast = luminance(picture).absoluteLaplacian()
    let saturationMeasure = saturation(picture)
    let exposure = wellExposedness(picture, params.exposureWeight)
    var values = [Float](repeating: 0, count: picture.width * picture.height)
    for index in values.indices {
      let contrastTerm = pow(Double(contrast.values[index]) + 1e-12, params.contrastWeight)
      let saturationTerm = pow(
        Double(saturationMeasure.values[index]) + 1e-12, params.saturationWeight)
      values[index] = Float(contrastTerm * saturationTerm) * exposure.values[index]
    }
    return Plane(width: picture.width, height: picture.height, values: values)
  }

  /// The product of the three channels' closeness to mid grey, with the exposure weight applied.
  private static func wellExposedness(_ picture: ColourPlanes, _ weight: Double) -> Plane {
    func closeness(_ value: Float) -> Float {
      Float(exp(-Double((value - 0.5) * (value - 0.5)) / (2 * 0.2 * 0.2)))
    }
    return Plane(
      width: picture.width, height: picture.height,
      values: (0..<(picture.width * picture.height)).map { index in
        let product =
          closeness(picture.red.values[index])
          * closeness(picture.green.values[index]) * closeness(picture.blue.values[index])
        return Float(pow(Double(product) + 1e-12, weight))
      })
  }

  /// Blends one channel of all frames with the given per-pixel weights, through pyramids.
  private static func blend(_ channels: [Plane], weights: [Plane], levels: Int) -> Plane {
    var layers: [Plane] = []
    for (channel, weight) in zip(channels, weights) {
      let image = laplacianPyramid(channel, levels: levels)
      let mask = gaussianPyramid(weight, levels: levels)
      for level in 0...levels {
        let contribution = image[level].combined(with: mask[level]) { $0 * $1 }
        if level < layers.count {
          layers[level] = layers[level].combined(with: contribution) { $0 + $1 }
        } else {
          layers.append(contribution)
        }
      }
    }
    var collapsed = layers[levels]
    for level in stride(from: levels - 1, through: 0, by: -1) {
      let enlarged = collapsed.resized(width: layers[level].width, height: layers[level].height)
      collapsed = enlarged.combined(with: layers[level]) { $0 + $1 }
    }
    return collapsed
  }

  private static func gaussianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
    var pyramid = [plane]
    for _ in 0..<levels {
      pyramid.append(pyramid[pyramid.count - 1].halved())
    }
    return pyramid
  }

  private static func laplacianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
    let gaussian = gaussianPyramid(plane, levels: levels)
    var laplacian: [Plane] = []
    for level in 0..<levels {
      let coarser = gaussian[level + 1].resized(
        width: gaussian[level].width, height: gaussian[level].height)
      laplacian.append(gaussian[level].combined(with: coarser) { $0 - $1 })
    }
    laplacian.append(gaussian[levels])
    return laplacian
  }

  // MARK: - Focus

  /// Focus stacking: each pixel is taken mostly from the frame where it is sharpest. Frames are
  /// first scaled to a common brightness, so a dark frame does not win on contrast alone.
  static func focusStack(_ pictures: [ColourPlanes], _ params: FusionParams) -> ColourPlanes {
    let width = pictures[0].width
    let height = pictures[0].height
    let brightness = pictures.map { picture -> Double in
      (picture.red.mean + picture.green.mean + picture.blue.mean) / 3 * 255
    }
    let sorted = brightness.sorted()
    let target = sorted[sorted.count / 2]
    let kernel = Plane.gaussianKernel(size: params.focusRadius)

    var red = Plane(width: width, height: height)
    var green = Plane(width: width, height: height)
    var blue = Plane(width: width, height: height)
    var total = Plane(width: width, height: height)
    for (index, picture) in pictures.enumerated() {
      let gray = picture.red.combined(with: picture.green) { $0 * 0.299 + $1 * 0.587 }
        .combined(with: picture.blue) { $0 + $1 * 0.114 }
        .mapped { $0 * 255 }
      let sharpness = gray.absoluteLaplacian().convolved(with: kernel)
      let weight = sharpness.mapped { Float(pow(Double($0) + 0.5, params.focusStrength)) }
      let scale = Float(min(max(target / max(brightness[index], 1e-9), 0.25), 4))
      red = red.combined(with: weight.combined(with: picture.red) { $0 * $1 * scale }) { $0 + $1 }
      green = green.combined(with: weight.combined(with: picture.green) { $0 * $1 * scale }) {
        $0 + $1
      }
      blue = blue.combined(with: weight.combined(with: picture.blue) { $0 * $1 * scale }) {
        $0 + $1
      }
      total = total.combined(with: weight) { $0 + $1 }
    }
    return ColourPlanes(
      width: width, height: height,
      red: red.combined(with: total) { $0 / $1 },
      green: green.combined(with: total) { $0 / $1 },
      blue: blue.combined(with: total) { $0 / $1 })
  }

  // MARK: - Median and averages

  /// The median of each channel over the frames, with the average of the two middle values for an
  /// even count.
  static func median(_ pictures: [ColourPlanes]) -> ColourPlanes {
    let width = pictures[0].width
    let height = pictures[0].height
    let count = width * height
    let frames = pictures.count
    func channel(_ keyPath: KeyPath<ColourPlanes, Plane>) -> Plane {
      var output = [Float](repeating: 0, count: count)
      var samples = [Float](repeating: 0, count: frames)
      for index in 0..<count {
        for frame in 0..<frames {
          samples[frame] = pictures[frame][keyPath: keyPath].values[index]
        }
        samples.sort()
        output[index] =
          frames % 2 == 1
          ? samples[frames / 2]
          : (samples[frames / 2 - 1] + samples[frames / 2]) / 2
      }
      return Plane(width: width, height: height, values: output)
    }
    return ColourPlanes(
      width: width, height: height,
      red: channel(\.red), green: channel(\.green), blue: channel(\.blue))
  }

  /// The average of the frames in linear light.
  static func linearAverage(_ pictures: [ColourPlanes]) -> ColourPlanes {
    let linear = pictures.map { $0.linear() }
    let scale = Float(1) / Float(pictures.count)
    func average(_ keyPath: KeyPath<ColourPlanes, Plane>) -> Plane {
      var sum = Plane(width: linear[0].width, height: linear[0].height)
      for frame in linear {
        sum = sum.combined(with: frame[keyPath: keyPath]) { $0 + $1 }
      }
      return sum.mapped { $0 * scale }
    }
    return ColourPlanes(
      width: linear[0].width, height: linear[0].height,
      red: average(\.red), green: average(\.green), blue: average(\.blue))
  }

  // MARK: - Trails

  /// Light streaks: the brightest value seen at each pixel is kept where it stands out from the
  /// average, so the streak survives and the rest stays averaged. Works in linear light.
  static func lightTrails(_ pictures: [ColourPlanes], _ params: FusionParams) -> ColourPlanes {
    let linear = pictures.map { $0.linear() }
    let base = linearAverage(pictures)
    let count = linear[0].width * linear[0].height

    var brightest = linear[0].planes
    var brightestIntensity = (0..<count).map { index in
      max(brightest[0].values[index], brightest[1].values[index], brightest[2].values[index])
    }
    for frame in linear.dropFirst() {
      for index in 0..<count {
        let intensity = max(
          frame.red.values[index], frame.green.values[index], frame.blue.values[index])
        if intensity > brightestIntensity[index] {
          brightestIntensity[index] = intensity
          brightest[0].values[index] = frame.red.values[index]
          brightest[1].values[index] = frame.green.values[index]
          brightest[2].values[index] = frame.blue.values[index]
        }
      }
    }

    let threshold = Float(params.lightTrailThreshold)
    let strength = Float(params.trailStrength)
    let mask = (0..<count).map { index -> Float in
      let baseIntensity = max(
        base.red.values[index], base.green.values[index], base.blue.values[index])
      let difference = brightestIntensity[index] - baseIntensity - threshold
      let scaled = min(max(difference, 0) / (1 - threshold), 1)
      return scaled.squareRoot() * strength
    }
    let maskPlane = Plane(width: linear[0].width, height: linear[0].height, values: mask)
    func blend(_ channel: Int, _ baseChannel: Plane) -> Plane {
      let streak = brightest[channel].combined(with: baseChannel) { $0 - $1 }
      return baseChannel.combined(with: streak.combined(with: maskPlane) { $0 * $1 }) { $0 + $1 }
    }
    return ColourPlanes(
      width: linear[0].width, height: linear[0].height,
      red: blend(0, base.red), green: blend(1, base.green), blue: blend(2, base.blue))
  }

  /// Motion trails: the frames are averaged with newer frames weighted more, then mixed with the
  /// newest frame by the trail strength. Works in linear light.
  static func motionTrails(_ pictures: [ColourPlanes], _ params: FusionParams) -> ColourPlanes {
    let linear = pictures.map { $0.linear() }
    let persistence = params.trailPersistence
    let weights = linear.indices.map { pow(persistence, Double(linear.count - 1 - $0)) }
    let total = weights.reduce(0, +)

    func weighted(_ keyPath: KeyPath<ColourPlanes, Plane>) -> Plane {
      var sum = Plane(width: linear[0].width, height: linear[0].height)
      for (frame, weight) in zip(linear, weights) {
        sum = sum.combined(with: frame[keyPath: keyPath]) { $0 + $1 * Float(weight) }
      }
      return sum.mapped { $0 / Float(total) }
    }

    let strength = Float(params.trailStrength)
    let latest = linear[linear.count - 1]
    func mix(_ keyPath: KeyPath<ColourPlanes, Plane>) -> Plane {
      latest[keyPath: keyPath].combined(with: weighted(keyPath)) { newest, average in
        newest * (1 - strength) + average * strength
      }
    }
    return ColourPlanes(
      width: latest.width, height: latest.height,
      red: mix(\.red), green: mix(\.green), blue: mix(\.blue))
  }
}
