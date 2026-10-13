import Foundation

/// The distance estimators of the folding kinds: the Mandelbox, the Menger sponge, the Sierpinski pyramid
/// and gasket, and the kaleidoscopic IFS family. Each follows the Android engine's Rust renderer, with its
/// constants. The iteration counts come from the caller's work plan. Each estimator returns a signed
/// distance.
enum Fractal3DFolds {

  /// Mandelbox: a box fold at +/-1, then a sphere fold, then z -> scale*z + c, with c the point. The scale
  /// is -1.65, the minimum radius^2 0.25 and the fixed radius^2 1.
  static func mandelbox(_ point: FractalVector, iterations: Int) -> Double {
    let scale = -1.65
    let minimumRadiusSquared = 0.25
    let fixedRadiusSquared = 1.0
    var z = point
    var derivative = 1.0
    for _ in 0..<max(iterations, 0) {
      z = FractalVector(boxFold(z.x), boxFold(z.y), boxFold(z.z))
      let radiusSquared = z.dot(z)
      if radiusSquared < minimumRadiusSquared {
        let factor = fixedRadiusSquared / minimumRadiusSquared
        z = z * factor
        derivative *= factor
      } else if radiusSquared < fixedRadiusSquared {
        let factor = fixedRadiusSquared / max(radiusSquared, 1e-12)
        z = z * factor
        derivative *= factor
      }
      z = z * scale + point
      derivative = derivative * abs(scale) + 1
    }
    return z.length / max(abs(derivative), 1e-12)
  }

  private static func boxFold(_ value: Double) -> Double {
    min(max(value, -1), 1) * 2 - value
  }

  /// Menger sponge: the cube of half-width 1, cut by the square holes at each level. The estimate is the
  /// maximum of the cube's distance and the cut at each level, as Inigo Quilez writes it.
  static func mengerSponge(_ point: FractalVector, iterations: Int) -> Double {
    let q = point.absolute - 1
    var distance = FractalVector(max(q.x, 0), max(q.y, 0), max(q.z, 0)).length
    distance += min(max(q.x, max(q.y, q.z)), 0)
    var scale = 1.0
    for _ in 0..<max(iterations, 0) {
      let a =
        FractalVector(
          wrappedModuloTwo(point.x * scale),
          wrappedModuloTwo(point.y * scale),
          wrappedModuloTwo(point.z * scale)) - 1
      scale *= 3
      let r = (FractalVector(1, 1, 1) - a.absolute * 3).absolute
      let da = max(r.x, r.y)
      let db = max(r.y, r.z)
      let dc = max(r.z, r.x)
      let cut = (min(da, min(db, dc)) - 1) / scale
      distance = max(distance, cut)
    }
    return distance
  }

  /// The value x mod 2 in [0, 2), as the engine's rem_euclid gives it.
  private static func wrappedModuloTwo(_ value: Double) -> Double {
    value - 2 * (value / 2).rounded(.down)
  }

  /// Sierpinski pyramid: each step moves the point to its nearest of four vertices, and doubles its offset
  /// from that vertex. The estimate is the length over the scale, less 0.012.
  static func sierpinskiPyramid(_ point: FractalVector, iterations: Int) -> Double {
    let vertices = [
      FractalVector(0.68, 0.68, 0.68), FractalVector(-0.68, -0.68, 0.68),
      FractalVector(-0.68, 0.68, -0.68), FractalVector(0.68, -0.68, -0.68),
    ]
    var p = point
    var scale = 1.0
    for _ in 0..<max(iterations, 0) {
      var nearest = vertices[0]
      var nearestDistance = (p - nearest).dot(p - nearest)
      for vertex in vertices.dropFirst() {
        let distance = (p - vertex).dot(p - vertex)
        if distance < nearestDistance {
          nearest = vertex
          nearestDistance = distance
        }
      }
      p = (p - nearest) * 2
      scale *= 2
    }
    return p.length / scale - 0.012
  }

  /// Sierpinski gasket: the tetrahedral fold with a sphere fold of the given minimum radius. The scale is
  /// 2 + fold/2, and the distance is scaled back by the object scale. The engine runs 5 to 16 steps.
  static func sierpinskiGasket(
    _ point: FractalVector, objectScale: Double, fold: Double, minimumRadius: Double,
    iterations: Int
  ) -> Double {
    foldedTetrahedron(
      point / objectScale, scale: 2 + fold * 0.5, minimumRadius: minimumRadius,
      iterations: min(max(iterations, 5), 16)) * objectScale
  }

