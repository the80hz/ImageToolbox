import Foundation

/// Draws the 15 raymarch presets on the CPU. Each scene is a signed distance function that is
/// rotated, a ray per pixel is marched to its surface, and the surface is lit by its environment:
/// the sky of the shader, or the equirectangular image that the caller passes in, as on Android.
/// The scene formulas and the shading follow the Android GLSL. A ray that misses the scene takes
/// the background colour, which is transparent by default, as in the Android shader.
enum RaymarchRenderer {
  /// `environment` replaces the sky with an image, mapped by longitude and colatitude.
  static func render(
    _ preset: TexturePreset,
    scene: RaymarchScene,
    width: Int,
    height: Int,
    environment: RasterImage? = nil
  ) -> RasterImage {
    let camera = Camera(preset: preset, environment: environment)
    let shape = Shape(scene: scene, preset: preset)
    // The shader's objectColor is the first colour, and its backgroundColor the second.
    let object = preset.colours.first ?? 0xFFFF_FFFF
    let tint = FastNoiseRenderer.colour(object)
    let objectAlpha = Double(object >> 24) / 255
    let background = preset.colours.count > 1 ? preset.colours[1] : 0
    let backgroundColour = FastNoiseRenderer.colour(background)
    let backgroundAlpha = Double(background >> 24) / 255
    let aspect = Double(width) / Double(height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)

    for y in 0..<height {
      for x in 0..<width {
        let u = (2 * (Double(x) + 0.5) / Double(width) - 1) * aspect
        let v = -(2 * (Double(y) + 0.5) / Double(height) - 1)
        let colour: SIMD3<Double>
        let alpha: Double
        if let hit = camera.shade(u: u, v: v, shape: shape, tint: tint) {
          colour = hit
          alpha = objectAlpha
        } else {
          colour = backgroundColour
          alpha = backgroundAlpha
        }
        let index = (y * width + x) * 4
        pixels[index] = byte(colour.x)
        pixels[index + 1] = byte(colour.y)
        pixels[index + 2] = byte(colour.z)
        pixels[index + 3] = byte(alpha)
      }
    }
    return RasterImage(width: width, height: height, pixels: pixels)
  }

  private static func byte(_ channel: Double) -> UInt8 {
    UInt8((min(max(channel, 0), 1) * 255).rounded())
  }

  /// The camera and the light, from the preset values.
  struct Camera {
    let distance: Double
    let yaw: Double
    let pitch: Double
    let fieldOfView: Double
    let metallic: Double
    let roughness: Double
    let transmission: Double
    let lightAzimuth: Double
    let lightElevation: Double
    let environment: RasterImage?

    init(preset: TexturePreset, environment: RasterImage?) {
      self.environment = environment
      distance = preset.value("cameraDistance", fallback: 3.5)
      yaw = radians(preset.value("cameraYaw"))
      pitch = radians(preset.value("cameraPitch"))
      fieldOfView = radians(preset.value("fieldOfView", fallback: 45))
      metallic = preset.value("metallic", fallback: 0.8)
      roughness = preset.value("roughness", fallback: 0.25)
      transmission = preset.value("transmission")
      lightAzimuth = radians(preset.value("lightAngle", fallback: -35))
      lightElevation = radians(preset.value("lightElevation", fallback: 50))
    }

