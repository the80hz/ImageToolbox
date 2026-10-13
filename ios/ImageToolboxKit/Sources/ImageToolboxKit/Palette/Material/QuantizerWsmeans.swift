// Port of Material Color Utilities (quantize/quantizer_wsmeans, quantizer_celebi,
// quantize/lab_point_provider).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// `java.util.Random`, so the clustering starts from the same state as the reference.
struct JavaRandom {
  private var seed: UInt64
  private static let mask: UInt64 = (1 << 48) - 1

  init(seed: Int64) {
    self.seed = (UInt64(bitPattern: seed) ^ 0x5DEE_CE66D) & Self.mask
  }

  private mutating func next(_ bits: Int) -> Int32 {
    seed = (seed &* 0x5DEE_CE66D &+ 0xB) & Self.mask
    return Int32(truncatingIfNeeded: Int64(seed >> UInt64(48 - bits)))
  }

  /// Uniform value in 0..<bound.
  mutating func nextInt(bound: Int) -> Int {
    precondition(bound > 0, "bound must be positive")
    var r = next(31)
    let m = Int32(bound - 1)
    if bound & (bound - 1) == 0 {
      return Int((Int64(bound) * Int64(r)) >> 31)
    }
    var u = r
    r = u % Int32(bound)
    while u &- r &+ m < 0 {
      u = next(31)
      r = u % Int32(bound)
    }
    return Int(r)
  }
}

/// K-means in CIE L*a*b* space, weighted by how often each colour occurs.
enum QuantizerWsmeans {
  private static let maxIterations = 10
  private static let minMovementDistance = 3.0

  private struct Distance {
    var distance = -1.0
    var index = -1
  }

  private static func squaredDistance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    let d = a - b
    return d.x * d.x + d.y * d.y + d.z * d.z
  }

  /// Clusters the pixels. The result lists each cluster colour with its pixel count.
  static func quantize(
    _ inputPixels: [UInt32], startingClusters: [UInt32], maxColors: Int
  ) -> [(argb: UInt32, count: Int)] {
    var random = JavaRandom(seed: 0x42688)
    var pixelToCount: [UInt32: Int] = [:]
    var points: [SIMD3<Double>] = []
    var pixels: [UInt32] = []
    for pixel in inputPixels {
      if let count = pixelToCount[pixel] {
        pixelToCount[pixel] = count + 1
      } else {
        points.append(MaterialColour.lab(fromARGB: pixel))
        pixels.append(pixel)
        pixelToCount[pixel] = 1
      }
    }
    let pointCount = points.count
    guard pointCount > 0, maxColors > 0 else { return [] }
    let counts = pixels.map { pixelToCount[$0] ?? 0 }

    var clusterCount = min(maxColors, pointCount)
    if !startingClusters.isEmpty { clusterCount = min(clusterCount, startingClusters.count) }

    var clusters: [SIMD3<Double>] = []
    for argb in startingClusters.prefix(clusterCount) {
      clusters.append(MaterialColour.lab(fromARGB: argb))
    }
    // Without starting clusters, begin from the first distinct colours.
    var seedIndex = 0
    while clusters.count < clusterCount {
      clusters.append(points[seedIndex])
      seedIndex += 1
    }

    var clusterIndices = (0..<pointCount).map { _ in random.nextInt(bound: clusterCount) }
    var matrix = [[Distance]](
      repeating: [Distance](repeating: Distance(), count: clusterCount), count: clusterCount)
    var pixelCountSums = [Int](repeating: 0, count: clusterCount)

    for iteration in 0..<maxIterations {
      for i in 0..<clusterCount {
        for j in (i + 1)..<max(i + 1, clusterCount) {
          let distance = squaredDistance(clusters[i], clusters[j])
          matrix[j][i] = Distance(distance: distance, index: i)
          matrix[i][j] = Distance(distance: distance, index: j)
        }
        // The reference sorts each row in place and then keeps writing by position.
        matrix[i] = matrix[i].enumerated().sorted {
          $0.element.distance != $1.element.distance
            ? $0.element.distance < $1.element.distance : $0.offset < $1.offset
        }.map(\.element)
      }

      var pointsMoved = 0
      for i in 0..<pointCount {
        let point = points[i]
        let previousIndex = clusterIndices[i]
        let previousDistance = squaredDistance(point, clusters[previousIndex])
        var minimum = previousDistance
        var newIndex = -1
        for j in 0..<clusterCount {
          if matrix[previousIndex][j].distance >= 4 * previousDistance { continue }
          let distance = squaredDistance(point, clusters[j])
          if distance < minimum {
            minimum = distance
            newIndex = j
          }
        }
        if newIndex != -1 {
          let change = abs(sqrt(minimum) - sqrt(previousDistance))
          if change > minMovementDistance {
            pointsMoved += 1
            clusterIndices[i] = newIndex
          }
        }
      }
      if pointsMoved == 0 && iteration != 0 { break }

      var sums = [SIMD3<Double>](repeating: .zero, count: clusterCount)
      pixelCountSums = [Int](repeating: 0, count: clusterCount)
      for i in 0..<pointCount {
        let cluster = clusterIndices[i]
        pixelCountSums[cluster] += counts[i]
        sums[cluster] += points[i] * Double(counts[i])
      }
      for i in 0..<clusterCount {
        let count = pixelCountSums[i]
        clusters[i] = count == 0 ? .zero : sums[i] / Double(count)
      }
    }

    var result: [(argb: UInt32, count: Int)] = []
    var seen = Set<UInt32>()
    for i in 0..<clusterCount where pixelCountSums[i] > 0 {
      let argb = MaterialColour.argb(fromLab: clusters[i])
      if seen.insert(argb).inserted { result.append((argb, pixelCountSums[i])) }
    }
    return result
  }
}

/// Wu quantizer for a good start, then WSMeans to refine it.
enum QuantizerCelebi {
  /// At most `maxColors` colours with the number of pixels each one stands for.
  static func quantize(_ pixels: [UInt32], maxColors: Int) -> [(argb: UInt32, count: Int)] {
    let wu = QuantizerWu.quantize(pixels, maxColors: maxColors)
    return QuantizerWsmeans.quantize(pixels, startingClusters: wu, maxColors: maxColors)
  }
}