  /// The tetrahedral fold, optionally with a sphere fold, then p -> sf*p - (sf - 1). The estimate is
  /// (|p| - 1) / |s|, with s the accumulated scale.
  private static func foldedTetrahedron(
    _ start: FractalVector, scale sf: Double, minimumRadius: Double?, iterations: Int
  ) -> Double {
    var p = start
    var scale = 1.0
    for _ in 0..<iterations {
      p = tetrahedralFold(p)
      if let minimumRadius {
        let minimumRadiusSquared = minimumRadius * minimumRadius
        let radiusSquared = max(p.dot(p), 1e-15)
        if radiusSquared < minimumRadiusSquared {
          let factor = minimumRadiusSquared / radiusSquared
          p = p * factor
          scale *= factor
        }
      }
      p = p * sf - (sf - 1)
      scale *= sf
    }
    return (p.length - 1) / max(abs(scale), 1e-12)
  }

  /// The tetrahedral reflections of the Android engine: each pair of coordinates is reflected when its
  /// sum is negative.
  private static func tetrahedralFold(_ value: FractalVector) -> FractalVector {
    var p = value
    if p.x + p.y < 0 { (p.x, p.y) = (-p.y, -p.x) }
    if p.x + p.z < 0 { (p.x, p.z) = (-p.z, -p.x) }
    if p.y + p.z < 0 { (p.y, p.z) = (-p.z, -p.y) }
    return p
  }

  /// Octahedral IFS: folds on the octahedral mirror planes, then p -> scale*p - (scale - 1), with
  /// scale = fold + 1. The estimate is (|p| - 2) / |d|, scaled by the object scale.
  static func octahedralIFS(
    _ point: FractalVector, objectScale: Double, fold: Double, iterations: Int
  ) -> Double {
    let scale = fold + 1
    var p = point / objectScale
    var derivative = 1.0
    for _ in 0..<min(max(iterations, 4), 18) {
      p = p.absolute.sortedDescending * scale - (scale - 1)
      derivative *= scale
      if p.length > 100 { break }
    }
    return (p.length - 2) / max(abs(derivative), 1e-12) * objectScale
  }

  /// The five mirror normals of the icosahedral group, each unit length.
  private static let icosahedralNormals: [FractalVector] = {
    let phi = (1 + 5.0.squareRoot()) / 2
    return [
      FractalVector(1, phi, 0), FractalVector(0, 1, phi), FractalVector(phi, 0, 1),
      FractalVector(-1, phi, 0), FractalVector(0, -1, phi),
    ].map(\.normalized)
  }()

  /// Icosahedral IFS: reflections in the five icosahedral mirror planes, then the same fold and scale as
  /// the octahedral IFS.
  static func icosahedralIFS(
    _ point: FractalVector, objectScale: Double, fold: Double, iterations: Int
  ) -> Double {
    let scale = fold + 1
    var p = point / objectScale
    var derivative = 1.0
    for _ in 0..<min(max(iterations, 4), 18) {
      for normal in icosahedralNormals {
        let t = p.dot(normal)
        if t < 0 { p = p - normal * (2 * t) }
      }
      p = p.absolute.sortedDescending * scale - (scale - 1)
      derivative *= scale
      if p.length > 100 { break }
    }
    return (p.length - 2) / max(abs(derivative), 1e-12) * objectScale
  }

  /// Apollonian gasket: the point is inverted in a sphere of radius `packing` or in the unit sphere,
  /// then folded and scaled by (1 + packing)*fold.
  static func apollonianGasket(
    _ point: FractalVector, objectScale: Double, fold: Double, packing: Double, iterations: Int
  ) -> Double {
    let scale = (1 + packing) * fold
    var p = point / objectScale
    var derivative = 1.0
    for _ in 0..<min(max(iterations, 4), 18) {
      p = p.absolute
      let radiusSquared = max(p.dot(p), 1e-15)
      if radiusSquared < packing * packing {
        let factor = 1 / (packing * packing)
        p = p * factor
        derivative *= factor
      } else if radiusSquared < 1 {
        let factor = 1 / radiusSquared
        p = p * factor
        derivative *= factor
      }
      p = p.sortedDescending * scale - packing
      derivative *= scale
      if p.length > 100 { break }
    }
    return (p.length - 1) / max(abs(derivative), 1e-12) * objectScale
  }

  /// Kleinian group: a fold, a box-like offset and an inversion clamped to [1, 3]. The estimate is
  /// (|p| - 0.4) / |d|, scaled by the object scale.
  static func kleinian(
    _ point: FractalVector, objectScale: Double, fold: Double, minimumRadius: Double,
    iterations: Int
  ) -> Double {
    let scale = fold + 1
    let size = FractalVector(1, 1, 1.3)
    let offset = FractalVector(0, 0, -minimumRadius)
    var p = point / objectScale
    var derivative = 1.0
    for _ in 0..<min(max(iterations, 6), 16) {
      p = p.absolute.sortedDescending
      p = p * scale - size * (scale - 1)
      let radiusSquared = max(p.dot(p), 1e-15)
      let inverse = min(max(1 / radiusSquared, 1), 3)
      p = p * inverse + offset
      derivative *= inverse * scale
    }
    return (p.length - 0.4) / max(abs(derivative), 1e-12) * objectScale
  }
}