    /// The colour of the pixel at screen position (u, v), with v pointing up, or nil when the ray
    /// misses the scene.
    func shade(u: Double, v: Double, shape: Shape, tint: SIMD3<Double>) -> SIMD3<Double>? {
      let origin =
        distance
        * SIMD3(
          sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
      let forward = normalise(-origin)
      let right = normalise(cross(forward, SIMD3(0, 1, 0)))
      let up = cross(right, forward)
      let scale = tan(fieldOfView / 2)
      let ray = normalise(forward + scale * (u * right + v * up))

      guard let hit = march(origin: origin, ray: ray, shape: shape) else { return nil }
      let point = origin + ray * hit
      var normal = normalAt(point, shape: shape)
      if dot(normal, ray) > 0 {
        normal = -normal
      }
      let light = SIMD3(
        sin(lightAzimuth) * cos(lightElevation),
        sin(lightElevation),
        cos(lightAzimuth) * cos(lightElevation))
      let diffuse = max(dot(normal, light), 0)
      let halfway = normalise(light - ray)
      let specular = pow(max(dot(normal, halfway), 0), mix(160, 4, roughness))
      let fresnel = pow(1 - max(dot(normal, -ray), 0), 5)

      let matte = tint * (0.18 + diffuse * 0.82)
      let reflected = environment(reflect(ray, normal)) * mix(SIMD3(repeating: 1), tint, metallic)
      var colour = mix(matte, reflected, metallic * 0.75 + fresnel * 0.2)
      colour += specular * mix(SIMD3(repeating: 0.25), tint, metallic) * (1 - roughness * 0.6)
      let glass = environment(refract(ray, normal, 0.67)) * tint
      colour = mix(colour, mix(glass, reflected, 0.08 + fresnel * 0.92), transmission)
      return colour.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
    }

    /// The distance travelled along the ray to the surface, or nil when it misses.
    private func march(origin: SIMD3<Double>, ray: SIMD3<Double>, shape: Shape) -> Double? {
      var travelled = 0.0
      for _ in 0..<128 {
        let step = shape.distance(origin + ray * travelled)
        if abs(step) < 0.001 * max(1, travelled) {
          return travelled
        }
        travelled += max(abs(step) * 0.6, 0.0005)
        if travelled > 30 { break }
      }
      return nil
    }

    private func normalAt(_ point: SIMD3<Double>, shape: Shape) -> SIMD3<Double> {
      let e = 0.001
      let dx = shape.distance(point + SIMD3(e, 0, 0)) - shape.distance(point - SIMD3(e, 0, 0))
      let dy = shape.distance(point + SIMD3(0, e, 0)) - shape.distance(point - SIMD3(0, e, 0))
      let dz = shape.distance(point + SIMD3(0, 0, e)) - shape.distance(point - SIMD3(0, 0, e))
      return normalise(SIMD3(dx, dy, dz))
    }

    /// The environment seen in a direction: the image when the caller passes one, or else the sky
    /// with its warm horizon strip, as the shader draws it.
    private func environment(_ direction: SIMD3<Double>) -> SIMD3<Double> {
      if let environment {
        return equirectangularColour(environment, direction)
      }
      let sky = mix(SIMD3(0.06, 0.09, 0.16), SIMD3(0.75, 0.87, 1.0), direction.y * 0.5 + 0.5)
      let strip = pow(max(0, 1 - abs(direction.y - 0.3)), mix(70, 3, roughness))
      return sky + SIMD3(1.0, 0.88, 0.67) * strip * 0.7
    }
  }

  /// One scene with its size, thickness and rotation.
  struct Shape {
    let scene: RaymarchScene
    let innerRadius: Double
    let size: Double
    let thickness: Double
    let roundness: Double
    let count: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double

    init(scene: RaymarchScene, preset: TexturePreset) {
      self.scene = scene
      innerRadius = preset.value("innerRadius", fallback: 0.9)
      size = preset.value("size", fallback: 1)
      thickness = preset.value("thickness", fallback: 0.18)
      roundness = preset.value("roundness", fallback: 0.06)
      count = preset.value("count", fallback: 3)
      rotationX = radians(preset.value("rotationX", fallback: 20))
      rotationY = radians(preset.value("rotationY", fallback: 30))
      rotationZ = radians(preset.value("rotationZ"))
    }

    /// The signed distance from a point to the scene, after the rotation and the size.
    func distance(_ point: SIMD3<Double>) -> Double {
      var p = point
      (p.y, p.z) = rotate(rotationX, p.y, p.z)
      (p.x, p.z) = rotate(rotationY, p.x, p.z)
      (p.x, p.y) = rotate(rotationZ, p.x, p.y)
      p /= size
      return shapeDistance(p) * size
    }

