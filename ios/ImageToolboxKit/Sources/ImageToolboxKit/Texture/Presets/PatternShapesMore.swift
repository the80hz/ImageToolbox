// The second half of the pattern shaders. See `PatternShapes` for the dispatch.

import Foundation

extension PatternShapes {
  static func voronoiGems(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let shadows = e.value("shadows")
    let variability = e.value("variability")
    let cell = p.rounded(.down)
    var chosen = cell
    var local = SIMD2<Double>.zero
    var nearest = 100.0
    for row in -1...1 {
      for column in -1...1 {
        let c = cell + SIMD2(Double(column), Double(row))
        let v = p - c - 0.5 - (e.hash2(c) - 0.5) * variability
        let d = (v * v).sum()
        if d < nearest {
          nearest = d
          chosen = c
          local = v
        }
      }
    }
    let facet = ((e.safeAngle(local) + tau * 0.5) / tau * 6).rounded(.down)
    let shade = 1 - shadows * (0.25 + 0.6 * e.hash(chosen + facet))
    let base = e.palette(e.hash(chosen))
    return SIMD4(base.x * shade, base.y * shade, base.z * shade, base.w)
  }

  static func citySkyline(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let layers = e.value("layers")
    var result = mix(e.colours[0], e.colours[1], e.smoothstep(-0.5, 0.5, p.y))
    let sun = 1 - e.smoothstep(0.13, 0.135, length(p - SIMD2(0.18, -0.18)))
    result = mix(result, e.colours[2], sun)
    for index in 0..<8 where Double(index) < layers {
      let layer = Double(index)
      let scale = 20 + layer * 9
      let column = (p.x * scale).rounded(.down)
      let top = 0.02 + layer * 0.055 - e.hash(SIMD2(column, layer)) * 0.17
      if p.y > top {
        var building = mix(e.colours[1], e.colours[0], (layer + 1) / layers)
        let grid = SIMD2(p.x * scale * 3, p.y * 90)
        let window = fract(grid)
        let lit = e.step(0.94, e.hash(grid.rounded(.down) + layer))
        let windowLit = lit * e.step(0.3, window.x) * e.step(0.3, window.y)
        building = mix(building, e.colours[3], windowLit)
        result = building
      }
    }
    return result
  }

  static func winterLandscape(
    _ p: SIMD2<Double>,
    _ e: PatternEnvironment
  ) -> SIMD4<Double> {
    var result = mix(e.colours[0], e.colours[1], min(max(p.y + 0.5, 0), 1))
    let moon = 1 - e.smoothstep(0.05, 0.055, length(p - SIMD2(0.22, -0.3)))
    result = mix(result, e.colours[3], moon)
    for index in 0..<4 {
      let layer = Double(index)
      let hill = 0.03 + layer * 0.12 + 0.09 * sin(p.x * 5 + layer * 2)
      if p.y > hill {
        result = mix(e.colours[1], e.colours[3], layer * 0.22 + 0.2)
      }
      for flake in 0..<16 {
        let r = e.hash2(SIMD2(Double(flake), layer))
        let x = r.x * 1.3 - 0.65
        let base = 0.03 + layer * 0.12 + 0.09 * sin(x * 5 + layer * 2)
        let height = 0.06 + r.y * 0.1
        let y = p.y - base
        if y < 0, y > -height, abs(p.x - x) < (y + height) * 0.25 {
          result = mix(e.colours[0], e.colours[2], 0.35 + layer * 0.15)
        }
      }
    }
    let snow = SIMD2(p.x, p.y + e.value("time") * 0.05) * 60
    let cell = snow.rounded(.down)
    let v = fract(snow) - e.hash2(cell)
    let flake = (1 - e.smoothstep(0.03, 0.08, length(v))) * e.step(0.8, e.hash(cell))
    return mix(result, e.colours[3], flake)
  }

