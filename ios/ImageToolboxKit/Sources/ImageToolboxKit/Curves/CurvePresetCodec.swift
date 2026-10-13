import Foundation

/// The state a preset stores: the four curves and the colour wheels.
public struct CurvePreset: Equatable, Sendable {
  public var curves: CurveSet
  public var wheels: ColorWheels

  public init(curves: CurveSet = .identity, wheels: ColorWheels = .identity) {
    self.curves = curves
    self.wheels = wheels
  }
}

/// Reads and writes curve presets in the formats the Android app uses:
/// - the ImageToolbox JSON format (`.itcurve`), read and written,
/// - Lightroom XMP and lrtemplate text, with the master and RGB curves, read and written,
///   XMP is written only for the master and RGB curves,
/// - Adobe ACV binary curves, read only,
/// - zip archives, read only: the first preset in them, by extension, as the Android app does.
public enum CurvePresetCodec {

  public enum DecodeError: Error, Equatable {
    /// The data is not a preset in a supported format.
    case unsupportedFormat
    /// The preset has no curve that the tool can use.
    case noCurves
  }

  /// Lightroom stores curve points as integers from 0 to 255.
  private static let lightroomScale = 255.0
  /// Lightroom curve names for the master curve, then red, green and blue.
  private static let lightroomNames = [
    "ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue",
  ]
  private static let jsonFormatName = "ImageToolbox Curves"

  /// The ImageToolbox JSON preset. The curves are the master curve, then red, green and blue, as
  /// `[x, y]` pairs. The colour wheels are the shadows, midtones and highlights as pairs, then edges.
  public static func encodeJSON(_ preset: CurvePreset) throws -> Data {
    let wheels = preset.wheels
    let object: [String: Any] = [
      "format": jsonFormatName,
      "version": 1,
      "curves": channels(of: preset.curves).map { curve in curve.points.map { [$0.x, $0.y] } },
      "colorWheels": [
        [wheels.shadows.x, wheels.shadows.y],
        [wheels.midtones.x, wheels.midtones.y],
        [wheels.highlights.x, wheels.highlights.y],
        [wheels.edges],
      ],
    ]
    return try JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  }

  /// A Lightroom-compatible XMP preset with the master and RGB curves. Lightroom has no colour
  /// wheels, so they are not written.
  public static func encodeXMP(_ preset: CurvePreset) -> Data {
    var text = """
      <?xml version="1.0" encoding="UTF-8"?>
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:PresetType="Normal"
            crs:Cluster="ImageToolbox"
            crs:SupportsAmount="False"
            crs:ProcessVersion="11.0"
            crs:HasSettings="True"
            crs:ToneCurveName2012="Custom">

      """
    for (name, curve) in zip(lightroomNames, channels(of: preset.curves)) {
      text += "    <crs:\(name)>\n      <rdf:Seq>\n"
      for point in curve.points {
        let x = Int((point.x * lightroomScale).rounded())
        let y = Int((point.y * lightroomScale).rounded())
        text += "        <rdf:li>\(x), \(y)</rdf:li>\n"
      }
      text += "      </rdf:Seq>\n    </crs:\(name)>\n"
    }
    text += """
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>

      """
    return Data(text.utf8)
  }

  /// Reads a preset. JSON, XMP and lrtemplate text, and ACV binary are recognised by their content.
  public static func decode(_ data: Data) throws -> CurvePreset {
    let bytes = [UInt8](data)
    guard !bytes.isEmpty else { throw DecodeError.unsupportedFormat }
    // A zip archive starts with "PK".
    if bytes.count >= 4, bytes[0] == 0x50, bytes[1] == 0x4B {
      return try decodeArchive(data)
    }
    if looksLikeText(bytes) {
      guard let text = String(bytes: bytes, encoding: .utf8) else {
        throw DecodeError.unsupportedFormat
      }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("{") {
        return try decodeJSON(data)
      }
      return try decodeLightroomText(text)
    }
    return try decodeACV(bytes)
  }

  // MARK: - ImageToolbox JSON

  private static func decodeJSON(_ data: Data) throws -> CurvePreset {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["format"] as? String == jsonFormatName,
      let rawCurves = object["curves"] as? [Any]
    else { throw DecodeError.unsupportedFormat }

    let curves = rawCurves.map { raw -> ToneCurve? in
      guard let pairs = raw as? [Any] else { return nil }
      let points = pairs.compactMap { pair -> CurvePoint? in
        guard let values = pair as? [Any], values.count >= 2,
          let x = number(values[0]), let y = number(values[1])
        else { return nil }
        return CurvePoint(x: x, y: y)
      }
      return points.count >= 2 ? ToneCurve(points: points) : nil
    }
    let wheels = colorWheels(from: object["colorWheels"])
    return CurvePreset(curves: try curveSet(from: curves), wheels: wheels)
  }

  /// Shadows, midtones and highlights as `[x, y]` pairs, then the edges value. Missing or
  /// malformed values give the identity wheels.
  private static func colorWheels(from value: Any?) -> ColorWheels {
    guard let groups = value as? [Any] else { return .identity }
    let values = groups.flatMap { group -> [Double] in
      if let pair = group as? [Any] {
        return pair.compactMap { number($0) }
      }
      return number(group).map { [$0] } ?? []
    }
    guard values.count == 7 else { return .identity }
    return ColorWheels(
      shadows: ColorWheelPoint(x: values[0], y: values[1]),
      midtones: ColorWheelPoint(x: values[2], y: values[3]),
      highlights: ColorWheelPoint(x: values[4], y: values[5]),
      edges: values[6])
  }

