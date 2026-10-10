import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("Brightness, contrast and negative")
struct LightColourFilterTests {

  @Test("a positive brightness bias raises every channel, a negative one lowers it")
  func brightnessDirection() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 100, green: 100, blue: 100)
    let brighter = try await BrightnessFilter(bias: 0.2).apply(to: picture)
    let darker = try await BrightnessFilter(bias: -0.2).apply(to: picture)
    #expect(brighter.pixels[0] > 100)
    #expect(darker.pixels[0] < 100)
  }

  @Test("zero brightness changes nothing")
  func brightnessZeroIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await BrightnessFilter(bias: 0).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("a contrast gain of 1 changes nothing")
  func contrastOneIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await ContrastFilter(gain: 1).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("a contrast gain above 1 pushes values away from middle grey")
  func contrastSpreads() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 64, green: 64, blue: 64)
    let output = try await ContrastFilter(gain: 2).apply(to: picture)
    #expect(output.pixels[0] < 64)
  }

  @Test("negative inverts each channel and keeps alpha")
  func negativeInverts() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 10, green: 200, blue: 0)
    let output = try await NegativeFilter().apply(to: picture)
    #expect(Array(output.pixels[0..<4]) == [245, 55, 255, 255])
  }
}

/// Тесты группы «Свет и цвет», добавленной вместе с Gamma, Exposure и далее.
@Suite("Light and colour group: gamma through vignette")
struct LightColourGroupTests {

  /// Наибольшее расхождение по каналам RGB (альфа не сравнивается).
  private func maxColourDifference(_ a: RasterImage, _ b: RasterImage) -> Int {
    var worst = 0
    for index in stride(from: 0, to: a.pixels.count, by: 4) {
      for channel in 0..<3 {
        worst = max(worst, abs(Int(a.pixels[index + channel]) - Int(b.pixels[index + channel])))
      }
    }
    return worst
  }

