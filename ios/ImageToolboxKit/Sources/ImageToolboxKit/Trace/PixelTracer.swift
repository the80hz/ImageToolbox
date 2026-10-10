import Foundation

/// Traces a picture into SVG: the picture is reduced to a few colours, and the outline of each colour's
/// pixels becomes a filled path. The outlines follow the pixel edges exactly, so the result is blocky
/// on curves. Smoothing into Bézier curves is not done here.
public enum PixelTracer {

  /// A closed outline of integer grid vertices. Outer outlines and holes have opposite orientations,
  /// so the even-odd rule fills the region between them.
  public typealias Loop = [(x: Int, y: Int)]

  /// Reduces the picture to `colours` colours and writes one filled path per colour.
  public static func svg(for raster: RasterImage, colours: Int) -> String {
    let palette = PaletteExtractor.dominantColors(raster, count: colours)
    var masks = [[Bool]](
      repeating: [Bool](repeating: false, count: raster.width * raster.height),
      count: palette.count)
    let straight = raster.straightRGBA()
    for index in 0..<(raster.width * raster.height) where raster.pixels[index * 4 + 3] > 0 {
      let nearest = nearestColour(
        red: straight[index * 4], green: straight[index * 4 + 1], blue: straight[index * 4 + 2],
        palette: palette)
      masks[nearest][index] = true
    }

    var svg =
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(raster.width)\" "
      + "height=\"\(raster.height)\" viewBox=\"0 0 \(raster.width) \(raster.height)\">\n"
    for (colour, mask) in zip(palette, masks) {
      let loops = contours(of: mask, width: raster.width, height: raster.height)
      guard !loops.isEmpty else { continue }
      svg += "  <path fill=\"\(hex(colour))\" fill-rule=\"evenodd\" d=\""
      svg += loops.map(pathData).joined(separator: " ")
      svg += "\"/>\n"
    }
    svg += "</svg>\n"
    return svg
  }

  /// The closed outlines of the `true` cells of `mask`, with collinear vertices removed.
  public static func contours(of mask: [Bool], width: Int, height: Int) -> [Loop] {
    let stride = width + 1
    func vertex(_ x: Int, _ y: Int) -> Int { y * stride + x }

    var outgoing: [Int: [Int]] = [:]
    func addEdge(_ from: Int, _ to: Int) {
      outgoing[from, default: []].append(to)
    }
    for y in 0..<height {
      for x in 0..<width where mask[y * width + x] {
        if y == 0 || !mask[(y - 1) * width + x] {
          addEdge(vertex(x, y), vertex(x + 1, y))
        }
        if x == width - 1 || !mask[y * width + x + 1] {
          addEdge(vertex(x + 1, y), vertex(x + 1, y + 1))
        }
        if y == height - 1 || !mask[(y + 1) * width + x] {
          addEdge(vertex(x + 1, y + 1), vertex(x, y + 1))
        }
        if x == 0 || !mask[y * width + x - 1] {
          addEdge(vertex(x, y + 1), vertex(x, y))
        }
      }
    }

    var loops: [Loop] = []
    while let start = outgoing.keys.min() {
      // Follow outgoing edges until the walk returns to its start. Where two edges leave a vertex
      // (diagonal pixels touching), the first one is taken, which still closes every loop.
      var vertices: [Int] = []
      var current = start
      repeat {
        vertices.append(current)
        guard var next = outgoing[current], !next.isEmpty else { break }
        let target = next.removeFirst()
        outgoing[current] = next.isEmpty ? nil : next
        current = target
      } while current != start
      if vertices.count >= 4 {
        loops.append(simplified(vertices.map { (x: $0 % stride, y: $0 / stride) }))
      }
    }
    return loops
  }

  /// Removes vertices that lie on the straight line through their neighbours.
  static func simplified(_ loop: Loop) -> Loop {
    guard loop.count > 2 else { return loop }
    var result: Loop = []
    for index in loop.indices {
      let previous = loop[(index + loop.count - 1) % loop.count]
      let current = loop[index]
      let next = loop[(index + 1) % loop.count]
      let cross =
        (current.x - previous.x) * (next.y - current.y)
        - (current.y - previous.y) * (next.x - current.x)
      if cross != 0 { result.append(current) }
    }
    return result.count >= 3 ? result : loop
  }

  // MARK: - Helpers

  private static func pathData(_ loop: Loop) -> String {
    guard let first = loop.first else { return "" }
    var text = "M\(first.x) \(first.y)"
    for point in loop.dropFirst() {
      text += " L\(point.x) \(point.y)"
    }
    return text + " Z"
  }

  private static func nearestColour(red: UInt8, green: UInt8, blue: UInt8, palette: [RGBA]) -> Int {
    var best = 0
    var bestDistance = Int.max
    for (index, colour) in palette.enumerated() {
      let dr = Int(red) - Int(colour.red)
      let dg = Int(green) - Int(colour.green)
      let db = Int(blue) - Int(colour.blue)
      let distance = dr * dr + dg * dg + db * db
      if distance < bestDistance {
        bestDistance = distance
        best = index
      }
    }
    return best
  }

  private static func hex(_ colour: RGBA) -> String {
    let parts = [colour.red, colour.green, colour.blue].map { String(format: "%02x", $0) }
    return "#" + parts.joined()
  }
}
