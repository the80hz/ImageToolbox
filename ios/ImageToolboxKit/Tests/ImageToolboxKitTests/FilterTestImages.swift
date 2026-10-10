import Foundation

@testable import ImageToolboxKit

/// Pictures the filter tests share. Each filter test builds its own input with these.
enum FilterTestImages {
  /// An opaque picture: red grows left to right, green top to bottom, blue is fixed.
  static func gradient(width: Int, height: Int) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        pixels[index] = UInt8(x * 255 / max(1, width - 1))
        pixels[index + 1] = UInt8(y * 255 / max(1, height - 1))
        pixels[index + 2] = 96
        pixels[index + 3] = 255
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  /// One opaque colour everywhere.
  static func solid(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> RasterImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      pixels[index] = red
      pixels[index + 1] = green
      pixels[index + 2] = blue
      pixels[index + 3] = 255
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }
}
