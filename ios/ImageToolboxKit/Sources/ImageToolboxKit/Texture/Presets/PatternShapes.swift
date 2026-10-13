import Foundation

/// The 28 pattern shaders, one function per `PatternKind`. Each follows its Android GLSL source;
/// `p` is the pixel position after the centring, aspect and frequency steps of `PatternRenderer`.
enum PatternShapes {
  static func shade(
    _ kind: PatternKind,
    _ p: SIMD2<Double>,
    _ e: PatternEnvironment
  ) -> SIMD4<Double> {
    switch kind {
    case .randomTriangles: randomTriangles(p, e)
    case .hexCubePattern: hexCube(p, e)
    case .squareLooper: squareLooper(p, e)
    case .moireInterference: moire(p, e)
    case .truchetArcs: truchetArcs(p, e)
    case .circuitPattern: circuit(p, e)
    case .rosacePattern: rosace(p, e, isRosette: false)
    case .rosettePattern: rosace(p, e, isRosette: true)
    case .lightArray: lightArray(p, e)
    case .voronoiGems: voronoiGems(p, e)
    case .citySkyline: citySkyline(p, e)
    case .winterLandscape: winterLandscape(p, e)
    case .circleRipplePattern: circleRipple(p, e)
    case .squareRipplePattern: squareRipple(p, e)
    case .hatchPattern: hatch(p, e)
    case .smoothHatch: smoothHatch(p, e)
    case .xorPattern: xorPattern(p, e)
    case .squareSpiralPattern: squareSpiral(p, e)
    case .crossStitchPattern: crossStitch(p, e)
    case .plaidPattern: plaid(p, e)
    case .generatedWaves: generatedWaves(p, e)
    case .voronoiHatch: voronoiHatch(p, e)
    case .loopPattern: loopPattern(p, e)
    case .scintillatingGrid: scintillatingGrid(p, e)
    case .circleSpiralPattern: circleSpiral(p, e)
    case .testChart: testChart(p, e)
    case .bentRows: bentRows(p, e)
    case .diamondsIllusion: diamonds(p, e)
    }
  }

  static func randomTriangles(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    var result = e.colours[0]
    for index in 0..<100 where Double(index) < e.value("count") {
      let n = Double(index)
      let a = e.hash2(SIMD2(n, 1)) - 0.5
      let b = e.hash2(SIMD2(n, 2)) - 0.5
      let c = e.hash2(SIMD2(n, 3)) - 0.5
      let v = p - a
      let u = b - a
      let w = c - a
      let cross = u.x * w.y - u.y * w.x
      let divisor = abs(cross) < 0.00001 ? 0.00001 : cross
      let s = (v.x * w.y - v.y * w.x) / divisor
      let t = (u.x * v.y - u.y * v.x) / divisor
      if s >= 0, t >= 0, s + t <= 1 {
        result = e.palette(e.hash(SIMD2(n, 4)))
      }
    }
    return result
  }

  static func hexCube(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let cell = (p / SIMD2(1.73205, 1.5)).rounded(.down)
    var local = SIMD2<Double>.zero
    var nearest = 100.0
    for row in -1...1 {
      for column in -1...1 {
        let c = cell + SIMD2(Double(column), Double(row))
        let centre = SIMD2((c.x + glMod(c.y, 2) * 0.5) * 1.73205, c.y * 1.5)
        let d = p - centre
        if (d * d).sum() < nearest {
          nearest = (d * d).sum()
          local = d
        }
      }
    }
    let angle = fract((e.safeAngle(local) + tau * 0.25) / tau)
    var result = e.colours[2]
    if angle < 0.333_333 {
      result = e.colours[0]
    } else if angle < 0.666_667 {
      result = e.colours[1]
    }
    let v = absVec(local)
    let edge = max(v.x * 0.866_025 + v.y * 0.5, v.y)
    if edge > 1 - thickness {
      result = e.colours[3]
    }
    return result
  }

  static func squareLooper(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let q = SIMD2(0.7071 * p.x + 0.7071 * p.y, -0.7071 * p.x + 0.7071 * p.y)
    let d = max(abs(q.x), abs(q.y))
    let wave = abs(fract(d - e.value("time") * 0.1) - 0.5)
    return mix(e.colours[0], e.colours[1], 1 - e.step(e.value("thickness") * 0.5, wave))
  }

  static func moire(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let intensity = e.value("intensity")
    let a = length(p - SIMD2(0.4, 0))
    let b = length(p + SIMD2(0.4, 0))
    let v = sin(a * intensity) * sin(b * intensity)
    let threshold = e.value("thickness")
    return mix(e.colours[0], e.colours[1], e.smoothstep(threshold - 0.6, threshold - 0.4, v))
  }

  static func truchetArcs(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let cell = p.rounded(.down)
    var q = p - cell
    if e.hash(cell) > 0.5 {
      q.x = 1 - q.x
    }
    let d = min(abs(length(q) - 0.5), abs(length(q - 1) - 0.5))
    let weight = 1 - e.smoothstep(thickness * 0.5, thickness * 0.5 + 0.015, d)
    return mix(e.colours[0], e.colours[1], weight)
  }

  static func circuit(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let radius = e.value("radius")
    let thickness = e.value("thickness")
    let cell = p.rounded(.down)
    var q = fract(p) - 0.5
    let choice = e.hash(cell)
    if choice > 0.5 {
      q = SIMD2(q.y, q.x)
    }
    if choice > 0.75 {
      q.x = -q.x
    }
    let wire = min(
      e.segment(q, SIMD2(-0.5, 0), SIMD2(0, 0)),
      e.segment(q, SIMD2(0, 0), SIMD2(0, 0.5)))
    let terminal = abs(length(q - SIMD2(0.3, -0.3)) - radius)
    let d = min(wire, terminal)
    return mix(e.colours[0], e.colours[1], 1 - e.smoothstep(thickness, thickness + 0.01, d))
  }

  /// The rosace puts its ring centres on the radius, the rosette at a fixed 0.4.
  static func rosace(
    _ p: SIMD2<Double>,
    _ e: PatternEnvironment,
    isRosette: Bool
  ) -> SIMD4<Double> {
    let count = e.value("count")
    let radius = e.value("radius")
    let thickness = e.value("thickness")
    let centreDistance = isRosette ? 0.4 : radius
    var d = 10.0
    for index in 0..<64 where Double(index) < count {
      let angle = Double(index) * tau / count
      let centre = SIMD2(cos(angle), sin(angle)) * centreDistance
      d = min(d, abs(length(p - centre) - radius))
    }
    return mix(e.colours[0], e.colours[1], 1 - e.smoothstep(thickness, thickness + 0.005, d))
  }

  static func lightArray(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let intensity = e.value("intensity")
    var light = SIMD3<Double>.zero
    var scale = 1.0
    for index in 0..<6 where Double(index) < e.value("layers") {
      let scaled = p * scale
      let q = fract(scaled) - 0.5
      let cell = scaled.rounded(.down)
      let rays =
        exp(-abs(q.x) * 120) * exp(-abs(q.y) * 5)
        + exp(-abs(q.y) * 120) * exp(-abs(q.x) * 5)
      let glow = exp(-(q * q).sum() * 60)
      let colour = e.palette(e.hash(cell + Double(index)))
      light += SIMD3(colour.x, colour.y, colour.z) * (rays + glow) * intensity / scale
      scale *= 2
    }
    let base = e.colours[0]
    return SIMD4(
      min(max(base.x + light.x, 0), 1),
      min(max(base.y + light.y, 0), 1),
      min(max(base.z + light.z, 0), 1),
      base.w)
  }
}
