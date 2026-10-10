import Foundation

/// One channel of float samples, row by row from the top.
struct Plane {
  let width: Int
  let height: Int
  var values: [Float]

  init(width: Int, height: Int, repeating value: Float = 0) {
    self.width = width
    self.height = height
    values = [Float](repeating: value, count: width * height)
  }

  init(width: Int, height: Int, values: [Float]) {
    self.width = width
    self.height = height
    self.values = values
  }

  @inline(__always)
  subscript(x: Int, y: Int) -> Float {
    get { values[y * width + x] }
    set { values[y * width + x] = newValue }
  }

  /// Separable convolution with edge samples repeated at the borders.
  func convolved(with kernel: [Float]) -> Plane {
    let radius = kernel.count / 2
    var horizontal = Plane(width: width, height: height)
    for y in 0..<height {
      for x in 0..<width {
        var sum: Float = 0
        for (offset, weight) in kernel.enumerated() {
          let sample = min(max(x + offset - radius, 0), width - 1)
          sum += weight * self[sample, y]
        }
        horizontal[x, y] = sum
      }
    }
    var result = Plane(width: width, height: height)
    for y in 0..<height {
      for x in 0..<width {
        var sum: Float = 0
        for (offset, weight) in kernel.enumerated() {
          let sample = min(max(y + offset - radius, 0), height - 1)
          sum += weight * horizontal[x, sample]
        }
        result[x, y] = sum
      }
    }
    return result
  }

  /// A Gaussian of `size` taps, with the standard deviation OpenCV uses when none is given.
  static func gaussianKernel(size: Int) -> [Float] {
    let sigma = 0.3 * (Double(size - 1) * 0.5 - 1) + 0.8
    let radius = size / 2
    let weights = (0..<size).map { index -> Double in
      let distance = Double(index - radius)
      return exp(-distance * distance / (2 * sigma * sigma))
    }
    let total = weights.reduce(0, +)
    return weights.map { Float($0 / total) }
  }

  /// The 5-tap binomial kernel of the Gaussian and Laplacian pyramids.
  static let pyramidKernel: [Float] = [1, 4, 6, 4, 1].map { $0 / 16 }

  /// Half the size, after blurring so no detail aliases.
  func halved() -> Plane {
    let blurred = convolved(with: Self.pyramidKernel)
    let newWidth = (width + 1) / 2
    let newHeight = (height + 1) / 2
    var result = Plane(width: newWidth, height: newHeight)
    for y in 0..<newHeight {
      for x in 0..<newWidth {
        result[x, y] = blurred[min(x * 2, width - 1), min(y * 2, height - 1)]
      }
    }
    return result
  }

  /// Bilinear resampling to another size.
  func resized(width newWidth: Int, height newHeight: Int) -> Plane {
    var result = Plane(width: newWidth, height: newHeight)
    let scaleX = Float(width) / Float(newWidth)
    let scaleY = Float(height) / Float(newHeight)
    for y in 0..<newHeight {
      let sourceY = max((Float(y) + 0.5) * scaleY - 0.5, 0)
      let y0 = min(Int(sourceY), height - 1)
      let y1 = min(y0 + 1, height - 1)
      let fractionY = sourceY - Float(y0)
      for x in 0..<newWidth {
        let sourceX = max((Float(x) + 0.5) * scaleX - 0.5, 0)
        let x0 = min(Int(sourceX), width - 1)
        let x1 = min(x0 + 1, width - 1)
        let fractionX = sourceX - Float(x0)
        let top = self[x0, y0] * (1 - fractionX) + self[x1, y0] * fractionX
        let bottom = self[x0, y1] * (1 - fractionX) + self[x1, y1] * fractionX
        result[x, y] = top * (1 - fractionY) + bottom * fractionY
      }
    }
    return result
  }

  func mapped(_ transform: (Float) -> Float) -> Plane {
    Plane(width: width, height: height, values: values.map(transform))
  }

  func combined(with other: Plane, _ transform: (Float, Float) -> Float) -> Plane {
    Plane(
      width: width, height: height,
      values: zip(values, other.values).map(transform))
  }

  var mean: Double {
    values.isEmpty ? 0 : values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
  }

  /// The 3x3 Laplacian, as its absolute value.
  func absoluteLaplacian() -> Plane {
    var result = Plane(width: width, height: height)
    for y in 0..<height {
      let up = max(y - 1, 0)
      let down = min(y + 1, height - 1)
      for x in 0..<width {
        let left = max(x - 1, 0)
        let right = min(x + 1, width - 1)
        let value =
          self[left, y] + self[right, y] + self[x, up] + self[x, down]
          - 4 * self[x, y]
        result[x, y] = abs(value)
      }
    }
    return result
  }
}

/// A picture as three planes of sRGB values from 0 to 1.
struct ColourPlanes {
  let width: Int
  let height: Int
  var red: Plane
  var green: Plane
  var blue: Plane

  init(width: Int, height: Int, red: Plane, green: Plane, blue: Plane) {
    self.width = width
    self.height = height
    self.red = red
    self.green = green
    self.blue = blue
  }

  init(_ raster: RasterImage) {
    width = raster.width
    height = raster.height
    let count = width * height
    var red = [Float](repeating: 0, count: count)
    var green = [Float](repeating: 0, count: count)
    var blue = [Float](repeating: 0, count: count)
    let straight = raster.straightRGBA()
    for index in 0..<count {
      red[index] = Float(straight[index * 4]) / 255
      green[index] = Float(straight[index * 4 + 1]) / 255
      blue[index] = Float(straight[index * 4 + 2]) / 255
    }
    self.red = Plane(width: width, height: height, values: red)
    self.green = Plane(width: width, height: height, values: green)
    self.blue = Plane(width: width, height: height, values: blue)
  }

  var planes: [Plane] { [red, green, blue] }

  /// The same picture with every channel converted from sRGB to linear light.
  func linear() -> ColourPlanes {
    ColourPlanes(
      width: width, height: height,
      red: red.mapped { Float(OklabColour.srgbToLinear(Double($0))) },
      green: green.mapped { Float(OklabColour.srgbToLinear(Double($0))) },
      blue: blue.mapped { Float(OklabColour.srgbToLinear(Double($0))) })
  }

  /// The same picture with every channel converted from linear light to sRGB.
  func encoded() -> ColourPlanes {
    ColourPlanes(
      width: width, height: height,
      red: red.mapped { Float(OklabColour.linearToSRGB(Double($0))) },
      green: green.mapped { Float(OklabColour.linearToSRGB(Double($0))) },
      blue: blue.mapped { Float(OklabColour.linearToSRGB(Double($0))) })
  }

  /// An opaque picture with 8-bit channels. Values outside 0...1 are clamped.
  func raster() -> RasterImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for index in 0..<(width * height) {
      pixels[index * 4] = Self.byte(red.values[index])
      pixels[index * 4 + 1] = Self.byte(green.values[index])
      pixels[index * 4 + 2] = Self.byte(blue.values[index])
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func byte(_ value: Float) -> UInt8 {
    UInt8((min(max(value, 0), 1) * 255).rounded())
  }
}
