// Port of the androidx.palette colour cut quantizer (androidx/palette/graphics/ColorCutQuantizer),
// which the Android app uses to pick the seed colour of a Material You scheme.
// Copyright 2014 The Android Open Source Project. Licensed under the Apache License,
// Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// A colour and the number of pixels it stands for.
struct PaletteSwatchData: Sendable, Equatable {
  let rgb: UInt32
  let population: Int

  /// HSL as `androidx.core.graphics.ColorUtils.colorToHSL`: hue 0...360, saturation and
  /// lightness 0...1.
  var hsl: (h: Float, s: Float, l: Float) { AndroidPaletteQuantizer.hsl(rgb) }
}

/// Median-cut quantizer over a 15-bit RGB histogram, with the default palette filter.
final class AndroidPaletteQuantizer {
  private static let wordWidth = 5
  private static let wordMask = (1 << 5) - 1

  fileprivate enum Component { case red, green, blue }

  private var colours: [Int] = []
  private var histogram = [Int](repeating: 0, count: 1 << 15)
  private(set) var quantized: [PaletteSwatchData] = []

  /// `pixels` are 0xAARRGGBB; alpha is ignored. Keeps at most `maxColours` swatches.
  init(pixels: [UInt32], maxColours: Int) {
    for pixel in pixels {
      histogram[Self.quantizeFromRGB888(pixel)] += 1
    }
    var distinct = 0
    for colour in histogram.indices {
      if histogram[colour] > 0 && Self.shouldIgnore(Self.approximateToRGB888(colour)) {
        histogram[colour] = 0
      }
      if histogram[colour] > 0 { distinct += 1 }
    }
    colours.reserveCapacity(distinct)
    for colour in histogram.indices where histogram[colour] > 0 { colours.append(colour) }

    if distinct <= maxColours {
      quantized = colours.map {
        PaletteSwatchData(rgb: Self.approximateToRGB888($0), population: histogram[$0])
      }
    } else {
      quantized = quantizePixels(maxColours)
    }
  }

  // MARK: Quantization

  private func quantizePixels(_ maxColours: Int) -> [PaletteSwatchData] {
    var queue = JavaVboxQueue()
    queue.offer(Vbox(lower: 0, upper: colours.count - 1, owner: self))
    while queue.count < maxColours {
      guard let box = queue.poll(), box.canSplit else { break }
      queue.offer(box.split())
      queue.offer(box)
    }
    var result: [PaletteSwatchData] = []
    for box in queue.elements {
      let swatch = box.averageColour()
      if !Self.shouldIgnore(swatch.rgb) { result.append(swatch) }
    }
    return result
  }

  /// A box in colour space covering `colours[lower...upper]`.
  final class Vbox {
    private unowned let owner: AndroidPaletteQuantizer
    private var lower: Int
    private var upper: Int
    private var population = 0
    private var minR = 0
    private var maxR = 0
    private var minG = 0
    private var maxG = 0
    private var minB = 0
    private var maxB = 0

    init(lower: Int, upper: Int, owner: AndroidPaletteQuantizer) {
      self.lower = lower
      self.upper = upper
      self.owner = owner
      fit()
    }

    var volume: Int { (maxR - minR + 1) * (maxG - minG + 1) * (maxB - minB + 1) }
    var canSplit: Bool { upper > lower }

    private func fit() {
      var lowR = Int.max
      var lowG = Int.max
      var lowB = Int.max
      var highR = Int.min
      var highG = Int.min
      var highB = Int.min
      var count = 0
      for i in lower...upper {
        let colour = owner.colours[i]
        count += owner.histogram[colour]
        let r = AndroidPaletteQuantizer.red(colour)
        let g = AndroidPaletteQuantizer.green(colour)
        let b = AndroidPaletteQuantizer.blue(colour)
        highR = max(highR, r)
        lowR = min(lowR, r)
        highG = max(highG, g)
        lowG = min(lowG, g)
        highB = max(highB, b)
        lowB = min(lowB, b)
      }
      minR = lowR
      maxR = highR
      minG = lowG
      maxG = highG
      minB = lowB
      maxB = highB
      population = count
    }

    func split() -> Vbox {
      let point = findSplitPoint()
      let other = Vbox(lower: point + 1, upper: upper, owner: owner)
      upper = point
      fit()
      return other
    }

    private var longestDimension: Component {
      let red = maxR - minR
      let green = maxG - minG
      let blue = maxB - minB
      if red >= green && red >= blue { return .red }
      if green >= red && green >= blue { return .green }
      return .blue
    }

    private func findSplitPoint() -> Int {
      let dimension = longestDimension
      // Sort by the longest dimension by moving it into the most significant bits and back.
      owner.swapSignificantComponent(dimension, lower, upper)
      owner.colours[lower...upper].sort()
      owner.swapSignificantComponent(dimension, lower, upper)

      let midpoint = population / 2
      var count = 0
      for i in lower...upper {
        count += owner.histogram[owner.colours[i]]
        if count >= midpoint {
          // Never split on the upper index, as that returns the same box.
          return min(upper - 1, i)
        }
      }
      return lower
    }

    func averageColour() -> PaletteSwatchData {
      var redSum = 0
      var greenSum = 0
      var blueSum = 0
      var total = 0
      for i in lower...upper {
        let colour = owner.colours[i]
        let count = owner.histogram[colour]
        total += count
        redSum += count * AndroidPaletteQuantizer.red(colour)
        greenSum += count * AndroidPaletteQuantizer.green(colour)
        blueSum += count * AndroidPaletteQuantizer.blue(colour)
      }
      let redMean = Int((Float(redSum) / Float(total)).rounded())
      let greenMean = Int((Float(greenSum) / Float(total)).rounded())
      let blueMean = Int((Float(blueSum) / Float(total)).rounded())
      return PaletteSwatchData(
        rgb: AndroidPaletteQuantizer.approximateToRGB888(
          red: redMean, green: greenMean, blue: blueMean),
        population: total)
    }
  }

