// Port of Material Color Utilities (temperature/temperature_cache, dislike/dislike_analyzer).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Nudges the colours people tend to dislike: dark yellow-greens ("bile").
enum DislikeAnalyzer {
  static func isDisliked(_ hct: Hct) -> Bool {
    let huePasses = hct.hue.rounded() >= 90.0 && hct.hue.rounded() <= 111.0
    let chromaPasses = hct.chroma.rounded() > 16.0
    let tonePasses = hct.tone.rounded() < 65.0
    return huePasses && chromaPasses && tonePasses
  }

  /// A disliked colour is lightened to tone 70; any other colour is returned unchanged.
  static func fixIfDisliked(_ hct: Hct) -> Hct {
    isDisliked(hct) ? Hct(hue: hct.hue, chroma: hct.chroma, tone: 70.0) : hct
  }
}

/// Warm/cool ordering of the hues at one chroma and tone, for complementary and analogous colours.
struct TemperatureCache {
  private let input: Hct
  /// One entry per whole degree, 0 through 360, then the input colour.
  private let colours: [Hct]
  private let temperatures: [Double]
  private let coldestIndex: Int
  private let warmestIndex: Int

  init(_ input: Hct) {
    self.input = input
    var colours = (0...360).map { Hct(hue: Double($0), chroma: input.chroma, tone: input.tone) }
    colours.append(input)
    let temperatures = colours.map(Self.rawTemperature)
    // Stable order: equal temperatures keep their position, as in the reference sort.
    let order = colours.indices.sorted {
      temperatures[$0] != temperatures[$1] ? temperatures[$0] < temperatures[$1] : $0 < $1
    }
    self.colours = colours
    self.temperatures = temperatures
    self.coldestIndex = order.first ?? 0
    self.warmestIndex = order.last ?? 0
  }

  /// CIE Lab based warmth, roughly -0.5 (cold) to 0.5 (warm).
  private static func rawTemperature(_ colour: Hct) -> Double {
    let lab = MaterialColour.lab(fromARGB: colour.argb)
    let hue = MaterialColour.sanitizeDegrees(atan2(lab.z, lab.y) * 180.0 / Double.pi)
    let chroma = hypot(lab.y, lab.z)
    return -0.5 + 0.02 * pow(chroma, 1.07)
      * cos(MaterialColour.sanitizeDegrees(hue - 50.0) * Double.pi / 180.0)
  }

  private func relativeTemperature(_ index: Int) -> Double {
    let range = temperatures[warmestIndex] - temperatures[coldestIndex]
    if range == 0 { return 0.5 }
    return (temperatures[index] - temperatures[coldestIndex]) / range
  }

  private static func isBetween(_ angle: Double, _ a: Double, _ b: Double) -> Bool {
    a < b ? (a <= angle && angle <= b) : (a <= angle || angle <= b)
  }

  /// The colour on the opposite side of the warm/cool axis, with the same chroma and tone.
  var complement: Hct {
    let coldestHue = colours[coldestIndex].hue
    let warmestHue = colours[warmestIndex].hue
    let coldestTemperature = temperatures[coldestIndex]
    let range = temperatures[warmestIndex] - coldestTemperature
    let startIsColdestToWarmest = Self.isBetween(input.hue, coldestHue, warmestHue)
    let startHue = startIsColdestToWarmest ? warmestHue : coldestHue
    let endHue = startIsColdestToWarmest ? coldestHue : warmestHue

    var smallestError = 1000.0
    var answer = colours[Int(input.hue.rounded())]
    let complementRelative = 1.0 - relativeTemperature(colours.count - 1)
    // Walk the other half of the wheel, looking for the temperature closest to the inverse.
    var addend = 0.0
    while addend <= 360.0 {
      defer { addend += 1.0 }
      let hue = MaterialColour.sanitizeDegrees(startHue + addend)
      if !Self.isBetween(hue, startHue, endHue) { continue }
      let index = Int(hue.rounded())
      let relative = (temperatures[index] - coldestTemperature) / range
      let error = abs(complementRelative - relative)
      if error < smallestError {
        smallestError = error
        answer = colours[index]
      }
    }
    return answer
  }

  /// `count` colours spaced evenly in temperature around the input; the input is in the middle.
  func analogous(count: Int, divisions: Int) -> [Hct] {
    let startHue = Int(input.hue.rounded())
    let startIndex = startHue
    var lastTemperature = relativeTemperature(startIndex)
    var allColours = [startIndex]
    var totalDelta = 0.0
    for offset in 0..<360 {
      let index = MaterialColour.sanitizeDegrees(startHue + offset)
      let temperature = relativeTemperature(index)
      totalDelta += abs(temperature - lastTemperature)
      lastTemperature = temperature
    }

    var hueAddend = 1
    let step = totalDelta / Double(divisions)
    var runningDelta = 0.0
    lastTemperature = relativeTemperature(startIndex)
    while allColours.count < divisions {
      let index = MaterialColour.sanitizeDegrees(startHue + hueAddend)
      let temperature = relativeTemperature(index)
      runningDelta += abs(temperature - lastTemperature)
      var desired = Double(allColours.count) * step
      var satisfied = runningDelta >= desired
      var indexAddend = 1
      // Repeat a hue while its temperature step is still covered: white and black have no
      // analogues and fill the remaining slots.
      while satisfied && allColours.count < divisions {
        allColours.append(index)
        desired = Double(allColours.count + indexAddend) * step
        satisfied = runningDelta >= desired
        indexAddend += 1
      }
      lastTemperature = temperature
      hueAddend += 1
      if hueAddend > 360 {
        while allColours.count < divisions { allColours.append(index) }
        break
      }
    }

    var answer = [input]
    let increaseCount = (count - 1) / 2
    for offset in 1..<(increaseCount + 1) {
      var index = 0 - offset
      while index < 0 { index = allColours.count + index }
      if index >= allColours.count { index %= allColours.count }
      answer.insert(colours[allColours[index]], at: 0)
    }
    let decreaseCount = count - increaseCount - 1
    for offset in 1..<(decreaseCount + 1) {
      var index = offset
      while index < 0 { index = allColours.count + index }
      if index >= allColours.count { index %= allColours.count }
      answer.append(colours[allColours[index]])
    }
    return answer
  }
}
