import Foundation

/// Finds dominant colours with k-means over a sample of pixels. Deterministic for a given seed.
public enum PaletteExtractor {

  public static func dominantColors(
    _ raster: RasterImage,
    count: Int,
    iterations: Int = 12,
    seed: UInt64 = 1
  ) -> [RGBA] {
    guard count > 0, raster.width > 0, raster.height > 0 else { return [] }

    // Sample at most 4000 pixels so large images stay fast. The sample is random rather than strided:
    // a stride that divides the row length would read the same column of every row.
    let total = raster.width * raster.height
    var generator = SeededGenerator(seed: seed)
    let indices: [Int] =
      total <= 4000
      ? Array(0..<total) : (0..<4000).map { _ in Int.random(in: 0..<total, using: &generator) }
    var samples: [[Double]] = []
    for index in indices {
      let base = index * 4
      guard raster.pixels[base + 3] > 0 else { continue }
      samples.append([
        Double(raster.pixels[base]), Double(raster.pixels[base + 1]),
        Double(raster.pixels[base + 2]),
      ])
    }
    guard !samples.isEmpty else { return [] }

    // k-means++ seeding: each new centre is drawn with probability proportional to its squared distance
    // from the nearest centre chosen so far, so small clusters are not lost to an unlucky start.
    var centroids: [[Double]] = [samples[Int.random(in: 0..<samples.count, using: &generator)]]
    while centroids.count < min(count, samples.count) {
      let distances = samples.map { sample in
        centroids.map { squaredDistance(sample, $0) }.min() ?? 0
      }
      let sum = distances.reduce(0, +)
      guard sum > 0 else { break }
      var target = Double.random(in: 0..<sum, using: &generator)
      var chosen = samples.count - 1
      for (index, distance) in distances.enumerated() {
        target -= distance
        if target < 0 {
          chosen = index
          break
        }
      }
      centroids.append(samples[chosen])
    }
    var assignment = [Int](repeating: 0, count: samples.count)

    for _ in 0..<iterations {
      for (sampleIndex, sample) in samples.enumerated() {
        assignment[sampleIndex] = nearestCentroid(sample, centroids)
      }
      for centroidIndex in centroids.indices {
        var sum = [0.0, 0.0, 0.0]
        var members = 0
        for (sampleIndex, sample) in samples.enumerated()
        where assignment[sampleIndex] == centroidIndex {
          sum[0] += sample[0]
          sum[1] += sample[1]
          sum[2] += sample[2]
          members += 1
        }
        if members > 0 {
          centroids[centroidIndex] = sum.map { $0 / Double(members) }
        }
      }
    }

    var population = [Int](repeating: 0, count: centroids.count)
    for index in assignment { population[index] += 1 }
    return centroids.indices
      .sorted { population[$0] > population[$1] }
      .map { index in
        let c = centroids[index]
        return RGBA(
          red: UInt8(c[0].rounded()), green: UInt8(c[1].rounded()), blue: UInt8(c[2].rounded()))
      }
  }

  private static func nearestCentroid(_ sample: [Double], _ centroids: [[Double]]) -> Int {
    var best = 0
    var bestDistance = Double.infinity
    for (index, centroid) in centroids.enumerated() {
      let distance = squaredDistance(sample, centroid)
      if distance < bestDistance {
        bestDistance = distance
        best = index
      }
    }
    return best
  }

  private static func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
    let d0 = a[0] - b[0]
    let d1 = a[1] - b[1]
    let d2 = a[2] - b[2]
    return d0 * d0 + d1 * d1 + d2 * d2
  }
}
