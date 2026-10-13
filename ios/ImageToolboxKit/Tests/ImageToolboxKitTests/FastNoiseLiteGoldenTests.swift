import Foundation
import Testing

@testable import ImageToolboxKit

@Test("FastNoiseLite matches the upstream C++ header bit for bit")
func fastNoiseLiteMatchesUpstreamBits() {
  var mismatches: [String] = []
  for golden in goldenCases {
    var noise = FastNoiseLite(seed: 1337)
    noise.noiseType = golden.noise
    noise.fractalType = golden.fractal
    noise.octaves = golden.octaves
    noise.gain = golden.gain
    noise.lacunarity = golden.lacunarity
    noise.weightedStrength = golden.weighted
    noise.pingPongStrength = golden.pingPong
    noise.frequency = golden.frequency
    noise.cellularDistanceFunction = golden.distance
    noise.cellularReturnType = golden.returnType
    noise.cellularJitter = golden.jitter
    noise.domainWarpType = golden.warp
    noise.domainWarpAmp = golden.warpAmp
    let values = golden.expected.split(separator: " ").compactMap { UInt32($0, radix: 16) }
    #expect(values.count == (golden.isWarp ? 2 : 1) * golden.points, "\(golden.name)")
    var index = 0
    for point in goldenPoints.prefix(golden.points) {
      if golden.isWarp {
        var x = point.0
        var y = point.1
        noise.domainWarp(x: &x, y: &y)
        if x.bitPattern != values[index] || y.bitPattern != values[index + 1] {
          mismatches.append(golden.name)
        }
        index += 2
      } else {
        let value = noise.noise(x: point.0, y: point.1)
        if value.bitPattern != values[index] { mismatches.append(golden.name) }
        index += 1
      }
    }
  }
  #expect(mismatches.isEmpty, "Mismatched cases: \(mismatches)")
}
