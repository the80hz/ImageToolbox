import Foundation

/// Native textures 51...70 of the Android fast-noise module, ported from `ProceduralTextures.cpp`
/// (`showcaseTexture`). Cases 52, 53, 60, 66 and 69 return from inside the switch, as the C++
/// does, so they skip the final contrast and accent step.
extension NativeTextureFunctions {
  private typealias M = NativeTextureMath
  private static let pi: Float = 3.14159265358979323846

  static func showcase(
    _ textureType: Int, _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ width: Int, _ height: Int, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let complexity = M.clamp01(parameter(p, 1, 0.62))
    let distortion = M.clamp01(parameter(p, 2, 0.48))
    let sharpness = M.clamp01(parameter(p, 3, 0.58))
    let glow = M.clamp01(parameter(p, 4, 0.52))
    let contrastAmount = M.maxOf(parameter(p, 5, 1.25), 0.05)
    let unit = Float(min(width, height))
    var u = (x - Float(width) * 0.5) / unit
    var v = (y - Float(height) * 0.5) / unit
    let spatialScale = M.clamp(s / 0.008, 0.125, 5)
    u *= spatialScale
    v *= spatialScale
    var nx = x
    var ny = y
    noise.warp(&nx, &ny, scale: s * 0.7, amount: distortion * 54)
    let base = noise.fbm(nx * s, ny * s)
    let fine = noise.fine(nx * s * 4.1, ny * s * 4.1)
    var result = base
    var accent: Float = 0

    switch textureType {
    case 51:
      let radius = (u * u + v * v).squareRoot() + (base - 0.5) * distortion * 0.16
      let bands = 0.5 + 0.5 * sin(radius * (55 + complexity * 95) + fine * 8)
      let cavity = 1 - M.smoothstep(0.05, 0.2, radius)
      let crystals = pow(
        M.clamp01(0.5 + 0.5 * sin(atan2(v, u) * (10 + complexity * 24) + radius * 180)), 5)
      result = M.contrast(bands * (1 - cavity * 0.55) + cavity * crystals, contrastAmount)
      accent = cavity * crystals * glow
    case 52:
      let angle = atan2(v, u)
      let radius = (u * u + v * v).squareRoot()
      let facets = abs(M.fract((angle / (2 * pi) + 0.5) * (5 + complexity * 13)) - 0.5)
      let beam = abs(sin((u * 0.84 + v * 0.54) * (42 + complexity * 86) + facets * 9))
      let spectrum = M.fract(angle / (2 * pi) + radius * (2 + distortion * 5) + facets)
      accent = (1 - M.smoothstep(0.01, 0.08 + (1 - sharpness) * 0.12, beam)) * glow
      return M.mixColor(palette4(c, spectrum), colour(c, 3, 0xFFFF_E47A), accent)
    case 53:
      let spacing = s * (1.3 + complexity * 3.2)
      let edge = noise.cellEdge(nx, ny, scale: spacing, jitter: 1)
      let lead = 1 - M.smoothstep(0.035, 0.095 + (1 - sharpness) * 0.08, edge)
      let glass = noise.cellVariation(nx, ny, scale: spacing, jitter: 1)
      var pane = palette4(c, M.fract(glass * 2.8 + fine * 0.22))
      pane = M.mixColor(pane, colour(c, 3, 0xFFFF_D34E), fine * glow * 0.3)
      return M.mixColor(pane, colour(c, 0, 0xFF12_0F18), lead)
    case 54:
      let depth = M.clamp01(v + 0.5)
      let stems = abs(
        sin((u + sin(v * 8 + base * 3) * distortion * 0.12) * (24 + complexity * 46)))
      let blades = 1 - M.smoothstep(0.015, 0.07 + (1 - sharpness) * 0.12, stems)
      let rays = pow(M.clamp01(0.5 + 0.5 * sin((u + v * 0.24) * 18 + fine * 2)), 7)
      result = M.clamp01(
        base * 0.28 + blades * (0.45 + depth * 0.35) + rays * (1 - depth) * glow)
      accent = rays * (1 - depth) * glow
    case 55:
      let angle = atan2(v, u)
      let radius = (u * u + v * v).squareRoot()
      let branches = abs(
        sin(angle * (5 + complexity * 13) + radius * 68 + base * distortion * 7))
      let needles = abs(sin((u * 0.7 - v) * (170 + complexity * 260)))
      accent = (1 - M.smoothstep(0.02, 0.14, branches)) * (0.55 + 0.45 * (1 - needles))
      result = M.clamp01(base * 0.45 + accent * (0.7 + glow * 0.35))
    case 56:
      let angle = atan2(v, u)
      let phase = base * 14 + angle * (4 + complexity * 10) + (u - v) * 28
      result = M.fract(phase / (2 * pi))
      accent = pow(0.5 + 0.5 * sin(phase * 1.73), 5) * glow
    case 57:
      let cellsX = x * s * (7 + complexity * 12)
      let cellsY = y * s * (5 + complexity * 9)
      let row = floor(cellsY)
      let px = M.fract(cellsX + Float(Int(row) & 1) * 0.5) - 0.5
      let py = M.fract(cellsY) - 0.32
      let scaleShape = (px * px + py * py * 0.65).squareRoot()
      let rim = 1 - M.smoothstep(0.32, 0.42 + (1 - sharpness) * 0.09, scaleShape)
      result = M.clamp01(rim * (0.34 + 0.66 * (0.5 - py)) + fine * 0.2)
      accent = rim * M.smoothstep(0.19, -0.1, py) * glow
    case 58:
      let density = 7 + complexity * 15
      let gx = (u + 0.5) * density
      let gy = (v + 0.5) * density
      var nearest: Float = 10
      var trail: Float = 10
      let cellX = Int32(floor(gx))
      let cellY = Int32(floor(gy))
      for oy in Int32(-1)...1 {
        for ox in Int32(-1)...1 {
          let cx = cellX &+ ox
          let cy = cellY &+ oy
          let px = Float(cx) + M.hash(Float(cx), Float(cy), seed) * 0.76 + 0.12
          let py = Float(cy) + M.hash(Float(cy), Float(cx), seed &+ 31) * 0.76 + 0.12
          let dx = gx - px
          let dy = gy - py
          nearest = M.minOf(nearest, (dx * dx + dy * dy).squareRoot())
          let skew = dx + dy * distortion * 0.8
          trail = M.minOf(trail, (skew * skew + dy * dy * 0.08).squareRoot())
        }
      }
      let spark = 1 - M.smoothstep(0.015, 0.10 + (1 - sharpness) * 0.12, nearest)
      let tail = 1 - M.smoothstep(0.03, 0.18, trail)
      result = M.clamp01(base * 0.18 + tail * 0.34 + spark)
      accent = spark * glow
    case 59:
      let edge1 = noise.cellEdge(nx, ny, scale: s * (2 + complexity * 3), jitter: 1.2)
      let edge2 = noise.secondaryCellEdge(
        nx + 37, ny - 19, scale: s * (4 + complexity * 5), jitter: 1.4)
      accent =
        (1 - M.smoothstep(0.018, 0.11, edge1)) * 0.7 + (1 - M.smoothstep(0.012, 0.08, edge2)) * 0.5
      result = M.clamp01(base * 0.3 + accent * (0.65 + glow * 0.35))
    case 60:
      let edge = noise.cellEdge(nx, ny, scale: s * (1.3 + complexity * 3.7), jitter: 1.3)
      let crack = 1 - M.smoothstep(0.012, 0.065 + (1 - sharpness) * 0.07, edge)
      let ceramic = M.mixColor(
        colour(c, 0, 0xFF10_131A), colour(c, 1, 0xFF34_4158), base * 0.7)
      let gold = M.mixColor(colour(c, 2, 0xFFD9_9B32), colour(c, 3, 0xFFFF_E7A3), fine * glow)
      return M.mixColor(ceramic, gold, crack)
    case 61:
      let frequency = 0.08 + s * 8 + complexity * 0.11
      let ax = sin((x + y * 0.48) * frequency * pi)
      let ay = sin((y - x * 0.48) * frequency * pi)
      let weave = ax * ay
      result = M.clamp01(0.38 + weave * 0.3 + fine * 0.22)
      accent = pow(M.clamp01(weave), 4) * glow
    case 62:
      let grid = 12 + complexity * 32
      let gx = M.fract(x * s * grid)
      let gy = M.fract(y * s * grid)
      let trace = M.minOf(abs(gx - 0.5), abs(gy - 0.5))
      let path = 1 - M.smoothstep(0.025, 0.08 + (1 - sharpness) * 0.06, trace)
      let radialGap = (gx - 0.5) * (gx - 0.5) + (gy - 0.5) * (gy - 0.5)
      let via = 1 - M.smoothstep(0.08, 0.17, radialGap.squareRoot())
      result = M.clamp01(base * 0.3 + path * 0.48 + via * 0.5)
      accent = via * glow
    case 63:
      let film = base * (8 + complexity * 18) + fine * distortion * 5 + (u * u - v * v) * 18
      result = M.fract(film)
      accent = pow(0.5 + 0.5 * sin(film * pi * 2), 6) * glow
    case 64:
      let r1 = ((u - 0.18) * (u - 0.18) + v * v).squareRoot()
      let r2 = ((u + 0.18) * (u + 0.18) + v * v).squareRoot()
      let pattern = sin(r1 * (120 + complexity * 260)) * sin(r2 * (124 + complexity * 252))
      result = M.contrast(pattern * 0.5 + 0.5, contrastAmount)
      accent = pow(result, 7) * glow
    case 65:
      let spacing = s * (2.5 + complexity * 4)
      let edge = noise.cellEdge(nx, ny, scale: spacing, jitter: 0.78)
      let inside = noise.cellVariation(nx, ny, scale: spacing, jitter: 0.78)
      let rim = 1 - M.smoothstep(0.025, 0.11, edge)
      result = M.clamp01(inside * 0.78 + (1 - rim) * fine * 0.2)
      accent = rim * glow
    case 66:
      let spacing = s * (4 + complexity * 8)
      let cells = noise.cellVariation(nx, ny, scale: spacing, jitter: 1.7)
      let edge = noise.cellEdge(nx, ny, scale: spacing, jitter: 1.7)
      let chips =
        M.smoothstep(0.68 - complexity * 0.22, 0.9, cells) * M.smoothstep(0.02, 0.13, edge)
      if chips > 0.05 {
        return palette4(c, M.fract(cells * 3.7 + fine * 0.2))
      }
      return M.mixColor(colour(c, 0, 0xFFE5_DCCF), colour(c, 3, 0xFFE5_A73D), fine * 0.08)
    case 67:
      let e1 =
        1
        - M.smoothstep(
          0.015, 0.13, noise.cellEdge(nx, ny, scale: s * (1.2 + complexity * 2), jitter: 1.4))
      let e2 =
        1
        - M.smoothstep(
          0.01, 0.08,
          noise.secondaryCellEdge(nx, ny, scale: s * (3.2 + complexity * 4), jitter: 1.5))
      let stars = M.smoothstep(0.998 - complexity * 0.006, 1, M.hash(x, y, seed))
      result = M.clamp01(e1 * 0.72 + e2 * 0.38 + stars)
      accent = stars + e1 * e2 * glow
    case 68:
      let spacing = s * (1.8 + complexity * 4)
      let facets = noise.cellVariation(nx, ny, scale: spacing, jitter: 1.2)
      let edge = 1 - M.smoothstep(0.02, 0.12, noise.cellEdge(nx, ny, scale: spacing, jitter: 1.2))
      result = M.clamp01(facets * 0.25 + edge * 0.22 + fine * 0.08)
      accent = edge * M.smoothstep(0.82, 1, base) * glow
    case 69:
      return circuitBoard(
        x, y, s, complexity, distortion, glow, base, seed, c)
    case 70:
      let grid = 4 + complexity * 9
      let gx = M.fract((u + 0.5) * grid) - 0.5
      let gy = M.fract((v + 0.5) * grid) - 0.5
      let radius = (gx * gx + gy * gy).squareRoot()
      let angle = atan2(gy, gx)
      let shell = 1 - M.smoothstep(0.31, 0.42, radius)
      let pores = 0.5 + 0.5 * sin(angle * (8 + complexity * 14) + radius * 90)
      result = M.clamp01(shell * (0.38 + pores * 0.62))
      accent = shell * pow(pores, 7) * glow
    default:
      break
    }
    result = M.contrast(result, contrastAmount)
    return M.mixColor(palette4(c, result), colour(c, 3, 0xFFFF_E8A3), M.clamp01(accent))
  }

