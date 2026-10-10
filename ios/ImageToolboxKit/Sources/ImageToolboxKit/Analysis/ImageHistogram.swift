import CoreGraphics

/// Counts of each level, 256 bins per channel, over the visible pixels (alpha above zero).
/// Luminance uses Rec. 601 weights, the same as `RasterImage.luminance`.
public struct ImageHistogram: Equatable, Sendable {
  public let red: [Int]
  public let green: [Int]
  public let blue: [Int]
  public let luminance: [Int]

  public init?(_ image: CGImage) {
    guard let raster = RasterImage(image) else { return nil }
    self.init(raster)
  }

  public init(_ raster: RasterImage) {
    var red = [Int](repeating: 0, count: 256)
    var green = [Int](repeating: 0, count: 256)
    var blue = [Int](repeating: 0, count: 256)
    var luminance = [Int](repeating: 0, count: 256)
    let straight = raster.straightRGBA()
    var index = 0
    while index < straight.count {
      if raster.pixels[index + 3] > 0 {
        let r = Int(straight[index])
        let g = Int(straight[index + 1])
        let b = Int(straight[index + 2])
        red[r] += 1
        green[g] += 1
        blue[b] += 1
        luminance[Self.level(red: r, green: g, blue: b)] += 1
      }
      index += 4
    }
    self.red = red
    self.green = green
    self.blue = blue
    self.luminance = luminance
  }

  /// Rec. 601 luma as a byte, rounded to the nearest level.
  static func level(red: Int, green: Int, blue: Int) -> Int {
    (299 * red + 587 * green + 114 * blue + 500) / 1000
  }
}