  /// Swaps the 5-bit components so the chosen one is the most significant. It is its own
  /// inverse.
  fileprivate func swapSignificantComponent(_ component: Component, _ lower: Int, _ upper: Int) {
    switch component {
    case .red:
      break
    case .green:
      for i in lower...upper {
        let colour = colours[i]
        colours[i] =
          Self.green(colour) << (Self.wordWidth * 2) | Self.red(colour) << Self.wordWidth
          | Self.blue(colour)
      }
    case .blue:
      for i in lower...upper {
        let colour = colours[i]
        colours[i] =
          Self.blue(colour) << (Self.wordWidth * 2) | Self.green(colour) << Self.wordWidth
          | Self.red(colour)
      }
    }
  }

  // MARK: Colour packing

  fileprivate static func red(_ colour: Int) -> Int { (colour >> (wordWidth * 2)) & wordMask }
  fileprivate static func green(_ colour: Int) -> Int { (colour >> wordWidth) & wordMask }
  fileprivate static func blue(_ colour: Int) -> Int { colour & wordMask }

  private static func modifyWordWidth(_ value: Int, from current: Int, to target: Int) -> Int {
    let shifted = target > current ? value << (target - current) : value >> (current - target)
    return shifted & ((1 << target) - 1)
  }

  private static func quantizeFromRGB888(_ colour: UInt32) -> Int {
    let r = modifyWordWidth(MaterialColour.red(colour), from: 8, to: 5)
    let g = modifyWordWidth(MaterialColour.green(colour), from: 8, to: 5)
    let b = modifyWordWidth(MaterialColour.blue(colour), from: 8, to: 5)
    return r << (wordWidth * 2) | g << wordWidth | b
  }

  fileprivate static func approximateToRGB888(red: Int, green: Int, blue: Int) -> UInt32 {
    MaterialColour.argb(
      red: modifyWordWidth(red, from: 5, to: 8), green: modifyWordWidth(green, from: 5, to: 8),
      blue: modifyWordWidth(blue, from: 5, to: 8))
  }

  private static func approximateToRGB888(_ colour: Int) -> UInt32 {
    approximateToRGB888(red: red(colour), green: green(colour), blue: blue(colour))
  }

  // MARK: Filter

  /// The default palette filter: drops near black, near white and the red side of the I line.
  private static func shouldIgnore(_ rgb: UInt32) -> Bool {
    let (h, s, l) = hsl(rgb)
    if l >= 0.95 || l <= 0.05 { return true }
    return h >= 10 && h <= 37 && s <= 0.82
  }

  /// `ColorUtils.colorToHSL`, in float like the original.
  static func hsl(_ rgb: UInt32) -> (h: Float, s: Float, l: Float) {
    let rf = Float(MaterialColour.red(rgb)) / 255
    let gf = Float(MaterialColour.green(rgb)) / 255
    let bf = Float(MaterialColour.blue(rgb)) / 255
    let maxValue = max(rf, max(gf, bf))
    let minValue = min(rf, min(gf, bf))
    let delta = maxValue - minValue
    var h: Float
    var s: Float
    let l = (maxValue + minValue) / 2
    if maxValue == minValue {
      h = 0
      s = 0
    } else {
      if maxValue == rf {
        h = ((gf - bf) / delta).truncatingRemainder(dividingBy: 6)
      } else if maxValue == gf {
        h = ((bf - rf) / delta) + 2
      } else {
        h = ((rf - gf) / delta) + 4
      }
      s = delta / (1 - abs(2 * l - 1))
    }
    h = (h * 60).truncatingRemainder(dividingBy: 360)
    if h < 0 { h += 360 }
    return (min(max(h, 0), 360), min(max(s, 0), 1), min(max(l, 0), 1))
  }
}

/// `java.util.PriorityQueue` of boxes, largest volume first, with the same sift rules so boxes
/// of equal volume come out in the same order.
private struct JavaVboxQueue {
  private(set) var elements: [AndroidPaletteQuantizer.Vbox] = []

  var count: Int { elements.count }

  private func compare(_ lhs: AndroidPaletteQuantizer.Vbox, _ rhs: AndroidPaletteQuantizer.Vbox)
    -> Int
  {
    rhs.volume - lhs.volume
  }

  mutating func offer(_ box: AndroidPaletteQuantizer.Vbox) {
    var k = elements.count
    elements.append(box)
    while k > 0 {
      let parent = (k - 1) >> 1
      let other = elements[parent]
      if compare(box, other) >= 0 { break }
      elements[k] = other
      k = parent
    }
    elements[k] = box
  }

  mutating func poll() -> AndroidPaletteQuantizer.Vbox? {
    guard !elements.isEmpty else { return nil }
    let result = elements[0]
    let last = elements.removeLast()
    let size = elements.count
    if size > 0 {
      var k = 0
      let half = size >> 1
      while k < half {
        var child = 2 * k + 1
        var candidate = elements[child]
        let right = child + 1
        if right < size && compare(candidate, elements[right]) > 0 {
          child = right
          candidate = elements[child]
        }
        if compare(last, candidate) <= 0 { break }
        elements[k] = candidate
        k = child
      }
      elements[k] = last
    }
    return result
  }
}