    private func shapeDistance(_ p: SIMD3<Double>) -> Double {
      let t = thickness
      switch scene {
      case .sphere3D:
        return length(p) - 0.75
      case .cube3D:
        return box(p, SIMD3(repeating: 0.65)) - roundness
      case .cubeStair3D:
        return stairs(p) - roundness
      case .cubeSpheres3D:
        return length(absVec3(p) - SIMD3(repeating: 0.43)) - t
      case .emptiedCube3D:
        return max(box(p, SIMD3(repeating: 0.7)) - roundness, -(length(p) - innerRadius))
      case .torus3D:
        return torus(p, 0.62, t)
      case .mobiusTorus3D:
        return mobius(p) - roundness * 0.25
      case .gyroRings3D:
        return min(
          torus(p, 0.68, t * 0.5),
          min(
            torus(SIMD3(p.y, p.x, p.z), 0.68, t * 0.5), torus(SIMD3(p.x, p.z, p.y), 0.68, t * 0.5)))
      case .torusGem3D:
        return (abs(hypot(p.x, p.z) - 0.62) + abs(p.y) - t) * 0.7071 - roundness
      case .cubeOctahedron3D:
        let octahedron = (abs(p.x) + abs(p.y) + abs(p.z) - 1.2) * 0.57735
        return max(box(p, SIMD3(repeating: 0.65)), octahedron) - roundness
      case .infiniteSpheroids3D:
        return max(length(repeatCell(p)) - t * 1.5, box(p, SIMD3(repeating: 2.4)))
      case .infiniteStructure3D:
        let cell = repeatCell(p)
        let bars = min(
          box(cell, SIMD3(0.5, t, t)),
          min(box(cell, SIMD3(t, 0.5, t)), box(cell, SIMD3(t, t, 0.5))))
        return max(bars - roundness, box(p, SIMD3(repeating: 2.4)))
      case .infiniteCylinders3D:
        let cell = repeatCell(p)
        return max(hypot(cell.x, cell.z) - t, box(p, SIMD3(repeating: 2.4)))
      case .truchetRings3D:
        return max(truchet(p, pipes: false), box(p, SIMD3(repeating: 2.4)))
      case .truchetPipes3D:
        return max(truchet(p, pipes: true), box(p, SIMD3(repeating: 2.4)))
      }
    }

