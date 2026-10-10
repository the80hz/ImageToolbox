import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Fractal supersampling: the averaged samples, the work plan and the defaults")
struct FractalSupersampleTests {

  @Test("one sample keeps its colour, and the average of four rounds half up")
  func averaging() {
    var single = SubsampleAverage()
    single.add((7, 200, 255))
    #expect(single.colour == (7, 200, 255))

    // Four samples with red 255, 255, 0 and 0: the mean 127.5 rounds up to 128.
    let four: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (255, 0, 0), (0, 0, 0), (0, 0, 0)]
    var fourAverage = SubsampleAverage()
    for colour in four {
      fourAverage.add(colour)
    }
    #expect(fourAverage.colour == (128, 0, 0))

    // Three samples with red 255, 0 and 0: the mean is exactly 85.
    let three: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 0, 0), (0, 0, 0)]
    var threeAverage = SubsampleAverage()
    for colour in three {
      threeAverage.add(colour)
    }
    #expect(threeAverage.colour == (85, 0, 0))
  }

  @Test("the supersampling is kept in 1 to 4, and the floor is off by default")
  func settingsDefaults() {
    #expect(EscapeTimeFractal.Settings().supersampling == 1)
    #expect(!EscapeTimeFractal.Settings().showFloor)
    #expect(EscapeTimeFractal.Settings(supersampling: 0).normalized().supersampling == 1)
    #expect(EscapeTimeFractal.Settings(supersampling: 9).normalized().supersampling == 4)
    #expect(EscapeTimeFractal.Settings(supersampling: 3).normalized().supersampling == 3)
  }

  @Test("the density budgets count the sampled pixels: two samples a side double the multiplier")
  func densityBudgetFollowsSampledPixels() {
    // 262 144 pixels are under one reference picture of 307 200, so the multiplier is 1 at one sample.
    #expect(
      FractalDensity.budgetedSteps(
        base: 128_000, pixels: 512 * 512, costPerStep: 25, supersampling: 1) == 128_000)
    // Two samples a side make 1 048 576 sampled pixels, 4 reference pictures, so the multiplier is 2.
    #expect(
      FractalDensity.budgetedSteps(
        base: 128_000, pixels: 512 * 512, costPerStep: 25, supersampling: 2) == 256_000)
    // The Buddhabrot takes half the sampled pixels: 524 288, under the budget of 624 463 orbits.
    #expect(
      FractalDensity.buddhabrotSamples(pixels: 512 * 512, maxIterations: 800, supersampling: 2)
        == 524_288)
  }

  @Test("the ray-march plan counts the sampled pixels: Mandelbulb at 512^2 with two samples a side")
  func rayMarchPlanCountsSamples() {
    // The allowance is 5*10^8 / 1 048 576 = 476. At the minimum of 8 estimator iterations, the 198
    // steps the request asks for cost 1 584, over 476, so the steps come down to 476 / 8 - 6 = 53.
    #expect(
      Fractal3D.rayMarchPlan(.mandelbulb, requested: 320, pixels: 512 * 512 * 4)
        == Fractal3D.RayMarchPlan(maximumSteps: 53, distanceIterations: 8))
  }

  @Test("the supersampling is lowered as the Android plan lowers it, and density kinds keep it")
  func effectiveSupersampling() {
    // At 512^2 the allowance for four samples a side is 119, below the 240 of the smallest march,
    // and for three it is 211, also below. At two it is 476, which gives 53 steps, below the 64 that
    // are preferred. So the picture is drawn with one sample.
    let mandelbulb = EscapeTimeFractal.Settings(
      kind: .mandelbulb, maxIterations: 320, supersampling: 4)
    #expect(EscapeTimeFractal.effectiveSupersampling(mandelbulb, width: 512, height: 512) == 1)
    let small = EscapeTimeFractal.Settings(
      kind: .mandelbulb, maxIterations: 320, supersampling: 2)
    #expect(EscapeTimeFractal.effectiveSupersampling(small, width: 64, height: 64) == 2)
    // The escape-time budget at 512^2 with four samples a side is 4 194 304 * 64 = 2.7 * 10^8, far
    // under the 10^10 limit, so the request stands.
    let mandelbrot = EscapeTimeFractal.Settings(
      kind: .mandelbrot, maxIterations: 320, supersampling: 4)
    #expect(EscapeTimeFractal.effectiveSupersampling(mandelbrot, width: 512, height: 512) == 4)
    let fern = EscapeTimeFractal.Settings(kind: .barnsleyFern, supersampling: 4)
    #expect(EscapeTimeFractal.effectiveSupersampling(fern, width: 512, height: 512) == 4)
  }

  @Test("a supersampled pixel is the rounded average of the colours at its sample centres")
  func supersampledPixelAverages() throws {
    let settings = EscapeTimeFractal.Settings(
      kind: .mandelbrot, centreReal: -0.75, centreImaginary: 0.1, span: 0.2, maxIterations: 64,
      supersampling: 2)
    let image = try #require(EscapeTimeFractal.render(settings, width: 8, height: 8))
    // The sample centres of pixel (3, 4) are at offsets of a quarter and three quarters of a pixel.
    let scale = 0.2 / 8
    var average = SubsampleAverage()
    for sampleY in 0..<2 {
      for sampleX in 0..<2 {
        let column = 3 + (Double(sampleX) + 0.5) / 2
        let row = 4 + (Double(sampleY) + 0.5) / 2
        let real = -0.75 + (column - 4) * scale
        let imaginary = 0.1 - (row - 4) * scale
        average.add(
          EscapeTimeFractal.colour(
            for: EscapeTimeFractal.escapeValue(
              real: real, imaginary: imaginary, settings.normalized())))
      }
    }
    let pixel = image.pixel(x: 3, y: 4)
    #expect((pixel.red, pixel.green, pixel.blue) == average.colour)
  }

  @Test("a supersampled ray-marched picture has the requested size and is not blank")
  func rayMarchedSupersampled() throws {
    let settings = EscapeTimeFractal.Settings(
      kind: .mandelbulb, maxIterations: 96, supersampling: 2)
    let image = try #require(EscapeTimeFractal.render(settings, width: 32, height: 32))
    #expect(image.width == 32 && image.height == 32)
    let lit = stride(from: 0, to: image.pixels.count, by: 4).filter {
      image.pixels[$0] | image.pixels[$0 + 1] | image.pixels[$0 + 2] != 0
    }.count
    #expect(lit > 32 * 32 / 50, "\(lit) lit pixels")
  }
}
