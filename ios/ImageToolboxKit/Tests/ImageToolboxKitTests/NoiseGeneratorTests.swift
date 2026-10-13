import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Noise generators")
struct NoiseGeneratorTests {

  /// A grid of sample points spread over a few lattice cells, with an irrational step.
  private var samples: [(x: Double, y: Double)] {
    (0..<400).map { index in
      (x: Double(index % 20) * 0.37 - 3.1, y: Double(index / 20) * 0.41 - 4.2)
    }
  }

  @Test("value noise stays in -1...1, repeats for a seed and changes with the seed")
  func valueNoise() {
    let noise = ValueNoise2D(seed: 5)
    let values = samples.map { noise.value(x: $0.x, y: $0.y) }
    #expect(values.allSatisfy { $0 >= -1 && $0 <= 1 })
    #expect(values == samples.map { ValueNoise2D(seed: 5).value(x: $0.x, y: $0.y) })
    #expect(values != samples.map { ValueNoise2D(seed: 6).value(x: $0.x, y: $0.y) })
    #expect(Set(values.map { ($0 * 1000).rounded() }).count > 100)
  }

  @Test("value noise is continuous between nearby points")
  func valueNoiseContinuity() {
    let noise = ValueNoise2D(seed: 9)
    for sample in samples {
      let next = noise.value(x: sample.x + 0.001, y: sample.y)
      #expect(abs(next - noise.value(x: sample.x, y: sample.y)) < 0.02)
    }
  }

  @Test("simplex noise stays near -1...1, repeats for a seed and changes with the seed")
  func simplexNoise() {
    let noise = SimplexNoise2D(seed: 3)
    let values = samples.map { noise.value(x: $0.x, y: $0.y) }
    #expect(values.allSatisfy { $0 >= -1.05 && $0 <= 1.05 })
    #expect(values == samples.map { SimplexNoise2D(seed: 3).value(x: $0.x, y: $0.y) })
    #expect(values != samples.map { SimplexNoise2D(seed: 4).value(x: $0.x, y: $0.y) })
    #expect(values.max()! > 0.5 && values.min()! < -0.5)
  }

  @Test("cellular distances are ordered, non-negative and repeat for a seed")
  func cellularNoise() {
    let noise = CellularNoise2D(seed: 2)
    for sample in samples {
      let distances = noise.distances(x: sample.x, y: sample.y)
      #expect(distances.nearest >= 0)
      #expect(distances.nearest <= distances.second)
      #expect(distances.second < 3)
    }
    let again = CellularNoise2D(seed: 2)
    #expect(
      samples.allSatisfy { sample in
        noise.distances(x: sample.x, y: sample.y).nearest
          == again.distances(x: sample.x, y: sample.y).nearest
      })
  }

  @Test("without jitter the feature points sit on the cell centres")
  func cellularNoiseGrid() {
    let noise = CellularNoise2D(seed: 8)
    let centre = noise.distances(x: 3.5, y: 4.5, jitter: 0)
    #expect(centre.nearest < 1e-9)
    #expect(abs(centre.second - 1) < 1e-9)
  }

  @Test("a fractal with one octave is the base noise itself")
  func singleOctave() {
    let noise = FractalNoise(seed: 12, basis: .perlin)
    for sample in samples {
      #expect(
        noise.fractal(x: sample.x, y: sample.y, octaves: 1)
          == noise.sample(x: sample.x, y: sample.y))
    }
  }

  @Test("fractal shapes keep their ranges")
  func fractalRanges() {
    for basis in [NoiseBasis.value, .perlin, .simplex] {
      let noise = FractalNoise(seed: 21, basis: basis)
      for sample in samples {
        let fbm = noise.fractal(x: sample.x, y: sample.y, octaves: 6, gain: 0.6)
        #expect(fbm >= -1.05 && fbm <= 1.05, "\(basis) fbm out of range")
        let ridged = noise.fractal(
          x: sample.x, y: sample.y, octaves: 6, gain: 0.6, shape: .ridged)
        #expect(ridged >= 0 && ridged <= 1, "\(basis) ridged out of range")
        let turbulence = noise.fractal(
          x: sample.x, y: sample.y, octaves: 6, gain: 0.6, shape: .turbulence)
        #expect(turbulence >= 0 && turbulence <= 1, "\(basis) turbulence out of range")
      }
    }
  }

  @Test("domain warp moves points deterministically, and zero amount leaves them alone")
  func domainWarp() {
    let noise = FractalNoise(seed: 30, basis: .simplex)
    for sample in samples {
      let unchanged = noise.warp(x: sample.x, y: sample.y, amount: 0)
      #expect(unchanged.x == sample.x && unchanged.y == sample.y)
      let first = noise.warp(x: sample.x, y: sample.y, amount: 2)
      let second = FractalNoise(seed: 30, basis: .simplex)
        .warp(x: sample.x, y: sample.y, amount: 2)
      #expect(first.x == second.x && first.y == second.y)
    }
    let moved = samples.filter {
      let warped = noise.warp(x: $0.x, y: $0.y, amount: 2)
      return abs(warped.x - $0.x) > 0.01
    }
    #expect(moved.count > samples.count / 2)
  }
}

