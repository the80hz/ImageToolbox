import Foundation

/// Runs the native texture code of the Android fast-noise module on the CPU. It mirrors the JNI
/// `generate` function of `ProceduralTextures.cpp`: codes 0...70 draw one pixel at a time, and
/// codes 71...121 first compute a field for the whole picture and then shade it.
enum NativeTextureRenderer {
  /// Renders a native texture and returns RGBA bytes, row 0 at the top. `parameters` are the
  /// values in native order (scale first) and `colours` the ARGB colours in native order.
  static func render(
    code: Int, width: Int, height: Int, seed: Int32, parameters: [Float], colours: [UInt32]
  ) -> [UInt8] {
    let noise = NativeNoiseBank(seed: seed)
    var bitmap = [UInt32](repeating: 0, count: width * height)
    if (71...121).contains(code) {
      var field = [Float](repeating: 0, count: width * height)
      for y in 0..<height {
        for x in 0..<width {
          field[y * width + x] = NativeTextureFunctions.simulationField(
            code, noise, Float(x), Float(y), seed, width, height, parameters)
        }
      }
      for y in 0..<height {
        for x in 0..<width {
          bitmap[y * width + x] = NativeTextureMath.argbToBitmapRgba(
            NativeTextureFunctions.shadeSimulation(
              code, field, x, y, width, height, parameters, colours))
        }
      }
    } else {
      for y in 0..<height {
        for x in 0..<width {
          bitmap[y * width + x] = NativeTextureMath.argbToBitmapRgba(
            NativeTextureFunctions.generatePixel(
              code, noise, Float(x), Float(y), seed, width, height, parameters, colours))
        }
      }
    }
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for (index, pixel) in bitmap.enumerated() {
      bytes[index * 4] = UInt8(pixel & 0xFF)
      bytes[index * 4 + 1] = UInt8((pixel >> 8) & 0xFF)
      bytes[index * 4 + 2] = UInt8((pixel >> 16) & 0xFF)
      bytes[index * 4 + 3] = UInt8((pixel >> 24) & 0xFF)
    }
    return bytes
  }
}

extension NativeTextureFunctions {
  /// One pixel of the codes 0...70, in the order of the native switch.
  static func generatePixel(
    _ textureType: Int, _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ width: Int, _ height: Int, _ p: [Float], _ c: [UInt32]
  ) -> UInt32 {
    switch textureType {
    case 0: return lava(noise, x, y, p, c)
    case 1: return clouds(noise, x, y, p, c)
    case 2: return smoke(noise, x, y, p, c)
    case 3: return stone(noise, x, y, p, c)
    case 4: return wood(noise, x, y, p, c)
    case 5: return camouflage(noise, x, y, p, c)
    case 6: return paper(noise, x, y, seed, p, c)
    case 7: return rust(noise, x, y, p, c)
    case 8: return fabric(noise, x, y, seed, p, c)
    case 9: return topography(noise, x, y, p, c)
    case 10: return cells(noise, x, y, p, c)
    case 11: return cracks(noise, x, y, p, c)
    case 12: return waterRipples(noise, x, y, p, c)
    case 13: return foliage(noise, x, y, p, c)
    case 14: return bricks(noise, x, y, p, c)
    case 15: return terrain(noise, x, y, p, c)
    case 16: return ice(noise, x, y, seed, p, c)
    case 17: return sand(noise, x, y, seed, p, c)
    case 18: return nebula(noise, x, y, seed, p, c)
    case 19: return honeycomb(noise, x, y, p, c)
    case 20: return grass(noise, x, y, p, c)
    case 21: return dirt(noise, x, y, seed, p, c)
    case 22: return leather(noise, x, y, p, c)
    case 23: return concrete(noise, x, y, seed, p, c)
    case 24: return asphalt(noise, x, y, seed, p, c)
    case 25: return moss(noise, x, y, seed, p, c)
    case 26: return fire(noise, x, y, p, c)
    case 27: return aurora(noise, x, y, seed, p, c)
    case 28: return oilSlick(noise, x, y, p, c)
    case 29: return watercolor(noise, x, y, seed, p, c)
    case 30: return flowTexture(noise, x, y, p, c)
    case 31: return opal(noise, x, y, p, c)
    case 32: return damascus(noise, x, y, p, c)
    case 33: return lightning(noise, x, y, p, c)
    case 34: return velvet(noise, x, y, p, c)
    case 35: return inkMarbling(noise, x, y, p, c)
    case 36: return holographic(noise, x, y, p, c)
    case 37: return bioluminescence(noise, x, y, p, c)
    case 38: return cosmicVortex(noise, x, y, width, height, seed, p, c)
    case 39: return lavaLamp(noise, x, y, p, c)
    case 40: return eventHorizon(noise, x, y, width, height, seed, p, c)
    case 41: return fractalBloom(noise, x, y, width, height, p, c)
    case 42: return chromaticTunnel(noise, x, y, width, height, p, c)
    case 43: return eclipseCorona(noise, x, y, width, height, p, c)
    case 44: return strangeAttractor(noise, x, y, width, height, p, c)
    case 45: return ferrofluidCrown(noise, x, y, width, height, p, c)
    case 46: return supernova(noise, x, y, width, height, seed, p, c)
    case 47: return iris(noise, x, y, width, height, p, c)
    case 48: return peacockFeather(noise, x, y, width, height, p, c)
    case 49: return nautilusShell(noise, x, y, width, height, p, c)
    case 50: return ringedPlanet(noise, x, y, width, height, seed, p, c)
    case 51...70:
      return showcase(textureType, noise, x, y, seed, width, height, p, c)
    default:
      return 0xFF00_0000
    }
  }