  /// Проверяет, что фильтр сохраняет размер на 1x1 и 5x3 при каждом крайнем значении.
  private func survivesExtremes(_ filter: (Double) -> any Filter, _ bounds: [Double]) async throws {
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      for value in bounds {
        let output = try await filter(value).apply(to: picture)
        #expect(output.width == picture.width)
        #expect(output.height == picture.height)
        #expect(output.pixels.count == picture.pixels.count)
      }
    }
  }

  @Test("gamma 1 changes nothing, gamma below 1 brightens midtones")
  func gammaNeutralAndDirection() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 64, green: 64, blue: 64)
    let neutral = try await GammaFilter(power: 1).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 1)
    // 64/255 ^ 0.5 = 0.502 -> 128 после округления, значит значение выросло.
    let brighter = try await GammaFilter(power: 0.5).apply(to: picture)
    #expect(brighter.pixels[0] > 64)
  }

  @Test("gamma keeps 0 and 2 inside the picture and the size")
  func gammaExtremes() async throws {
    try await survivesExtremes({ GammaFilter(power: $0) }, [0, 2])
  }

  @Test("exposure 0 stops changes nothing, +1 stop doubles 50 to 100")
  func exposureStops() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 50, green: 50, blue: 50)
    let neutral = try await ExposureFilter(stops: 0).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 1)
    let doubled = try await ExposureFilter(stops: 1).apply(to: picture)
    #expect(abs(Int(doubled.pixels[0]) - 100) <= 1)
  }

  @Test("exposure keeps -4 and 4 inside the picture and the size")
  func exposureExtremes() async throws {
    try await survivesExtremes({ ExposureFilter(stops: $0) }, [-4, 4])
  }

  @Test("hue 0 changes nothing, a 90 degree turn changes a coloured picture")
  func hueNeutralAndTurn() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let neutral = try await HueFilter(degrees: 0).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 1)
    let turned = try await HueFilter(degrees: 90).apply(to: picture)
    #expect(turned.pixels != picture.pixels)
  }

  @Test("hue keeps 0 and 255 inside the picture and the size")
  func hueExtremes() async throws {
    try await survivesExtremes({ HueFilter(degrees: $0) }, [0, 255])
  }

  @Test("saturation 1 changes nothing, 0 makes a coloured picture grey")
  func saturationNeutralAndGrey() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 200, green: 40, blue: 40)
    let neutral = try await SaturationFilter(strength: 1, tonemapping: false).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 1)
    let grey = try await SaturationFilter(strength: 0, tonemapping: false).apply(to: picture)
    #expect(grey.pixels[0] == grey.pixels[1])
    #expect(grey.pixels[1] == grey.pixels[2])
  }

  @Test("saturation keeps 0 and 2 inside the picture and the size, with and without tonemapping")
  func saturationExtremes() async throws {
    for tonemapping in [false, true] {
      try await survivesExtremes(
        { SaturationFilter(strength: $0, tonemapping: tonemapping) }, [0, 2])
    }
  }

  @Test("vibrance changes a coloured picture and keeps the range -5 and 5 valid")
  func vibranceChangesAndExtremes() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await VibranceFilter(amount: 5).apply(to: picture)
    #expect(output.pixels != picture.pixels)
    try await survivesExtremes({ VibranceFilter(amount: $0) }, [-5, 5])
  }

  @Test("white balance at 6500 K and tint 0 changes nothing")
  func whiteBalanceNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let neutral = try await WhiteBalanceFilter(temperature: 6500, tint: 0).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 2)
  }

  @Test("white balance keeps 1000 K and 10000 K valid on 1x1 and 5x3")
  func whiteBalanceExtremes() async throws {
    for temperature in [1000.0, 10000.0] {
      for tint in [-100.0, 100.0] {
        for picture in [
          FilterTestImages.gradient(width: 1, height: 1),
          FilterTestImages.gradient(width: 5, height: 3),
        ] {
          let output = try await WhiteBalanceFilter(temperature: temperature, tint: tint)
            .apply(to: picture)
          #expect(output.width == picture.width)
          #expect(output.height == picture.height)
        }
      }
    }
  }

  @Test("levels 0 to 1 on both sides changes nothing")
  func levelsNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await LevelsFilter(lowInput: 0, highInput: 1, lowOutput: 0, highOutput: 1)
      .apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("raising the low input clips darker values and stretches the rest")
  func levelsLowInputDarkens() async throws {
    let dark = FilterTestImages.solid(width: 1, height: 1, red: 100, green: 100, blue: 100)
    let output = try await LevelsFilter(lowInput: 0.5, highInput: 1, lowOutput: 0, highOutput: 1)
      .apply(to: dark)
    #expect(output.pixels[0] == 0)
    // (200/255 - 0.5) / 0.5 = 0.5686, а 0.5686 * 255 = 145.
    let mid = FilterTestImages.solid(width: 1, height: 1, red: 200, green: 200, blue: 200)
    let stretched = try await LevelsFilter(lowInput: 0.5, highInput: 1, lowOutput: 0, highOutput: 1)
      .apply(to: mid)
    #expect(abs(Int(stretched.pixels[0]) - 145) <= 1)
  }

  @Test("levels keep equal input bounds and the extreme output values valid")
  func levelsExtremes() async throws {
    let picture = FilterTestImages.gradient(width: 5, height: 3)
    let equal = try await LevelsFilter(lowInput: 0.5, highInput: 0.5, lowOutput: 0, highOutput: 1)
      .apply(to: picture)
    #expect(equal.width == 5)
    let full = try await LevelsFilter(lowInput: 1, highInput: 0, lowOutput: 1, highOutput: 0)
      .apply(to: FilterTestImages.gradient(width: 1, height: 1))
    #expect(full.width == 1)
  }

  @Test("highlights and shadows 0 changes nothing, a positive value lifts the shadows")
  func highlightsNeutralAndLift() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 30, green: 30, blue: 30)
    let neutral = try await HighlightsAndShadowsFilter(shadows: 0).apply(to: picture)
    #expect(maxColourDifference(neutral, picture) <= 2)
    let lifted = try await HighlightsAndShadowsFilter(shadows: 1).apply(to: picture)
    #expect(lifted.pixels[0] > 30)
  }

  @Test("highlights and shadows keep 0 and 2 valid on 1x1 and 5x3")
  func highlightsExtremes() async throws {
    try await survivesExtremes({ HighlightsAndShadowsFilter(shadows: $0) }, [0, 2])
  }

  @Test("black and white makes every pixel grey and keeps alpha")
  func blackAndWhiteIsGrey() async throws {
    let picture = FilterTestImages.solid(width: 3, height: 1, red: 200, green: 40, blue: 40)
    let output = try await BlackAndWhiteFilter().apply(to: picture)
    for index in stride(from: 0, to: output.pixels.count, by: 4) {
      #expect(output.pixels[index] == output.pixels[index + 1])
      #expect(output.pixels[index + 1] == output.pixels[index + 2])
      #expect(output.pixels[index + 3] == 255)
    }
    #expect(output.pixels != picture.pixels)
  }

  @Test("sepia changes a coloured picture and keeps the size on 1x1")
  func sepiaChanges() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 100, green: 100, blue: 100)
    let output = try await SepiaFilter().apply(to: picture)
    #expect(output.pixels != picture.pixels)
    #expect(output.pixels[0] > output.pixels[2])
    let tiny = try await SepiaFilter().apply(to: FilterTestImages.gradient(width: 1, height: 1))
    #expect(tiny.width == 1)
  }

  @Test("posterize with one level gives black, many levels keep the picture close")
  func posterizeLevels() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 128, green: 128, blue: 128)
    let flat = try await PosterizeFilter(levels: 1).apply(to: picture)
    #expect(flat.pixels[0] == 0)
    let fine = try await PosterizeFilter(levels: 40).apply(to: picture)
    #expect(abs(Int(fine.pixels[0]) - 128) <= 4)
  }

  @Test("posterize keeps 1 and 40 levels valid on 1x1 and 5x3")
  func posterizeExtremes() async throws {
    try await survivesExtremes({ PosterizeFilter(levels: $0) }, [1, 40])
  }

  @Test("solarize at 1 changes nothing, at 0 inverts every channel above it")
  func solarizeNeutralAndInvert() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 200, green: 10, blue: 128)
    let neutral = try await SolarizeFilter(threshold: 1).apply(to: picture)
    #expect(neutral.pixels == picture.pixels)
    let inverted = try await SolarizeFilter(threshold: 0).apply(to: picture)
    #expect(inverted.pixels[0] == 55)
    #expect(inverted.pixels[1] == 245)
  }

  @Test("solarize keeps 0 and 1 valid on 1x1 and 5x3")
  func solarizeExtremes() async throws {
    try await survivesExtremes({ SolarizeFilter(threshold: $0) }, [0, 1])
  }

  @Test("vignette with a start beyond the picture changes nothing")
  func vignetteNeutral() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await VignetteFilter(start: 1, end: 2, color: .black).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("vignette darkens the corners and leaves the centre brighter")
  func vignetteDarkensCorners() async throws {
    let picture = FilterTestImages.solid(width: 9, height: 9, red: 200, green: 200, blue: 200)
    let output = try await VignetteFilter(start: 0.1, end: 0.5, color: .black).apply(to: picture)
    let centre = (4 * 9 + 4) * 4
    #expect(output.pixels[0] < output.pixels[centre])
    #expect(output.pixels[centre] == 200)
  }

  @Test("vignette keeps the extremes valid on 1x1 and 5x3")
  func vignetteExtremes() async throws {
    let colours = [FilterColor.black, FilterColor.white]
    for colour in colours {
      try await survivesExtremes(
        { VignetteFilter(start: $0, end: 2 - $0, color: colour) }, [-2, 2])
    }
  }
}