@Suite("FastNoiseLite")
struct FastNoiseLiteTests {

  /// Sample points over a few lattice cells, with an irrational step.
  private var samples: [(x: Float, y: Float)] {
    (0..<400).map { index in
      (x: Float(index % 20) * 0.37 - 3.1, y: Float(index / 20) * 0.41 - 4.2)
    }
  }

  private static let basicTypes: [FastNoiseLite.NoiseType] = [
    .openSimplex2, .openSimplex2S, .perlin, .valueCubic, .value, .cellular,
  ]

  @Test("every noise type repeats for a seed and changes with the seed")
  func deterministicPerSeed() {
    for type in Self.basicTypes {
      var first = FastNoiseLite(seed: 17)
      first.noiseType = type
      first.frequency = 0.3
      var second = first
      second.seed = 18
      let values = samples.map { first.noise(x: $0.x, y: $0.y) }
      let repeated = samples.map { first.noise(x: $0.x, y: $0.y) }
      let other = samples.map { second.noise(x: $0.x, y: $0.y) }
      #expect(values == repeated, "\(type) is not deterministic")
      #expect(values != other, "\(type) ignores the seed")
    }
  }

  @Test("the fractal modes repeat for a seed")
  func fractalsDeterministic() {
    for fractal in [FastNoiseLite.FractalType.fbm, .ridged, .pingPong] {
      var noise = FastNoiseLite(seed: 4)
      noise.noiseType = .openSimplex2S
      noise.fractalType = fractal
      noise.octaves = 4
      noise.frequency = 0.2
      let values = samples.map { noise.noise(x: $0.x, y: $0.y) }
      #expect(values == samples.map { noise.noise(x: $0.x, y: $0.y) }, "\(fractal)")
      #expect(values.allSatisfy { $0.isFinite && abs($0) < 2 }, "\(fractal) out of range")
    }
  }

  @Test("signed noise types stay near -1...1 and cellular values are non-negative")
  func valueRanges() {
    for type in Self.basicTypes {
      var noise = FastNoiseLite(seed: 9)
      noise.noiseType = type
      noise.frequency = 0.7
      let values = samples.map { noise.noise(x: $0.x, y: $0.y) }
      #expect(values.allSatisfy { $0 >= -1.25 && $0 <= 1.25 }, "\(type) out of range")
      if type != .cellular {
        #expect(values.max()! > 0.2 && values.min()! < -0.2, "\(type) is flat")
      }
    }
    var cells = FastNoiseLite(seed: 9)
    cells.noiseType = .cellular
    cells.cellularReturnType = .cellValue
    cells.frequency = 0.5
    let values = samples.map { cells.noise(x: $0.x, y: $0.y) }
    #expect(values.allSatisfy { $0 >= -1 && $0 <= 1 }, "cell values are out of range")
  }

  @Test("Perlin noise is exactly zero at lattice points")
  func perlinLattice() {
    var noise = FastNoiseLite(seed: 2)
    noise.noiseType = .perlin
    noise.frequency = 1
    for x in -3...3 {
      for y in -3...3 {
        #expect(noise.noise(x: Float(x), y: Float(y)) == 0)
      }
    }
  }

  @Test("the smooth types change little between nearby points")
  func continuity() {
    for type in [
      FastNoiseLite.NoiseType.openSimplex2, .openSimplex2S, .perlin, .value, .valueCubic,
    ] {
      var noise = FastNoiseLite(seed: 31)
      noise.noiseType = type
      noise.frequency = 0.5
      for sample in samples {
        let here = noise.noise(x: sample.x, y: sample.y)
        let next = noise.noise(x: sample.x + 0.001, y: sample.y)
        #expect(abs(next - here) < 0.02, "\(type) jumps at \(sample)")
      }
    }
  }

  @Test("a domain warp of zero amplitude leaves points alone")
  func zeroWarp() {
    var noise = FastNoiseLite(seed: 6)
    noise.domainWarpAmp = 0
    for sample in samples {
      var x = sample.x
      var y = sample.y
      noise.domainWarp(x: &x, y: &y)
      #expect(x == sample.x && y == sample.y)
    }
  }
}
