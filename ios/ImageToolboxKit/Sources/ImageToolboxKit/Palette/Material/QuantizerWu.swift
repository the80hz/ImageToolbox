// Port of Material Color Utilities (quantize/quantizer_wu).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Xiaolin Wu's colour quantizer: cuts a 5-bit RGB histogram into boxes that minimise variance.
///
/// Arithmetic is 64-bit. The Java reference squares 32-bit sums, which overflows on large images.
struct QuantizerWu {
  private static let indexBits = 5
  private static let indexCount = 33
  private static let totalSize = 35937

  private struct Box {
    var r0 = 0
    var r1 = 0
    var g0 = 0
    var g1 = 0
    var b0 = 0
    var b1 = 0
    var vol = 0
  }

  private enum Direction { case red, green, blue }

  private var weights = [Int](repeating: 0, count: totalSize)
  private var momentsR = [Int](repeating: 0, count: totalSize)
  private var momentsG = [Int](repeating: 0, count: totalSize)
  private var momentsB = [Int](repeating: 0, count: totalSize)
  private var moments = [Double](repeating: 0, count: totalSize)
  private var cubes: [Box] = []

  /// Up to `maxColors` colours that stand for the pixels, in box order.
  static func quantize(_ pixels: [UInt32], maxColors: Int) -> [UInt32] {
    guard maxColors > 0, !pixels.isEmpty else { return [] }
    var counts: [UInt32: Int] = [:]
    for pixel in pixels { counts[pixel, default: 0] += 1 }
    var quantizer = QuantizerWu()
    quantizer.constructHistogram(counts)
    quantizer.createMoments()
    let generated = quantizer.createBoxes(maxColors)
    var seen = Set<UInt32>()
    return quantizer.createResult(generated).filter { seen.insert($0).inserted }
  }

  private static func index(_ r: Int, _ g: Int, _ b: Int) -> Int {
    (r << (indexBits * 2)) + (r << (indexBits + 1)) + r + (g << indexBits) + g + b
  }

  private mutating func constructHistogram(_ pixels: [UInt32: Int]) {
    let shift = 8 - Self.indexBits
    for (pixel, count) in pixels {
      let red = MaterialColour.red(pixel)
      let green = MaterialColour.green(pixel)
      let blue = MaterialColour.blue(pixel)
      let i = Self.index((red >> shift) + 1, (green >> shift) + 1, (blue >> shift) + 1)
      weights[i] += count
      momentsR[i] += red * count
      momentsG[i] += green * count
      momentsB[i] += blue * count
      moments[i] += Double(count * (red * red + green * green + blue * blue))
    }
  }

  /// Turns the histogram into cumulative moments, so any box sum is eight look-ups.
  private mutating func createMoments() {
    let count = Self.indexCount
    for r in 1..<count {
      var area = [Int](repeating: 0, count: count)
      var areaR = area
      var areaG = area
      var areaB = area
      var area2 = [Double](repeating: 0, count: count)
      for g in 1..<count {
        var line = 0
        var lineR = 0
        var lineG = 0
        var lineB = 0
        var line2 = 0.0
        for b in 1..<count {
          let i = Self.index(r, g, b)
          line += weights[i]
          lineR += momentsR[i]
          lineG += momentsG[i]
          lineB += momentsB[i]
          line2 += moments[i]
          area[b] += line
          areaR[b] += lineR
          areaG[b] += lineG
          areaB[b] += lineB
          area2[b] += line2
          let previous = Self.index(r - 1, g, b)
          weights[i] = weights[previous] + area[b]
          momentsR[i] = momentsR[previous] + areaR[b]
          momentsG[i] = momentsG[previous] + areaG[b]
          momentsB[i] = momentsB[previous] + areaB[b]
          moments[i] = moments[previous] + area2[b]
        }
      }
    }
  }

  private mutating func createBoxes(_ maxColors: Int) -> Int {
    cubes = [Box](repeating: Box(), count: maxColors)
    var volumeVariance = [Double](repeating: 0, count: maxColors)
    cubes[0].r1 = Self.indexCount - 1
    cubes[0].g1 = Self.indexCount - 1
    cubes[0].b1 = Self.indexCount - 1
    var generated = maxColors
    var next = 0
    var i = 1
    while i < maxColors {
      if cut(next, i) {
        volumeVariance[next] = cubes[next].vol > 1 ? variance(cubes[next]) : 0.0
        volumeVariance[i] = cubes[i].vol > 1 ? variance(cubes[i]) : 0.0
      } else {
        volumeVariance[next] = 0.0
        i -= 1
      }
      next = 0
      var best = volumeVariance[0]
      if i >= 1 {
        for j in 1...i where volumeVariance[j] > best {
          best = volumeVariance[j]
          next = j
        }
      }
      if best <= 0.0 {
        generated = i + 1
        break
      }
      i += 1
    }
    return generated
  }

  private func createResult(_ count: Int) -> [UInt32] {
    var colours: [UInt32] = []
    for i in 0..<count {
      let cube = cubes[i]
      let weight = Self.volume(cube, weights)
      guard weight > 0 else { continue }
      let r = Int((Double(Self.volume(cube, momentsR)) / Double(weight)).rounded())
      let g = Int((Double(Self.volume(cube, momentsG)) / Double(weight)).rounded())
      let b = Int((Double(Self.volume(cube, momentsB)) / Double(weight)).rounded())
      colours.append(MaterialColour.argb(red: r, green: g, blue: b))
    }
    return colours
  }