  /// The field value of one pixel of the codes 71...121, before shading.
  static func simulationField(
    _ textureType: Int, _ noise: NativeNoiseBank, _ x: Float, _ y: Float, _ seed: Int32,
    _ width: Int, _ height: Int, _ p: [Float]
  ) -> Float {
    let s = M.maxOf(parameter(p, 0, 0.009), 0.00001)
    let complexity = M.clamp01(parameter(p, 1, 0.62))
    let distortion = M.clamp01(parameter(p, 2, 0.48))
    let unit = Float(min(width, height))
    var u = (x - Float(width) * 0.5) / unit
    var v = (y - Float(height) * 0.5) / unit
    let spatialScale = M.clamp(s / 0.008, 0.125, 5)
    u *= spatialScale
    v *= spatialScale
    var nx = x
    var ny = y
    noise.warp(&nx, &ny, scale: s * 0.65, amount: distortion * 62)
    let a = noise.fbm(nx * s, ny * s)
    let b = noise.fine(nx * s * 3.8, ny * s * 3.8)
    let input = NativeFieldInput(
      noise: noise, x: x, y: y, u: u, v: v, nx: nx, ny: ny, a: a, b: b,
      radius: (u * u + v * v).squareRoot(), angle: atan2(v, u), spatialScale: spatialScale,
      s: s, complexity: complexity, distortion: distortion, seed: seed,
      width: width, height: height, p: p)
    switch textureType {
    case 71: return reactionDiffusion(input)
    case 72: return coralGrowth(input)
    case 73: return slimeMold(input)
    case 74: return dendriticCrystal(input)
    case 75: return electricArcField(input)
    case 76: return cloudChamber(input)
    case 77: return turbulentInk(input)
    case 78: return cellularEmbryo(input)
    case 79: return neuralGarden(input)
    case 80: return magneticField(input)
    case 81: return riverDelta(input)
    case 82: return lichenColony(input)
    case 83: return bacterialCulture(input)
    case 84: return fluidVorticity(input)
    case 85: return crystalGrowth(input)
    case 86: return galacticWeb(input)
    case 87: return veinedLeaf(input)
    case 88: return porousSponge(input)
    case 89: return rainOnGlass(input)
    case 90: return emberField(input)
    case 91: return quantumFoam(input)
    case 92: return chladniPlate(input)
    case 93: return cymaticRosette(input)
    case 94: return lichtenbergFigure(input)
    case 95: return quasicrystal(input)
    case 96: return mandelbrot(input)
    case 97: return burningShip(input)
    case 98: return juliaSet(input)
    case 99: return kaleidoscopeCrystal(input)
    case 100: return spectralPrism(input)
    case 101: return topologicalKnot(input)
    case 102: return xRayBotanical(input)
    case 103: return chromatophore(input)
    case 104: return biomechanicalTissue(input)
    case 105: return gildedFiligree(input)
    case 106: return ancientRunes(input)
    case 107: return solarGranulation(input)
    case 108: return lunarEjecta(input)
    case 109: return oceanCurrents(input)
    case 110: return inkWashMountains(input)
    case 111: return neonCity(input)
    case 112: return phyllotaxisBloom(input)
    case 113: return sierpinskiTriangle(input)
    case 114: return apollonianGasket(input)
    case 115: return hyperbolicTiling(input)
    case 116: return moebiusWeave(input)
    case 117: return rorschachInkblot(input)
    case 118: return seismicInterference(input)
    case 119: return rayleighBenard(input)
    case 120: return origamiFacets(input)
    case 121: return fiberOpticBundle(input)
    default: return a
    }
  }

  private typealias M = NativeTextureMath

  private static func parameter(_ p: [Float], _ index: Int, _ fallback: Float) -> Float {
    NativeTextureMath.parameter(p, index, fallback)
  }
}