  static func circleRipple(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let radius = e.value("radius")
    let cell = p.rounded(.down)
    var q = fract(p) - 0.5
    q.x += glMod(cell.y, 2) * 0.5
    q.x = glMod(q.x + 0.5, 1) - 0.5
    q.y /= e.value("shapeAspect")
    let d = length(q)
    var result = e.colours[0]
    if d < radius {
      let angle = fract(e.safeAngle(q) / tau)
      result = angle < 0.5 ? e.colours[1] : e.colours[2]
      if d < radius * 0.75 {
        result = e.colours[3]
      }
    }
    return result
  }

  static func squareRipple(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let offset = e.value("offset")
    let q = p + SIMD2(sin(p.y * 1.2), sin(p.x * 1.2)) * offset
    let cell = q.rounded(.down)
    let v = fract(q)
    let parity = glMod(cell.x + cell.y, 2)
    var result = parity < 1 ? e.colours[0] : e.colours[1]
    if min(min(v.x, 1 - v.x), min(v.y, 1 - v.y)) < thickness {
      result = parity < 1 ? e.colours[2] : e.colours[3]
    }
    return result
  }

  static func hatch(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    mix(e.colours[0], e.colours[1], e.step(e.value("thickness"), fract(p.x)))
  }

  static func smoothHatch(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let hardness = e.value("hardness")
    let balance = e.value("balance")
    let v = 0.5 + 0.5 * cos(p.x * tau)
    let weight = e.smoothstep(balance - 0.5 / hardness, balance + 0.5 / hardness, v)
    return mix(e.colours[0], e.colours[1], weight)
  }

  static func xorPattern(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let intensity = e.value("intensity")
    var cell = (absVec(p) * 8).rounded(.down)
    var total = 0.0
    var weight = 1.0
    for index in 0..<12 where Double(index) < intensity {
      total += glMod(glMod(cell.x, 2) + glMod(cell.y, 2), 2) * weight
      cell = (cell * 0.5).rounded(.down)
      weight *= 2
    }
    return mix(e.colours[0], e.colours[1], total / max(weight - 1, 1))
  }

  static func squareSpiral(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let count = e.value("count")
    let thickness = e.value("thickness")
    let v = fract(p) - 0.5
    var d = 10.0
    var start = SIMD2(0.47, 0.47)
    let inset = 0.94 / (count * 2)
    for index in 0..<48 where Double(index) < count * 4 {
      let j = Double(index)
      let side = glMod(j, 4)
      let r = 0.47 - (j / 4).rounded(.down) * inset
      let end: SIMD2<Double>
      if side < 0.5 {
        end = SIMD2(-r, r)
      } else if side < 1.5 {
        end = SIMD2(-r, -r)
      } else if side < 2.5 {
        end = SIMD2(r - inset, -r)
      } else {
        end = SIMD2(r - inset, r - inset)
      }
      d = min(d, e.segment(v, start, end))
      start = end
    }
    let width = thickness * 0.235 / count
    return mix(e.colours[0], e.colours[1], 1 - e.smoothstep(width, width + 0.005, d))
  }

  static func crossStitch(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let shadows = e.value("shadows")
    let v = fract(p) - 0.5
    let parity = glMod(p.x.rounded(.down) + p.y.rounded(.down), 2)
    let horizontal = abs(v.y) < thickness * 0.5
    let vertical = abs(v.x) < thickness * 0.5
    var result = e.colours[0]
    if horizontal || vertical {
      let top = horizontal && (!vertical || parity < 0.5)
      let across = top ? v.y : v.x
      result = top ? e.colours[1] : e.colours[2]
      let darkening = 1 - shadows * pow(abs(across) * 2 / thickness, 2) * 0.6
      let ripple = 0.9 + 0.1 * cos(across * tau * 40)
      result = SIMD4(
        result.x * darkening * ripple,
        result.y * darkening * ripple,
        result.z * darkening * ripple,
        result.w)
    }
    return result
  }