  // MARK: - Lightroom XMP and lrtemplate

  private static func decodeLightroomText(_ text: String) throws -> CurvePreset {
    let curves = lightroomNames.map { name -> ToneCurve? in
      let xmp = "<(?:[\\w.-]+:)?\(name)\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?\(name)\\s*>"
      if let body = firstGroup(xmp, in: text), let curve = curve(fromNumbersIn: body) {
        return curve
      }
      let lrtemplate = "\\b\(name)\\s*=\\s*\\{([\\s\\S]*?)\\}"
      if let body = firstGroup(lrtemplate, in: text) {
        return curve(fromNumbersIn: body)
      }
      return nil
    }
    return CurvePreset(curves: try curveSet(from: curves))
  }

  /// Pairs of numbers from 0 to 255, as Lightroom writes them.
  private static func curve(fromNumbersIn text: String) -> ToneCurve? {
    let values = numbers(in: text)
    guard values.count >= 4, values.count % 2 == 0 else { return nil }
    let points = stride(from: 0, to: values.count, by: 2).map { index in
      CurvePoint(x: values[index] / lightroomScale, y: values[index + 1] / lightroomScale)
    }
    return ToneCurve(points: points)
  }

  // MARK: - Adobe ACV

  /// Version, curve count, then per curve a point count and `(output, input)` pairs, all as
  /// big-endian 16-bit numbers.
  private static func decodeACV(_ bytes: [UInt8]) throws -> CurvePreset {
    var offset = 0
    func readUnsignedShort() throws -> Int {
      guard offset + 2 <= bytes.count else { throw DecodeError.unsupportedFormat }
      let value = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
      offset += 2
      return value
    }

    let version = try readUnsignedShort()
    guard version == 1 || version == 4 else { throw DecodeError.unsupportedFormat }
    let curveCount = try readUnsignedShort()
    guard (1...4).contains(curveCount) else { throw DecodeError.unsupportedFormat }

    var rawCurves: [[(input: Int, output: Int)]] = []
    for _ in 0..<curveCount {
      let pointCount = try readUnsignedShort()
      guard (2...256).contains(pointCount) else { throw DecodeError.unsupportedFormat }
      var points: [(input: Int, output: Int)] = []
      for _ in 0..<pointCount {
        let output = try readUnsignedShort()
        let input = try readUnsignedShort()
        points.append((input, output))
      }
      rawCurves.append(points)
    }

    let largest = rawCurves.flatMap { $0 }.map { max($0.input, $0.output) }.max() ?? 0
    let scale = largest > 255 ? 65535.0 : 255.0
    let curves = rawCurves.map { points in
      ToneCurve(
        points: points.map {
          CurvePoint(x: Double($0.input) / scale, y: Double($0.output) / scale)
        })
    }
    return CurvePreset(curves: try curveSet(from: curves))
  }

  // MARK: - Zip archives

  /// Preset extensions in the order the Android app prefers them.
  private static let archiveExtensions = ["itcurve", "xmp", "lrtemplate", "acv"]

  /// Decodes the most preferred preset in a zip archive. macOS metadata files are ignored.
  private static func decodeArchive(_ data: Data) throws -> CurvePreset {
    let entries: [ZipReader.Entry]
    do {
      entries = try ZipReader.entries(in: data) { archivePriority(of: $0) != nil }
    } catch {
      throw DecodeError.unsupportedFormat
    }
    let best = entries.min { first, second in
      (archivePriority(of: first.name) ?? .max) < (archivePriority(of: second.name) ?? .max)
    }
    guard let best else { throw DecodeError.noCurves }
    return try decode(best.data)
  }

  /// The position of the file's extension in `archiveExtensions`, or nil for other files.
  private static func archivePriority(of name: String) -> Int? {
    let fileName = name.split(separator: "/").last.map(String.init) ?? name
    guard !name.hasPrefix("__MACOSX/"), !fileName.hasPrefix("._") else { return nil }
    let extensionName = (fileName as NSString).pathExtension.lowercased()
    return archiveExtensions.firstIndex(of: extensionName)
  }

  // MARK: - Helpers

  /// Master, red, green and blue in that order. A missing channel is the identity.
  private static func curveSet(from curves: [ToneCurve?]) throws -> CurveSet {
    guard curves.contains(where: { $0 != nil }) else { throw DecodeError.noCurves }
    func channel(_ index: Int) -> ToneCurve {
      curves.indices.contains(index) ? (curves[index] ?? .identity) : .identity
    }
    return CurveSet(master: channel(0), red: channel(1), green: channel(2), blue: channel(3))
  }

  private static func channels(of curves: CurveSet) -> [ToneCurve] {
    [curves.master, curves.red, curves.green, curves.blue]
  }

  private static func number(_ value: Any) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  private static func numbers(in text: String) -> [Double] {
    matches("-?\\d+(?:\\.\\d+)?", in: text).compactMap { Double($0[0]) }
  }

  private static func firstGroup(_ pattern: String, in text: String) -> String? {
    matches(pattern, in: text).first?[1]
  }

  /// Every match with its capture groups. Index 0 is the whole match.
  private static func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
      (0..<match.numberOfRanges).map { index in
        Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
      }
    }
  }

  /// Printable ASCII, whitespace and UTF-8 text. ACV files are binary and fail this check.
  private static func looksLikeText(_ bytes: [UInt8]) -> Bool {
    bytes.prefix(64).allSatisfy { byte in
      byte == 0x09 || byte == 0x0A || byte == 0x0D || (0x20...0x7E).contains(byte) || byte >= 0x80
    }
  }
}
