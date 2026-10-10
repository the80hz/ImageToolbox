// Port of Material Color Utilities (score/score).
// Copyright 2021 Google LLC. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0). Adapted to Swift for ImageToolbox.

import Foundation

/// Ranks quantized colours as candidates for a theme's source colour.
///
/// A colour scores higher the more of the image sits near its hue and the closer its chroma is
/// to a pleasant 48. Colours that are nearly grey or very rare are dropped when `filter` is on.
enum Score {
  private static let targetChroma = 48.0
  private static let weightProportion = 0.7
  private static let weightChromaAbove = 0.3
  private static let weightChromaBelow = 0.1
  private static let cutoffChroma = 5.0
  private static let cutoffExcitedProportion = 0.01

  /// The Google blue used when nothing in the image qualifies.
  static let fallback: UInt32 = 0xFF42_85F4

  /// Up to `desired` colours, best first, as different in hue from each other as possible.
  static func score(
    _ colours: [(argb: UInt32, count: Int)], desired: Int = 4,
    fallback: UInt32 = Score.fallback, filter: Bool = true
  ) -> [UInt32] {
    var hcts: [Hct] = []
    var huePopulation = [Int](repeating: 0, count: 360)
    var populationSum = 0.0
    for entry in colours {
      let hct = Hct(argb: entry.argb)
      hcts.append(hct)
      huePopulation[min(359, Int(floor(hct.hue)))] += entry.count
      populationSum += Double(entry.count)
    }

    // A hue also counts the usage of its neighbours in a 30 degree window.
    var excited = [Double](repeating: 0, count: 360)
    for hue in 0..<360 {
      let proportion = populationSum > 0 ? Double(huePopulation[hue]) / populationSum : 0
      for i in (hue - 14)..<(hue + 16) {
        excited[MaterialColour.sanitizeDegrees(i)] += proportion
      }
    }

    var scored: [(hct: Hct, score: Double)] = []
    for hct in hcts {
      let hue = MaterialColour.sanitizeDegrees(Int(hct.hue.rounded()))
      let proportion = excited[hue]
      if filter && (hct.chroma < cutoffChroma || proportion <= cutoffExcitedProportion) {
        continue
      }
      let proportionScore = proportion * 100.0 * weightProportion
      let chromaWeight = hct.chroma < targetChroma ? weightChromaBelow : weightChromaAbove
      let chromaScore = (hct.chroma - targetChroma) * chromaWeight
      scored.append((hct, proportionScore + chromaScore))
    }
    // Highest score first; equal scores keep their original order.
    let ordered = scored.enumerated().sorted {
      $0.element.score != $1.element.score
        ? $0.element.score > $1.element.score : $0.offset < $1.offset
    }.map(\.element.hct)

    // Look for the widest hue spacing that still yields enough colours, from 90 down to 15.
    var chosen: [Hct] = []
    for difference in stride(from: 90, through: 15, by: -1) {
      chosen.removeAll()
      for hct in ordered {
        let duplicate = chosen.contains {
          MaterialColour.differenceDegrees(hct.hue, $0.hue) < Double(difference)
        }
        if !duplicate { chosen.append(hct) }
        if chosen.count >= desired { break }
      }
      if chosen.count >= desired { break }
    }
    return chosen.isEmpty ? [fallback] : chosen.map(\.argb)
  }
}