    private func box(_ p: SIMD3<Double>, _ halfSize: SIMD3<Double>) -> Double {
      let q = absVec3(p) - halfSize
      return length(pointwiseMax(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
    }

    private func torus(_ p: SIMD3<Double>, _ radius: Double, _ width: Double) -> Double {
      hypot(hypot(p.x, p.z) - radius, p.y) - width
    }

    private func repeatCell(_ p: SIMD3<Double>) -> SIMD3<Double> {
      SIMD3(glMod(p.x + 0.5, 1) - 0.5, glMod(p.y + 0.5, 1) - 0.5, glMod(p.z + 0.5, 1) - 0.5)
    }

    private func stairs(_ p: SIMD3<Double>) -> Double {
      var distance = 10.0
      for index in 0..<6 {
        let step = Double(index) / 6
        let offset = SIMD3(0, step - 0.5, step - 0.5)
        distance = min(distance, box(p - offset, SIMD3(0.65, 0.09, 0.65 - step * 0.5)))
      }
      return distance
    }

    private func mobius(_ p: SIMD3<Double>) -> Double {
      let angle = atan2(p.z, p.x)
      let (qx, qy) = rotate(angle * count * 0.5, hypot(p.x, p.z) - 0.65, p.y)
      return box(SIMD3(qx, qy, 0), SIMD3(thickness, 0.035, 1))
    }

    private func truchet(_ p: SIMD3<Double>, pipes: Bool) -> Double {
      let cell = (p + 0.5).rounded(.down)
      var q = repeatCell(p)
      let hash = fract(sin(cell.x * 127.1 + cell.y * 311.7 + cell.z * 74.7) * 43758.5453)
      if hash > 0.5 {
        q.x = -q.x
      }
      if hash > 0.75 || hash < 0.25 {
        q = SIMD3(q.y, q.z, q.x)
      }
      if pipes {
        let a = hypot(hypot(q.x - 0.5, q.y - 0.5) - 0.5, q.z)
        let b = hypot(hypot(q.x + 0.5, q.y + 0.5) - 0.5, q.z)
        return min(a, b) - thickness * 0.45
      }
      return torus(q, 0.34, thickness * 0.45)
    }
  }
}

private func radians(_ degrees: Double) -> Double {
  degrees * Double.pi / 180
}

/// The shader's `texture2D` of the environment image in a direction. The longitude is the column
/// and the colatitude the row, with row 0 at the top. The texels are blended in premultiplied form
/// with their edges repeated, and the blend is divided by its alpha, as the shader does.
private func equirectangularColour(_ image: RasterImage, _ direction: SIMD3<Double>) -> SIMD3<
  Double
> {
  let longitude = atan2(direction.z, direction.x) / (2 * Double.pi) + 0.5
  let colatitude = acos(min(max(direction.y, -1), 1)) / Double.pi
  let x = longitude * Double(image.width) - 0.5
  let y = colatitude * Double(image.height) - 0.5
  let left = x.rounded(.down)
  let top = y.rounded(.down)
  let fractionX = x - left
  let fractionY = y - top
  var premultiplied = SIMD3<Double>.zero
  var alpha = 0.0
  let corners: [(Int, Int, Double)] = [
    (0, 0, (1 - fractionX) * (1 - fractionY)),
    (1, 0, fractionX * (1 - fractionY)),
    (0, 1, (1 - fractionX) * fractionY),
    (1, 1, fractionX * fractionY),
  ]
  for (dx, dy, weight) in corners {
    let column = min(max(Int(left) + dx, 0), image.width - 1)
    let row = min(max(Int(top) + dy, 0), image.height - 1)
    let index = (row * image.width + column) * 4
    let texelAlpha = Double(image.pixels[index + 3]) / 255
    let texel =
      SIMD3(
        Double(image.pixels[index]), Double(image.pixels[index + 1]),
        Double(image.pixels[index + 2])) / 255
    premultiplied += texel * texelAlpha * weight
    alpha += texelAlpha * weight
  }
  return premultiplied / max(alpha, 0.00001)
}

/// The shader's `rotate(a) * (u, v)`: a 2D rotation with the sign convention of the GLSL mat2.
private func rotate(_ angle: Double, _ u: Double, _ v: Double) -> (Double, Double) {
  let cosine = cos(angle)
  let sine = sin(angle)
  return (cosine * u + sine * v, -sine * u + cosine * v)
}

private func absVec3(_ v: SIMD3<Double>) -> SIMD3<Double> {
  SIMD3(abs(v.x), abs(v.y), abs(v.z))
}

private func length(_ v: SIMD3<Double>) -> Double {
  (v * v).sum().squareRoot()
}

private func normalise(_ v: SIMD3<Double>) -> SIMD3<Double> {
  let size = length(v)
  return size > 0 ? v / size : v
}

private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
  (a * b).sum()
}

private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
  a + (b - a) * t
}

private func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
  a + (b - a) * t
}

private func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: SIMD3<Double>) -> SIMD3<Double> {
  a + (b - a) * t
}

private func reflect(_ incident: SIMD3<Double>, _ normal: SIMD3<Double>) -> SIMD3<Double> {
  incident - 2 * dot(normal, incident) * normal
}

private func refract(
  _ incident: SIMD3<Double>,
  _ normal: SIMD3<Double>,
  _ eta: Double
) -> SIMD3<Double> {
  let cosine = dot(normal, incident)
  let k = 1 - eta * eta * (1 - cosine * cosine)
  guard k >= 0 else { return .zero }
  return eta * incident - (eta * cosine + k.squareRoot()) * normal
}