  static func plaid(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let a = e.palette(e.hash(SIMD2(p.x.rounded(.down), 0)))
    let b = e.palette(e.hash(SIMD2(p.y.rounded(.down), 0)))
    let over = e.step(0.5, fract((p.x + p.y) * 12))
    var result = mix(a, b, over)
    if fract(p.x) < thickness * 0.2 || fract(p.y) < thickness * 0.2 {
      result = mix(result, e.colours[0], 0.6)
    }
    return result
  }

  static func generatedWaves(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let band = (p.y + sin(p.x * tau * 0.3) * e.value("variability")).rounded(.down)
    return e.palette(e.hash(SIMD2(band, 1)))
  }

  static func voronoiHatch(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let variability = e.value("variability")
    let cell = p.rounded(.down)
    var chosen = cell
    var nearest = 100.0
    for row in -1...1 {
      for column in -1...1 {
        let c = cell + SIMD2(Double(column), Double(row))
        let v = p - c - 0.5 - (e.hash2(c) - 0.5) * variability
        let d = (v * v).sum()
        if d < nearest {
          nearest = d
          chosen = c
        }
      }
    }
    let angle = e.hash(chosen) * tau
    let stripe = fract((p * SIMD2(cos(angle), sin(angle))).sum() * 8)
    return mix(e.colours[0], e.colours[1], e.step(e.value("thickness"), stripe))
  }

  static func loopPattern(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let radius = e.value("radius")
    let thickness = e.value("thickness")
    var d = 10.0
    for index in 0..<64 where Double(index) < e.value("count") {
      let n = Double(index)
      let centre = e.hash2(SIMD2(n, 1)) - 0.5
      d = min(d, abs(length(p - centre) - radius * (0.5 + e.hash(SIMD2(n, 3)))))
    }
    let edge = thickness * 0.2
    return mix(e.colours[0], e.colours[1], 1 - e.smoothstep(edge, edge + 0.005, d))
  }

  static func scintillatingGrid(
    _ p: SIMD2<Double>,
    _ e: PatternEnvironment
  ) -> SIMD4<Double> {
    let thickness = e.value("thickness")
    let radius = e.value("radius")
    let q = absVec(fract(p + 0.5) - 0.5)
    let line = min(q.x, q.y)
    let result = mix(e.colours[0], e.colours[1], 1 - e.step(thickness, line))
    return mix(result, e.colours[2], 1 - e.step(radius, length(q)))
  }

  static func circleSpiral(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let phase = length(p) - e.safeAngle(p) / tau
    return mix(e.colours[0], e.colours[1], e.step(0.5, fract(phase * e.value("count"))))
  }

  static func testChart(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let q = fract(p + 0.5) * 2
    let v: Double
    if q.y < 1, q.x < 1 {
      v = e.step(0.5, fract(length(q - 0.5) * 8))
    } else if q.y < 1 {
      v = e.step(0.5, fract((q.x + q.y) * 8))
    } else if q.x < 1 {
      let rgb = e.hsv(q.x, 1, 2 - q.y)
      return SIMD4(rgb.x, rgb.y, rgb.z, 1)
    } else {
      v = glMod(floor(q.x * 8) + floor(q.y * 8), 2)
    }
    return mix(e.colours[0], e.colours[1], v)
  }

  static func bentRows(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let row = p.y.rounded(.down)
    let x = p.x + sin(row * 1.7) * e.value("offset")
    let v = glMod(x.rounded(.down) + row, 2)
    var result = mix(e.colours[0], e.colours[1], v)
    if fract(p.y) < e.value("thickness") {
      result = e.colours[2]
    }
    return result
  }

  static func diamonds(_ p: SIMD2<Double>, _ e: PatternEnvironment) -> SIMD4<Double> {
    let q = fract(p) - 0.5
    let d = max(abs(q.x), abs(q.y))
    var phase = d * e.value("count") * 4
    if q.x + q.y > 0 {
      phase += 0.5
    }
    if q.x - q.y > 0 {
      phase += 0.5
    }
    return mix(e.colours[0], e.colours[1], e.step(e.value("thickness"), fract(phase)))
  }
}
