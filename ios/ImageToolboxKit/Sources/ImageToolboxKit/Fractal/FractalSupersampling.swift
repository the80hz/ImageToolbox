import Foundation

extension EscapeTimeFractal {

  /// The engine's work limit for an escape-time picture: its sampled pixels times its iterations.
  static let escapeTimeWorkLimit = 10_000_000_000

  /// The supersampling a picture is drawn with. The density kinds keep the requested count, since the
  /// engine uses it only for their step budget. An escape-time or ray-marched picture is lowered one
  /// step at a time, as the Android app's render plan lowers it, until its sampled pixels fit the budget
  /// with at least the preferred iterations, which are the request or 64 when that is less. The plan
  /// of the ray-marched kinds counts their marching steps. A picture of one sample per pixel is never
  /// lowered.
  static func effectiveSupersampling(_ settings: Settings, width: Int, height: Int) -> Int {
    let requested = min(max(settings.supersampling, 1), 4)
    guard !settings.kind.isDensity, width > 0, height > 0 else { return requested }
    let pixels = width * height
    let preferred = min(settings.maxIterations, 64)
    var supersampling = requested
    while supersampling > 1,
      !fits(
        settings.kind, maxIterations: settings.maxIterations,
        sampledPixels: pixels * supersampling * supersampling, preferred: preferred)
    {
      supersampling -= 1
    }
    return supersampling
  }

  /// Whether the picture of the given sampled pixels keeps at least the preferred iterations in budget.
  private static func fits(
    _ kind: Kind, maxIterations: Int, sampledPixels: Int, preferred: Int
  ) -> Bool {
    if kind.is3D {
      guard
        let plan = Fractal3D.rayMarchPlan(
          kind, requested: maxIterations, pixels: sampledPixels)
      else { return false }
      return plan.maximumSteps >= preferred
    }
    return sampledPixels * preferred <= escapeTimeWorkLimit
  }
}

/// The average of the subsamples of one pixel, as the engine averages opaque colours. Each channel is
/// the sum over the samples, divided by their count and rounded half up, so one sample is its own colour.
struct SubsampleAverage {
  private var red = 0
  private var green = 0
  private var blue = 0
  private(set) var count = 0

  mutating func add(_ colour: (UInt8, UInt8, UInt8)) {
    red += Int(colour.0)
    green += Int(colour.1)
    blue += Int(colour.2)
    count += 1
  }

  /// The rounded average. An average of no samples is black.
  var colour: (UInt8, UInt8, UInt8) {
    guard count > 0 else { return (0, 0, 0) }
    let divisor = count * 255
    func channel(_ sum: Int) -> UInt8 {
      UInt8((sum * 255 + divisor / 2) / divisor)
    }
    return (channel(red), channel(green), channel(blue))
  }
}