  /// Case 69: a circuit board with traces, vias, chips and heat spots.
  private static func circuitBoard(
    _ x: Float, _ y: Float, _ s: Float, _ complexity: Float, _ distortion: Float,
    _ glow: Float, _ base: Float, _ seed: Int32, _ c: [UInt32]
  ) -> UInt32 {
    let boardScale = 2.2 + complexity * 4.8
    let boardX = x * s * boardScale
    let boardY = y * s * boardScale
    let cellX = Int32(floor(boardX))
    let cellY = Int32(floor(boardY))
    let localX = M.fract(boardX) - 0.5
    let localY = M.fract(boardY) - 0.5
    let cellKind = M.hash(Float(cellX), Float(cellY), seed)
    let offsetY = M.hash(Float(cellY), Float(cellX), seed &+ 17)
    let offsetVia = M.hash(Float(cellY), Float(cellX), seed &+ 31)
    let horizontal = 1 - M.smoothstep(0.018, 0.055, abs(localY - (cellKind - 0.5) * 0.42))
    let vertical = 1 - M.smoothstep(0.018, 0.055, abs(localX - (offsetY - 0.5) * 0.42))
    let route =
      cellKind < 0.5
      ? M.maxOf(horizontal, vertical * M.smoothstep(0.05, 0.42, abs(localY)))
      : M.maxOf(vertical, horizontal * M.smoothstep(0.05, 0.42, abs(localX)))
    let viaX = localX - (cellKind - 0.5) * 0.38
    let viaY = localY - (offsetVia - 0.5) * 0.38
    let viaDistance = (viaX * viaX + viaY * viaY).squareRoot()
    let via = 1 - M.smoothstep(0.055, 0.115, viaDistance)
    let chip =
      cellKind > 0.76
      ? 1 - M.smoothstep(0.22, 0.29, M.maxOf(abs(localX), abs(localY) * 1.45)) : 0
    let pins = chip * (1 - M.smoothstep(0.02, 0.06, abs(abs(localY) - 0.2)))
    var heat: Float = 0
    for oy in Int32(-1)...1 {
      for ox in Int32(-1)...1 {
        let hotX = cellX &+ ox
        let hotY = cellY &+ oy
        let hotKind = M.hash(Float(hotX), Float(hotY), seed)
        if hotKind <= 0.76 { continue }
        let dx = boardX - (Float(hotX) + 0.5)
        let dy = boardY - (Float(hotY) + 0.5)
        heat = M.maxOf(heat, exp(-(dx * dx + dy * dy) * (2.5 + distortion * 7)))
      }
    }
    var board = M.mixColor(colour(c, 0, 0xFF07_120E), colour(c, 1, 0xFF08_705B), 0.2 + base * 0.32)
    board = M.mixColor(board, 0xFF02_0504, chip * 0.8)
    board = M.mixColor(
      board, colour(c, 2, 0xFFFF_7B22), M.clamp01(route * 0.62 + via * 0.78 + pins))
    board = M.mixColor(
      board, colour(c, 3, 0xFFFF_F1A8), heat * glow * (0.35 + via * 0.65))
    return board
  }

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }

  private static func colour(_ c: [UInt32], _ index: Int, _ fallback: UInt32) -> UInt32 {
    NativeTextureMath.color(c, index, fallback)
  }
}