@Suite("Hue rotation on the CPU")
struct HueRotationTests {

  @Test("a full turn returns the original colours")
  func fullTurnIsIdentity() async throws {
    let picture = FilterTestImages.gradient(width: 6, height: 4)
    let output = try await HueFilter(degrees: 360).apply(to: picture)
    let largest = zip(output.pixels, picture.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(largest <= 1)
  }

  @Test("pure red turns green after 120 degrees")
  func redToGreen() async throws {
    let picture = FilterTestImages.solid(width: 1, height: 1, red: 255, green: 0, blue: 0)
    let output = try await HueFilter(degrees: 120).apply(to: picture)
    #expect(output.pixels[0] <= 1)
    #expect(output.pixels[1] == 255)
    #expect(output.pixels[2] <= 1)
  }

  @Test("grey stays grey")
  func greyIsUnchanged() async throws {
    let picture = FilterTestImages.solid(width: 2, height: 2, red: 90, green: 90, blue: 90)
    let output = try await HueFilter(degrees: 90).apply(to: picture)
    #expect(output.pixels == picture.pixels)
  }

  @Test("extreme angles keep the size on 1x1 and 5x3 pictures")
  func extremes() async throws {
    for picture in [
      FilterTestImages.gradient(width: 1, height: 1),
      FilterTestImages.gradient(width: 5, height: 3),
    ] {
      for degrees in [0.0, 255.0, -255.0] {
        let output = try await HueFilter(degrees: degrees).apply(to: picture)
        #expect(output.width == picture.width && output.height == picture.height)
      }
    }
  }
}