  private func variance(_ cube: Box) -> Double {
    let dr = Self.volume(cube, momentsR)
    let dg = Self.volume(cube, momentsG)
    let db = Self.volume(cube, momentsB)
    let xx = Self.volume(cube, moments)
    let hypotenuse = dr * dr + dg * dg + db * db
    let volume = Self.volume(cube, weights)
    return xx - Double(hypotenuse) / Double(volume)
  }

  private mutating func cut(_ oneIndex: Int, _ twoIndex: Int) -> Bool {
    let one = cubes[oneIndex]
    let wholeR = Self.volume(one, momentsR)
    let wholeG = Self.volume(one, momentsG)
    let wholeB = Self.volume(one, momentsB)
    let wholeW = Self.volume(one, weights)
    let red = maximize(one, .red, one.r0 + 1, one.r1, wholeR, wholeG, wholeB, wholeW)
    let green = maximize(one, .green, one.g0 + 1, one.g1, wholeR, wholeG, wholeB, wholeW)
    let blue = maximize(one, .blue, one.b0 + 1, one.b1, wholeR, wholeG, wholeB, wholeW)

    let direction: Direction
    if red.max >= green.max && red.max >= blue.max {
      if red.cut < 0 { return false }
      direction = .red
    } else if green.max >= red.max && green.max >= blue.max {
      direction = .green
    } else {
      direction = .blue
    }

    var first = one
    var second = Box()
    second.r1 = first.r1
    second.g1 = first.g1
    second.b1 = first.b1
    switch direction {
    case .red:
      first.r1 = red.cut
      second.r0 = first.r1
      second.g0 = first.g0
      second.b0 = first.b0
    case .green:
      first.g1 = green.cut
      second.r0 = first.r0
      second.g0 = first.g1
      second.b0 = first.b0
    case .blue:
      first.b1 = blue.cut
      second.r0 = first.r0
      second.g0 = first.g0
      second.b0 = first.b1
    }
    first.vol = (first.r1 - first.r0) * (first.g1 - first.g0) * (first.b1 - first.b0)
    second.vol = (second.r1 - second.r0) * (second.g1 - second.g0) * (second.b1 - second.b0)
    cubes[oneIndex] = first
    cubes[twoIndex] = second
    return true
  }

  private func maximize(
    _ cube: Box, _ direction: Direction, _ first: Int, _ last: Int,
    _ wholeR: Int, _ wholeG: Int, _ wholeB: Int, _ wholeW: Int
  ) -> (cut: Int, max: Double) {
    let bottomR = Self.bottom(cube, direction, momentsR)
    let bottomG = Self.bottom(cube, direction, momentsG)
    let bottomB = Self.bottom(cube, direction, momentsB)
    let bottomW = Self.bottom(cube, direction, weights)
    var best = 0.0
    var cut = -1
    guard first < last else { return (cut, best) }
    for i in first..<last {
      var halfR = bottomR + Self.top(cube, direction, i, momentsR)
      var halfG = bottomG + Self.top(cube, direction, i, momentsG)
      var halfB = bottomB + Self.top(cube, direction, i, momentsB)
      var halfW = bottomW + Self.top(cube, direction, i, weights)
      if halfW == 0 { continue }
      var temp = Double(halfR * halfR + halfG * halfG + halfB * halfB) / Double(halfW)
      halfR = wholeR - halfR
      halfG = wholeG - halfG
      halfB = wholeB - halfB
      halfW = wholeW - halfW
      if halfW == 0 { continue }
      temp += Double(halfR * halfR + halfG * halfG + halfB * halfB) / Double(halfW)
      if temp > best {
        best = temp
        cut = i
      }
    }
    return (cut, best)
  }

  private static func volume<T: Numeric>(_ c: Box, _ m: [T]) -> T {
    m[index(c.r1, c.g1, c.b1)] - m[index(c.r1, c.g1, c.b0)] - m[index(c.r1, c.g0, c.b1)]
      + m[index(c.r1, c.g0, c.b0)] - m[index(c.r0, c.g1, c.b1)] + m[index(c.r0, c.g1, c.b0)]
      + m[index(c.r0, c.g0, c.b1)] - m[index(c.r0, c.g0, c.b0)]
  }

  private static func bottom(_ c: Box, _ direction: Direction, _ m: [Int]) -> Int {
    switch direction {
    case .red:
      return -m[index(c.r0, c.g1, c.b1)] + m[index(c.r0, c.g1, c.b0)]
        + m[index(c.r0, c.g0, c.b1)] - m[index(c.r0, c.g0, c.b0)]
    case .green:
      return -m[index(c.r1, c.g0, c.b1)] + m[index(c.r1, c.g0, c.b0)]
        + m[index(c.r0, c.g0, c.b1)] - m[index(c.r0, c.g0, c.b0)]
    case .blue:
      return -m[index(c.r1, c.g1, c.b0)] + m[index(c.r1, c.g0, c.b0)]
        + m[index(c.r0, c.g1, c.b0)] - m[index(c.r0, c.g0, c.b0)]
    }
  }

  private static func top(_ c: Box, _ direction: Direction, _ p: Int, _ m: [Int]) -> Int {
    switch direction {
    case .red:
      return m[index(p, c.g1, c.b1)] - m[index(p, c.g1, c.b0)] - m[index(p, c.g0, c.b1)]
        + m[index(p, c.g0, c.b0)]
    case .green:
      return m[index(c.r1, p, c.b1)] - m[index(c.r1, p, c.b0)] - m[index(c.r0, p, c.b1)]
        + m[index(c.r0, p, c.b0)]
    case .blue:
      return m[index(c.r1, c.g1, p)] - m[index(c.r1, c.g0, p)] - m[index(c.r0, c.g1, p)]
        + m[index(c.r0, c.g0, p)]
    }
  }
}
